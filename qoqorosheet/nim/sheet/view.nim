## QoqoroSheet's grid: canvas rendering, selection, editing, keyboard,
## clipboard, column/row resizing, sheet tabs, toolbar and formula bar.
##
## The page is built with qweb (DOM handles, events) and drawn with the
## Canvas2D recorder (canvas.nim) that qweb replays in one call per frame.
## Scrolling as in Luckysheet: two native scrollbar strips (12 px, the
## horizontal one starting at the row header) hold the scroll offsets, the
## canvas draws whatever they show, and the wheel over the cells moves whole
## rows (1-3 per notch, landing on a row boundary) or 20 px sideways. Touch
## drags scroll; a tap selects.

import std/[tables, strutils, math, json, sequtils]
import ../host, ../canvas, ../web/qweb
import model, formula

const
  RowHeaderW = 46.0
  ColHeaderH = 24.0
  GridLine = "#e2e3e3"
  HeaderFill = "#f8f9fa"
  HeaderLine = "#c0c0c0"
  SelBlue = "#1a73e8"
  ScrollBar = 12.0          ## Luckysheet's cellMainSrollBarSize
  DefaultFont = "Arial"
  DefaultSize = 10.0

type
  Change = object
    sheet, r, c: int
    before, after: Cell
    isMerge: bool                     ## a merge change: the sheet's merges before/after
    mergesBefore, mergesAfter: seq[Merge]
  Action = seq[Change]

  SheetView* = ref object
    wb*: Workbook
    root*, toolbar, fxName, fxInput, grid*, canvas, hit*, sbX*, sbY*, spacerX, spacerY, editor*, tabs*: Node
    programPanel*, programText*, programOut*, programTemplates*: Node
    ctx: Node
    rec: Ctx
    dpr, width, height: float64
    scrollX, scrollY: float64
    # selection: anchor (ar, ac) and moving corner (cr, cc); active cell = anchor
    ar*, ac*, cr*, cc*: int
    editing*: bool
    editFromFormulaBar: bool
    dragging: int            ## 0 none, 1 cells, 2 col resize, 3 row resize, 4 col headers, 5 row headers
    resizeIndex: int
    resizeStart, resizeOrig: float64
    touchX, touchY, touchScrollX, touchScrollY: float64
    touchMoved: bool
    undo, redo: seq[Action]
    framePending: bool
    fileName*: string
    onChange*: proc()        ## after any edit (the host may mark the document dirty)
    hostCall*: proc(name: string, args: JsonNode)   ## toolbar actions handled by the page (open, save…)

proc sheet*(v: SheetView): Sheet = v.wb.sheets[v.wb.active]

proc expandToMerges*(s: Sheet, r1, c1, r2, c2: int): (int, int, int, int) =
  ## The smallest range containing r1..r2 x c1..c2 and every merge it touches.
  var (a, b, e, f) = (r1, c1, r2, c2)
  var changed = s.merges.len > 0
  while changed:
    changed = false
    for m in s.merges:
      if m.r2 >= a and m.r1 <= e and m.c2 >= b and m.c1 <= f:
        if m.r1 < a: a = m.r1; changed = true
        if m.c1 < b: b = m.c1; changed = true
        if m.r2 > e: e = m.r2; changed = true
        if m.c2 > f: f = m.c2; changed = true
  (a, b, e, f)

proc selRect*(v: SheetView): (int, int, int, int) =
  v.sheet.expandToMerges(min(v.ar, v.cr), min(v.ac, v.cc), max(v.ar, v.cr), max(v.ac, v.cc))

proc snapAnchor*(v: SheetView) =
  ## The active cell of a merged range is its top-left cell.
  let i = v.sheet.mergeAt(v.ar, v.ac)
  if i >= 0:
    let m = v.sheet.merges[i]
    if v.cr == v.ar and v.cc == v.ac: v.cr = m.r1; v.cc = m.c1
    v.ar = m.r1; v.ac = m.c1

proc stepFrom(s: Sheet, r, c, dr, dc: int): (int, int) =
  ## One cell on from (r, c), stepping over a merged range as a whole.
  var rr = r
  var cc = c
  let i = s.mergeAt(r, c)
  if i >= 0:
    let m = s.merges[i]
    if dr > 0: rr = m.r2
    if dr < 0: rr = m.r1
    if dc > 0: cc = m.c2
    if dc < 0: cc = m.c1
  (rr + dr, cc + dc)

# ------------------------------------------------------------- display text --

proc displayText*(wb: Workbook, cell: Cell): string =
  let st = wb.styles[cell.style]
  case cell.value.kind
  of vkNum: (if st.numFmt.len > 0: formatNumber(cell.value.num, st.numFmt) else: fmtGeneral(cell.value.num))
  else: toText(cell.value)

proc fontOf(st: Style, scale = 1.0): string =
  (if st.italic: "italic " else: "") & (if st.bold: "bold " else: "") &
    $(if st.fontSize > 0: st.fontSize else: DefaultSize) & "pt " &
    (if st.font.len > 0: "\"" & st.font & "\", " else: "") & DefaultFont & ", sans-serif"

# ------------------------------------------------------------------ drawing --

proc draw*(v: SheetView)

proc requestDraw*(v: SheetView) =
  if v.framePending: return
  v.framePending = true
  requestAnimationFrame(proc(now: float64) =
    v.framePending = false
    v.draw())

proc visibleCols(v: SheetView): (int, int) =
  let s = v.sheet
  let first = s.colAt(v.scrollX)
  var last = first
  while last < MaxCols - 1 and s.colX(last) - v.scrollX < v.width - RowHeaderW: inc last
  (first, last)

proc visibleRows(v: SheetView): (int, int) =
  let s = v.sheet
  let first = s.rowAt(v.scrollY)
  var last = first
  while last < MaxRows - 1 and s.rowY(last) - v.scrollY < v.height - ColHeaderH: inc last
  (first, last)

proc cellBox*(v: SheetView, r, c: int): (float64, float64, float64, float64) =
  ## A cell's box in grid coordinates (relative to the grid's top-left).
  let s = v.sheet
  (RowHeaderW + s.colX(c) - v.scrollX, ColHeaderH + s.rowY(r) - v.scrollY, s.colWidth(c), s.rowHeight(r))

proc rangeBox*(v: SheetView, r1, c1, r2, c2: int): (float64, float64, float64, float64) =
  let s = v.sheet
  let x = s.colX(c1)
  let y = s.rowY(r1)
  (RowHeaderW + x - v.scrollX, ColHeaderH + y - v.scrollY, s.colX(c2 + 1) - x, s.rowY(r2 + 1) - y)

proc activeBox*(v: SheetView): (float64, float64, float64, float64) =
  ## The active cell's box: the whole range when it is merged.
  let i = v.sheet.mergeAt(v.ar, v.ac)
  if i < 0: return v.cellBox(v.ar, v.ac)
  let m = v.sheet.merges[i]
  v.rangeBox(m.r1, m.c1, m.r2, m.c2)

