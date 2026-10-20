## QoqoroSheet's workbook model: sheets of sparse cells, shared styles,
## column widths and row heights. Pure Nim (no host imports), so the model
## and the formula engine can be tested natively.

import std/[tables, hashes, math, sets]
export sets

type
  ValKind* = enum vkEmpty, vkNum, vkStr, vkBool, vkErr, vkArr
  Value* = object
    case kind*: ValKind
    of vkNum: num*: float64
    of vkStr, vkErr: str*: string
    of vkBool: b*: bool
    of vkArr:
      rows*, cols*: int
      items*: seq[Value]           ## row-major
    of vkEmpty: discard

  HAlign* = enum haGeneral, haLeft, haCenter, haRight
  VAlign* = enum vaDefault, vaBottom, vaMiddle, vaTop   ## vaDefault: none set (Luckysheet draws it middle, Excel bottom)
  BorderKind* = enum bkNone, bkThin, bkMedium, bkThick, bkDashed, bkDotted, bkDouble, bkHair
  Border* = object
    kind*: BorderKind
    color*: string                 ## "" = black

  Style* = object
    bold*, italic*, underline*, strike*, wrap*: bool
    fontSize*: float64             ## points; 0 = default
    font*: string                  ## family; "" = default
    color*, fill*: string          ## "" = default
    hAlign*: HAlign
    vAlign*: VAlign
    numFmt*: string                ## "" = General
    left*, right*, top*, bottom*: Border
    rotation*: int                 ## text angle in degrees (-90 .. 90), 255 stacked vertically (Excel's textRotation)
    unlocked*: bool                ## Excel's Format Cells > Protection > Locked, inverted (cells are locked by default)

  ExprKind* = enum ekNum, ekStr, ekBool, ekErr, ekRef, ekRange, ekUnary, ekBinary, ekCall, ekPercent, ekArray
  Expr* = ref object
    case kind*: ExprKind
    of ekNum: num*: float64
    of ekStr, ekErr: s*: string
    of ekBool: b*: bool
    of ekRef, ekRange:
      sheet*: string               ## "" = the formula's own sheet
      r1*, c1*, r2*, c2*: int      ## 0-based; for ekRef r2 = r1, c2 = c1
    of ekUnary, ekPercent:
      op*: char
      arg*: Expr
    of ekBinary:
      bop*: string
      left*, right*: Expr
    of ekCall:
      name*: string
      args*: seq[Expr]
    of ekArray:
      arows*, acols*: int
      aitems*: seq[Expr]

  RichRun* = object               ## a part of a rich-text cell, with its own font (Luckysheet's inlineStr s[])
    text*: string
    bold*, italic*, underline*, strike*: bool
    color*, font*: string          ## "" = the cell's
    fontSize*: float64             ## 0 = the cell's

  Cell* = object
    value*: Value                  ## the literal, or the formula's last result
    formula*: string               ## "=..." or ""
    ast*: Expr                     ## parsed formula (nil if none or unparsable)
    style*: int32                  ## index into Workbook.styles; 0 = default
    stamp*: int32                  ## recalculation pass that computed `value`
    rich*: seq[RichRun]            ## rich text (value is their text); empty for plain cells

  Sheet* = ref object
    name*: string
    cells*: Table[int64, Cell]
    colWidths*: Table[int, float64]
    rowHeights*: Table[int, float64]
    maxRow*, maxCol*: int          ## used range (exclusive); grows, recomputed on demand
    merges*: seq[Merge]            ## merged ranges; the top-left cell holds the content
    rowsTotal*, colsTotal*: int    ## the sheet's size beyond its data ("Add rows"); see rowCount
    hiddenRows*, hiddenCols*: HashSet[int]   ## hidden: no size on screen (Luckysheet's rowhidden / colhidden), sizes kept
    tabColor*: string              ## the sheet tab's colour ("" none)
    hidden*: bool                  ## a hidden sheet (no tab)
    frozenRows*, frozenCols*: int  ## Freeze Panes: rows above / columns left of the split stay put
    filter*: AutoFilter
    filterRows*: HashSet[int]      ## rows the filter hides (kept apart from rows hidden by hand)
    condRules*: seq[CondRule]
    validations*: seq[Validation]
    notes*: Table[int64, string]   ## Excel's notes (Luckysheet's postil), by cell
    links*: Table[int64, string]   ## hyperlinks by cell: a URL, or "#Sheet1!A1" inside the workbook
    pictures*: seq[Picture]
    protected*: bool               ## Protect Sheet: locked cells cannot change
    protectHash*: string           ## the password's hash ("" no password)
    pivot*: PivotDef               ## set on a pivot table's sheet (source == "" otherwise)
    viewRows*, viewCols*: int      ## how far the view was scrolled or stepped past the data (Excel: wheel / arrows go on; not saved)

  Merge* = object
    r1*, c1*, r2*, c2*: int        ## inclusive, 0-based

  CondKind* = enum                 ## Excel's conditional formatting rules
    ckGreater, ckLess, ckBetween, ckEqual, ckTextContains, ckDuplicate, ckUnique,
    ckTop, ckBottom, ckAboveAverage, ckBelowAverage, ckFormula, ckDataBar, ckColorScale
  CondRule* = object
    r1*, c1*, r2*, c2*: int
    kind*: CondKind
    v1*, v2*: string               ## the rule's values (a number, text, a formula, N for top / bottom)
    fill*, color*: string          ## the format a matching cell gets ("" keeps its own)
    bold*: bool
    colors*: seq[string]           ## a data bar's colour, a colour scale's 2 or 3 colours

  DvKind* = enum dvAny, dvList, dvWhole, dvDecimal, dvTextLength, dvDate
  Validation* = object             ## Excel's Data Validation for a range
    r1*, c1*, r2*, c2*: int
    kind*: DvKind
    op*: string                    ## between, notBetween, equal, notEqual, greaterThan, lessThan, greaterThanOrEqual, lessThanOrEqual
    v1*, v2*: string
    list*: string                  ## a list's items, comma separated, or a range "=$A$1:$A$5"
    allowBlank*: bool
    error*: string                 ## the message a wrong entry gets ("" the default one)

  AutoFilter* = object             ## Excel's AutoFilter: a header row and the values each column hides
    on*: bool
    r1*, c1*, r2*, c2*: int        ## r1 is the header row
    hidden*: Table[int, seq[string]]   ## column -> the display texts unticked

  Picture* = object                ## a picture floating over the grid
    src*: string                   ## a data: URL
    x*, y*, w*, h*: float64        ## content pixels

  PivotDef* = object               ## how a pivot table sheet was made (Refresh rebuilds it)
    source*: string                ## sheet name
    r1*, c1*, r2*, c2*: int
    rowField*, colField*, valueField*: int   ## columns of the source (-1 none)
    agg*: string                   ## SUM, COUNT, AVERAGE, MAX, MIN

  Workbook* = ref object
    sheets*: seq[Sheet]
    active*: int
    styles*: seq[Style]
    styleIds: Table[Style, int32]
    pass*: int32                   ## recalculation pass counter

