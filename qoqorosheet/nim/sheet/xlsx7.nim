## Stage 7's parts of a worksheet in .xlsx, included into xlsx.nim: frozen
## panes, sheet protection, AutoFilter, conditional formatting (and the dxf
## formats it uses), data validation, hyperlinks, notes (comments + their
## VML shapes, which Excel needs to show them) and pictures (a drawing with
## its media). Read back the same way.

const
  NsRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  Emu = 9525.0                     ## EMU per pixel at 96 dpi

type Dxf = object                  ## a differential format (what a rule applies)
  fill, color: string
  bold: bool

proc cellText(wb: Workbook, cell: Cell): string =
  ## the text a cell shows (view.displayText)
  let st = wb.styles[cell.style]
  case cell.value.kind
  of vkNum: (if st.numFmt.len > 0: formatNumber(cell.value.num, st.numFmt) else: fmtGeneral(cell.value.num))
  else: toText(cell.value)

proc refRange(r1, c1, r2, c2: int): string =
  if r1 == r2 and c1 == c2: cellName(r1, c1) else: cellName(r1, c1) & ":" & cellName(r2, c2)

proc sqrefRange(t: string): (bool, int, int, int, int) =
  ## the first range of a space-separated sqref
  let first = t.strip.split(' ')[0]
  if first.len == 0: return (false, 0, 0, 0, 0)
  let parts = first.replace("$", "").split(':')
  let (r1, c1) = parseRef(parts[0])
  let (r2, c2) = if parts.len > 1: parseRef(parts[1]) else: (r1, c1)
  (r1 >= 0 and c1 >= 0 and r2 >= r1 and c2 >= c1, r1, c1, min(r2, MaxRows - 1), min(c2, MaxCols - 1))

# ------------------------------------------------------------------ reading --

proc readDxfs(xml: string): seq[Dxf] =
  var x = initXml(xml)
  var inDxfs, inFont, inFill = false
  var cur: Dxf
  while true:
    x.next()
    case x.kind
    of xkEof: break
    of xkStart:
      case x.name
      of "dxfs": inDxfs = true
      of "dxf": (if inDxfs: cur = Dxf())
      of "font": inFont = inDxfs
      of "fill": inFill = inDxfs
      of "b": (if inDxfs and inFont: cur.bold = x.attr("val", "1") notin ["0", "false"])
      of "color": (if inDxfs and inFont: cur.color = colorOf(x))
      of "bgColor", "fgColor": (if inDxfs and inFill and cur.fill.len == 0: cur.fill = colorOf(x))
      else: discard
    of xkEnd:
      case x.name
      of "dxfs": inDxfs = false
      of "dxf": (if inDxfs: result.add cur)
      of "font": inFont = false
      of "fill": inFill = false
      else: discard
    else: discard

proc readRels(z: ZipArchive, partPath: string): Table[string, (string, string, bool)] =
  ## a part's relationships: id -> (target, type, external)
  let slash = partPath.rfind('/')
  let relsPath = partPath[0 .. slash] & "_rels/" & partPath[slash + 1 .. ^1] & ".rels"
  var x = initXml(z.tryReadEntry(relsPath))
  while true:
    x.next()
    if x.kind == xkEof: break
    if x.kind == xkStart and x.name == "Relationship":
      let external = x.attr("TargetMode") == "External"
      let target = if external: x.attr("Target") else: resolvePath(partPath, x.attr("Target"))
      result[x.attr("Id")] = (target, x.attr("Type"), external)

proc mimeOf(path: string): string =
  let p = path.toLowerAscii
  if p.endsWith(".jpg") or p.endsWith(".jpeg"): "image/jpeg"
  elif p.endsWith(".gif"): "image/gif"
  elif p.endsWith(".svg"): "image/svg+xml"
  elif p.endsWith(".webp"): "image/webp"
  else: "image/png"

proc readComments(s: Sheet, xml: string) =
  var x = initXml(xml)
  var at = (-1, -1)
  var text = ""
  var inText = false
  while true:
    x.next()
    case x.kind
    of xkEof: break
    of xkStart:
      case x.name
      of "comment": at = parseRef(x.attr("ref")); text = ""
      of "text": inText = true
      of "t": (if inText: text.add x.readText())
      else: discard
    of xkEnd:
      case x.name
      of "text": inText = false
      of "comment":
        if at[0] >= 0 and at[1] >= 0: s.notes[key(at[0], at[1])] = text
      else: discard
    else: discard

