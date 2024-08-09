import std/[
  xmltree, 
  strutils, 
  times,
  tables, strtabs,
  os, paths, streams,
  algorithm,
  sugar]

import pkg/htmlparser

# ---------------------------------------

type
  Html = distinct XmlNode

  HashTag* = object
    ## simple tag: #math
    ## data   tag: #page: 2
    name*, value*: string


  Note* = ref object
    id*       : string
    path*     : Path         ## original file path
    timestamp*: Datetime
    content*  : XmlNode
    hashtags* : seq[HashTag]


using 
  x: XmlNode
  p: Path
  s: string
  n: Note


const 
  noteViewT   = "note-view" # note view template name
  htmlPrefix  = "<!DOCTYPE html>"

func initHashTag(name, val: string): HashTag = 
  HashTag(name: name, value: val)

# ---------------------------------------

template `<<`(smth): untyped {.dirty.} =
  result.add  smth

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

  result = Note(path: path)
    
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

          of "action_btns":
            discard

          of "id": 
            result.id = el.innerText
          
          # of "time": 
          #   result.timestamp = fromUnix parseInt strip el.innerText
          
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


func isWrapper(x): bool =
  x.isElement and x.tag in ["", "template"]

func newWrapper: XmlNode =
  newElement ""

# func addCustom(father: var XmlNode, x: XmlNode) = 
#   if x.isWrapper:
#     for n in x:
#       father.add n
#   else:
#     father.add x

func map(father: var XmlNode, src: XmlNode, mapper: proc(x: XmlNode): XmlNode) {.effectsOf: mapper.} = 
  if src.isWrapper:
    for n in src:
      map father, n, mapper
  
  else:
    var el = mapper src

    if el.isWrapper:
      map father, el, mapper

    else:
      father.add el

      if el.isElement: # and src.isElement:
        for n in src:
          map el, n, mapper

func renderTemplate(t: XmlNode, ctx: proc(key: string): XmlNode): XmlNode = 
  result = newWrapper()

  proc repl(x): XmlNode = 
    if x.isElement:
      case x.tag
      of   "slot": ctx x.attr"name"
      else:        newXmlTree(x.tag, [], x.attrs)
    else:          x

  map result, t, repl

func wrap(hashtags: seq[HashTag], templates: Table[string, XmlNode]): XmlNode = 
  result = newWrapper()
  
  for ht in hashtags:
    let ctx = capture ht:
      proc (k: string): XmlNode = 
        case k
        of "name": newText ht.name
        # of "icon": newText ht.name
        else:      raisev "invalid property for hashtag render: " & k
    
    for n in renderTemplate(templates["hashtag"], ctx):
      << n
  
func renderHtml(n; templates: Table[string, XmlNode]): XmlNode = 
  proc repl(x: XmlNode): XmlNode =
    if x.isElement:
      case x.tag
      of "use":
        let  tname = x.attr"template"
        case tname
        of   "article"    : n.content
        of   "tags"       : n.hashtags.wrap(templates)
        of   "action_btns": raisev "no defined yet"
        else              : templates[tname]
      else                : newXmlTree(x.tag, [], x.attrs)
    else                  : x
  
  result = newElement "html"
  map result, templates[noteViewT], repl


func toStringImpl(result: var string; x) = 
  case x.kind
  of   xnElement:
    let t = x.tag
    << '<'
    << t

    if x.attrsLen != 0:
      for k, v in x.attrs:
        << ' '
        << k

        if v != "":
          << '='
          << '"'
          << v
          << '"'

    << '>'

    for n in x:
      toStringImpl result, n

    case t
    of   "link", "img", "input": discard
    else:
      << '<'
      << '/'
      << t
      << '>'

  of xnText:
    << x.text

  of xnComment: discard
  else: raisev "unsuppored xml kind: " & $x.kind

func `$`(h: Html): string = 
  toStringImpl result, h.XmlNode 

proc writeHtml(p, x) = 
  let f = newFileStream($p, fmWrite)
  f.write htmlPrefix
  f.write $Html x
  f.close

func `/`(a: Path, b: string): Path = 
  Path $a / b


func `index.html`(): XmlNode = 
  discard

func `about.html`(): XmlNode = 
  discard

func `settings.html`(): XmlNode = 
  discard


proc genWebsite(templateDir, notesDir, saveNoteDir: Path) = 
  let tmpls = loadHtmlTemplates templateDir
  var notes: seq[Note]
  
  for p in discover notesDir:
    echo "+ processing ", p
    let 
      doc   = parseHtmlFromFile p
      note  = initNote(doc, p)
      html  = renderHtml(note, tmpls)
      fname = extractFilename $p

    add notes, note
    writeHtml saveNoteDir/fname, html

  echo "creating other pages ..."

  writeHtml saveNoteDir/"index.html",    html
  # writeHtml saveNoteDir/"about.html",    html
  # writeHtml saveNoteDir/"settings.html", html

  # notes table:
  #   different formuals forr scoring
  #   searchable
  #   show name, tag, time, score

  # confisgurable templates
  # config file "for base_url, site_name"
  #   export local DB
  #   import DB


when isMainModule:
  genWebsite Path "./partials/templates.html", 
             Path "./notes", 
             Path "./dist/notes"