const
  MaxRows* = 1_048_576
  MaxCols* = 16_384
  # Luckysheet's defaultcollen / defaultrowlen: a column's or row's own size,
  # without the 1 px grid line after it (rhchInit: pitch = len + 1).
  DefaultColWidth* = 73.0
  DefaultRowHeight* = 19.0
  DefaultRowCount* = 84            ## Luckysheet's defaultrowNum / defaultcolumnNum
  DefaultColCount* = 60

proc runStyle*(base: Style, run: RichRun): Style =
  ## The style a run is drawn with: the cell's, its font overridden by the run.
  result = base
  result.bold = run.bold; result.italic = run.italic; result.underline = run.underline; result.strike = run.strike
  if run.color.len > 0: result.color = run.color
  if run.font.len > 0: result.font = run.font
  if run.fontSize > 0: result.fontSize = run.fontSize

proc toRun*(st: Style, text: string): RichRun =
  RichRun(text: text, bold: st.bold, italic: st.italic, underline: st.underline, strike: st.strike,
          color: st.color, font: st.font, fontSize: st.fontSize)

proc withoutFontOverrides*(r: RichRun): RichRun =
  ## The run as the cell's font: color / font / size left to the cell.
  result = r
  result.color = ""; result.font = ""; result.fontSize = 0

proc sameFont*(a, b: RichRun): bool =
  a.bold == b.bold and a.italic == b.italic and a.underline == b.underline and a.strike == b.strike and
    a.color == b.color and a.font == b.font and a.fontSize == b.fontSize