proc draw*(v: SheetView) =
  let w = max(0.0, v.grid.getNum("clientWidth") - ScrollBar)
  let h = max(0.0, v.grid.getNum("clientHeight") - ScrollBar)
  let dpr = max(1.0, window.getNum("devicePixelRatio"))
  if w != v.width or h != v.height or dpr != v.dpr:
    v.width = w; v.height = h; v.dpr = dpr
    v.canvas.setProp("width", int(round(w * dpr)))
    v.canvas.setProp("height", int(round(h * dpr)))
    v.canvas.style("width", $w & "px")
    v.canvas.style("height", $h & "px")
  v.scrollX = v.sbX.getNum("scrollLeft")
  v.scrollY = v.sbY.getNum("scrollTop")
  let s = v.sheet
  let c = v.rec
  c.reset()
  c.setTransform(dpr, 0, 0, dpr, 0, 0)
  c.fillStyle = "#ffffff"
  c.fillRect(0, 0, w, h)
  let (c0, c1) = v.visibleCols()
  let (r0, r1) = v.visibleRows()
  let (sr1, sc1, sr2, sc2) = v.selRect()

  # Cells area (clipped below/right of the headers)
  c.save()
  c.beginPath(); c.rect(RowHeaderW, ColHeaderH, w - RowHeaderW, h - ColHeaderH); c.clip()
  # fills
  for r in r0 .. r1:
    for col in c0 .. c1:
      let k = key(r, col)
      if s.cells.hasKey(k):
        let st = v.wb.styles[s.cells[k].style]
        if st.fill.len > 0:
          let (x, y, cw, ch) = v.cellBox(r, col)
          c.fillStyle = st.fill
          c.fillRect(x, y, cw, ch)
  # grid lines
  c.strokeStyle = GridLine
  c.lineWidth = 1
  c.beginPath()
  for col in c0 .. c1 + 1:
    let x = floor(RowHeaderW + s.colX(col) - v.scrollX) + 0.5
    c.moveTo(x, ColHeaderH); c.lineTo(x, h)
  for r in r0 .. r1 + 1:
    let y = floor(ColHeaderH + s.rowY(r) - v.scrollY) + 0.5
    c.moveTo(RowHeaderW, y); c.lineTo(w, y)
  c.stroke()
  # merged ranges: one box over the grid lines inside, in the top-left cell's fill
  var visMerges: seq[Merge]
  for m in s.merges:
    if m.r2 >= r0 and m.r1 <= r1 and m.c2 >= c0 and m.c1 <= c1: visMerges.add m
  for m in visMerges:
    let (x, y, mw, mh) = v.rangeBox(m.r1, m.c1, m.r2, m.c2)
    let st = v.wb.styles[s.cellAt(m.r1, m.c1).style]
    c.fillStyle = (if st.fill.len > 0: st.fill else: "#ffffff")
    c.fillRect(floor(x) + 1, floor(y) + 1, floor(x + mw) - floor(x) - 1, floor(y + mh) - floor(y) - 1)

  proc drawText(cell: Cell, x, y, cw, ch: float64, row, col: int, overflow: bool) =
    let text = v.wb.displayText(cell)
    if text.len == 0: return
    let st = v.wb.styles[cell.style]
    c.font = fontOf(st)
    var align = st.hAlign
    if align == haGeneral:
      align = case cell.value.kind
        of vkNum: haRight
        of vkBool, vkErr: haCenter
        else: haLeft
    let tw = measureText(c.font, text)
    var clipW = cw
    var shown = text
    if cell.value.kind == vkNum and tw > cw - 4 and st.numFmt.len == 0:
      # General in a narrow column: fewer significant digits, decimal while it
      # still shows a significant digit, else scientific; ### as a last resort.
      shown = "###"
      let x = cell.value.num
      block fit:
        for sig in countdown(10, 1):
          let d = fmtSignificant(x, sig, false)
          if d.anyIt(it in {'1'..'9'}) and abs(x) >= 1e-4 and measureText(c.font, d) <= cw - 4: shown = d; break fit
          let e = fmtSignificant(x, sig, true)
          if measureText(c.font, e) <= cw - 4: shown = e; break fit
    elif overflow and align == haLeft and tw > cw - 4:
      var nx = col + 1
      while nx < MaxCols and clipW < tw + 6 and not s.hasCell(row, nx) and (s.merges.len == 0 or s.mergeAt(row, nx) < 0):
        clipW += s.colWidth(nx); inc nx
    c.save()
    c.beginPath(); c.rect(x, y, clipW, ch); c.clip()
    c.fillStyle = (if st.color.len > 0: st.color elif cell.value.kind == vkErr: "#c5221f" else: "#000000")
    let ty = case st.vAlign
      of vaTop: y + 8
      of vaMiddle: y + ch / 2
      of vaBottom: y + ch - 8
    var tx: float64
    case align
    of haCenter:
      c.textAlign = "center"; tx = x + cw / 2
    of haRight:
      c.textAlign = "right"; tx = x + cw - 3
    else:
      c.textAlign = "left"; tx = x + 3
    c.fillText(shown, tx, ty)
    if st.underline or st.strike:
      let sw = min(measureText(c.font, shown), clipW - 4)
      let lx = if align == haCenter: tx - sw / 2 elif align == haRight: tx - sw else: tx
      c.strokeStyle = c.fillStyle
      c.beginPath()
      if st.underline: c.moveTo(lx, ty + 7); c.lineTo(lx + sw, ty + 7)
      if st.strike: c.moveTo(lx, ty); c.lineTo(lx + sw, ty)
      c.stroke()
    c.restore()

  # text
  c.textBaseline = "middle"
  let anyMerge = s.merges.len > 0
  for r in r0 .. r1:
    var col = c0
    # text overflowing from a cell left of the view
    var startCol = c0
    while startCol > 0 and startCol > c0 - 8 and not s.hasCell(r, startCol - 1): dec startCol
    if startCol > 0 and s.hasCell(r, startCol - 1): col = startCol - 1 else: col = c0
    while col <= c1:
      let k = key(r, col)
      if not s.cells.hasKey(k) or (anyMerge and s.mergeAt(r, col) >= 0): inc col; continue
      let (x, y, cw, ch) = v.cellBox(r, col)
      drawText(s.cells[k], x, y, cw, ch, r, col, true)
      inc col
  for m in visMerges:
    let (x, y, mw, mh) = v.rangeBox(m.r1, m.c1, m.r2, m.c2)
    drawText(s.cellAt(m.r1, m.c1), x, y, mw, mh, m.r1, m.c1, false)

  # borders (each cell's own; adjacent cells may both draw a shared edge)
  proc edge(b: Border, x1, y1, x2, y2: float64) =
    if b.kind == bkNone: return
    c.strokeStyle = (if b.color.len > 0: b.color else: "#000000")
    let width = case b.kind
      of bkMedium: 2.0
      of bkThick: 3.0
      else: 1.0
    c.lineWidth = width
    case b.kind
    of bkDashed: c.setLineDash([4.0, 2.0])
    of bkDotted: c.setLineDash([1.0, 2.0])
    of bkHair: c.setLineDash([1.0, 1.0])
    else: c.setLineDash([])
    let off = if int(width) mod 2 == 1: 0.5 else: 0.0
    let vertical = x1 == x2
    let ax = if vertical: floor(x1) + off else: x1
    let ay = if vertical: y1 else: floor(y1) + off
    let bx = if vertical: floor(x2) + off else: x2
    let by = if vertical: y2 else: floor(y2) + off
    c.beginPath()
    if b.kind == bkDouble:
      if vertical:
        c.moveTo(ax - 1, ay); c.lineTo(bx - 1, by); c.moveTo(ax + 1, ay); c.lineTo(bx + 1, by)
      else:
        c.moveTo(ax, ay - 1); c.lineTo(bx, by - 1); c.moveTo(ax, ay + 1); c.lineTo(bx, by + 1)
    else:
      c.moveTo(ax, ay); c.lineTo(bx, by)
    c.stroke()
  for r in r0 .. r1:
    for col in c0 .. c1:
      let k = key(r, col)
      if not s.cells.hasKey(k): continue
      let st = v.wb.styles[s.cells[k].style]
      if st.left.kind == bkNone and st.right.kind == bkNone and st.top.kind == bkNone and st.bottom.kind == bkNone: continue
      let (x, y, cw, ch) = v.cellBox(r, col)
      edge(st.top, x, y, x + cw, y)
      edge(st.bottom, x, y + ch, x + cw, y + ch)
      edge(st.left, x, y, x, y + ch)
      edge(st.right, x + cw, y, x + cw, y + ch)
  c.setLineDash([])

  # selection
  let (sx, sy, sw, sh) = v.rangeBox(sr1, sc1, sr2, sc2)
  let (ax, ay, aw, ah) = v.activeBox()
  let single = ax == sx and ay == sy and aw == sw and ah == sh
  if not single:
    c.fillStyle = "rgba(26,115,232,0.10)"
    c.fillRect(sx, sy, sw, sh)
  c.strokeStyle = SelBlue
  c.lineWidth = 2
  c.strokeRect(sx + 1, sy + 1, sw - 2, sh - 2)   # inside the cell: never half under the headers
  if not single:
    c.lineWidth = 1
    c.strokeRect(ax + 1.5, ay + 1.5, aw - 3, ah - 3)
  c.fillStyle = SelBlue
  c.fillRect(sx + sw - 3, sy + sh - 3, 6, 6)
  c.restore()

  # Column headers
  c.fillStyle = HeaderFill
  c.fillRect(0, 0, w, ColHeaderH)
  c.fillRect(0, 0, RowHeaderW, h)
  c.font = "10pt Arial, sans-serif"
  c.textAlign = "center"
  c.textBaseline = "middle"
  c.save()
  c.beginPath(); c.rect(RowHeaderW, 0, w - RowHeaderW, ColHeaderH); c.clip()
  for col in c0 .. c1:
    let x = RowHeaderW + s.colX(col) - v.scrollX
    let cw = s.colWidth(col)
    let selected = col >= sc1 and col <= sc2
    if selected:
      c.fillStyle = "#e8f0fe"; c.fillRect(x, 0, cw, ColHeaderH)
    c.fillStyle = (if selected: SelBlue else: "#444444")
    c.fillText(colName(col), x + cw / 2, ColHeaderH / 2 + 1)
  c.strokeStyle = HeaderLine
  c.lineWidth = 1
  c.beginPath()
  for col in c0 .. c1 + 1:
    let x = floor(RowHeaderW + s.colX(col) - v.scrollX) + 0.5
    c.moveTo(x, 0); c.lineTo(x, ColHeaderH)
  c.stroke()
  c.restore()
  # Row headers
  c.save()
  c.beginPath(); c.rect(0, ColHeaderH, RowHeaderW, h - ColHeaderH); c.clip()
  for r in r0 .. r1:
    let y = ColHeaderH + s.rowY(r) - v.scrollY
    let rh = s.rowHeight(r)
    let selected = r >= sr1 and r <= sr2
    if selected:
      c.fillStyle = "#e8f0fe"; c.fillRect(0, y, RowHeaderW, rh)
    c.fillStyle = (if selected: SelBlue else: "#444444")
    c.fillText($(r + 1), RowHeaderW / 2, y + rh / 2 + 1)
  c.strokeStyle = HeaderLine
  c.beginPath()
  for r in r0 .. r1 + 1:
    let y = floor(ColHeaderH + s.rowY(r) - v.scrollY) + 0.5
    c.moveTo(0, y); c.lineTo(RowHeaderW, y)
  c.stroke()
  c.restore()
  # header borders and corner
  c.strokeStyle = HeaderLine
  c.beginPath()
  c.moveTo(0, ColHeaderH + 0.5); c.lineTo(w, ColHeaderH + 0.5)
  c.moveTo(RowHeaderW + 0.5, 0); c.lineTo(RowHeaderW + 0.5, h)
  c.stroke()
  c.fillStyle = "#e8eaed"
  c.fillRect(0, 0, RowHeaderW, ColHeaderH)
  c.finish()
  replay(v.ctx, addr c.buf)

  # Scroll extent: the used range plus room to grow.
  let needW = max(s.colX(max(s.maxCol, c1) + 30), v.scrollX + w * 2)
  let needH = max(s.rowY(max(s.maxRow, r1) + 100), v.scrollY + h * 2)
  v.spacerX.style("width", $int(needW) & "px")
  v.spacerY.style("height", $int(needH + ColHeaderH) & "px")
  # The editor follows the active cell.
  if v.editing and not v.editFromFormulaBar:
    let (x, y, cw, ch) = v.activeBox()
    v.editor.style("left", $x & "px"); v.editor.style("top", $y & "px")
    v.editor.style("min-width", $cw & "px"); v.editor.style("height", $ch & "px")
  flush()