proc readDrawing(s: Sheet, z: ZipArchive, path: string) =
  ## pictures from a drawing part: each anchor's place and its image
  let rels = readRels(z, path)
  var x = initXml(z.tryReadEntry(path))
  var inFrom, inTo = false
  var fr, fc, tr, tc: int
  var fro, fco, tro, tco, cx, cy: float64
  var hasTo = false
  var embed = ""
  var field = ""
  while true:
    x.next()
    case x.kind
    of xkEof: break
    of xkStart:
      case x.name
      of "twoCellAnchor", "oneCellAnchor", "absoluteAnchor":
        fr = 0; fc = 0; tr = 0; tc = 0; fro = 0; fco = 0; tro = 0; tco = 0; cx = 0; cy = 0; hasTo = false; embed = ""
      of "from": inFrom = true
      of "to": inTo = true; hasTo = true
      of "col", "colOff", "row", "rowOff":
        let n = try: parseFloat(x.readText().strip) except ValueError: 0.0
        if inFrom:
          case x.name
          of "col": fc = int(n)
          of "colOff": fco = n / Emu
          of "row": fr = int(n)
          else: fro = n / Emu
        elif inTo:
          case x.name
          of "col": tc = int(n)
          of "colOff": tco = n / Emu
          of "row": tr = int(n)
          else: tro = n / Emu
      of "ext":
        if cx == 0: (cx = (try: parseFloat(x.attr("cx")) except ValueError: 0.0) / Emu; cy = (try: parseFloat(x.attr("cy")) except ValueError: 0.0) / Emu)
      of "blip": embed = x.attr("embed")
      else: discard
      discard field
    of xkEnd:
      case x.name
      of "from": inFrom = false
      of "to": inTo = false
      of "twoCellAnchor", "oneCellAnchor", "absoluteAnchor":
        if embed.len > 0 and rels.hasKey(embed):
          let media = rels[embed][0]
          let bytes = z.tryReadEntry(media)
          if bytes.len > 0:
            let px = s.colX(fc) + fco
            let py = s.rowY(fr) + fro
            var w = cx
            var h = cy
            if hasTo: w = s.colX(tc) + tco - px; h = s.rowY(tr) + tro - py
            if w > 0 and h > 0:
              s.pictures.add Picture(src: "data:" & mimeOf(media) & ";base64," & encode(bytes), x: px, y: py, w: w, h: h)
      else: discard
    else: discard

