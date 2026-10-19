## QoqoroSheet's workbook model: sheets of sparse cells, shared styles,
## column widths and row heights. Pure Nim (no host imports), so the model
## and the formula engine can be tested natively.

import std/[tables, hashes]

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
  VAlign* = enum vaBottom, vaMiddle, vaTop
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

  Cell* = object
    value*: Value                  ## the literal, or the formula's last result
    formula*: string               ## "=..." or ""
    ast*: Expr                     ## parsed formula (nil if none or unparsable)
    style*: int32                  ## index into Workbook.styles; 0 = default
    stamp*: int32                  ## recalculation pass that computed `value`

  Sheet* = ref object
    name*: string
    cells*: Table[int64, Cell]
    colWidths*: Table[int, float64]
    rowHeights*: Table[int, float64]
    maxRow*, maxCol*: int          ## used range (exclusive); grows, recomputed on demand
    merges*: seq[Merge]            ## merged ranges; the top-left cell holds the content

  Merge* = object
    r1*, c1*, r2*, c2*: int        ## inclusive, 0-based

  Workbook* = ref object
    sheets*: seq[Sheet]
    active*: int
    styles*: seq[Style]
    styleIds: Table[Style, int32]
    pass*: int32                   ## recalculation pass counter

const
  MaxRows* = 1_048_576
  MaxCols* = 16_384
  DefaultColWidth* = 80.0
  DefaultRowHeight* = 21.0

proc hash*(s: Style): Hash =
  var h: Hash = 0
  h = h !& hash(s.bold) !& hash(s.italic) !& hash(s.underline) !& hash(s.strike) !& hash(s.wrap)
  h = h !& hash(s.fontSize) !& hash(s.font) !& hash(s.color) !& hash(s.fill)
  h = h !& hash(ord(s.hAlign)) !& hash(ord(s.vAlign)) !& hash(s.numFmt)
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

proc colX*(s: Sheet, c: int): float64 =
  ## Left edge of column c, from the sheet's left edge.
  result = float64(c) * DefaultColWidth
  for k, w in s.colWidths:
    if k < c: result += w - DefaultColWidth

proc rowY*(s: Sheet, r: int): float64 =
  result = float64(r) * DefaultRowHeight
  for k, h in s.rowHeights:
    if k < r: result += h - DefaultRowHeight

proc colAt*(s: Sheet, x: float64): int =
  ## The column containing x (sheet coordinates).
  if s.colWidths.len == 0: return clamp(int(x / DefaultColWidth), 0, MaxCols - 1)
  var c = clamp(int(x / DefaultColWidth), 0, MaxCols - 1)
  while c > 0 and s.colX(c) > x: dec c
  while c < MaxCols - 1 and s.colX(c + 1) <= x: inc c
  c

proc rowAt*(s: Sheet, y: float64): int =
  if s.rowHeights.len == 0: return clamp(int(y / DefaultRowHeight), 0, MaxRows - 1)
  var r = clamp(int(y / DefaultRowHeight), 0, MaxRows - 1)
  while r > 0 and s.rowY(r) > y: dec r
  while r < MaxRows - 1 and s.rowY(r + 1) <= y: inc r
  r

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

proc serialize*(wb: Workbook): string =
  result = "QSW2"
  result.putU32(wb.styles.len)
  for st in wb.styles:
    result.add char(ord(st.bold) or (ord(st.italic) shl 1) or (ord(st.underline) shl 2) or (ord(st.strike) shl 3) or (ord(st.wrap) shl 4))
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

proc deserialize*(data: string, parseFormula: proc(cell: var Cell, text: string)): Workbook =
  var r = Reader(s: data)
  if data.len < 4 or data[0 .. 3] != "QSW2": raise newException(ValueError, "not a workbook")
  r.i = 4
  result = Workbook(styles: @[])
  let ns = r.u32()
  for _ in 0 ..< ns:
    let flags = r.u8()
    var st = Style(bold: (flags and 1) != 0, italic: (flags and 2) != 0, underline: (flags and 4) != 0,
                   strike: (flags and 8) != 0, wrap: (flags and 16) != 0)
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
      if row >= 0 and col >= 0 and row < MaxRows and col < MaxCols: s.putCell(row, col, cell)
  result.active = clamp(result.active, 0, max(result.sheets.len - 1, 0))
