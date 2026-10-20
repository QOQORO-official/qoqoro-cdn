## Insert Chart: Excel's chart-type gallery over the selection, included into
## view.nim (the JS app's chartUI.js dialog). The option is built here from
## the selected cells; ECharts draws it over the grid (window.SheetCharts in
## wasm/sheet-host.js).

const ChartTypes = [("column", "Clustered Column", "❙❙❙"), ("bar", "Bar", "▬▬"), ("line", "Line", "╱╲"),
  ("area", "Area", "◢"), ("pie", "Pie", "◕"), ("scatter", "Scatter (X Y)", "∷")]

proc chartOption(v: SheetView, kind: string): JsonNode =
  ## Excel's reading of a selection: a text first row names the series, a
  ## text first column (or X for a scatter) gives the categories.
  let s = v.sheet
  let (r1, c1, r2, c2) = v.selRect()
  let rEnd = min(r2, min(r1 + 5000, s.maxRow - 1))
  let cEnd = min(c2, min(c1 + 50, s.maxCol - 1))
  if rEnd < r1 or cEnd < c1: return newJNull()
  var m: seq[seq[Cell]]
  for r in r1 .. rEnd:
    var row: seq[Cell]
    for c in c1 .. cEnd: row.add s.cellAt(r, c)
    m.add row
  proc isText(cell: Cell): bool = cell.value.kind in {vkStr, vkBool, vkErr} and v.wb.displayText(cell).len > 0
  proc num(cell: Cell): JsonNode = (if cell.value.kind == vkNum: %cell.value.num else: newJNull())
  let header = m[0].anyIt(isText(it))
  let body = if header: m[1 .. ^1] else: m
  let cols = m[0].len
  let catCol = cols > 1 and (kind == "scatter" or body.anyIt(isText(it[0])))
  var cats: seq[string]
  for i, row in body: cats.add (if catCol: v.wb.displayText(row[0]) else: $(i + 1))
  proc name(c: int): string =
    if header and v.wb.displayText(m[0][c]).len > 0: v.wb.displayText(m[0][c]) else: "Series " & $(c + 1)
  if kind == "pie":
    var data = newJArray()
    let vc = if catCol: 1 else: 0
    for i, row in body: data.add %*{"name": cats[i], "value": num(row[vc])}
    return %*{"tooltip": {"trigger": "item"}, "legend": {"type": "scroll", "bottom": 0},
              "series": [{"type": "pie", "radius": "60%", "data": data}]}
  var series = newJArray()
  for c in (if catCol: 1 else: 0) ..< cols:
    var data = newJArray()
    for row in body:
      data.add (if kind == "scatter": %[num(row[0]), num(row[c])] else: num(row[c]))
    var one = %*{"name": name(c), "type": (case kind
      of "column", "bar": "bar"
      of "area": "line"
      else: kind), "data": data}
    if kind == "area": one["areaStyle"] = newJObject()
    series.add one
  let cat = %*{"type": "category", "data": cats}
  let val = %*{"type": "value", "scale": true}
  %*{"tooltip": {"trigger": (if kind == "scatter": "item" else: "axis")}, "legend": {"type": "scroll", "bottom": 0},
     "grid": {"left": 50, "right": 20, "top": 30, "bottom": 50},
     "xAxis": (if kind == "bar" or kind == "scatter": val else: cat),
     "yAxis": (if kind == "bar": cat else: val), "series": series}

proc openChartDialog*(v: SheetView) =
  if v.editing: v.endEdit(true)
  let old = byId("qs-chart-dialog")
  if not old.isNil: old.remove()
  let mask = byId("luckysheet-modal-dialog-mask")
  let box = el("div", "luckysheet-modal-dialog")
  box.setAttribute("id", "qs-chart-dialog")
  box.setAttribute("style", "z-index:100003;display:block;min-width:420px")
  var types = ""
  for (id, label, glyph) in ChartTypes:
    types.add "<button type=\"button\" data-type=\"" & id & "\" class=\"btn btn-default\" style=\"padding:10px 4px\"><div style=\"font-size:20px\">" &
      glyph & "</div>" & label & "</button>"
  box.setProp("innerHTML", "<div class=\"luckysheet-modal-dialog-title\"><span class=\"luckysheet-modal-dialog-title-text\">Insert Chart</span>" &
    "<span class=\"luckysheet-modal-dialog-title-close\" role=\"button\"><i class=\"fa fa-times\"></i></span></div>" &
    "<div class=\"luckysheet-modal-dialog-content\"><div style=\"display:grid;grid-template-columns:repeat(3,1fr);gap:8px\">" & types &
    "</div><label style=\"display:block;margin-top:10px\">Title <input type=\"text\" class=\"qs-chart-title\" style=\"width:70%\" value=\"Chart\"></label></div>" &
    "<div class=\"luckysheet-modal-dialog-buttons\"><button class=\"btn btn-primary qs-ok\">OK</button> <button class=\"btn btn-default qs-cancel\">Cancel</button></div>")
  discard document.query("body").add box
  box.style("left", px((window.getNum("innerWidth") - box.getNum("offsetWidth")) / 2))
  box.style("top", px((window.getNum("innerHeight") - box.getNum("offsetHeight")) / 3))
  if not mask.isNil: mask.style("display", "block")
  var kind = "column"
  let buttons = box.queryAll("[data-type]")
  proc pick(b: Node) =
    for x in buttons: x.style("outline", if x.same(b): "2px solid #0188fb" else: "")
    kind = b.invoke("getAttribute", "data-type").toStr
  proc close() =
    box.remove()
    if not mask.isNil: mask.style("display", "none")
    v.editor.focus(true)
  proc ok() =
    let option = v.chartOption(kind)
    if option.kind == JNull:
      toast("Select the data for the chart first", "warn"); return
    let title = box.query(".qs-chart-title").value
    close()
    let charts = window.getNode("SheetCharts")
    if charts.isNil: toast("Charts are not available", "error"); return
    charts.call("create", jsJson($ %*{"title": title, "option": option}))
  for b_1 in buttons:
    let b_0 = b_1
    closureScope:
      let b = b_0
      b.on("click", proc(e: Event) = pick(b))
      b.on("dblclick", proc(e: Event) = (pick(b); ok()))
  pick(buttons[0])
  box.query(".luckysheet-modal-dialog-title-close").on("click", proc(e: Event) = close())
  box.query(".qs-cancel").on("click", proc(e: Event) = close())
  box.query(".qs-ok").on("click", proc(e: Event) = ok())
