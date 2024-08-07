import std/[
  xmltree, 
  strutils, 
  times,
  tables,
  os, paths, streams,
  algorithm]

import pkg/htmlparser

# ---------------------------------------

type
  HashTag* = object
    ## simple tag: #math
    ## data   tag: #page: 2
    name*, value*: string


  Note* = object
    timestamp*: Datetime
    # title*: string
    content*: XmlNode
    hashtags*: seq[HashTag]


using 
  x: XmlNode
  p: Path
  s: string
  n: Note


func initHashTag(name, val: string): HashTag = 
  HashTag(name: name, value: val)

# ---------------------------------------

template `<<`(smth): untyped {.dirty.} =
  result.add smth

template raisev(msg): untyped {.dirty.} =
  raise newException(ValueError, msg)

template impossible: untyped = 
  raise newException(KeyError, "this region of code is impossible to reach, if so, seems there are logical bugs")

# ---------------------------------------

func isElement(x): bool = 
  x.kind == xnElement

func tagLabel(s): string = 
  if   s.len <  2 : raisev "tag cannot have length of < 2"
  elif s[0] != '#': raisev "tag should start with #"
  else            : s.substr 1

func parseHashTag(s): HashTag = 
  let  parts    = s.split(':', 1)
  case parts.len
  of 1: initHashTag tagLabel parts[0], ""
  of 2: initHashTag tagLabel parts[0], strip parts[1]
  else: impossible

func parseHashTags(s): seq[HashTag] = 
  for l in splitLines s:
    if not isEmptyOrWhitespace l:
      <<   parseHashTag  strip l


proc discover(dir: Path): seq[Path] = 
  for f in walkDirRec $dir:
    if f.endsWith ".html":
      << Path f

proc parseHtmlFromFile(p): XmlNode = 
  parseHtml newFileStream($p, fmRead)


func dfs(x; visit: proc(n: XmlNode): bool) {.effectsOf: visit.} = 
  ## DFS traversesal
  if x.visit and x.isElement:
    for ent in x:
      dfs ent, visit

func findTitle(x): string = 
  var titles: seq[XmlNode]
  
  proc visit(n: XmlNode): bool = 
    if 
      n.isElement                    and
      n.tag       in "h1 h2 h3 h4 h5 h6"
    :
      add titles, n
    true

  func headingTagCmp(a, b: XmlNode): int = 
    cmp a.tag[1], b.tag[1] # only compare number part - i.e. h[1] vs h[3]
  
  dfs  x,      visit
  sort titles, headingTagCmp, Ascending
  
  case  titles.len 
  of 0: raisev "cannot find any header tag (h1 .. h6) in the note"
  else: titles[0].innerText


func initNode(html: sink XmlNode): Note =
  case html.tag
  of "document": # automatically generated tag for wrapping
    for el in html:
      if el.kind == xnElement:
        case el.tag
        of "article": 
          result.content = el
        
        of "tags":
          result.hashtags = el.innerText.parseHashTags
        
        of "time": 
          discard
        
        of "data": 
          discard
        
        else: 
          raisev "invalid tag in direct child of html file: " & el.tag
  
  else:
    raisev "the note should have at least these tags at the root: artice, tags"

const noteViewTemplate = "note-view"

proc loadHtmlTemplates(p): Table[string, XmlNode] = 
  let defDoc = parseHtmlFromFile p
  for x in defDoc:
    if x.isElement:
      case x.tag
      of "template":
        result[x.attr"name"] = x 
      else: 
        raisev "only <template> is allowed in top level"


func toHtml(n; templates: Table[string, XmlNode]): XmlNode = 
  let tmpl = templates[noteViewTemplate]
  # traverse tmpl to build
  # extract params



when isMainModule:
  let tmpls = loadHtmlTemplates Path "./templates.html"

  for p in discover Path "./notes":
    let 
      doc  = parseHtmlFromFile p
      html = toHtml(initNode doc, tmpls)

    writeFile "test.html", $html


# block config:
#   configurable templates
#   config file "for base_url, site_name"

# block pages:
#   about
#   settings:
#     name
#     export local DB
#     import DB

#   notes table:
#     different formuals forr scoring
#     searchable
#     show name, tag, time, score

#   note view:
#     content
#     buttuns forr remembering