# ---------------------------------------------------------------- editing --

proc refreshFormulaBar*(v: SheetView) =
  v.fxName.setProp("textContent", cellName(v.ar, v.ac) &
    (if v.ar != v.cr or v.ac != v.cc: ":" & cellName(v.cr, v.cc) else: ""))
  if not v.editing:
    let cell = v.sheet.cellAt(v.ar, v.ac)
    v.fxInput.setProp("value", if cell.formula.len > 0: cell.formula else: toText(cell.value))

proc commitAction(v: SheetView, act: Action) =
  if act.len == 0: return
  v.undo.add act
  if v.undo.len > 200: v.undo.delete(0)
  v.redo.setLen(0)
  recalc(v.wb)
  if v.onChange != nil: v.onChange()

proc setCellRaw*(v: SheetView, si, r, c: int, cell: Cell, act: var Action) =
  let s = v.wb.sheets[si]
  let before = s.cellAt(r, c)
  s.putCell(r, c, cell)
  act.add Change(sheet: si, r: r, c: c, before: before, after: s.cellAt(r, c))

proc parseInput*(wb: Workbook, text: string, old: Cell): Cell =
  ## What typing `text` into a cell stores: a formula, a number, a boolean or text.
  result = Cell(style: old.style)
  let t = text
  if t.len > 1 and t[0] == '=':
    result.setFormula(t)
  elif t.len == 0:
    result.value = emptyVal()
  else:
    let st = t.strip
    var isNum = false
    var n = 0.0
    if st.len > 0 and st[0] in {'0'..'9', '-', '+', '.'}:
      try:
        if st.endsWith("%"): n = parseFloat(st[0 ..< ^1].replace(",", "")) / 100
        else: n = parseFloat(st.replace(",", ""))
        isNum = true
      except ValueError: discard
    if isNum: result.value = numVal(n)
    elif cmpIgnoreCase(st, "TRUE") == 0: result.value = boolVal(true)
    elif cmpIgnoreCase(st, "FALSE") == 0: result.value = boolVal(false)
    else: result.value = strVal(t)