proc richText*(runs: seq[RichRun]): string =
  for r in runs: result.add r.text

proc hash*(s: Style): Hash =
  var h: Hash = 0
  h = h !& hash(s.bold) !& hash(s.italic) !& hash(s.underline) !& hash(s.strike) !& hash(s.wrap)
  h = h !& hash(s.fontSize) !& hash(s.font) !& hash(s.color) !& hash(s.fill)
  h = h !& hash(ord(s.hAlign)) !& hash(ord(s.vAlign)) !& hash(s.numFmt) !& hash(s.rotation) !& hash(s.unlocked)
  for b in [s.left, s.right, s.top, s.bottom]: h = h !& hash(ord(b.kind)) !& hash(b.color)
  !$h

proc key*(r, c: int): int64 {.inline.} = (int64(r) shl 16) or int64(c)
proc rowOf*(k: int64): int {.inline.} = int(k shr 16)
proc colOf*(k: int64): int {.inline.} = int(k and 0xFFFF)

proc emptyVal*(): Value = Value(kind: vkEmpty)
proc numVal*(x: float64): Value = Value(kind: vkNum, num: x)
proc strVal*(s: string): Value = Value(kind: vkStr, str: s)
proc boolVal*(b: bool): Value = Value(kind: vkBool, b: b)
proc errVal*(s: string): Value = Value(kind: vkErr, str: s)

proc `==`*(a, b: Value): bool =
  if a.kind != b.kind: return false
  case a.kind
  of vkEmpty: true
  of vkNum: a.num == b.num
  of vkStr, vkErr: a.str == b.str
  of vkBool: a.b == b.b
  of vkArr:
    if a.rows != b.rows or a.cols != b.cols or a.items.len != b.items.len: return false
    for i in 0 ..< a.items.len:
      if not (a.items[i] == b.items[i]): return false
    true

proc newWorkbook*(): Workbook =
  result = Workbook(styles: @[Style()])
  result.styleIds[Style()] = 0

proc styleId*(wb: Workbook, s: Style): int32 =
  ## The shared index of a style, adding it on first use.
  result = wb.styleIds.getOrDefault(s, -1)
  if result < 0:
    result = int32(wb.styles.len)
    wb.styles.add s
    wb.styleIds[s] = result

proc addSheet*(wb: Workbook, name: string): Sheet =
  result = Sheet(name: name)
  wb.sheets.add result

proc sheetNamed*(wb: Workbook, name: string): Sheet =
  for s in wb.sheets:
    if s.name.len == name.len:
      var same = true
      for i in 0 ..< name.len:
        if (if name[i] in {'A'..'Z'}: char(ord(name[i]) + 32) else: name[i]) !=
           (if s.name[i] in {'A'..'Z'}: char(ord(s.name[i]) + 32) else: s.name[i]):
          same = false; break
      if same: return s
  nil

const
  GrowRows* = 20     ## the empty rows kept below the data: entering data near the bottom extends the sheet
  GrowCols* = 10

proc rowCount*(s: Sheet): int =
  ## Rows the sheet shows: 84 at least, and always GrowRows below its data
  ## (Excel-like: data typed, pasted, filled, loaded or set by a program near
  ## the bottom extends the sheet; scrolling does not).
  min(MaxRows, max(max(max(s.rowsTotal, DefaultRowCount), s.viewRows), s.maxRow + GrowRows))

proc colCount*(s: Sheet): int = min(MaxCols, max(max(max(s.colsTotal, DefaultColCount), s.viewCols), s.maxCol + GrowCols))

proc cellAt*(s: Sheet, r, c: int): Cell =
  s.cells.getOrDefault(key(r, c))

proc hasCell*(s: Sheet, r, c: int): bool = s.cells.hasKey(key(r, c))

proc putCell*(s: Sheet, r, c: int, cell: Cell) =
  ## Stores a cell; an empty, unstyled cell is removed instead.
  if cell.value.kind == vkEmpty and cell.formula.len == 0 and cell.style == 0:
    s.cells.del(key(r, c))
  else:
    s.cells[key(r, c)] = cell
    if r >= s.maxRow: s.maxRow = r + 1
    if c >= s.maxCol: s.maxCol = c + 1

