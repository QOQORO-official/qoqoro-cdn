## .xlsx and .csv in Nim: read a workbook from bytes, write one back.
##
## Reading covers what QoqoroSheet models: shared strings and rich text,
## numbers, booleans, errors, formulas (shared formulas expanded), cell styles
## (font, colour, fill, number format, alignment, wrap), column widths, row
## heights and the active sheet. Writing produces a complete package with the
## same styles, deflate-compressed.

import std/[tables, strutils, math, algorithm]
import model, formula, xmlscan
import ../nimdocx/[ziparchive, pngenc]

type XlsxError* = object of ValueError

# ------------------------------------------------------------------ colours --

const ThemeColors = ["FFFFFF", "000000", "E7E6E6", "44546A", "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47"]
const IndexedColors = ["000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
  "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
  "800000", "008000", "000080", "808000", "800080", "008080", "C0C0C0", "808080",
  "9999FF", "993366", "FFFFCC", "CCFFFF", "660066", "FF8080", "0066CC", "CCCCFF",
  "000080", "FF00FF", "FFFF00", "00FFFF", "800080", "800000", "008080", "0000FF",
  "00CCFF", "CCFFFF", "CCFFCC", "FFFF99", "99CCFF", "FF99CC", "CC99FF", "FFCC99",
  "3366FF", "33CCCC", "99CC00", "FFCC00", "FF9900", "FF6600", "666699", "969696",
  "003366", "339966", "003300", "333300", "993300", "993366", "333399", "333333"]

proc applyTint(hex: string, tint: float64): string =
  if tint == 0 or hex.len != 6: return hex
  result = ""
  for i in 0 ..< 3:
    var c = float64(parseHexInt(hex[i * 2 .. i * 2 + 1]))
    c = if tint < 0: c * (1 + tint) else: c + (255 - c) * tint
    result.add toHex(clamp(int(round(c)), 0, 255), 2)

proc colorOf(x: XmlScanner): string =
  ## "#RRGGBB" from an rgb / theme / indexed colour element, "" for auto.
  if x.hasAttr("rgb"):
    let v = x.attr("rgb")
    if v.len >= 6: return "#" & v[^6 .. ^1].toUpperAscii
  let tint = try: parseFloat(x.attr("tint", "0")) except ValueError: 0.0
  if x.hasAttr("theme"):
    let t = try: parseInt(x.attr("theme")) except ValueError: -1
    if t in 0 .. ThemeColors.high: return "#" & applyTint(ThemeColors[t], tint)
  if x.hasAttr("indexed"):
    let n = try: parseInt(x.attr("indexed")) except ValueError: -1
    if n in 0 .. IndexedColors.high: return "#" & applyTint(IndexedColors[n], tint)
  ""

# --------------------------------------------------------------- number fmts --

proc builtinFormat(id: int): string =
  case id
  of 0: ""
  of 1: "0"
  of 2: "0.00"
  of 3: "#,##0"
  of 4: "#,##0.00"
  of 9: "0%"
  of 10: "0.00%"
  of 11: "0.00E+00"
  of 12: "# ?/?"
  of 13: "# ??/??"
  of 14: "m/d/yyyy"
  of 15: "d-mmm-yy"
  of 16: "d-mmm"
  of 17: "mmm-yy"
  of 18: "h:mm AM/PM"
  of 19: "h:mm:ss AM/PM"
  of 20: "h:mm"
  of 21: "h:mm:ss"
  of 22: "m/d/yyyy h:mm"
  of 37: "#,##0 ;(#,##0)"
  of 38: "#,##0 ;[Red](#,##0)"
  of 39: "#,##0.00;(#,##0.00)"
  of 40: "#,##0.00;[Red](#,##0.00)"
  of 45: "mm:ss"
  of 46: "[h]:mm:ss"
  of 47: "mmss.0"
  of 48: "##0.0E+0"
  of 49: "@"
  else: ""

proc builtinId(code: string): int =
  for id in [1, 2, 3, 4, 9, 10, 11, 14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47, 49]:
    if builtinFormat(id) == code: return id
  -1

# ------------------------------------------------------------------- reading --

type
  FontInfo = object
    bold, italic, underline, strike: bool
    size: float64
    name, color: string

