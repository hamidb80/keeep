import std/[
  xmltree,  json,
  strutils, strformat, sequtils,
  times,
  tables, strtabs,
  os, paths, streams,
  algorithm, oids,
  times,
  sugar]

import std/parsecfg
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

  AppConfig* = ref object
    baseUrl*      : string
    templateFile* : Path
    notesDir*     : Path
    buildDir*     : Path
    libsDir*      : Path
    

using 
  x: XmlNode
  p: Path
  s: string
  n: NoteItem
  templates: Table[string, XmlNode]

const 
  htmlPrefix  = "<!DOCTYPE html>"
  configPath = "./config.ini"
  appname = "Keeep"
  help    = dedent fmt"""

    ..:: {appname} ::..

    Commands:
        init                  Creates config file
        new   [path to note]  Creates new note in desired directory
        build                 Generates static HTML/CSS/JS files in desired directory
        watch                 watch chanes for a single note

    Usage:
        ./app  init

  """

  

func initHashTag(name, val: string): HashTag = 
  HashTag(name: name, value: val)

# ---------------------------------------

template str(smth): untyped =
  $smth

template xa(attrs): XmlAttributes = 
  toXmlAttributes attrs

template `<<`(smth): untyped {.dirty.} =
  result.add  smth

template raisev(msg): untyped =
  raise newException(ValueError, msg)

template iff(cond, iftrue, iffalse): untyped = 
  if cond: iftrue
  else   : iffalse

template xmlEscape(s): untyped =
  xmltree.escape s

# ---------------------------------------

template popd(l): untyped = 
  # pop and discard
  setLen l, l.high

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

func `%`(p): JsonNode = 
  % str p

proc rmdir(p) = 
  removeDir str p

proc mkdir(p) = 
  discard existsOrCreateDir str p

proc mkfile(p; content: sink string) = 
  let (dir, _) = splitPath p
  mkdir dir
  writeFile str p, content


func addExt(p; ext: string): Path = 
  ## adds file extention if missing
  if   p.str.endsWith ext:   p
  else               : Path $p & ext


proc cpdir(src, dest: Path) = 
  copyDir $src, $dest


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
    << xmlEscape x.text

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


proc findFilesWithExt(dir: Path, ext: string): seq[Path] = 
  for f in walkDirRec $dir:
    if f.endsWith ext:
      << Path f

proc loadHtmlTemplates(p): Table[string, XmlNode] = 
  let defDoc = parseHtmlFromFile p
  for x in defDoc:
    if x.isElement:
      case x.tag
      of "template":
        result[x.attr"name"] = x 
      else: 
        raisev "only <template> is allowed in top level of templates file"


func getTemplate(templates; name: string): XmlNode = 
  if name in templates: templates[name]
  else: raisev "cannot find the template: '" & name & "'"

template last(smth): untyped = 
  smth[^1]

func removeTrainOfSpaces(s): string = 
  var lastWasSpace = true
  for ch in s: 
    case ch
    of Whitespace: 
      if not lastWasSpace:
        << ' '
      lastWasSpace = true
    else:
      << ch
      lastWasSpace = false

  if result.last in Whitespace:
    popd result

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
  else: titles[0].innerText.removeTrainOfSpaces

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
  let t = templates.getTemplate"hashtag"
  
  for ht in hashtags:
    let ctx = capture ht:
      proc (k: string): XmlNode = 
        case k
        of "name" : newText ht.name
        of "value": newText ht.value
        # of "icon": newText ht.name
        else:      raisev "invalid property for hashtag render: " & k
    
    for n in renderTemplate(t, ctx):
      << n
  
func newHtmlDoc: XmlNode = 
  newElement "html"

