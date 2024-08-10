import std/[
  xmltree, 
  strutils, sequtils,
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
  templates: Table[string, XmlNode]

const 
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

func identity[T](t: T): T = t


func splitOnce(s; c: char): (string, string) = 
  let parts = s.split(c, 1)
  (parts[0], iff(parts.len == 2, parts[1], ""))

func isElement(x): bool = 
  x.kind == xnElement

func isWrapper(x): bool =
  x.isElement and x.tag in ["", "template"]

func newWrapper: XmlNode =
  newElement ""


func `/`(a: Path, b: string): Path = 
  Path $a / b


func toStringImpl(result: var string; x) = 
  case x.kind
  of xnElement:
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

proc parseHtmlFromFile(p): XmlNode = 
  parseHtml newFileStream($p, fmRead)

proc writeHtml(p, x) = 
  let f = newFileStream($p, fmWrite)
  f.write htmlPrefix
  f.write $Html x
  f.close

func shallowCopy(x): XmlNode = 
  newXmlTree x.tag, [], x.attrs


func hashTagLabel(s): string = 
  if   s.len <  2 : raisev "tag cannot have length of < 2"
  elif s[0] != '#': raisev "tag should start with #"
  else            : s.substr 1

func parseHashTag(s): HashTag = 
  let (name, val) = splitOnce(s, ':')
  initHashTag hashTagLabel name, strip val

func parseHashTags(s): seq[HashTag] = 
  for l in splitLines s:
    if not isEmptyOrWhitespace l:
      <<   parseHashTag  strip l


proc discover(dir: Path): seq[Path] = 
  for f in walkDirRec $dir:
    if f.endsWith ".html":
      << Path f

proc loadHtmlTemplates(p): Table[string, XmlNode] = 
  let defDoc = parseHtmlFromFile p
  for x in defDoc:
    if x.isElement:
      case x.tag
      of "template":
        result[x.attr"name"] = x 
      else: 
        raisev "only <template> is allowed in top level"


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
      else:        shallowCopy x
    else:          x

  map result, t, repl

func wrap(hashtags: seq[HashTag], templates): XmlNode = 
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

  
func newHtmlDoc: XmlNode = 
  newElement "html"

func renderHtml(n; templates): XmlNode = 
  proc repl(x): XmlNode =
    if x.isElement:
      case x.tag
      of "use":
        let  tname = x.attr"template"
        case tname
        of   "article"    : n.content
        of   "tags"       : n.hashtags.wrap(templates)
        of   "action_btns": raisev "no defined yet"
        else              : templates[tname]
      else                : shallowCopy x
    else                  : x
  
  result = newHtmlDoc()
  map result, templates["note-page"], repl

template xa(attrs): XmlAttributes = 
  toXmlAttributes attrs

func notesItemRows(notes: seq[Note]; templates): XmlNode = 
  result = newWrapper()

  for n in notes:
    let repl = capture n:
      proc (x): XmlNode =
        if x.isElement:
          case x.tag
          of   "slot": 
            case  x.attr"name"
            of    "title": newText n.content.findTitle
            of    "date" : newText "today"
            of    "tags" : newText "wtf"
            of    "score": newText "-"
            else         : raisev "invalid field"
          else           : shallowCopy x
        else             : x
      
    map result, templates["notes-page.note-item"], repl
    

func fnScores: XmlNode =
  result = newWrapper()

  for n in ["date", "by_date_passed", "failed_times"]:
    result.add newXmlTree("option", [newText n], xa {"value": n})

func `notes.html`(templates; notes: seq[Note]): XmlNode = 
  let t = templates["notes-page"]

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use":              templates[x.attr"template"]
      of    "score-fn-options": fnScores()
      of    "notes-rows":       notesItemRows(notes, templates)
      of    "notes-page-title": newText "Keeep" # XXX from config
      else:                     shallowCopy x
    else:                       x

  result = newHtmlDoc()
  map result, t, identityXml
  # notes table:
  #   different formuals forr scoring
  #   searchable
  #   show name, tag, time, score

func `index.html`(templates): XmlNode = 
  let t = templates["index-page"]

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use": templates[x.attr"template"]
      else:        shallowCopy x
    else:                      x

  result = newHtmlDoc()
  map result, t, identityXml

func `profile.html`(templates): XmlNode = 
  let t = templates["profile-page"]

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use": templates[x.attr"template"]
      else:        shallowCopy x
    else:                      x

  result = newHtmlDoc()
  map result, t, identityXml
  # config file "for base_url, site_name"
  #   export local DB
  #   import DB

proc genWebsite(templateDir, notesDir, saveDir, saveNoteDir: Path) = 
  let templates = loadHtmlTemplates templateDir
  var notes: seq[Note]
  
  for p in discover notesDir:
    echo "+ ", p
    let 
      doc   = parseHtmlFromFile p
      note  = initNote(doc, p)
      html  = renderHtml(note, templates)
      fname = extractFilename $p

    # TODO write time if not exists
    # TODO write id   if not exists

    add notes, note
    writeHtml saveNoteDir/fname, html

  echo "+ index.html"
  writeHtml saveDir/"index.html",    `index.html`(   templates)
  echo "+ notes.html"
  writeHtml saveDir/"notes.html",    `notes.html`(   templates, notes)
  echo "+ profile.html"
  writeHtml saveDir/"profile.html", `profile.html`(templates)

  # XXX copy frontend folder


when isMainModule:
  genWebsite Path "./templates.html", 
             Path "./notes", 
             Path "./dist",
             Path "./dist/notes"