proc readSheetExtras(wb: Workbook, s: Sheet, z: ZipArchive, path, xml: string, dxfs: seq[Dxf]) =
  let rels = readRels(z, path)
  var x = initXml(xml)
  var shown = initTable[int, seq[string]]()
  var blanks = initTable[int, bool]()
  var fcol = -1
  var cf = (false, 0, 0, 0, 0)
  var rule: CondRule
  var inRule = false
  var formulas: seq[string]
  var colors: seq[string]
  var dv: Validation
  var inDv = false
  while true:
    x.next()
    case x.kind
    of xkEof: break
    of xkStart:
      case x.name
      of "pane":
        if x.attr("state") in ["frozen", "frozenSplit"]:
          s.frozenCols = int(try: parseFloat(x.attr("xSplit", "0")) except ValueError: 0.0)
          s.frozenRows = int(try: parseFloat(x.attr("ySplit", "0")) except ValueError: 0.0)
      of "sheetProtection":
        if x.attr("sheet") in ["1", "true"]:
          s.protected = true
          s.protectHash = x.attr("password").toUpperAscii
      of "autoFilter":
        let (ok, a, b, c, d) = sqrefRange(x.attr("ref"))
        if ok: s.filter = AutoFilter(on: true, r1: a, c1: b, r2: c, c2: d)
      of "filterColumn":
        fcol = s.filter.c1 + (try: parseInt(x.attr("colId", "0")) except ValueError: 0)
      of "filters":
        if fcol >= 0:
          shown[fcol] = @[]
          if x.attr("blank") in ["1", "true"]: blanks[fcol] = true
      of "filter": (if fcol >= 0 and shown.hasKey(fcol): shown[fcol].add x.attr("val"))
      of "conditionalFormatting": cf = sqrefRange(x.attr("sqref"))
      of "cfRule":
        formulas = @[]; colors = @[]
        rule = CondRule(r1: cf[1], c1: cf[2], r2: cf[3], c2: cf[4])
        let dxf = try: parseInt(x.attr("dxfId", "-1")) except ValueError: -1
        if dxf >= 0 and dxf < dxfs.len: rule.fill = dxfs[dxf].fill; rule.color = dxfs[dxf].color; rule.bold = dxfs[dxf].bold
        inRule = cf[0]
        case x.attr("type")
        of "cellIs":
          rule.kind = case x.attr("operator")
            of "greaterThan", "greaterThanOrEqual": ckGreater
            of "lessThan", "lessThanOrEqual": ckLess
            of "between": ckBetween
            else: ckEqual
        of "containsText": rule.kind = ckTextContains; rule.v1 = x.attr("text")
        of "duplicateValues": rule.kind = ckDuplicate
        of "uniqueValues": rule.kind = ckUnique
        of "top10":
          rule.kind = if x.attr("bottom") in ["1", "true"]: ckBottom else: ckTop
          rule.v1 = x.attr("rank", "10")
          if x.attr("percent") in ["1", "true"]: rule.v2 = "%"
        of "aboveAverage": rule.kind = if x.attr("aboveAverage") in ["0", "false"]: ckBelowAverage else: ckAboveAverage
        of "expression": rule.kind = ckFormula
        of "dataBar": rule.kind = ckDataBar
        of "colorScale": rule.kind = ckColorScale
        else: inRule = false
      of "formula", "formula1", "formula2":
        let f = x.readText()
        if inRule: formulas.add f
        elif inDv: (if x.name == "formula2": dv.v2 = f else: dv.v1 = f)
      of "color": (if inRule: colors.add colorOf(x))
      of "dataValidation":
        let (ok, a, b, c, d) = sqrefRange(x.attr("sqref"))
        inDv = ok
        dv = Validation(r1: a, c1: b, r2: c, c2: d, op: x.attr("operator", "between"), allowBlank: x.attr("allowBlank") in ["1", "true"],
          error: x.attr("error"))
        dv.kind = case x.attr("type")
          of "list": dvList
          of "whole": dvWhole
          of "decimal": dvDecimal
          of "date": dvDate
          of "textLength": dvTextLength
          else: dvAny
      of "hyperlink":
        let (r, c) = parseRef(x.attr("ref").split(':')[0])
        if r >= 0 and c >= 0:
          let id = x.attr("id")
          if id.len > 0 and rels.hasKey(id): s.links[key(r, c)] = rels[id][0] & (if x.attr("location").len > 0: "#" & x.attr("location") else: "")
          elif x.attr("location").len > 0: s.links[key(r, c)] = "#" & x.attr("location")
      else: discard
    of xkEnd:
      case x.name
      of "filterColumn": fcol = -1
      of "cfRule":
        if inRule:
          case rule.kind
          of ckGreater, ckLess, ckEqual, ckBetween:
            if formulas.len > 0: rule.v1 = formulas[0]
            if formulas.len > 1: rule.v2 = formulas[1]
            if rule.kind == ckEqual and rule.v1.len >= 2 and rule.v1[0] == '"': rule.v1 = rule.v1[1 .. ^2]
          of ckFormula: (if formulas.len > 0: rule.v1 = "=" & formulas[0])
          of ckDataBar, ckColorScale: rule.colors = colors
          else: discard
          s.condRules.add rule
        inRule = false
      of "dataValidation":
        if inDv:
          if dv.kind == dvList:
            let f = dv.v1.strip
            dv.list = if f.len >= 2 and f[0] == '"': f[1 .. ^2] else: "=" & f
            dv.v1 = ""
          s.validations.add dv
        inDv = false
      else: discard
    else: discard
  # the filter: the values not listed are the hidden ones; hidden rows in it are the filter's
  if s.filter.on:
    for c, vals in shown:
      var hidden: seq[string]
      for r in s.filter.r1 + 1 .. s.filter.r2:
        var t = cellText(wb, s.cellAt(r, c))
        if t.len == 0:
          if blanks.getOrDefault(c): continue
          t = "(Blanks)"
        elif t in vals: continue
        if t notin hidden: hidden.add t
      if hidden.len > 0: s.filter.hidden[c] = hidden
    if s.filter.hidden.len > 0:
      for r in s.filter.r1 + 1 .. s.filter.r2:
        if r in s.hiddenRows: s.hiddenRows.excl r; s.filterRows.incl r
  # notes and pictures, through the sheet's relationships
  for id, (target, typ, external) in rels:
    if external: continue
    if typ.endsWith("/comments"): readComments(s, z.tryReadEntry(target))
    elif typ.endsWith("/drawing"): readDrawing(s, z, target)

