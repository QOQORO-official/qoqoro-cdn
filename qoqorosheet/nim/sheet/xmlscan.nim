## A small pull scanner for the XML inside .xlsx packages: start/end tags
## with attributes, text with entities decoded, CDATA; comments, processing
## instructions and doctypes are skipped. Namespace prefixes are dropped from
## element and attribute names ("x:c" -> "c"), which is all SpreadsheetML needs.

import std/strutils

type
  XmlKind* = enum xkStart, xkEnd, xkText, xkEof
  XmlScanner* = object
    s: string
    i: int
    kind*: XmlKind
    name*: string                     ## element name (start/end)
    attrs*: seq[(string, string)]
    selfClosing*: bool                ## <x/> (an xkEnd for it follows)
    text*: string                     ## xkText
    pendingEnd: bool

proc initXml*(s: string): XmlScanner = XmlScanner(s: s)

proc localName(n: string): string =
  let c = n.rfind(':')
  if c >= 0: n[c + 1 .. ^1] else: n

proc decodeEntities*(s: string): string =
  if '&' notin s: return s
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '&':
      let semi = s.find(';', i)
      if semi > i and semi - i <= 10:
        let ent = s[i + 1 ..< semi]
        var ok = true
        case ent
        of "amp": result.add '&'
        of "lt": result.add '<'
        of "gt": result.add '>'
        of "quot": result.add '"'
        of "apos": result.add '\''
        else:
          if ent.len > 1 and ent[0] == '#':
            try:
              let code = if ent[1] in {'x', 'X'}: parseHexInt(ent[2 .. ^1]) else: parseInt(ent[1 .. ^1])
              # UTF-8 encode
              if code < 0x80: result.add char(code)
              elif code < 0x800:
                result.add char(0xC0 or (code shr 6)); result.add char(0x80 or (code and 0x3F))
              elif code < 0x10000:
                result.add char(0xE0 or (code shr 12)); result.add char(0x80 or ((code shr 6) and 0x3F)); result.add char(0x80 or (code and 0x3F))
              else:
                result.add char(0xF0 or (code shr 18)); result.add char(0x80 or ((code shr 12) and 0x3F))
                result.add char(0x80 or ((code shr 6) and 0x3F)); result.add char(0x80 or (code and 0x3F))
            except ValueError: ok = false
          else: ok = false
        if ok:
          i = semi + 1
          continue
    result.add s[i]
    inc i

proc escapeXml*(s: string, attr = false): string =
  result = newStringOfCap(s.len + 8)
  for ch in s:
    case ch
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': (if attr: result.add "&quot;" else: result.add ch)
    of '\n': (if attr: result.add "&#10;" else: result.add ch)
    of '\r': (if attr: result.add "&#13;" else: result.add ch)
    of '\t': (if attr: result.add "&#9;" else: result.add ch)
    else:
      if ord(ch) < 0x20: discard          # not allowed in XML 1.0
      else: result.add ch

proc next*(x: var XmlScanner) =
  if x.pendingEnd:
    x.pendingEnd = false
    x.kind = xkEnd
    x.attrs.setLen(0)
    return
  let s = x.s
  while true:
    if x.i >= s.len:
      x.kind = xkEof; return
    if s[x.i] != '<':
      let j = s.find('<', x.i)
      let stop = if j < 0: s.len else: j
      x.kind = xkText
      x.text = decodeEntities(s[x.i ..< stop])
      x.i = stop
      return
    # markup
    if s.continuesWith("<!--", x.i):
      let j = s.find("-->", x.i + 4)
      x.i = if j < 0: s.len else: j + 3
      continue
    if s.continuesWith("<![CDATA[", x.i):
      let j = s.find("]]>", x.i + 9)
      let stop = if j < 0: s.len else: j
      x.kind = xkText
      x.text = s[x.i + 9 ..< stop]
      x.i = if j < 0: s.len else: j + 3
      return
    if x.i + 1 < s.len and s[x.i + 1] in {'?', '!'}:
      let j = s.find('>', x.i)
      x.i = if j < 0: s.len else: j + 1
      continue
    if x.i + 1 < s.len and s[x.i + 1] == '/':
      let j = s.find('>', x.i)
      x.kind = xkEnd
      x.name = localName(s[x.i + 2 ..< (if j < 0: s.len else: j)].strip)
      x.attrs.setLen(0)
      x.i = if j < 0: s.len else: j + 1
      return
    # start tag
    var j = x.i + 1
    while j < s.len and s[j] notin {' ', '\t', '\r', '\n', '/', '>'}: inc j
    x.kind = xkStart
    x.name = localName(s[x.i + 1 ..< j])
    x.attrs.setLen(0)
    x.selfClosing = false
    while j < s.len:
      while j < s.len and s[j] in {' ', '\t', '\r', '\n'}: inc j
      if j >= s.len: break
      if s[j] == '>': inc j; break
      if s[j] == '/':
        x.selfClosing = true
        let k = s.find('>', j)
        j = if k < 0: s.len else: k + 1
        break
      let ns = j
      while j < s.len and s[j] notin {'=', ' ', '\t', '\r', '\n', '>', '/'}: inc j
      let an = localName(s[ns ..< j])
      while j < s.len and s[j] in {' ', '\t', '\r', '\n'}: inc j
      var av = ""
      if j < s.len and s[j] == '=':
        inc j
        while j < s.len and s[j] in {' ', '\t', '\r', '\n'}: inc j
        if j < s.len and s[j] in {'"', '\''}:
          let q = s[j]
          let k = s.find(q, j + 1)
          let stop = if k < 0: s.len else: k
          av = decodeEntities(s[j + 1 ..< stop])
          j = stop + 1
      x.attrs.add (an, av)
    x.i = j
    if x.selfClosing: x.pendingEnd = true
    return

proc attr*(x: XmlScanner, name: string, default = ""): string =
  for (k, v) in x.attrs:
    if k == name: return v
  default

proc hasAttr*(x: XmlScanner, name: string): bool =
  for (k, _) in x.attrs:
    if k == name: return true
  false

proc readText*(x: var XmlScanner): string =
  ## The text content of the element just started (nested markup ignored),
  ## leaving the scanner on its end tag.
  if x.selfClosing:
    x.next()              # its synthetic end
    return ""
  var depth = 1
  while depth > 0:
    x.next()
    case x.kind
    of xkText: result.add x.text
    of xkStart: inc depth
    of xkEnd: dec depth
    of xkEof: return
