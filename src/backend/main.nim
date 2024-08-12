import std/[
  xmltree, 
  strutils, strformat, sequtils,
  times,
  tables, strtabs,
  os, paths, streams,
  algorithm, oids,
  sugar]

import pkg/htmlparser

# ---------------------------------------

type
  Html = distinct XmlNode

  HashTag* = object
    ## simple tag: #math
    ## data   tag: #page: 2
    name*, value*: string

  UnixTimestamp* = int

  NoteItem* = object
    id*       : string
    timestamp*: UnixTimestamp
    title*    : string
    path*     : Path
    hashtags* : seq[HashTag]


using 
  x: XmlNode
  p: Path
  s: string
  n: NoteItem
  templates: Table[string, XmlNode]

const 
  htmlPrefix  = "<!DOCTYPE html>"

func initHashTag(name, val: string): HashTag = 
  HashTag(name: name, value: val)

# ---------------------------------------

template str(smth): untyped =
  $smth

template `<<`(smth): untyped {.dirty.} =
  result.add  smth

template raisev(msg): untyped =
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


func getTemplate(templates; name: string): XmlNode = 
  if name in templates: templates[name]
  else: raisev "cannot find template: '" & name & "'"


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

func extractNoteElement(x): XmlNode = 
  if x.isElement:
    case x.tag
    of "document": # automatically generated tag for wrapping multiple tags
      for n in x:
        if n.isElement and n.tag == "note":
          return n
      raisev "cannot find <note> element"
    of "note": return x
    else     : raisev "the note should have at least these tags at the root: artice, tags"
  else       : raisev "provided node as XML is not element kind"


func articleElement(x): XmlNode = 
  for n in x:
    if n.isElement:
      case n.tag
      of "article": return n
      else        : discard

  raisev "cannot find <article> element"

func noteTags(x): seq[HashTag] = 
  for n in x:
    if n.isElement:
      case n.tag
      of "tags": return parseHashTags n.innerText
      else     : discard

  raisev "cannot find <tags> element"


func map(father: var XmlNode, src: XmlNode, mapper: proc(x: XmlNode): XmlNode) {.effectsOf: mapper.} = 
  if src.isWrapper:
    for n in src:
      map father, n, mapper
  
  else:
    var el = mapper src

    if el.isWrapper:
      map father, el, mapper

    else:
      add father, el

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
    
    for n in renderTemplate(templates.getTemplate"hashtag", ctx):
      << n
  
func newHtmlDoc: XmlNode = 
  newElement "html"

func renderNote(doc: XmlNode, note: NoteItem, templates): XmlNode =
  proc repl(x): XmlNode =
    if x.isElement:
      case x.tag
      of "use":
        let  tname = x.attr"template"
        case tname
        of   "title"      : newText note.title
        of   "article"    : doc.articleElement
        of   "tags"       : note.hashtags.wrap(templates)
        of   "action_btns": raisev "no defined yet"
        else              : templates.getTemplate tname
      else                : shallowCopy x
    else                  : x
  
  result = newHtmlDoc()
  map result, templates.getTemplate"note-page", repl

template xa(attrs): XmlAttributes = 
  toXmlAttributes attrs

func notesItemRows(notes: seq[NoteItem]; templates): XmlNode = 
  result = newWrapper()

  proc ctx(n; varname: string): string = 
    case varname
    of "link": "/notes/" & n.id & ".html"
    else     : raisev "invalid var: " & varname 

  for n in notes:
    let repl = capture n:
      proc (x): XmlNode =
        if x.isElement:
          case x.tag
          of   "slot": 
            case  x.attr"name"
            of    "title": newText n.title
            of    "date" : newText $n.timestamp
            of    "tags" : n.hashtags.wrap templates
            of    "score": newText "-"
            else         : raisev "invalid field"
          else           : 
            var newAttrs: seq[(string, string)]

            if not isNil x.attrs:
              for k, v in x.attrs:
                newAttrs.add:
                  if k[0] == ':': (k.substr 1, ctx(n, v))
                  else          : (k, v)
                  
            newXmlTree x.tag, [], xa newattrs

        else             : x
      
    map result, templates.getTemplate"notes-page.note-item", repl
    