proc recomputeUsed*(s: Sheet) =
  s.maxRow = 0; s.maxCol = 0
  for k in s.cells.keys:
    if rowOf(k) >= s.maxRow: s.maxRow = rowOf(k) + 1
    if colOf(k) >= s.maxCol: s.maxCol = colOf(k) + 1

proc mergeAt*(s: Sheet, r, c: int): int =
  ## Index of the merged range containing (r, c), or -1.
  for i, m in s.merges:
    if r >= m.r1 and r <= m.r2 and c >= m.c1 and c <= m.c2: return i
  -1

proc addMerge*(s: Sheet, m: Merge) =
  ## Merges a range, replacing any merge it overlaps.
  var kept: seq[Merge]
  for x in s.merges:
    if x.r2 < m.r1 or x.r1 > m.r2 or x.c2 < m.c1 or x.c1 > m.c2: kept.add x
  if m.r2 > m.r1 or m.c2 > m.c1: kept.add m
  s.merges = kept

proc removeMerges*(s: Sheet, r1, c1, r2, c2: int) =
  var kept: seq[Merge]
  for x in s.merges:
    if x.r2 < r1 or x.r1 > r2 or x.c2 < c1 or x.c1 > c2: kept.add x
  s.merges = kept

proc colWidth*(s: Sheet, c: int): float64 = s.colWidths.getOrDefault(c, DefaultColWidth)
proc rowHeight*(s: Sheet, r: int): float64 = s.rowHeights.getOrDefault(r, DefaultRowHeight)

proc colHidden*(s: Sheet, c: int): bool {.inline.} = c in s.hiddenCols
proc rowHidden*(s: Sheet, r: int): bool {.inline.} = r in s.hiddenRows or r in s.filterRows

proc colX*(s: Sheet, c: int): float64 =
  ## Left edge of column c from the sheet's left edge: Luckysheet's
  ## visibledatacolumn[c - 1]: each column takes round(length + 1 px line)
  ## (rhchInit.js:83).
  result = float64(c) * (DefaultColWidth + 1)
  for k, w in s.colWidths:
    if k < c: result += round(w + 1) - (DefaultColWidth + 1)
  for k in s.hiddenCols:
    if k < c: result -= round(s.colWidth(k) + 1)

proc rowY*(s: Sheet, r: int): float64 =
  ## Top edge of row r: visibledatarow[r - 1], round(length + 1) per row (rhchInit.js:28).
  result = float64(r) * (DefaultRowHeight + 1)
  for k, h in s.rowHeights:
    if k < r: result += round(h + 1) - (DefaultRowHeight + 1)
  for k in s.hiddenRows:
    if k < r: result -= round(s.rowHeight(k) + 1)
  for k in s.filterRows:
    if k < r and k notin s.hiddenRows: result -= round(s.rowHeight(k) + 1)

proc colAt*(s: Sheet, x: float64): int =
  ## The column containing x (sheet coordinates).
  if s.colWidths.len == 0 and s.hiddenCols.len == 0: return clamp(int(x / (DefaultColWidth + 1)), 0, MaxCols - 1)
  var c = clamp(int(x / (DefaultColWidth + 1)), 0, MaxCols - 1)
  while c > 0 and s.colX(c) > x: dec c
  while c < MaxCols - 1 and s.colX(c + 1) <= x: inc c
  c

proc rowAt*(s: Sheet, y: float64): int =
  if s.rowHeights.len == 0 and s.hiddenRows.len == 0 and s.filterRows.len == 0: return clamp(int(y / (DefaultRowHeight + 1)), 0, MaxRows - 1)
  var r = clamp(int(y / (DefaultRowHeight + 1)), 0, MaxRows - 1)
  while r > 0 and s.rowY(r) > y: dec r
  while r < MaxRows - 1 and s.rowY(r + 1) <= y: inc r
  r

proc toHexLower(h: int): string =
  const d = "0123456789ABCDEF"
  for shift in [12, 8, 4, 0]: result.add d[(h shr shift) and 15]

proc passwordHash*(pw: string): string =
  ## Excel's legacy sheet-protection hash (ECMA-376 Part 4, 14.7.1), as 4 hex digits.
  if pw.len == 0: return ""
  var h = 0
  for i in countdown(pw.len - 1, 0):
    h = ((h shr 14) and 1) or ((h shl 1) and 0x7FFF)
    h = h xor ord(pw[i])
  h = ((h shr 14) and 1) or ((h shl 1) and 0x7FFF)
  h = h xor pw.len xor 0xCE4B
  toHexLower(h)