proc readStyles(xml: string): seq[Style] =
  ## One Style per cellXfs entry (the `s` index of a cell).
  var fmts = initTable[int, string]()
  var fonts: seq[FontInfo]
  var fills: seq[string]
  var borders: seq[array[4, Border]]       # left, right, top, bottom
  var curBorder: array[4, Border]
  var side = -1
  var x = initXml(xml)
  var section = ""
  var curFont: FontInfo
  var curFill = ""
  var inPattern = false
  var cur: Style
  var inXf = false
  while true:
    x.next()
    case x.kind
    of xkEof: break
    of xkStart:
      case x.name
      of "numFmt":
        let id = try: parseInt(x.attr("numFmtId")) except ValueError: -1
        if id >= 0: fmts[id] = x.attr("formatCode")
      of "fonts", "fills", "cellXfs", "cellStyleXfs", "borders", "dxfs": section = x.name
      of "font":
        if section == "fonts": curFont = FontInfo()
      of "b": (if section == "fonts": curFont.bold = x.attr("val", "1") notin ["0", "false"])
      of "i": (if section == "fonts": curFont.italic = x.attr("val", "1") notin ["0", "false"])
      of "u": (if section == "fonts": curFont.underline = x.attr("val", "single") != "none")
      of "strike": (if section == "fonts": curFont.strike = x.attr("val", "1") notin ["0", "false"])
      of "sz": (if section == "fonts": curFont.size = (try: parseFloat(x.attr("val")) except ValueError: 0.0))
      of "name": (if section == "fonts": curFont.name = x.attr("val"))
      of "color":
        if section == "fonts": curFont.color = colorOf(x)
        elif section == "borders" and side >= 0:
          let c = colorOf(x)
          if c != "#000000": curBorder[side].color = c
      of "fill": (if section == "fills": curFill = "")
      of "border": (if section == "borders": curBorder = default(array[4, Border]))
      of "left", "start", "right", "end", "top", "bottom":
        if section == "borders":
          side = case x.name
            of "left", "start": 0
            of "right", "end": 1
            of "top": 2
            else: 3
          let kind = case x.attr("style")
            of "thin": bkThin
            of "medium", "mediumDashed", "mediumDashDot", "mediumDashDotDot", "slantDashDot": bkMedium
            of "thick": bkThick
            of "dashed", "dashDot", "dashDotDot": bkDashed
            of "dotted": bkDotted
            of "double": bkDouble
            of "hair": bkHair
            else: bkNone
          curBorder[side] = Border(kind: kind)
          if x.selfClosing: side = -1
      of "patternFill":
        if section == "fills": inPattern = x.attr("patternType", "none") notin ["none", "gray125"]
      of "fgColor": (if section == "fills" and inPattern: curFill = colorOf(x))
      of "xf":
        if section == "cellXfs":
          inXf = true
          cur = Style()
          let fontId = try: parseInt(x.attr("fontId", "0")) except ValueError: 0
          let fillId = try: parseInt(x.attr("fillId", "0")) except ValueError: 0
          let fmtId = try: parseInt(x.attr("numFmtId", "0")) except ValueError: 0
          if fontId > 0 and fontId < fonts.len:
            let f = fonts[fontId]
            let base = fonts[0]
            cur.bold = f.bold; cur.italic = f.italic; cur.underline = f.underline; cur.strike = f.strike
            if f.size > 0 and f.size != base.size: cur.fontSize = f.size
            if f.name.len > 0 and f.name != base.name: cur.font = f.name
            if f.color.len > 0 and f.color != "#000000" and f.color != base.color: cur.color = f.color
          elif fonts.len > 0:
            let f = fonts[0]
            cur.bold = f.bold; cur.italic = f.italic
          if fillId >= 2 and fillId < fills.len: cur.fill = fills[fillId]
          let borderId = try: parseInt(x.attr("borderId", "0")) except ValueError: 0
          if borderId > 0 and borderId < borders.len:
            let b = borders[borderId]
            cur.left = b[0]; cur.right = b[1]; cur.top = b[2]; cur.bottom = b[3]
          cur.numFmt = fmts.getOrDefault(fmtId, builtinFormat(fmtId))
          if cur.numFmt == "General": cur.numFmt = ""
          if x.selfClosing:
            result.add cur; inXf = false
      of "alignment":
        if inXf:
          case x.attr("horizontal")
          of "left": cur.hAlign = haLeft
          of "center", "centerContinuous": cur.hAlign = haCenter
          of "right": cur.hAlign = haRight
          else: discard
          case x.attr("vertical", "bottom")
          of "top": cur.vAlign = vaTop
          of "center": cur.vAlign = vaMiddle
          else: discard
          cur.wrap = x.attr("wrapText") in ["1", "true"]
      else: discard
    of xkEnd:
      case x.name
      of "font": (if section == "fonts": fonts.add curFont)
      of "fill": (if section == "fills": fills.add curFill)
      of "border": (if section == "borders": borders.add curBorder)
      of "left", "start", "right", "end", "top", "bottom": side = -1
      of "patternFill": inPattern = false
      of "xf":
        if inXf: result.add cur; inXf = false
      of "fonts", "fills", "cellXfs", "cellStyleXfs", "borders", "dxfs": section = ""
      else: discard
    else: discard