func renderNote(doc: XmlNode, note: NoteItem, templates): XmlNode =
  proc ctx(key: string): string = 
    case key
    of   "note-id"  : note.id
    else            : raisev "invalid key: " & key 

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
        of   "note-id"    : newText note.id
        of   "note-path"  : newText $note.path
        of   "date"       : newText $note.timestamp
        else              : templates.getTemplate tname
      else                : 
        var newAttrs: seq[(string, string)]

        if not isNil x.attrs:
          for k, v in x.attrs:
            newAttrs.add:
              if k[0] == ':': (k.substr 1, ctx(v))
              else          : (k, v)
              
        newXmlTree x.tag, [], xa newattrs

    else                  : x
  
  result = newHtmlDoc()
  map result, templates.getTemplate"note-page", repl


func notesItemRows(notes: seq[NoteItem]; templates): XmlNode = 
  result = newWrapper()

  proc ctx(i: int, n: NoteItem, key: string): string = 
    case key
    of   "link"     : "@/notes/" & n.id & ".html"
    of   "index"    : $i
    of   "timestamp": $n.timestamp 
    of   "note-id"  : n.id
    else            : raisev "invalid key: " & key 

  for i, n in notes:
    let repl = capture n:
      proc (x): XmlNode =
        if x.isElement:
          case x.tag
          of   "note-json" : newXmlTree("data", [newText str %n], xa {"note-data": "", "index": $i, "hidden": ""})
          of   "slot": 
            case  x.attr"name"
            of    "title"     : newText n.title
            of    "timestamp" : newText $n.timestamp
            of    "tags"      : n.hashtags.wrap templates
            of    "score"     : newText "-"
            else              : raisev "invalid field"
          else                : 
            var newAttrs: seq[(string, string)]

            if not isNil x.attrs:
              for k, v in x.attrs:
                newAttrs.add:
                  if k[0] == ':': (k.substr 1, ctx(i, n, v))
                  else          : (k, v)
                  
            newXmlTree x.tag, [], xa newattrs

        else             : x
      
    map result, templates.getTemplate"note-item", repl
    

func `notes.html`(templates; notes: seq[NoteItem], suggestedTags: seq[HashTag]): XmlNode = 
  let t = templates.getTemplate"notes-page"

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use"             : templates.getTemplate x.attr"template"
      of    "notes-rows"      : notesItemRows(notes, templates)
      of    "tags-by-usage"   : suggestedTags.wrap templates
      else                    : shallowCopy x
    else                      : x

  result = newHtmlDoc()
  map result, t, identityXml

func `index.html`(templates): XmlNode = 
  let t = templates.getTemplate"index-page"

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use"          : templates.getTemplate x.attr"template"
      else                 : shallowCopy x
    else                   : x

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

func `info.html`(templates; tagsCount: CountTable[string]): XmlNode = 
  let t = templates.getTemplate"info-page"

  func identityXml(x): XmlNode = 
    if x.isElement: 
      case  x.tag
      of    "use": templates.getTemplate x.attr"template"
      else       : shallowCopy x
    else         : x

  result = newHtmlDoc()
  map result, t, identityXml

proc fixUrlsImpl(relPath: Path, baseUrl: string, x: XmlNode) = 
  if x.isElement:
    if not isNil x.attrs:
      for k, v in x.attrs:
        x.attrs[k] =
          if   v.startsWith "@/" : baseUrl &                       (v.substr 2)
          elif v.startsWith "./" : baseUrl / "assets" / $relPath / (v.substr 3)
          else                   : continue


    for n in x:
      fixUrlsImpl relPath, baseUrl, n

func fixUrls(relPath: Path, baseUrl: string, x: sink XmlNode): XmlNode = 
  fixUrlsImpl relPath, baseUrl, x
  x