# ------------------------------------------------------------------ writing --

proc dxfXml(rule: CondRule): string =
  result = "<dxf>"
  if rule.bold or rule.color.len > 0:
    result.add "<font>" & (if rule.bold: "<b/>" else: "") & (if rule.color.len > 0: "<color rgb=\"" & hex8(rule.color) & "\"/>" else: "") & "</font>"
  if rule.fill.len > 0:
    result.add "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"" & hex8(rule.fill) & "\"/><bgColor rgb=\"" & hex8(rule.fill) & "\"/></patternFill></fill>"
  result.add "</dxf>"

proc formulaText(v: string): string =
  ## a rule's value as formula text: numbers and formulas as they are, text quoted
  let t = v.strip
  if t.startsWith("="): return escapeXml(t[1 .. ^1])
  try: discard parseFloat(t); return t
  except ValueError: return escapeXml("\"" & t.replace("\"", "\"\"") & "\"")

proc dateText(v: string): string =
  ## a validation's date ("2026-10-21") as its serial
  let p = v.strip.replace('/', '-').split('-')
  if p.len == 3:
    try:
      if p[0].len == 4: return $int(fromCivil(parseInt(p[0]), parseInt(p[1]), parseInt(p[2])))
      return $int(fromCivil(parseInt(p[2]), parseInt(p[0]), parseInt(p[1])))
    except ValueError: discard
  formulaText(v)

proc condXml(s: Sheet, dxfIx: Table[string, int]): string =
  for i, rule in s.condRules:
    let sq = refRange(rule.r1, rule.c1, min(rule.r2, MaxRows - 1), min(rule.c2, MaxCols - 1))
    let dxf = if rule.kind in {ckDataBar, ckColorScale}: "" else: " dxfId=\"" & $dxfIx.getOrDefault(dxfXml(rule)) & "\""
    let p = " priority=\"" & $(i + 1) & "\""
    var body = ""
    case rule.kind
    of ckGreater: body = "<cfRule type=\"cellIs\"" & dxf & p & " operator=\"greaterThan\"><formula>" & formulaText(rule.v1) & "</formula></cfRule>"
    of ckLess: body = "<cfRule type=\"cellIs\"" & dxf & p & " operator=\"lessThan\"><formula>" & formulaText(rule.v1) & "</formula></cfRule>"
    of ckEqual: body = "<cfRule type=\"cellIs\"" & dxf & p & " operator=\"equal\"><formula>" & formulaText(rule.v1) & "</formula></cfRule>"
    of ckBetween: body = "<cfRule type=\"cellIs\"" & dxf & p & " operator=\"between\"><formula>" & formulaText(rule.v1) & "</formula><formula>" & formulaText(rule.v2) & "</formula></cfRule>"
    of ckTextContains:
      body = "<cfRule type=\"containsText\"" & dxf & p & " operator=\"containsText\" text=\"" & escapeXml(rule.v1, true) &
        "\"><formula>NOT(ISERROR(SEARCH(" & escapeXml("\"" & rule.v1.replace("\"", "\"\"") & "\"") & "," & cellName(rule.r1, rule.c1) & ")))</formula></cfRule>"
    of ckDuplicate: body = "<cfRule type=\"duplicateValues\"" & dxf & p & "/>"
    of ckUnique: body = "<cfRule type=\"uniqueValues\"" & dxf & p & "/>"
    of ckTop, ckBottom:
      body = "<cfRule type=\"top10\"" & dxf & p & " rank=\"" & (if rule.v1.len > 0: rule.v1 else: "10") & "\"" &
        (if rule.v2 == "%": " percent=\"1\"" else: "") & (if rule.kind == ckBottom: " bottom=\"1\"" else: "") & "/>"
    of ckAboveAverage: body = "<cfRule type=\"aboveAverage\"" & dxf & p & "/>"
    of ckBelowAverage: body = "<cfRule type=\"aboveAverage\"" & dxf & p & " aboveAverage=\"0\"/>"
    of ckFormula: body = "<cfRule type=\"expression\"" & dxf & p & "><formula>" & escapeXml(rule.v1.strip(chars = {'='}, trailing = false)) & "</formula></cfRule>"
    of ckDataBar:
      body = "<cfRule type=\"dataBar\"" & p & "><dataBar><cfvo type=\"min\"/><cfvo type=\"max\"/><color rgb=\"" &
        hex8(if rule.colors.len > 0: rule.colors[0] else: "#638ec6") & "\"/></dataBar></cfRule>"
    of ckColorScale:
      body = "<cfRule type=\"colorScale\"" & p & "><colorScale><cfvo type=\"min\"/>" & (if rule.colors.len >= 3: "<cfvo type=\"percentile\" val=\"50\"/>" else: "") &
        "<cfvo type=\"max\"/>"
      for c in rule.colors: body.add "<color rgb=\"" & hex8(c) & "\"/>"
      body.add "</colorScale></cfRule>"
    result.add "<conditionalFormatting sqref=\"" & sq & "\">" & body & "</conditionalFormatting>"