proc moveTo*(v: SheetView, r, c: int, extend = false)

proc beginEdit*(v: SheetView, initial = "", keep = false) =
  if v.editing: return
  v.editing = true
  v.editFromFormulaBar = false
  let cell = v.sheet.cellAt(v.ar, v.ac)
  let text = if keep: (if cell.formula.len > 0: cell.formula else: toText(cell.value)) else: initial
  v.editor.setProp("value", text)
  v.editor.addClass("editing")
  let st = v.wb.styles[cell.style]
  v.editor.style("font", fontOf(st))
  v.fxInput.setProp("value", text)
  v.draw()
  v.editor.focus(true)
  let n = text.len
  v.editor.call("setSelectionRange", n, n)

proc endEdit*(v: SheetView, commit: bool) =
  if not v.editing: return
  let text = if v.editFromFormulaBar: v.fxInput.value else: v.editor.value
  v.editing = false
  v.editFromFormulaBar = false
  v.editor.removeClass("editing")
  v.editor.setProp("value", "")
  # Park the (invisible) editor off the grid again: left over a cell it would
  # take that cell's clicks.
  v.editor.style("left", "-9999px"); v.editor.style("top", "0")
  v.editor.style("min-width", "0"); v.editor.style("height", "1px")
  if commit:
    let old = v.sheet.cellAt(v.ar, v.ac)
    var act: Action
    v.setCellRaw(v.wb.active, v.ar, v.ac, parseInput(v.wb, text, old), act)
    v.commitAction(act)
  v.refreshFormulaBar()
  v.editor.focus(true)
  v.requestDraw()

proc scrollIntoView(v: SheetView, r, c: int) =
  let s = v.sheet
  let x = s.colX(c)
  let y = s.rowY(r)
  let vw = v.width - RowHeaderW
  let vh = v.height - ColHeaderH
  if x < v.scrollX: v.sbX.setProp("scrollLeft", x)
  elif x + s.colWidth(c) > v.scrollX + vw: v.sbX.setProp("scrollLeft", x + s.colWidth(c) - vw + 2)
  if y < v.scrollY: v.sbY.setProp("scrollTop", y)
  elif y + s.rowHeight(r) > v.scrollY + vh:
    # land on a row boundary, as the wheel does
    v.sbY.setProp("scrollTop", s.rowY(s.rowAt(y + s.rowHeight(r) - vh + 2) + 1))

proc moveTo*(v: SheetView, r, c: int, extend = false) =
  let rr = clamp(r, 0, MaxRows - 1)
  let cc = clamp(c, 0, MaxCols - 1)
  if extend:
    v.cr = rr; v.cc = cc
  else:
    v.ar = rr; v.ac = cc; v.cr = rr; v.cc = cc
    v.snapAnchor()
  v.scrollIntoView(rr, cc)
  v.refreshFormulaBar()
  v.requestDraw()

proc jump(v: SheetView, r, c, dr, dc: int): (int, int) =
  ## Ctrl+arrow: to the edge of the current block of filled cells.
  let s = v.sheet
  var rr = r
  var cc = c
  let filled = s.hasCell(r, c)
  let nextFilled = s.hasCell(r + dr, c + dc)
  if filled and nextFilled:
    while rr + dr >= 0 and cc + dc >= 0 and rr + dr < MaxRows and cc + dc < MaxCols and s.hasCell(rr + dr, cc + dc):
      rr += dr; cc += dc
  else:
    rr += dr; cc += dc
    while rr >= 0 and cc >= 0 and rr < max(s.maxRow, 1) + 1 and cc < max(s.maxCol, 1) + 1 and not s.hasCell(rr, cc):
      rr += dr; cc += dc
    if rr < 0 or cc < 0 or not s.hasCell(rr, cc):
      rr = if dr > 0: max(s.maxRow - 1, r) elif dr < 0: 0 else: rr
      cc = if dc > 0: max(s.maxCol - 1, c) elif dc < 0: 0 else: cc
  (clamp(rr, 0, MaxRows - 1), clamp(cc, 0, MaxCols - 1))