proc readSharedStrings(xml: string): seq[string] =
  var x = initXml(xml)
  var cur = ""
  var inSi, inT, inPh = false
  while true:
    x.next()
    case x.kind
    of xkEof: break
    of xkStart:
      case x.name
      of "si": inSi = true; cur = ""
      of "t": inT = not x.selfClosing
      of "rPh": inPh = true
      else: discard
    of xkText:
      if inSi and inT and not inPh: cur.add x.text
    of xkEnd:
      case x.name
      of "si": result.add cur; inSi = false
      of "t": inT = false
      of "rPh": inPh = false
      else: discard
    else: discard

proc parseRef(s: string): (int, int) =
  ## "B12" -> (11, 1)
  var i = 0
  var col = 0
  while i < s.len and s[i] in Letters:
    col = col * 26 + (ord(toUpperAscii(s[i])) - ord('A') + 1); inc i
  let row = try: parseInt(s[i .. ^1]) except ValueError: 0
  (row - 1, col - 1)

proc resolvePath(base, target: string): string =
  ## A relationship target relative to xl/.
  if target.startsWith("/"): return target[1 .. ^1]
  var parts = base.split('/')
  if parts.len > 0: parts.setLen(parts.len - 1)
  for p in target.split('/'):
    if p == "..":
      if parts.len > 0: parts.setLen(parts.len - 1)
    elif p != "." and p.len > 0: parts.add p
  parts.join("/")