proc validationXml(s: Sheet): string =
  if s.validations.len == 0: return
  result = "<dataValidations count=\"" & $s.validations.len & "\">"
  for dv in s.validations:
    let typ = case dv.kind
      of dvList: "list"
      of dvWhole: "whole"
      of dvDecimal: "decimal"
      of dvDate: "date"
      of dvTextLength: "textLength"
      else: "none"
    result.add "<dataValidation type=\"" & typ & "\"" & (if dv.kind != dvList and dv.op.len > 0: " operator=\"" & dv.op & "\"" else: "") &
      (if dv.allowBlank: " allowBlank=\"1\"" else: "") & " showErrorMessage=\"1\"" &
      (if dv.error.len > 0: " error=\"" & escapeXml(dv.error, true) & "\"" else: "") &
      " sqref=\"" & refRange(dv.r1, dv.c1, min(dv.r2, MaxRows - 1), min(dv.c2, MaxCols - 1)) & "\">"
    if dv.kind == dvList:
      let src = dv.list.strip
      result.add "<formula1>" & (if src.startsWith("="): escapeXml(src[1 .. ^1]) else: escapeXml("\"" & src & "\"")) & "</formula1>"
    else:
      let date = dv.kind == dvDate
      if dv.v1.len > 0: result.add "<formula1>" & (if date: dateText(dv.v1) else: formulaText(dv.v1)) & "</formula1>"
      if dv.v2.len > 0 and dv.op in ["between", "notBetween"]: result.add "<formula2>" & (if date: dateText(dv.v2) else: formulaText(dv.v2)) & "</formula2>"
    result.add "</dataValidation>"
  result.add "</dataValidations>"

proc filterXml(wb: Workbook, s: Sheet): string =
  let f = s.filter
  if not f.on: return
  result = "<autoFilter ref=\"" & refRange(f.r1, f.c1, f.r2, f.c2) & "\""
  if f.hidden.len == 0: return result & "/>"
  result.add ">"
  var cols: seq[int]
  for c in f.hidden.keys: cols.add c
  cols.sort()
  for c in cols:
    let hidden = f.hidden[c]
    var shown: seq[string]
    var blank = false
    for r in f.r1 + 1 .. f.r2:
      let t = cellText(wb, s.cellAt(r, c))
      if t.len == 0:
        if "(Blanks)" notin hidden: blank = true
      elif t notin hidden and t notin shown: shown.add t
    result.add "<filterColumn colId=\"" & $(c - f.c1) & "\"><filters" & (if blank: " blank=\"1\"" else: "") & ">"
    for t in shown: result.add "<filter val=\"" & escapeXml(t, true) & "\"/>"
    result.add "</filters></filterColumn>"
  result.add "</autoFilter>"