func fnScores: XmlNode =
  result = newWrapper()

  for n in ["date", "by_date_passed", "failed_times"]:
    result.add newXmlTree("option", [newText n], xa {"value": n})

func `notes.html`(templates; notes: seq[NoteItem]): XmlNode = 
  let t = templates.getTemplate"notes-page"

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use"             : templates.getTemplate x.attr"template"
      of    "score-fn-options": fnScores()
      of    "notes-rows"      : notesItemRows(notes, templates)
      else                    : shallowCopy x
    else                      : x

  result = newHtmlDoc()
  map result, t, identityXml
  # notes table:
  #   different formuals forr scoring
  #   searchable
  #   show name, tag, time, score

func `index.html`(templates): XmlNode = 
  let t = templates.getTemplate"index-page"

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use": templates.getTemplate x.attr"template"
      else       : shallowCopy x
    else         : x

  result = newHtmlDoc()
  map result, t, identityXml

func `profile.html`(templates): XmlNode = 
  let t = templates.getTemplate"profile-page"

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use": templates.getTemplate x.attr"template"
      else       : shallowCopy x
    else         : x

  result = newHtmlDoc()
  map result, t, identityXml
  # config file "for base_url, site_name"
  #   export local DB
  #   import DB

proc genWebsite(templateDir, notesDir, saveDir, saveNoteDir: Path) = 
  let templates = loadHtmlTemplates templateDir
  
  var pathById: Table[string, Path] # id => file path
  var notes   : seq[NoteItem]
  
  template tamper(stmt): untyped = 
    isTampered = true
    stmt

  for p in discover notesDir:
    echo "+ ", p
    
    var isTampered   = false
    let doc          = extractNoteElement parseHtmlFromFile p
    let docId        = doc.attr"id"
    let docTimestamp = doc.attr"timestamp"
    let
      id = 
        if    docid == "": tamper(p.str.splitFile.name & '-' & $genOid())
        else: docid
      timestamp = 
        if docTimestamp == "": tamper toUnix toTime now()
        else                 : parseint docTimestamp

    if id in pathById:
      raisev "Error: Duplicated id! ids of " & $pathById[id] & " and " & $p & "are the same"
    else:
      pathById[id] = p

    let note = NoteItem(
        id       : id, 
        timestamp: timestamp, 
        path     : p,
        title    : findTitle doc, 
        hashtags : noteTags  doc)

    if isTampered:
      doc.attrs = xa {"id": id, "timestamp": $timestamp}
      writefile $p, $Html doc

    let path = saveNoteDir/(id & ".html")
    let html = renderNote(doc, note, templates)

    add notes, note
    writeHtml path, html 

  echo "+ index.html"
  writeHtml saveDir/"index.html",    `index.html`(templates)
  echo "+ notes.html"
  writeHtml saveDir/"notes.html",    `notes.html`(templates, notes)
  echo "+ profile.html"
  writeHtml saveDir/"profile.html", `profile.html`(templates)

  # XXX copy frontend folder

const 
  appname = "Keeep"
  help    = dedent fmt"""

    ..:: {appname} ::..

    Commands:
      - new    [dir path] creates new note in desired directory
      - build  [dir path] generates static HTML/CSS/JS files in desired directory
  """


when isMainModule:
  let params = commandLineParams()

  case params.len
  of 0: echo help
  else:
    case toLowerAscii params[0]
    of   "build":
      genWebsite Path "./templates.html", 
                 Path "./notes", 
                 Path "./dist",
                 Path "./dist/notes"
   
    of   "new":
      echo "not implemented"
    
    else:
      echo "Error: invalid command"
      echo help
      quit 1