proc colName*(c: int): string =
  ## 0 -> "A", 25 -> "Z", 26 -> "AA".
  var n = c + 1
  while n > 0:
    let m = (n - 1) mod 26
    result = char(ord('A') + m) & result
    n = (n - 1) div 26

proc cellName*(r, c: int): string = colName(c) & $(r + 1)

# ------------------------------------------------------------ serialization --
# A compact binary form of a workbook, for handing one between the page and
# its file worker (cheaper than JSON on both sides). Formulas travel as text;
# the receiver parses them.

proc putU32(s: var string, v: int) =
  for shift in [0, 8, 16, 24]: s.add char((v shr shift) and 0xFF)
proc putF64(s: var string, x: float64) =
  var b: array[8, char]
  copyMem(addr b[0], unsafeAddr x, 8)
  for ch in b: s.add ch
proc putStr(s: var string, t: string) =
  s.putU32(t.len); s.add t

type Reader = object
  s: string
  i: int
proc u32(r: var Reader): int =
  if r.i + 4 > r.s.len: raise newException(ValueError, "truncated workbook")
  result = ord(r.s[r.i]) or (ord(r.s[r.i + 1]) shl 8) or (ord(r.s[r.i + 2]) shl 16) or (ord(r.s[r.i + 3]) shl 24)
  r.i += 4
proc f64(r: var Reader): float64 =
  if r.i + 8 > r.s.len: raise newException(ValueError, "truncated workbook")
  copyMem(addr result, unsafeAddr r.s[r.i], 8)
  r.i += 8
proc str(r: var Reader): string =
  let n = r.u32()
  if n < 0 or r.i + n > r.s.len: raise newException(ValueError, "truncated workbook")
  result = r.s[r.i ..< r.i + n]
  r.i += n
proc u8(r: var Reader): int =
  if r.i >= r.s.len: raise newException(ValueError, "truncated workbook")
  result = ord(r.s[r.i]); inc r.i

proc putRect(s: var string, r1, c1, r2, c2: int) =
  s.putU32(r1); s.putU32(c1); s.putU32(r2); s.putU32(c2)

proc putSheetExtras(o: var string, s: Sheet) =
  ## freeze, filter, rules, validation, notes, links, pictures, protection, pivot
  o.putU32(s.frozenRows); o.putU32(s.frozenCols)
  o.add char(ord(s.filter.on))
  o.putRect(s.filter.r1, s.filter.c1, s.filter.r2, s.filter.c2)
  o.putU32(s.filter.hidden.len)
  for c, vals in s.filter.hidden:
    o.putU32(c); o.putU32(vals.len)
    for t in vals: o.putStr(t)
  o.putU32(s.filterRows.len)
  for r in s.filterRows: o.putU32(r)
  o.putU32(s.condRules.len)
  for cr in s.condRules:
    o.putRect(cr.r1, cr.c1, cr.r2, cr.c2); o.add char(ord(cr.kind))
    o.putStr(cr.v1); o.putStr(cr.v2); o.putStr(cr.fill); o.putStr(cr.color); o.add char(ord(cr.bold))
    o.putU32(cr.colors.len)
    for c in cr.colors: o.putStr(c)
  o.putU32(s.validations.len)
  for dv in s.validations:
    o.putRect(dv.r1, dv.c1, dv.r2, dv.c2); o.add char(ord(dv.kind))
    o.putStr(dv.op); o.putStr(dv.v1); o.putStr(dv.v2); o.putStr(dv.list); o.add char(ord(dv.allowBlank)); o.putStr(dv.error)
  for t in [s.notes, s.links]:
    o.putU32(t.len)
    for k, text in t: o.putU32(rowOf(k)); o.putU32(colOf(k)); o.putStr(text)
  o.putU32(s.pictures.len)
  for p in s.pictures:
    o.putStr(p.src); o.putF64(p.x); o.putF64(p.y); o.putF64(p.w); o.putF64(p.h)
  o.add char(ord(s.protected)); o.putStr(s.protectHash)
  o.putStr(s.pivot.source); o.putRect(s.pivot.r1, s.pivot.c1, s.pivot.r2, s.pivot.c2)
  o.putU32(s.pivot.rowField + 1); o.putU32(s.pivot.colField + 1); o.putU32(s.pivot.valueField + 1); o.putStr(s.pivot.agg)

