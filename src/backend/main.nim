import std/[
  xmltree, 
  strutils, 
  times,
  tables, strtabs,
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
  noteViewT = "note-view" # note view template name


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


func initNote(html: sink XmlNode, path: Path): Note =
  template articleResolver(doc): untyped =
    result.content = doc

  result.path = path
    
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


type
  Xxx = tuple
    node: XmlNode
    onlyChildren: bool


func map(father: var XmlNode, src: XmlNode, onlyChildren: bool, mapper: proc(x: XmlNode): Xxx) {.effectsOf: mapper.} = 
  if onlyChildren:
    for n in src:
      map father, n, false, mapper
  
  else:
    var (el, oc) = mapper src

    if oc:
      map father, el, true, mapper
    else:
      father.add el

      if el.isElement:
        for n in src:
          map el, n, false, mapper

func wrap(hts: seq[HashTag]): XmlNode = 
  # to HTML
  newElement("wtf")
  
func renderHtml(n; templates: Table[string, XmlNode]): XmlNode = 
  proc repl(x: XmlNode): Xxx =
    if x.isElement:
      case x.tag
      of "use":
        let  tname = x.attr"template"
        case tname
        of   "article": (n.content,                      false)
        of   "tags"   : (n.hashtags.wrap,                true )
        else          : (templates[tname],               true )
      else            : (newXmlTree(x.tag, [], x.attrs), false)
    else              : (x,                              false)
  
  result = newElement "html"
  map(result, templates[noteViewT], true, repl)

type Html = distinct XmlNode

func toStringImpl(result: var string; x) = 
  case x.kind
  of   xnElement:
    let t = x.tag

    result.add '<'
    result.add t

    if x.attrsLen != 0:
      for k, v in x.attrs:
        result.add ' '
        result.add k

        if v != "":
          result.add '='
          result.add '"'
          result.add v
          result.add '"'

    result.add '>'

    for n in x:
      toStringImpl result, n

    case t
    of   "link": discard
    else:
      result.add '<'
      result.add '/'
      result.add t
      result.add '>'

  of xnText:
    result.add x.text

  of xnComment: discard
  else: raisev "unsuppored xml kind: " & $x.kind

func `$`(h: Html): string = 
  toStringImpl result, h.XmlNode 

proc writeHtml(p, x) = 
  let f = newFileStream($p, fmWrite)
  f.write "<!DOCTYPE html>"
  f.write $x.Html
  f.close

func `/`(a: Path, b: string): Path = 
  Path $a / b

proc main(templateDir, notesDir, saveNotedDir: Path) = 
  let tmpls = loadHtmlTemplates templateDir

  for p in discover notesDir:
    echo p
    let 
      doc   = parseHtmlFromFile p
      html  = renderHtml(initNote(doc, p), tmpls)
      fname = extractFilename $p

    writeHtml saveNotedDir/fname, html

  # build index.html



when isMainModule:
  main Path "./partials/templates.html", 
       Path "./notes", 
       Path "./dist/notes"

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
