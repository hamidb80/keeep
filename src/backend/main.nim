import std/[xmlparser, xmltree, strtabs, os, strutils]


proc discover: seq[Path] = 
  for f in walkDirRec "./":
    if f.endsWith ".html":
      add htmlFiles, f


# parse


find "<article ..."
find "<tags ..."

find "<time" if not, fill time

find title inside rticles

configurable templates
config file for base_url, site_name, ...


page:
  about
  settings
    name
    export local DB
    import DB

  notes table:
    - different formuals for scoring
    - searchable
    - show name, tag, time, score

  note view:
    - content
    - buttuns for remembering
  