proc serialize*(wb: Workbook): string =
  result = "QSW3"
  result.putU32(wb.styles.len)
  for st in wb.styles:
    result.add char(ord(st.bold) or (ord(st.italic) shl 1) or (ord(st.underline) shl 2) or (ord(st.strike) shl 3) or (ord(st.wrap) shl 4) or (ord(st.unlocked) shl 5))
    result.putU32(st.rotation + 1000)
    result.putF64(st.fontSize)
    result.putStr(st.font); result.putStr(st.color); result.putStr(st.fill); result.putStr(st.numFmt)
    result.add char(ord(st.hAlign)); result.add char(ord(st.vAlign))
    for b in [st.left, st.right, st.top, st.bottom]:
      result.add char(ord(b.kind)); result.putStr(b.color)
  result.putU32(wb.active)
  result.putU32(wb.sheets.len)
  for s in wb.sheets:
    result.putStr(s.name)
    result.putU32(s.colWidths.len)
    for c, w in s.colWidths: result.putU32(c); result.putF64(w)
    result.putU32(s.rowHeights.len)
    for r, h in s.rowHeights: result.putU32(r); result.putF64(h)
    result.putU32(s.merges.len)
    for m in s.merges: result.putU32(m.r1); result.putU32(m.c1); result.putU32(m.r2); result.putU32(m.c2)
    result.putU32(s.hiddenRows.len)
    for r in s.hiddenRows: result.putU32(r)
    result.putU32(s.hiddenCols.len)
    for c in s.hiddenCols: result.putU32(c)
    result.putStr(s.tabColor)
    result.add char(ord(s.hidden))
    result.putSheetExtras(s)
    result.putU32(s.cells.len)
    for k, cell in s.cells:
      result.putU32(rowOf(k)); result.putU32(colOf(k)); result.putU32(int(cell.style))
      result.add char(ord(cell.value.kind))
      case cell.value.kind
      of vkNum: result.putF64(cell.value.num)
      of vkStr, vkErr: result.putStr(cell.value.str)
      of vkBool: result.add char(ord(cell.value.b))
      else: discard
      result.putStr(cell.formula)
      result.putU32(cell.rich.len)
      for run in cell.rich:
        result.putStr(run.text)
        result.add char(ord(run.bold) or (ord(run.italic) shl 1) or (ord(run.underline) shl 2) or (ord(run.strike) shl 3))
        result.putStr(run.color); result.putStr(run.font); result.putF64(run.fontSize)

proc getSheetExtras(r: var Reader, s: Sheet) =
  s.frozenRows = r.u32(); s.frozenCols = r.u32()
  s.filter.on = r.u8() != 0
  s.filter.r1 = r.u32(); s.filter.c1 = r.u32(); s.filter.r2 = r.u32(); s.filter.c2 = r.u32()
  for _ in 0 ..< r.u32():
    let c = r.u32()
    var vals: seq[string]
    for _ in 0 ..< r.u32(): vals.add r.str()
    s.filter.hidden[c] = vals
  for _ in 0 ..< r.u32(): s.filterRows.incl r.u32()
  for _ in 0 ..< r.u32():
    var cr = CondRule(r1: r.u32(), c1: r.u32(), r2: r.u32(), c2: r.u32())
    cr.kind = CondKind(clamp(r.u8(), 0, ord(CondKind.high)))
    cr.v1 = r.str(); cr.v2 = r.str(); cr.fill = r.str(); cr.color = r.str(); cr.bold = r.u8() != 0
    for _ in 0 ..< r.u32(): cr.colors.add r.str()
    s.condRules.add cr
  for _ in 0 ..< r.u32():
    var dv = Validation(r1: r.u32(), c1: r.u32(), r2: r.u32(), c2: r.u32())
    dv.kind = DvKind(clamp(r.u8(), 0, ord(DvKind.high)))
    dv.op = r.str(); dv.v1 = r.str(); dv.v2 = r.str(); dv.list = r.str(); dv.allowBlank = r.u8() != 0; dv.error = r.str()
    s.validations.add dv
  for which in 0 .. 1:
    for _ in 0 ..< r.u32():
      let rr = r.u32(); let cc = r.u32(); let text = r.str()
      if which == 0: s.notes[key(rr, cc)] = text else: s.links[key(rr, cc)] = text
  for _ in 0 ..< r.u32():
    s.pictures.add Picture(src: r.str(), x: r.f64(), y: r.f64(), w: r.f64(), h: r.f64())
  s.protected = r.u8() != 0; s.protectHash = r.str()
  s.pivot.source = r.str()
  s.pivot.r1 = r.u32(); s.pivot.c1 = r.u32(); s.pivot.r2 = r.u32(); s.pivot.c2 = r.u32()
  s.pivot.rowField = r.u32() - 1; s.pivot.colField = r.u32() - 1; s.pivot.valueField = r.u32() - 1; s.pivot.agg = r.str()