proc commentsXml(s: Sheet): string =
  result = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<comments xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><authors><author>QoqoroSheet</author></authors><commentList>"
  var keys: seq[int64]
  for k in s.notes.keys: keys.add k
  keys.sort()
  for k in keys:
    result.add "<comment ref=\"" & cellName(rowOf(k), colOf(k)) & "\" authorId=\"0\"><text><t xml:space=\"preserve\">" & escapeXml(s.notes[k]) & "</t></text></comment>"
  result.add "</commentList></comments>"

proc notesVml(s: Sheet, sheetNo: int): string =
  ## the notes' shapes (Excel shows a note only with one)
  result = "<xml xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:x=\"urn:schemas-microsoft-com:office:excel\">" &
    "<o:shapelayout v:ext=\"edit\"><o:idmap v:ext=\"edit\" data=\"" & $sheetNo & "\"/></o:shapelayout>" &
    "<v:shapetype id=\"_x0000_t202\" coordsize=\"21600,21600\" o:spt=\"202\" path=\"m,l,21600r21600,l21600,xe\"><v:stroke joinstyle=\"miter\"/><v:path gradientshapeok=\"t\" o:connecttype=\"rect\"/></v:shapetype>"
  var i = 0
  for k in s.notes.keys:
    let (r, c) = (rowOf(k), colOf(k))
    result.add "<v:shape id=\"_x0000_s" & $(sheetNo * 1024 + 1 + i) & "\" type=\"#_x0000_t202\" style=\"position:absolute;margin-left:59.25pt;margin-top:1.5pt;width:108pt;height:59.25pt;z-index:" &
      $(i + 1) & ";visibility:hidden\" fillcolor=\"#ffffe1\" o:insetmode=\"auto\"><v:fill color2=\"#ffffe1\"/><v:shadow on=\"t\" color=\"black\" obscured=\"t\"/>" &
      "<v:path o:connecttype=\"none\"/><v:textbox style=\"mso-direction-alt:auto\"><div style=\"text-align:left\"></div></v:textbox>" &
      "<x:ClientData ObjectType=\"Note\"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>" & $(c + 1) & ", 15, " & $max(r - 1, 0) & ", 10, " & $(c + 3) & ", 15, " &
      $(max(r - 1, 0) + 4) & ", 4</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>" & $r & "</x:Row><x:Column>" & $c & "</x:Column></x:ClientData></v:shape>"
    inc i
  result.add "</xml>"

proc pictureBytes(src: string): (string, string) =
  ## a data: URL's bytes and file extension
  let comma = src.find(',')
  if not src.startsWith("data:") or comma < 0: return ("", "")
  let head = src[5 ..< comma]
  let ext = if "jpeg" in head or "jpg" in head: "jpeg" elif "gif" in head: "gif" else: "png"
  let body = src[comma + 1 .. ^1]
  if ";base64" in head:
    try: return (decode(body), ext) except ValueError: return ("", "")
  (body, ext)

proc drawingXml(s: Sheet, firstImage: int): string =
  result = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<xdr:wsDr xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"" & NsRel & "\">"
  for i, p in s.pictures:
    let c = s.colAt(p.x)
    let r = s.rowAt(p.y)
    let cx = int(p.w * Emu)
    let cy = int(p.h * Emu)
    result.add "<xdr:oneCellAnchor><xdr:from><xdr:col>" & $c & "</xdr:col><xdr:colOff>" & $int((p.x - s.colX(c)) * Emu) & "</xdr:colOff><xdr:row>" & $r &
      "</xdr:row><xdr:rowOff>" & $int((p.y - s.rowY(r)) * Emu) & "</xdr:rowOff></xdr:from><xdr:ext cx=\"" & $cx & "\" cy=\"" & $cy & "\"/>" &
      "<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=\"" & $(i + 2) & "\" name=\"Picture " & $(i + 1) & "\"/><xdr:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></xdr:cNvPicPr></xdr:nvPicPr>" &
      "<xdr:blipFill><a:blip r:embed=\"rIdImg" & $(i + 1) & "\"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>" &
      "<xdr:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"" & $cx & "\" cy=\"" & $cy & "\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>"
  result.add "</xdr:wsDr>"
  discard firstImage
