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
    id*       : string
    path*     : Path         ## original file path
    timestamp*: Datetime
    # title*: string
    content*: XmlNode
    hashtags*: seq[HashTag]


using 
  x: XmlNode
  p: Path
  s: string
  n: Note


const 
  noteViewTemplate = "note-view"


func initHashTag(name, val: string): HashTag = 
  HashTag(name: name, value: val)

# ---------------------------------------

template `<<`(smth): untyped {.dirty.} =
  result.add smth

template raisev(msg): untyped {.dirty.} =
  raise newException(ValueError, msg)

template impossible: untyped = 
  raise newException(KeyError, "this region of code must be unreachable, if note, there are some wrong reasoning in the code")

template iff(cond, iftrue, iffalse): untyped = 
  if cond: iftrue
  else   : iffalse

# ---------------------------------------

func splitOnce(s; c: char): (string, string) = 
  let parts = s.split(c, 1)
  (parts[0], iff(parts.len == 2, parts[1], ""))

func isElement(x): bool = 
  x.kind == xnElement

func tagLabel(s): string = 
  if   s.len <  2 : raisev "tag cannot have length of < 2"
  elif s[0] != '#': raisev "tag should start with #"
  else            : s.substr 1

func parseHashTag(s): HashTag = 
  let (name, val) = splitOnce(s, ':')
  initHashTag tagLabel name, strip val

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
  template articleResolver(doc): untyped =
    result.content = doc
    
  if html.isElement:
    case html.tag
    of "document": # automatically generated tag for wrapping multiple tags
      for el in html:
        if el.kind == xnElement:
          case el.tag
          of "article": 
            articleResolver el

          of "tags":
            result.hashtags = el.innerText.parseHashTags

          of "id": 
            # TODO if not present, create one
            discard
          
          of "time": 
            # TODO if not present, create one
            discard
          
          of "data": 
            discard
          
          else: 
            raisev "invalid tag in direct child of html file: " & el.tag
    
    of "article": # he document only has single article element
      articleResolver html

    else:
      raisev "the note should have at least these tags at the root: artice, tags"

  else:
    raisev "provided node as HTML is not element kind"

proc loadHtmlTemplates(p): Table[string, XmlNode] = 
  let defDoc = parseHtmlFromFile p
  for x in defDoc:
    if x.isElement:
      case x.tag
      of "template":
        result[x.attr"name"] = x 
      else: 
        raisev "only <template> is allowed in top level"


func copyTemplate(root: XmlNode, modifier: proc(x: XmlNode): XmlNode): XmlNode {.effectsOf: modifier.} = 
  ## traversed through it and replaces what modifier
  discard

func renderHtml(n; templates: Table[string, XmlNode]): XmlNode = 
  let tmpl = templates[noteViewTemplate]
  # for x in 
  # traverse tmpl to build
  # extract params


when isMainModule:
  let tmpls = loadHtmlTemplates Path "./templates.html"
  echo tmpls
  for p in discover Path "./notes":
    let 
      doc  = parseHtmlFromFile p
      html = renderHtml(initNode doc, tmpls)

    writeFile "play.html", $html


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
