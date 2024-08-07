import std/[
  xmltree, 
  strutils, 
  times,
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

# ---------------------------------------

template `<<`(smth): untyped {.dirty.} =
  result.add smth

template raisev(msg): untyped {.dirty.} =
  raise newException(ValueError, msg)

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
  of 1: HashTag(name: tagLabel parts[0])
  of 2: HashTag(name: tagLabel parts[0], value: parts[1])
  else: raisev "cannot happen"

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
  if x.visit and x.isElement:
    for ent in x:
      dfs ent, visit

func findTitle(x): string = 
  var titles: seq[XmlNode]
  
  proc visit(n: XmlNode): bool = 
    if n.isElement and n.tag in "h1 h2 h3 h4 h5 h6":
      titles.add n
    true

  func tagCmp(a, b: XmlNode): int = 
    cmp a.tag[1], b.tag[1] # only compare number part - i.e. h[1] vs h[3]
  
  dfs x, visit
  sort titles, tagCmp, Ascending
  
  case  titles.len 
  of 0: raisev "cannot find any header tag"
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

when false:
  block config:
    configurable templates
    config file "for base_url, site_name"

  block pages:
    about
    settings:
      name
      export local DB
      import DB

    notes table:
      different formuals forr scoring
      searchable
      show name, tag, time, score

    note view:
      content
      buttuns forr remembering


when isMainModule:
  for p in discover Path "./notes":
    let html = parseHtmlFromFile p
    echo initNode html