proc genWebsite(templates; config: AppConfig, notesPaths: seq[Path], demo: bool) =
  let 
    saveDir      = config.buildDir
    saveNoteDir  = saveDir / "notes"
    saveLibsDir  = saveDir / "libs"
    saveAssetDir = saveDir / "assets"

  var 
    notes     : seq[NoteItem]
    pathById  = initTable[string, Path]()
    tagsCount = initCountTable[string]()
  
  if not demo: # prepare
    mkdir saveNoteDir
    cpdir config.notesDir, saveAssetDir
    cpdir config.libsDir , saveLibsDir

  for p in notesPaths:
    echo "+ ", p

    var isTampered   = false
    template tamper(stmt): untyped = 
      isTampered = true
      stmt
    
    let 
      doc          = extractNoteElement parseHtmlFromFile p
      docId        = doc.attr"id"
      docTimestamp = doc.attr"timestamp"
      id = 
        if    docid == "": tamper (p.str.splitFile.name & '-' & $genOid())
        else: docid
      timestamp = 
        if docTimestamp == "": tamper toUnix toTime now()
        else                 : parseint docTimestamp
      note = NoteItem(
        id       : id, 
        timestamp: timestamp, 
        path     : p,
        title    : findTitle doc, 
        hashtags : noteTags  doc)
      path = saveNoteDir / (id & ".html")
      html = fixUrls( relativePath(parentDir p, config.notesDir),
                      config.baseUrl, 
                      renderNote(doc, note, templates))

    if id in pathById:
      raisev "Error: Duplicated id! ids of " & $pathById[id] & " and " & $p & "are the same"
    else:
      pathById[id] = p

    for t in note.hashtags:
      inc tagsCount, t.name

    if isTampered:
      doc.attrs = xa {"id": id, "timestamp": $timestamp}
      writefile $p, $Html doc

    add notes, note
    writeHtml path, html 

  if not demo: # otherPages
    sort tagsCount
    let suggestedTags = tagsCount.keys.toseq.mapit initHashTag(it, "")

    echo "+ index.html"
    writeHtml saveDir/"index.html",    fixUrls(Path"", config.baseUrl, `index.html`(templates))
    echo "+ notes.html"
    writeHtml saveDir/"notes.html",    fixUrls(Path"", config.baseUrl, `notes.html`(templates, notes, suggestedTags))
    echo "+ profile.html"
    writeHtml saveDir/"profile.html",  fixUrls(Path"", config.baseUrl, `profile.html`(templates))
    # TODO info page -- tags, number of usages of tags, diagrams, ...
    echo "+ info.html"
    writeHtml saveDir/"info.html",     fixUrls(Path"", config.baseUrl, `info.html`(templates, tagsCount))


func toAppConfig(cfg: Config): AppConfig =
  proc gsv(namespace, key: string): string = 
    getSectionValue(cfg, namespace, key)
  
  AppConfig(
    baseUrl      :      gsv("",      "base_url"),

    templateFile : Path gsv("paths", "template_file"),
    notesDir     : Path gsv("paths", "notes_dir"),
    buildDir     : Path gsv("paths", "build_dir"),
    libsDir      : Path gsv("paths", "libs_dir"),
  )

# TODO RSS for all tags, and some specific tags stated in the config file
# TODO name mangle config.libsDir
# TODO download deps

when isMainModule:
  let params = commandLineParams()

  case params.len
  of 0: echo help
  else:

    if fileExists configPath:
      let config = toAppConfig loadConfig configPath
      echo config[]
      
      case toLowerAscii params[0]
      of "clean":
        echo ">>>> removing ", config.buildDir
        rmdir config.buildDir

      of "build":
        echo ">>>> creating ", config.buildDir
        mkdir                  config.buildDir
        
        echo ">>>> copying libraries"
        echo ">>>> generating HTML files"
        
        let        templates  =       loadHtmlTemplates config.templateFile
        genWebsite templates, config, findFilesWithExt(config.notesDir, ".html"), false

      of "watch":
        echo ">>>> generating HTML file of desired note"
        let        
          templates  = loadHtmlTemplates config.templateFile
          fpath      = Path params[1]

        var lastModif: Time
        while true:
          let t = getLastModificationTime str fpath
          if lastModif < t:
             lastModif = t
             genWebsite templates, config, @[fpath], true
          sleep 100

      of "init":
        echo "download necessary files from: ..."
          
      of "new":
        let    notePath = addExt(config.notesDir / params[1], ".html")
        mkfile notePath, readfile "/frontend/blueprint.html"
        echo "new note created in: ", $notePath
          
      else:
        echo "Error: Invalid command: '", params[0], "'"
        echo help
        quit 1

    else:
      raisev "the config file does not exist: " & configPath