proc clearSelection*(v: SheetView, formats = false) =
  let (r1, c1, r2, c2) = v.selRect()
  var act: Action
  let s = v.sheet
  for r in r1 .. min(r2, s.maxRow):
    for c in c1 .. min(c2, s.maxCol):
      if s.hasCell(r, c):
        let old = s.cellAt(r, c)
        v.setCellRaw(v.wb.active, r, c, Cell(style: if formats: 0'i32 else: old.style), act)
  v.commitAction(act)
  v.refreshFormulaBar()
  v.requestDraw()

proc applyAction(v: SheetView, act: Action, forward: bool) =
  for i in 0 ..< act.len:
    let ch = act[if forward: i else: act.len - 1 - i]
    if ch.isMerge: v.wb.sheets[ch.sheet].merges = (if forward: ch.mergesAfter else: ch.mergesBefore)
    else: v.wb.sheets[ch.sheet].putCell(ch.r, ch.c, if forward: ch.after else: ch.before)
  recalc(v.wb)

proc doUndo*(v: SheetView) =
  if v.undo.len == 0: return
  let act = v.undo.pop()
  v.applyAction(act, false)
  v.redo.add act
  if v.onChange != nil: v.onChange()
  v.refreshFormulaBar(); v.requestDraw()

proc doRedo*(v: SheetView) =
  if v.redo.len == 0: return
  let act = v.redo.pop()
  v.applyAction(act, true)
  v.undo.add act
  if v.onChange != nil: v.onChange()
  v.refreshFormulaBar(); v.requestDraw()

proc styleSelection*(v: SheetView, change: proc(st: var Style)) =
  let (r1, c1, r2, c2) = v.selRect()
  if (r2 - r1 + 1) * (c2 - c1 + 1) > 200_000: return
  var act: Action
  for r in r1 .. r2:
    for c in c1 .. c2:
      var cell = v.sheet.cellAt(r, c)
      var st = v.wb.styles[cell.style]
      change(st)
      cell.style = v.wb.styleId(st)
      v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.requestDraw()

proc activeStyle*(v: SheetView): Style = v.wb.styles[v.sheet.cellAt(v.ar, v.ac).style]

proc toggleMerge*(v: SheetView) =
  ## Merge the selection (keeping only its upper-left value, as Excel does),
  ## or unmerge it when it already holds merged ranges.
  let s = v.sheet
  let (r1, c1, r2, c2) = v.selRect()
  if r2 - r1 > 5000 or c2 - c1 > 500: return
  var act: Action
  var has = false
  for m in s.merges:
    if m.r2 >= r1 and m.r1 <= r2 and m.c2 >= c1 and m.c1 <= c2: has = true
  let before = s.merges
  if has:
    s.removeMerges(r1, c1, r2, c2)
  else:
    if r1 == r2 and c1 == c2: return
    var others = false
    for r in r1 .. r2:
      for c in c1 .. c2:
        if (r != r1 or c != c1) and s.hasCell(r, c) and v.wb.displayText(s.cellAt(r, c)).len > 0: others = true
    if others and not window.invoke("confirm", "Merging keeps only the upper-left value. Merge anyway?").toBool: return
    for r in r1 .. r2:
      for c in c1 .. c2:
        if (r != r1 or c != c1) and s.hasCell(r, c):
          v.setCellRaw(v.wb.active, r, c, Cell(style: s.cellAt(r, c).style), act)
    s.addMerge(Merge(r1: r1, c1: c1, r2: r2, c2: c2))
  act.add Change(sheet: v.wb.active, isMerge: true, mergesBefore: before, mergesAfter: s.merges)
  v.ar = r1; v.ac = c1; v.cr = r2; v.cc = c2
  v.snapAnchor()
  v.commitAction(act)
  v.refreshFormulaBar()
  v.requestDraw()

proc applyBorders*(v: SheetView, mode: string) =
  ## all, outside, top, bottom, left, right, thick (outside), none
  let (r1, c1, r2, c2) = v.selRect()
  if (r2 - r1 + 1) * (c2 - c1 + 1) > 200_000: return
  let thin = Border(kind: bkThin)
  let thick = Border(kind: bkThick)
  var act: Action
  for r in r1 .. r2:
    for c in c1 .. c2:
      var cell = v.sheet.cellAt(r, c)
      var st = v.wb.styles[cell.style]
      case mode
      of "none": st.left = Border(); st.right = Border(); st.top = Border(); st.bottom = Border()
      of "all": st.left = thin; st.right = thin; st.top = thin; st.bottom = thin
      of "outside", "thick":
        let b = if mode == "thick": thick else: thin
        if r == r1: st.top = b
        if r == r2: st.bottom = b
        if c == c1: st.left = b
        if c == c2: st.right = b
      of "top": (if r == r1: st.top = thin)
      of "bottom": (if r == r2: st.bottom = thin)
      of "left": (if c == c1: st.left = thin)
      of "right": (if c == c2: st.right = thin)
      else: discard
      let id = v.wb.styleId(st)
      if id != cell.style:
        cell.style = id
        v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.requestDraw()

# -------------------------------------------------------------- clipboard --

proc selectionTsv*(v: SheetView): string =
  let (r1, c1, r2, c2) = v.selRect()
  let s = v.sheet
  for r in r1 .. min(r2, max(s.maxRow - 1, r1)):
    if r > r1: result.add "\r\n"
    for c in c1 .. min(c2, max(s.maxCol - 1, c1)):
      if c > c1: result.add '\t'
      var t = v.wb.displayText(s.cellAt(r, c))
      if '\t' in t or '\n' in t or '"' in t: t = "\"" & t.replace("\"", "\"\"") & "\""
      result.add t

var internalClip: tuple[text: string, sheet, r1, c1, r2, c2: int]

proc copySelection*(v: SheetView): string =
  result = v.selectionTsv()
  let (r1, c1, r2, c2) = v.selRect()
  internalClip = (result, v.wb.active, r1, c1, r2, c2)

proc parseTsv(text: string): seq[seq[string]] =
  var row: seq[string]
  var field = ""
  var i = 0
  var quoted = false
  while i < text.len:
    let ch = text[i]
    if quoted:
      if ch == '"':
        if i + 1 < text.len and text[i + 1] == '"': field.add '"'; inc i
        else: quoted = false
      else: field.add ch
    elif ch == '"' and field.len == 0: quoted = true
    elif ch == '\t': row.add field; field = ""
    elif ch == '\n' or ch == '\r':
      if ch == '\r' and i + 1 < text.len and text[i + 1] == '\n': inc i
      row.add field; field = ""
      result.add row; row = @[]
    else: field.add ch
    inc i
  if field.len > 0 or row.len > 0:
    row.add field
    result.add row

proc paste*(v: SheetView, text: string) =
  var act: Action
  let s = v.sheet
  if internalClip.text.len > 0 and internalClip.text == text:
    # Copied inside this workbook: cells with formulas and styles, references shifted.
    let src = v.wb.sheets[min(internalClip.sheet, v.wb.sheets.len - 1)]
    let dr = v.ar - internalClip.r1
    let dc = v.ac - internalClip.c1
    var cells: seq[(int, int, Cell)]
    for r in internalClip.r1 .. internalClip.r2:
      for c in internalClip.c1 .. internalClip.c2:
        var cell = src.cellAt(r, c)
        if cell.formula.len > 0: cell.setFormula(shiftFormula(cell.formula, dr, dc))
        cells.add (r + dr, c + dc, cell)
    for (r, c, cell) in cells: v.setCellRaw(v.wb.active, r, c, cell, act)
    v.cr = v.ar + internalClip.r2 - internalClip.r1
    v.cc = v.ac + internalClip.c2 - internalClip.c1
  else:
    let rows = parseTsv(text)
    for i, row in rows:
      for j, field in row:
        let old = s.cellAt(v.ar + i, v.ac + j)
        v.setCellRaw(v.wb.active, v.ar + i, v.ac + j, parseInput(v.wb, field, old), act)
    if rows.len > 0:
      v.cr = v.ar + rows.len - 1
      var w = 0
      for row in rows: w = max(w, row.len)
      v.cc = v.ac + max(w - 1, 0)
  v.commitAction(act)
  v.refreshFormulaBar()
  v.requestDraw()

proc fillDown*(v: SheetView, right = false) =
  ## Ctrl+D / Ctrl+R: copy the first row (column) of the selection over the rest.
  let (r1, c1, r2, c2) = v.selRect()
  var act: Action
  let s = v.sheet
  if right:
    for r in r1 .. r2:
      let src = s.cellAt(r, c1)
      for c in c1 + 1 .. c2:
        var cell = src
        if cell.formula.len > 0: cell.setFormula(shiftFormula(src.formula, 0, c - c1))
        v.setCellRaw(v.wb.active, r, c, cell, act)
  else:
    for c in c1 .. c2:
      let src = s.cellAt(r1, c)
      for r in r1 + 1 .. r2:
        var cell = src
        if cell.formula.len > 0: cell.setFormula(shiftFormula(src.formula, r - r1, 0))
        v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.requestDraw()

# ------------------------------------------------------------------ input --

proc hitCell(v: SheetView, gx, gy: float64): (int, int) =
  let s = v.sheet
  (s.rowAt(max(0.0, gy - ColHeaderH + v.scrollY)), s.colAt(max(0.0, gx - RowHeaderW + v.scrollX)))

proc gridPoint(v: SheetView, e: Event): (float64, float64) =
  let r = v.grid.rect
  (e.clientX - r.left, e.clientY - r.top)

proc colEdgeAt(v: SheetView, gx: float64): int =
  ## The column whose right edge is within 4px of gx (header resize), or -1.
  let s = v.sheet
  let c = s.colAt(max(0.0, gx - RowHeaderW + v.scrollX))
  for cand in [c - 1, c]:
    if cand >= 0 and abs(RowHeaderW + s.colX(cand + 1) - v.scrollX - gx) <= 4: return cand
  -1

proc rowEdgeAt(v: SheetView, gy: float64): int =
  let s = v.sheet
  let r = s.rowAt(max(0.0, gy - ColHeaderH + v.scrollY))
  for cand in [r - 1, r]:
    if cand >= 0 and abs(ColHeaderH + s.rowY(cand + 1) - v.scrollY - gy) <= 3: return cand
  -1

proc onWheel(v: SheetView, e: Event) =
  ## Luckysheet's wheel: whole rows (1-3 by the notch size) or 20 px sideways.
  e.preventDefault()
  let s = v.sheet
  let dy = e.deltaY
  let dx = if e.deltaX != 0: e.deltaX elif e.shiftKey: dy else: 0.0
  if dx != 0:
    v.sbX.setProp("scrollLeft", max(0.0, v.scrollX + (if dx > 0: 20.0 else: -20.0)))
  elif dy != 0:
    let first = s.rowAt(v.scrollY + 0.01)
    let mag = abs(dy)
    let step = if mag < 40: 1 elif mag < 80: 2 else: 3
    let target = if dy > 0: min(first + step, MaxRows - 1) else: max(first - step, 0)
    v.sbY.setProp("scrollTop", s.rowY(target))
  v.requestDraw()

proc onPointerDown(v: SheetView, e: Event) =
  if e.pointerType == "touch":
    v.dragging = 6
    v.touchX = e.clientX; v.touchY = e.clientY
    v.touchScrollX = v.scrollX; v.touchScrollY = v.scrollY
    v.touchMoved = false
    v.hit.call("setPointerCapture", e.pointerId)
    return
  if e.button != 0: return
  let (gx, gy) = v.gridPoint(e)
  if v.editing: v.endEdit(true)
  if gy < ColHeaderH and gx > RowHeaderW:
    let edge = v.colEdgeAt(gx)
    if edge >= 0:
      v.dragging = 2; v.resizeIndex = edge; v.resizeStart = gx; v.resizeOrig = v.sheet.colWidth(edge)
    else:
      let (_, c) = v.hitCell(gx, ColHeaderH + 1)
      if e.shiftKey: v.cc = c else: (v.ac = c; v.cc = c)
      v.ar = 0; v.cr = MaxRows - 1
      v.dragging = 4
  elif gx < RowHeaderW and gy > ColHeaderH:
    let edge = v.rowEdgeAt(gy)
    if edge >= 0:
      v.dragging = 3; v.resizeIndex = edge; v.resizeStart = gy; v.resizeOrig = v.sheet.rowHeight(edge)
    else:
      let (r, _) = v.hitCell(RowHeaderW + 1, gy)
      if e.shiftKey: v.cr = r else: (v.ar = r; v.cr = r)
      v.ac = 0; v.cc = MaxCols - 1
      v.dragging = 5
  elif gx < RowHeaderW and gy < ColHeaderH:
    v.ar = 0; v.ac = 0; v.cr = MaxRows - 1; v.cc = MaxCols - 1
  else:
    let (r, c) = v.hitCell(gx, gy)
    if e.shiftKey: v.cr = r; v.cc = c
    else: v.ar = r; v.ac = c; v.cr = r; v.cc = c; v.snapAnchor()
    v.dragging = 1
  v.hit.call("setPointerCapture", e.pointerId)
  e.preventDefault()
  v.editor.focus(true)
  v.refreshFormulaBar()
  v.requestDraw()

proc onPointerMove(v: SheetView, e: Event) =
  let (gx, gy) = v.gridPoint(e)
  case v.dragging
  of 0:
    let cursor = if gy < ColHeaderH and gx > RowHeaderW and v.colEdgeAt(gx) >= 0: "col-resize"
                 elif gx < RowHeaderW and gy > ColHeaderH and v.rowEdgeAt(gy) >= 0: "row-resize"
                 else: "cell"
    v.hit.style("cursor", cursor)
  of 1:
    let (r, c) = v.hitCell(gx, gy)
    if r != v.cr or c != v.cc:
      v.cr = r; v.cc = c
      v.refreshFormulaBar(); v.requestDraw()
  of 2:
    v.sheet.colWidths[v.resizeIndex] = max(8.0, v.resizeOrig + gx - v.resizeStart)
    v.requestDraw()
  of 3:
    v.sheet.rowHeights[v.resizeIndex] = max(8.0, v.resizeOrig + gy - v.resizeStart)
    v.requestDraw()
  of 4:
    let (_, c) = v.hitCell(gx, ColHeaderH + 1)
    if c != v.cc: v.cc = c; v.refreshFormulaBar(); v.requestDraw()
  of 5:
    let (r, _) = v.hitCell(RowHeaderW + 1, gy)
    if r != v.cr: v.cr = r; v.refreshFormulaBar(); v.requestDraw()
  of 6:
    let dx = e.clientX - v.touchX
    let dy = e.clientY - v.touchY
    if abs(dx) + abs(dy) > 6: v.touchMoved = true
    if v.touchMoved:
      v.sbX.setProp("scrollLeft", max(0.0, v.touchScrollX - dx))
      v.sbY.setProp("scrollTop", max(0.0, v.touchScrollY - dy))
      v.requestDraw()
  else: discard

proc onKeyDown(v: SheetView, e: Event) =
  let k = e.key
  let ctrl = e.ctrlKey or e.metaKey
  if v.editing:
    case k
    of "Enter":
      if e.altKey: return                      # newline inside the cell
      e.preventDefault(); v.endEdit(true); (let (r, c) = v.sheet.stepFrom(v.ar, v.ac, (if e.shiftKey: -1 else: 1), 0); v.moveTo(r, c))
    of "Tab":
      e.preventDefault(); v.endEdit(true); (let (r, c) = v.sheet.stepFrom(v.ar, v.ac, 0, (if e.shiftKey: -1 else: 1)); v.moveTo(r, c))
    of "Escape":
      e.preventDefault(); v.endEdit(false)
    else: discard
    return
  if ctrl:
    case toLowerAscii(k)
    of "z": e.preventDefault(); v.doUndo()
    of "y": e.preventDefault(); v.doRedo()
    of "b": e.preventDefault(); v.styleSelection(proc(st: var Style) = st.bold = not v.activeStyle.bold)
    of "i": e.preventDefault(); v.styleSelection(proc(st: var Style) = st.italic = not v.activeStyle.italic)
    of "u": e.preventDefault(); v.styleSelection(proc(st: var Style) = st.underline = not v.activeStyle.underline)
    of "d": e.preventDefault(); v.fillDown()
    of "r": e.preventDefault(); v.fillDown(right = true)
    of "a": e.preventDefault(); v.ar = 0; v.ac = 0; v.cr = MaxRows - 1; v.cc = MaxCols - 1; v.requestDraw()
    of "arrowdown", "arrowup", "arrowleft", "arrowright":
      e.preventDefault()
      let (dr, dc) = case k
        of "ArrowDown": (1, 0)
        of "ArrowUp": (-1, 0)
        of "ArrowLeft": (0, -1)
        else: (0, 1)
      let fromR = if e.shiftKey: v.cr else: v.ar
      let fromC = if e.shiftKey: v.cc else: v.ac
      let (r, c) = v.jump(fromR, fromC, dr, dc)
      v.moveTo(r, c, e.shiftKey)
    of "home": e.preventDefault(); v.moveTo(0, 0)
    of "end": e.preventDefault(); v.moveTo(max(v.sheet.maxRow - 1, 0), max(v.sheet.maxCol - 1, 0))
    else: discard
    return
  let pageRows = max(1, int((v.height - ColHeaderH) / DefaultRowHeight) - 1)
  let baseR = if e.shiftKey: v.cr else: v.ar
  let baseC = if e.shiftKey: v.cc else: v.ac
  case k
  of "ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight":
    e.preventDefault()
    let (dr, dc) = case k
      of "ArrowDown": (1, 0)
      of "ArrowUp": (-1, 0)
      of "ArrowLeft": (0, -1)
      else: (0, 1)
    let (r, c) = v.sheet.stepFrom(baseR, baseC, dr, dc)
    v.moveTo(r, c, e.shiftKey)
  of "PageDown": e.preventDefault(); v.moveTo(baseR + pageRows, baseC, e.shiftKey)
  of "PageUp": e.preventDefault(); v.moveTo(baseR - pageRows, baseC, e.shiftKey)
  of "Home": e.preventDefault(); v.moveTo(baseR, 0, e.shiftKey)
  of "Enter": e.preventDefault(); (let (r, c) = v.sheet.stepFrom(v.ar, v.ac, (if e.shiftKey: -1 else: 1), 0); v.moveTo(r, c))
  of "Tab": e.preventDefault(); (let (r, c) = v.sheet.stepFrom(v.ar, v.ac, 0, (if e.shiftKey: -1 else: 1)); v.moveTo(r, c))
  of "F2": e.preventDefault(); v.beginEdit(keep = true)
  of "Delete", "Backspace": e.preventDefault(); v.clearSelection()
  else: discard

proc onInput(v: SheetView) =
  ## A printable key while not editing: start editing with what was typed.
  if v.editing:
    v.fxInput.setProp("value", v.editor.value)
    return
  let typed = v.editor.value
  if typed.len == 0: return
  v.editor.setProp("value", "")
  v.beginEdit(typed)

# -------------------------------------------------------------- the shell --

proc button(v: SheetView, parent: Node, label, title: string, action: proc()): Node =
  result = el("button", "qs-btn")
  result.setAttribute("type", "button")
  result.setAttribute("title", title)
  result.setProp("textContent", label)
  discard parent.add result
  result.on("mousedown", proc(e: Event) = e.preventDefault())   # keep focus on the grid
  result.on("click", proc(e: Event) = action())

proc rebuildTabs*(v: SheetView)

proc activate*(v: SheetView, index: int) =
  if index < 0 or index >= v.wb.sheets.len: return
  if v.editing: v.endEdit(true)
  v.wb.active = index
  v.ar = 0; v.ac = 0; v.cr = 0; v.cc = 0
  v.sbX.setProp("scrollLeft", 0); v.sbY.setProp("scrollTop", 0)
  v.rebuildTabs()
  v.refreshFormulaBar()
  v.requestDraw()
  if v.hostCall != nil: v.hostCall("sheetActivated", %index)

proc rebuildTabs*(v: SheetView) =
  v.tabs.dropChildren()
  for i, s in v.wb.sheets:
    let tab = el("button", "qs-tab" & (if i == v.wb.active: " active" else: ""))
    tab.setAttribute("type", "button")
    tab.setProp("textContent", s.name)
    let idx = i
    tab.on("click", proc(e: Event) = v.activate(idx))
    tab.on("dblclick", proc(e: Event) =
      let name = window.invoke("prompt", "Rename sheet", v.wb.sheets[idx].name).toStr
      if name.strip.len > 0 and v.wb.sheetNamed(name.strip) == nil:
        v.wb.sheets[idx].name = name.strip
        v.rebuildTabs())
    discard v.tabs.add tab
  discard v.button(v.tabs, "+", "Add sheet", proc() =
    var n = v.wb.sheets.len + 1
    while v.wb.sheetNamed("Sheet" & $n) != nil: inc n
    discard v.wb.addSheet("Sheet" & $n)
    v.activate(v.wb.sheets.len - 1))

proc separator(parent: Node) = discard parent.add el("span", "qs-sep")

proc buildToolbar(v: SheetView) =
  let t = v.toolbar
  let host = proc(name: string): proc() = (proc() = (if v.hostCall != nil: v.hostCall(name, newJNull())))
  discard v.button(t, "Open", "Open a .xlsx, .xls or .csv file", host("open"))
  discard v.button(t, "Save", "Save (to the vault when opened from it, otherwise download .xlsx)", host("save"))
  discard v.button(t, "CSV", "Download the active sheet as .csv", host("csv"))
  separator(t)
  discard v.button(t, "↶", "Undo (Ctrl+Z)", proc() = v.doUndo())
  discard v.button(t, "↷", "Redo (Ctrl+Y)", proc() = v.doRedo())
  separator(t)
  let b = v.button(t, "B", "Bold (Ctrl+B)", proc() = v.styleSelection(proc(st: var Style) = st.bold = not v.activeStyle.bold))
  b.style("font-weight", "bold")
  let i = v.button(t, "I", "Italic (Ctrl+I)", proc() = v.styleSelection(proc(st: var Style) = st.italic = not v.activeStyle.italic))
  i.style("font-style", "italic")
  let u = v.button(t, "U", "Underline (Ctrl+U)", proc() = v.styleSelection(proc(st: var Style) = st.underline = not v.activeStyle.underline))
  u.style("text-decoration", "underline")
  let s = v.button(t, "S", "Strikethrough", proc() = v.styleSelection(proc(st: var Style) = st.strike = not v.activeStyle.strike))
  s.style("text-decoration", "line-through")
  separator(t)
  let size = el("select", "qs-select")
  size.setAttribute("title", "Font size")
  for n in ["8", "9", "10", "11", "12", "14", "16", "18", "24", "36"]:
    let o = el("option")
    o.setProp("textContent", n); o.setProp("value", n)
    if n == "10": o.setAttribute("selected", "")
    discard size.add o
  discard t.add size
  size.on("change", proc(e: Event) =
    let n = parseFloat(size.value)
    v.styleSelection(proc(st: var Style) = st.fontSize = n)
    v.editor.focus(true))
  for (label, title, fill) in [("A", "Text colour", false), ("▇", "Fill colour", true)]:
    let wrap = el("label", "qs-color")
    wrap.setAttribute("title", title)
    let txt = el("span")
    txt.setProp("textContent", label)
    discard wrap.add txt
    let inp = el("input")
    inp.setAttribute("type", "color")
    inp.setProp("value", if fill: "#fff2cc" else: "#c00000")
    discard wrap.add inp
    discard t.add wrap
    let isFill = fill
    inp.on("change", proc(e: Event) =
      let color = inp.value
      v.styleSelection(proc(st: var Style) = (if isFill: st.fill = color else: st.color = color))
      v.editor.focus(true))
  separator(t)
  discard v.button(t, "⇤", "Align left", proc() = v.styleSelection(proc(st: var Style) = st.hAlign = haLeft))
  discard v.button(t, "≡", "Align center", proc() = v.styleSelection(proc(st: var Style) = st.hAlign = haCenter))
  discard v.button(t, "⇥", "Align right", proc() = v.styleSelection(proc(st: var Style) = st.hAlign = haRight))
  separator(t)
  let fmt = el("select", "qs-select")
  fmt.setAttribute("title", "Number format")
  for (label, code) in [("General", ""), ("0.00", "0.00"), ("1,234.56", "#,##0.00"), ("Percent", "0.00%"), ("Scientific", "0.00E+00"), ("Integer", "0")]:
    let o = el("option")
    o.setProp("textContent", label); o.setProp("value", code)
    discard fmt.add o
  discard t.add fmt
  fmt.on("change", proc(e: Event) =
    let code = fmt.value
    v.styleSelection(proc(st: var Style) = st.numFmt = code)
    v.editor.focus(true))
  let borders = el("select", "qs-select")
  borders.setAttribute("title", "Borders")
  for (label, code) in [("Borders", ""), ("All borders", "all"), ("Outside", "outside"), ("Thick outside", "thick"),
                        ("Top", "top"), ("Bottom", "bottom"), ("Left", "left"), ("Right", "right"), ("No borders", "none")]:
    let o = el("option")
    o.setProp("textContent", label); o.setProp("value", code)
    discard borders.add o
  discard t.add borders
  borders.on("change", proc(e: Event) =
    let code = borders.value
    borders.setProp("value", "")
    if code.len > 0: v.applyBorders(code)
    v.editor.focus(true))
  discard v.button(t, "Merge", "Merge the selected cells, or unmerge them", proc() = v.toggleMerge())
  discard v.button(t, "Clear format", "Remove formatting from the selection", proc() =
    v.styleSelection(proc(st: var Style) = st = Style()))
  separator(t)
  discard v.button(t, "Program (Luau)", "Run a Luau program on the workbook", host("program"))

proc newSheetView*(parent: Node, wb: Workbook): SheetView =
  let v = SheetView(wb: wb, rec: newCtx())
  v.root = parent.add el("div", "qs-app")
  v.toolbar = v.root.add el("div", "qs-toolbar")
  let fx = v.root.add el("div", "qs-formula")
  v.fxName = fx.add el("span", "qs-name")
  discard fx.add(el("span", "qs-fx-label")).add createTextNode("fx")
  v.fxInput = fx.add el("input", "qs-fx")
  v.fxInput.setAttribute("spellcheck", "false")
  v.grid = v.root.add el("div", "qs-grid")
  v.canvas = v.grid.add el("canvas", "qs-canvas")
  v.hit = v.grid.add el("div", "qs-hit")
  v.sbY = v.grid.add el("div", "qs-sb qs-sb-y")
  v.spacerY = v.sbY.add el("div", "qs-sb-spacer")
  v.sbX = v.grid.add el("div", "qs-sb qs-sb-x")
  v.spacerX = v.sbX.add el("div", "qs-sb-spacer")
  discard v.grid.add el("div", "qs-sb-corner")
  v.editor = v.grid.add el("textarea", "qs-editor")
  v.editor.setAttribute("spellcheck", "false")
  v.editor.setAttribute("aria-label", "Cell editor")
  v.tabs = v.root.add el("div", "qs-tabs")
  v.ctx = v.canvas.context2d(alpha = false)
  v.buildToolbar()

  v.sbX.on("scroll", proc(e: Event) = v.requestDraw(), passive = true)
  v.sbY.on("scroll", proc(e: Event) = v.requestDraw(), passive = true)
  v.hit.on("wheel", proc(e: Event) = v.onWheel(e))
  v.hit.on("pointerdown", proc(e: Event) = v.onPointerDown(e))
  v.hit.on("pointermove", proc(e: Event) = v.onPointerMove(e))
  v.hit.on("pointerup", proc(e: Event) =
    if v.dragging in {2, 3}:
      if v.onChange != nil: v.onChange()
    if v.dragging == 6 and not v.touchMoved:
      # a tap: select the cell under it
      let (gx, gy) = v.gridPoint(e)
      if gx > RowHeaderW and gy > ColHeaderH:
        if v.editing: v.endEdit(true)
        let (r, c) = v.hitCell(gx, gy)
        v.ar = r; v.ac = c; v.cr = r; v.cc = c; v.snapAnchor()
        v.refreshFormulaBar(); v.requestDraw()
    v.dragging = 0)
  v.hit.on("dblclick", proc(e: Event) =
    let (gx, gy) = v.gridPoint(e)
    if gx > RowHeaderW and gy > ColHeaderH: v.beginEdit(keep = true))
  v.editor.on("keydown", proc(e: Event) = v.onKeyDown(e))
  v.editor.on("input", proc(e: Event) = v.onInput())
  v.editor.on("copy", proc(e: Event) =
    if v.editing: return
    e.preventDefault()
    let cd = e.eventObject.getNode("clipboardData")
    cd.call("setData", "text/plain", v.copySelection()))
  v.editor.on("cut", proc(e: Event) =
    if v.editing: return
    e.preventDefault()
    let cd = e.eventObject.getNode("clipboardData")
    cd.call("setData", "text/plain", v.copySelection())
    v.clearSelection())
  v.editor.on("paste", proc(e: Event) =
    if v.editing: return
    e.preventDefault()
    let cd = e.eventObject.getNode("clipboardData")
    v.paste(cd.invoke("getData", "text/plain").toStr))
  v.fxInput.on("focus", proc(e: Event) =
    if not v.editing:
      v.editing = true
      v.editFromFormulaBar = true)
  v.fxInput.on("keydown", proc(e: Event) =
    case e.key
    of "Enter": e.preventDefault(); v.endEdit(true); v.moveTo(v.ar + 1, v.ac)
    of "Escape": e.preventDefault(); v.endEdit(false)
    else: discard)
  window.on("resize", proc(e: Event) = v.requestDraw())
  v.rebuildTabs()
  v.refreshFormulaBar()
  v.editor.focus(true)
  v.requestDraw()
  v