proc readSheet(wb: Workbook, s: Sheet, xml: string, strings: seq[string], styleMap: seq[int32]) =
  var x = initXml(xml)
  var shared = initTable[string, (int, int, string)]()   # si -> (row, col, formula)
  var r, c = 0
  var t = ""
  var styleIx = 0
  var v = ""
  var f = ""
  var fShared = ""
  var fRef = ""
  var hasV, hasF = false
  var inIs = false
  var nextRow = 0
  var nextCol = 0
  while true:
    x.next()
    case x.kind
    of xkEof: break
    of xkStart:
      case x.name
      of "col":
        let mn = (try: parseInt(x.attr("min")) except ValueError: 0) - 1
        let mx = (try: parseInt(x.attr("max")) except ValueError: 0) - 1
        let w = try: parseFloat(x.attr("width")) except ValueError: 0.0
        if mn >= 0 and w > 0 and mx - mn < 2000:
          let px = round(w * 7 + 5)
          for i in mn .. min(mx, MaxCols - 1): s.colWidths[i] = if x.attr("hidden") in ["1", "true"]: 0.1 else: px
      of "row":
        let rr = (try: parseInt(x.attr("r", $(nextRow + 1))) except ValueError: nextRow + 1) - 1
        nextRow = rr + 1
        nextCol = 0
        if x.attr("customHeight") in ["1", "true"] or x.hasAttr("ht"):
          let ht = try: parseFloat(x.attr("ht")) except ValueError: 0.0
          if ht > 0 and abs(ht * 4 / 3 - DefaultRowHeight) > 0.6: s.rowHeights[rr] = round(ht * 4 / 3)
        if x.attr("hidden") in ["1", "true"]: s.rowHeights[rr] = 0.1
      of "c":
        if x.hasAttr("r"): (r, c) = parseRef(x.attr("r"))
        else: r = nextRow - 1; c = nextCol
        nextCol = c + 1
        t = x.attr("t", "n")
        styleIx = try: parseInt(x.attr("s", "0")) except ValueError: 0
        v = ""; f = ""; fShared = ""; fRef = ""; hasV = false; hasF = false
        if x.selfClosing:
          # a styled empty cell
          let st = if styleIx < styleMap.len: styleMap[styleIx] else: 0'i32
          if st != 0 and r >= 0 and c >= 0 and r < MaxRows and c < MaxCols: s.putCell(r, c, Cell(style: st))
      of "v": v = x.readText(); hasV = true
      of "f":
        let kind = x.attr("t")
        if kind == "shared": fShared = x.attr("si"); fRef = x.attr("ref")
        f = x.readText(); hasF = true
      of "is": inIs = true
      of "mergeCell":
        let parts = x.attr("ref").split(':')
        if parts.len == 2:
          let (r1, c1) = parseRef(parts[0])
          let (r2, c2) = parseRef(parts[1])
          if r1 >= 0 and c1 >= 0 and r2 >= r1 and c2 >= c1: s.addMerge(Merge(r1: r1, c1: c1, r2: r2, c2: c2))
      of "t":
        if inIs: v.add x.readText(); hasV = true
      else: discard
    of xkEnd:
      case x.name
      of "is": inIs = false
      of "c":
        if r < 0 or c < 0 or r >= MaxRows or c >= MaxCols: continue
        var cell = Cell(style: if styleIx < styleMap.len: styleMap[styleIx] else: 0'i32)
        if hasF and fShared.len > 0:
          if f.len > 0: shared[fShared] = (r, c, f)
          elif shared.hasKey(fShared):
            let (mr, mc, mf) = shared[fShared]
            f = shiftFormula("=" & mf, r - mr, c - mc)[1 .. ^1]
        if hasV:
          case t
          of "s":
            let i = try: parseInt(v.strip) except ValueError: -1
            cell.value = if i >= 0 and i < strings.len: strVal(strings[i]) else: strVal("")
          of "str", "inlineStr": cell.value = strVal(v)
          of "b": cell.value = boolVal(v.strip == "1")
          of "e": cell.value = errVal(v.strip)
          else:
            try: cell.value = numVal(parseFloat(v.strip))
            except ValueError: cell.value = strVal(v)
        if hasF and f.len > 0:
          let cached = cell.value
          cell.setFormula("=" & f)
          cell.value = cached
        if cell.value.kind == vkStr and cell.value.str.len == 0 and cell.formula.len == 0: cell.value = emptyVal()
        s.putCell(r, c, cell)
      else: discard
    else: discard

proc readXlsx*(data: string): Workbook =
  var z: ZipArchive
  try: z = openZipBytes(data)
  except CatchableError as e: raise newException(XlsxError, "Not an .xlsx file (" & e.msg & ")")
  if not z.hasEntry("xl/workbook.xml"): raise newException(XlsxError, "Not an .xlsx file: no xl/workbook.xml")
  let wb = newWorkbook()
  # relationships
  var rels = initTable[string, string]()
  var x = initXml(z.tryReadEntry("xl/_rels/workbook.xml.rels"))
  var stylesPath = "xl/styles.xml"
  var stringsPath = "xl/sharedStrings.xml"
  while true:
    x.next()
    if x.kind == xkEof: break
    if x.kind == xkStart and x.name == "Relationship":
      let target = resolvePath("xl/workbook.xml", x.attr("Target"))
      rels[x.attr("Id")] = target
      let typ = x.attr("Type")
      if typ.endsWith("/styles"): stylesPath = target
      elif typ.endsWith("/sharedStrings"): stringsPath = target
  let strings = readSharedStrings(z.tryReadEntry(stringsPath))
  var styleMap: seq[int32]
  for st in readStyles(z.tryReadEntry(stylesPath)): styleMap.add wb.styleId(st)
  # sheets in workbook order
  x = initXml(z.readEntry("xl/workbook.xml"))
  var active = 0
  var sheets: seq[(string, string)]
  while true:
    x.next()
    if x.kind == xkEof: break
    if x.kind == xkStart:
      if x.name == "workbookView": active = try: parseInt(x.attr("activeTab", "0")) except ValueError: 0
      elif x.name == "sheet": sheets.add (x.attr("name"), rels.getOrDefault(x.attr("id"), ""))
  for (name, path) in sheets:
    let s = wb.addSheet(if name.len > 0: name else: "Sheet" & $(wb.sheets.len + 1))
    if path.len > 0 and z.hasEntry(path): readSheet(wb, s, z.readEntry(path), strings, styleMap)
  if wb.sheets.len == 0: discard wb.addSheet("Sheet1")
  wb.active = clamp(active, 0, wb.sheets.len - 1)
  wb

# ------------------------------------------------------------------- writing --

var crcTable: array[256, uint32]
proc initCrc() =
  if crcTable[1] != 0: return
  for n in 0 ..< 256:
    var c = uint32(n)
    for _ in 0 ..< 8: c = if (c and 1) != 0: 0xEDB88320'u32 xor (c shr 1) else: c shr 1
    crcTable[n] = c

proc crc32(data: string): uint32 =
  initCrc()
  var c = 0xFFFFFFFF'u32
  for ch in data: c = crcTable[(c xor uint32(ord(ch))) and 0xFF] xor (c shr 8)
  not c

proc u16(s: var string, v: int) =
  s.add char(v and 0xFF); s.add char((v shr 8) and 0xFF)
proc u32(s: var string, v: uint32) =
  for shift in [0, 8, 16, 24]: s.add char((v shr shift) and 0xFF)

proc writeZipDeflated*(files: openArray[(string, string)]): string =
  ## A ZIP with each entry deflated (stored when that is not smaller).
  var central = ""
  for (name, data) in files:
    let offset = uint32(result.len)
    let crc = crc32(data)
    var packed = if data.len > 64: deflateFixed(data) else: ""
    var meth = 8
    if packed.len == 0 or packed.len >= data.len: packed = data; meth = 0
    result.u32(0x04034b50); result.u16(20); result.u16(0x800); result.u16(meth)
    result.u16(0); result.u16(0x21); result.u32(crc)
    result.u32(uint32(packed.len)); result.u32(uint32(data.len))
    result.u16(name.len); result.u16(0); result.add name; result.add packed
    central.u32(0x02014b50); central.u16(20); central.u16(20); central.u16(0x800); central.u16(meth)
    central.u16(0); central.u16(0x21); central.u32(crc)
    central.u32(uint32(packed.len)); central.u32(uint32(data.len))
    central.u16(name.len); central.u16(0); central.u16(0); central.u16(0); central.u16(0); central.u32(0)
    central.u32(offset); central.add name
  let cdOffset = uint32(result.len)
  result.add central
  result.u32(0x06054b50); result.u16(0); result.u16(0); result.u16(files.len); result.u16(files.len)
  result.u32(uint32(central.len)); result.u32(cdOffset); result.u16(0)

proc numText(x: float64): string =
  ## Full precision, as Excel stores it.
  if x == trunc(x) and abs(x) < 1e15: $int64(x) else: $x

proc hex8(color: string): string =
  var c = color.strip(chars = {'#'})
  if c.len == 3: c = $c[0] & c[0] & c[1] & c[1] & c[2] & c[2]
  if c.len != 6: return "FF000000"
  "FF" & c.toUpperAscii

proc writeXlsx*(wb: Workbook): string =
  # styles: one xf per workbook style, same index
  var fonts: seq[string] = @["<font><sz val=\"10\"/><name val=\"Arial\"/></font>"]
  var fontIx = initTable[string, int]()
  var fills: seq[string] = @["<fill><patternFill patternType=\"none\"/></fill>", "<fill><patternFill patternType=\"gray125\"/></fill>"]
  var fillIx = initTable[string, int]()
  var borders: seq[string] = @["<border><left/><right/><top/><bottom/><diagonal/></border>"]
  var borderIx = initTable[string, int]()
  var customFmts: seq[(int, string)]
  var fmtIx = initTable[string, int]()
  var xfs = ""
  for st in wb.styles:
    var font = "<font>"
    if st.bold: font.add "<b/>"
    if st.italic: font.add "<i/>"
    if st.strike: font.add "<strike/>"
    if st.underline: font.add "<u/>"
    font.add "<sz val=\"" & $(if st.fontSize > 0: st.fontSize else: 10.0) & "\"/>"
    if st.color.len > 0: font.add "<color rgb=\"" & hex8(st.color) & "\"/>"
    font.add "<name val=\"" & escapeXml(if st.font.len > 0: st.font else: "Arial", true) & "\"/></font>"
    var fi = fontIx.getOrDefault(font, -1)
    if fi < 0:
      fi = if font == fonts[0]: 0 else: fonts.len
      if fi == fonts.len: fonts.add font
      fontIx[font] = fi
    var fl = 0
    if st.fill.len > 0:
      let fill = "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"" & hex8(st.fill) & "\"/><bgColor indexed=\"64\"/></patternFill></fill>"
      fl = fillIx.getOrDefault(fill, -1)
      if fl < 0:
        fl = fills.len; fills.add fill; fillIx[fill] = fl
    var bd = 0
    if st.left.kind != bkNone or st.right.kind != bkNone or st.top.kind != bkNone or st.bottom.kind != bkNone:
      var b = "<border>"
      for (tag, side) in [("left", st.left), ("right", st.right), ("top", st.top), ("bottom", st.bottom)]:
        if side.kind == bkNone: b.add "<" & tag & "/>"
        else:
          let name = case side.kind
            of bkThin: "thin"
            of bkMedium: "medium"
            of bkThick: "thick"
            of bkDashed: "dashed"
            of bkDotted: "dotted"
            of bkDouble: "double"
            else: "hair"
          b.add "<" & tag & " style=\"" & name & "\"><color rgb=\"" & hex8(if side.color.len > 0: side.color else: "#000000") & "\"/></" & tag & ">"
      b.add "<diagonal/></border>"
      bd = borderIx.getOrDefault(b, -1)
      if bd < 0:
        bd = borders.len; borders.add b; borderIx[b] = bd
    var nf = 0
    if st.numFmt.len > 0:
      nf = builtinId(st.numFmt)
      if nf < 0:
        nf = fmtIx.getOrDefault(st.numFmt, -1)
        if nf < 0:
          nf = 164 + customFmts.len
          customFmts.add (nf, st.numFmt)
          fmtIx[st.numFmt] = nf
    xfs.add "<xf numFmtId=\"" & $nf & "\" fontId=\"" & $fi & "\" fillId=\"" & $fl & "\" borderId=\"" & $bd & "\" xfId=\"0\""
    if nf != 0: xfs.add " applyNumberFormat=\"1\""
    if fi != 0: xfs.add " applyFont=\"1\""
    if fl != 0: xfs.add " applyFill=\"1\""
    if bd != 0: xfs.add " applyBorder=\"1\""
    if st.hAlign != haGeneral or st.vAlign != vaBottom or st.wrap:
      xfs.add " applyAlignment=\"1\"><alignment"
      case st.hAlign
      of haLeft: xfs.add " horizontal=\"left\""
      of haCenter: xfs.add " horizontal=\"center\""
      of haRight: xfs.add " horizontal=\"right\""
      else: discard
      case st.vAlign
      of vaTop: xfs.add " vertical=\"top\""
      of vaMiddle: xfs.add " vertical=\"center\""
      else: discard
      if st.wrap: xfs.add " wrapText=\"1\""
      xfs.add "/></xf>"
    else: xfs.add "/>"
  var styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
  if customFmts.len > 0:
    styles.add "<numFmts count=\"" & $customFmts.len & "\">"
    for (id, code) in customFmts: styles.add "<numFmt numFmtId=\"" & $id & "\" formatCode=\"" & escapeXml(code, true) & "\"/>"
    styles.add "</numFmts>"
  styles.add "<fonts count=\"" & $fonts.len & "\">" & fonts.join("") & "</fonts>"
  styles.add "<fills count=\"" & $fills.len & "\">" & fills.join("") & "</fills>"
  styles.add "<borders count=\"" & $borders.len & "\">" & borders.join("") & "</borders>"
  styles.add "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
  styles.add "<cellXfs count=\"" & $wb.styles.len & "\">" & xfs & "</cellXfs>"
  styles.add "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"

  var strings: seq[string]
  var stringIx = initTable[string, int]()
  proc sst(s: string): int =
    result = stringIx.getOrDefault(s, -1)
    if result < 0:
      result = strings.len; strings.add s; stringIx[s] = result

  var files: seq[(string, string)]
  var sheetEntries = ""
  var sheetRels = ""
  var overrides = ""
  for i, s in wb.sheets:
    var keys: seq[int64]
    for k in s.cells.keys: keys.add k
    keys.sort()
    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
    let dim = if s.maxRow > 0 and s.maxCol > 0: "A1:" & cellName(s.maxRow - 1, s.maxCol - 1) else: "A1"
    xml.add "<dimension ref=\"" & dim & "\"/>"
    xml.add "<sheetViews><sheetView workbookViewId=\"0\"" & (if i == wb.active: " tabSelected=\"1\"" else: "") & "/></sheetViews>"
    xml.add "<sheetFormatPr defaultRowHeight=\"" & $(DefaultRowHeight * 0.75) & "\"/>"
    if s.colWidths.len > 0:
      var cols: seq[int]
      for c in s.colWidths.keys: cols.add c
      cols.sort()
      xml.add "<cols>"
      for c in cols:
        let px = s.colWidths[c]
        if px < 1: xml.add "<col min=\"" & $(c + 1) & "\" max=\"" & $(c + 1) & "\" width=\"0\" hidden=\"1\" customWidth=\"1\"/>"
        else: xml.add "<col min=\"" & $(c + 1) & "\" max=\"" & $(c + 1) & "\" width=\"" & formatFloat(max(0.0, (px - 5) / 7), ffDecimal, 4) & "\" customWidth=\"1\"/>"
      xml.add "</cols>"
    xml.add "<sheetData>"
    var row = -1
    proc openRow(r: int) =
      if row >= 0: xml.add "</row>"
      row = r
      xml.add "<row r=\"" & $(r + 1) & "\""
      if s.rowHeights.hasKey(r):
        let px = s.rowHeights[r]
        if px < 1: xml.add " hidden=\"1\""
        else: xml.add " ht=\"" & formatFloat(px * 0.75, ffDecimal, 2) & "\" customHeight=\"1\""
      xml.add ">"
    for r, _ in s.rowHeights:
      discard r
    var heightOnly: seq[int]
    for r in s.rowHeights.keys: heightOnly.add r
    heightOnly.sort()
    var hi = 0
    for k in keys:
      let r = rowOf(k)
      while hi < heightOnly.len and heightOnly[hi] < r:
        if heightOnly[hi] > row: openRow(heightOnly[hi])
        inc hi
      if r != row: openRow(r)
      let c = colOf(k)
      let cell = s.cells[k]
      xml.add "<c r=\"" & cellName(r, c) & "\""
      if cell.style != 0: xml.add " s=\"" & $cell.style & "\""
      let val = cell.value
      if cell.formula.len > 0:
        case val.kind
        of vkStr: xml.add " t=\"str\""
        of vkBool: xml.add " t=\"b\""
        of vkErr: xml.add " t=\"e\""
        else: discard
        xml.add "><f>" & escapeXml(cell.formula[1 .. ^1]) & "</f>"
        case val.kind
        of vkNum: xml.add "<v>" & numText(val.num) & "</v>"
        of vkStr, vkErr: xml.add "<v>" & escapeXml(val.str) & "</v>"
        of vkBool: xml.add "<v>" & (if val.b: "1" else: "0") & "</v>"
        else: discard
        xml.add "</c>"
      else:
        case val.kind
        of vkNum: xml.add "><v>" & numText(val.num) & "</v></c>"
        of vkStr: xml.add " t=\"s\"><v>" & $sst(val.str) & "</v></c>"
        of vkBool: xml.add " t=\"b\"><v>" & (if val.b: "1" else: "0") & "</v></c>"
        of vkErr: xml.add " t=\"e\"><v>" & escapeXml(val.str) & "</v></c>"
        else: xml.add "/>"
    while hi < heightOnly.len:
      if heightOnly[hi] > row: openRow(heightOnly[hi])
      inc hi
    if row >= 0: xml.add "</row>"
    xml.add "</sheetData>"
    if s.merges.len > 0:
      xml.add "<mergeCells count=\"" & $s.merges.len & "\">"
      for m in s.merges: xml.add "<mergeCell ref=\"" & cellName(m.r1, m.c1) & ":" & cellName(m.r2, m.c2) & "\"/>"
      xml.add "</mergeCells>"
    xml.add "<pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/></worksheet>"
    files.add ("xl/worksheets/sheet" & $(i + 1) & ".xml", xml)
    sheetEntries.add "<sheet name=\"" & escapeXml(s.name.substr(0, 30), true) & "\" sheetId=\"" & $(i + 1) & "\" r:id=\"rId" & $(i + 1) & "\"/>"
    sheetRels.add "<Relationship Id=\"rId" & $(i + 1) & "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet" & $(i + 1) & ".xml\"/>"
    overrides.add "<Override PartName=\"/xl/worksheets/sheet" & $(i + 1) & ".xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
  let n = wb.sheets.len
  var sstXml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"" & $strings.len & "\" uniqueCount=\"" & $strings.len & "\">"
  for s in strings:
    let keep = s.len > 0 and (s[0] in Whitespace or s[^1] in Whitespace)
    sstXml.add "<si><t" & (if keep: " xml:space=\"preserve\"" else: "") & ">" & escapeXml(s) & "</t></si>"
  sstXml.add "</sst>"
  let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
  result = writeZipDeflated(@[
    ("[Content_Types].xml", head & "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" &
      "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" &
      "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" &
      "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>" &
      overrides &
      "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" &
      "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>" &
      "</Types>"),
    ("_rels/.rels", head & "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" &
      "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
    ("xl/workbook.xml", head & "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" &
      "<bookViews><workbookView activeTab=\"" & $wb.active & "\"/></bookViews><sheets>" & sheetEntries & "</sheets><calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"/></workbook>"),
    ("xl/_rels/workbook.xml.rels", head & "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" & sheetRels &
      "<Relationship Id=\"rId" & $(n + 1) & "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>" &
      "<Relationship Id=\"rId" & $(n + 2) & "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/></Relationships>"),
    ("xl/styles.xml", styles),
    ("xl/sharedStrings.xml", sstXml)] & files)

# ----------------------------------------------------------------------- csv --

proc valueFromText*(t: string): Value =
  ## What a typed or imported text means: a number (also 12%, 1,234.5), TRUE/FALSE, or text.
  let st = t.strip
  if st.len == 0: return emptyVal()
  if st[0] in {'0'..'9', '-', '+', '.'}:
    try:
      if st.endsWith("%"): return numVal(parseFloat(st[0 ..< ^1].replace(",", "")) / 100)
      let plain = if st.count(',') > 0 and st.count('.') <= 1 and ',' notin st[st.rfind(',') + 1 .. ^1] and st.rfind(',') == st.len - 4: st.replace(",", "") else: st
      return numVal(parseFloat(plain))
    except ValueError: discard
  if cmpIgnoreCase(st, "TRUE") == 0: return boolVal(true)
  if cmpIgnoreCase(st, "FALSE") == 0: return boolVal(false)
  strVal(t)

proc readCsv*(text: string, name = "Sheet1"): Workbook =
  result = newWorkbook()
  let s = result.addSheet(name)
  var body = text
  if body.startsWith("\xEF\xBB\xBF"): body = body[3 .. ^1]
  # delimiter: the most frequent of , ; tab on the first line
  let firstLine = body.split({'\n'}, 1)[0]
  var delim = ','
  var best = firstLine.count(',')
  for d in [';', '\t']:
    if firstLine.count(d) > best: best = firstLine.count(d); delim = d
  var r, c = 0
  var field = ""
  var quoted, wasQuoted = false
  var i = 0
  template emit() =
    if field.len > 0 or wasQuoted:
      let v = if wasQuoted: (if field.len > 0: strVal(field) else: emptyVal()) else: valueFromText(field)
      if v.kind != vkEmpty and r < MaxRows and c < MaxCols:
        var cell = Cell(value: v)
        if not wasQuoted and field.len > 1 and field[0] == '=': cell.setFormula(field)
        s.putCell(r, c, cell)
    field = ""; wasQuoted = false
  while i < body.len:
    let ch = body[i]
    if quoted:
      if ch == '"':
        if i + 1 < body.len and body[i + 1] == '"': field.add '"'; inc i
        else: quoted = false
      else: field.add ch
    elif ch == '"' and field.len == 0: quoted = true; wasQuoted = true
    elif ch == delim: emit(); inc c
    elif ch == '\n' or ch == '\r':
      if ch == '\r' and i + 1 < body.len and body[i + 1] == '\n': inc i
      emit(); inc r; c = 0
    else: field.add ch
    inc i
  emit()

proc writeCsv*(wb: Workbook, s: Sheet): string =
  for r in 0 ..< s.maxRow:
    if r > 0: result.add "\r\n"
    for c in 0 ..< s.maxCol:
      if c > 0: result.add ','
      let cell = s.cellAt(r, c)
      var t = case cell.value.kind
        of vkNum: numText(cell.value.num)
        else: toText(cell.value)
      if t.contains({',', '"', '\n', '\r'}) or (t.len > 0 and t[0] in Whitespace): t = "\"" & t.replace("\"", "\"\"") & "\""
      result.add t