proc deserialize*(data: string, parseFormula: proc(cell: var Cell, text: string)): Workbook =
  var r = Reader(s: data)
  if data.len < 4 or data[0 .. 3] != "QSW3": raise newException(ValueError, "not a workbook")
  r.i = 4
  result = Workbook(styles: @[])
  let ns = r.u32()
  for _ in 0 ..< ns:
    let flags = r.u8()
    var st = Style(bold: (flags and 1) != 0, italic: (flags and 2) != 0, underline: (flags and 4) != 0,
                   strike: (flags and 8) != 0, wrap: (flags and 16) != 0, unlocked: (flags and 32) != 0)
    st.rotation = r.u32() - 1000
    st.fontSize = r.f64()
    st.font = r.str(); st.color = r.str(); st.fill = r.str(); st.numFmt = r.str()
    st.hAlign = HAlign(clamp(r.u8(), 0, ord(HAlign.high)))
    st.vAlign = VAlign(clamp(r.u8(), 0, ord(VAlign.high)))
    for side in 0 .. 3:
      let b = Border(kind: BorderKind(clamp(r.u8(), 0, ord(BorderKind.high))), color: r.str())
      case side
      of 0: st.left = b
      of 1: st.right = b
      of 2: st.top = b
      else: st.bottom = b
    result.styleIds[st] = int32(result.styles.len)
    result.styles.add st
  if result.styles.len == 0:
    result.styles.add Style(); result.styleIds[Style()] = 0
  result.active = r.u32()
  let nsheets = r.u32()
  for _ in 0 ..< nsheets:
    let s = result.addSheet(r.str())
    for _ in 0 ..< r.u32():
      let c = r.u32(); s.colWidths[c] = r.f64()
    for _ in 0 ..< r.u32():
      let rr = r.u32(); s.rowHeights[rr] = r.f64()
    for _ in 0 ..< r.u32():
      s.merges.add Merge(r1: r.u32(), c1: r.u32(), r2: r.u32(), c2: r.u32())
    for _ in 0 ..< r.u32(): s.hiddenRows.incl r.u32()
    for _ in 0 ..< r.u32(): s.hiddenCols.incl r.u32()
    s.tabColor = r.str()
    s.hidden = r.u8() != 0
    r.getSheetExtras(s)
    let n = r.u32()
    for _ in 0 ..< n:
      let row = r.u32(); let col = r.u32()
      var cell = Cell(style: int32(clamp(r.u32(), 0, result.styles.len - 1)))
      let kind = ValKind(clamp(r.u8(), 0, ord(ValKind.high)))
      case kind
      of vkNum: cell.value = numVal(r.f64())
      of vkStr: cell.value = strVal(r.str())
      of vkErr: cell.value = errVal(r.str())
      of vkBool: cell.value = boolVal(r.u8() != 0)
      else: cell.value = emptyVal()
      let f = r.str()
      if f.len > 0:
        let cached = cell.value
        parseFormula(cell, f)
        cell.value = cached
      for _ in 0 ..< r.u32():
        var run = RichRun(text: r.str())
        let fl = r.u8()
        run.bold = (fl and 1) != 0; run.italic = (fl and 2) != 0; run.underline = (fl and 4) != 0; run.strike = (fl and 8) != 0
        run.color = r.str(); run.font = r.str(); run.fontSize = r.f64()
        cell.rich.add run
      if row >= 0 and col >= 0 and row < MaxRows and col < MaxCols: s.putCell(row, col, cell)
  result.active = clamp(result.active, 0, max(result.sheets.len - 1, 0))
