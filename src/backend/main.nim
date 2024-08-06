import std/[xmlparser, xmltree, strtabs, os, strutils]


proc discover: seq[Path] = 
  for f in walkDirRec "./":
    if f.endsWith ".html":
      add htmlFiles, f


# parse