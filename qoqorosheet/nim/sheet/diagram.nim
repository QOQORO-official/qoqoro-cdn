## Diagram Editor: QoChart (the QOQORO diagram app, /qochart/) in a popup over
## the sheet, included into view.nim. It takes the place of the JS app's
## mxGraph bridge (js/visualScriptBridge.js): open a .qochart / draw.io file,
## download the diagram, maximise, close. QoChart is driven the way the
## QOQORO workspace drives it (its window's graph, editorUi and
## PixelMxGraphFormat).

const
  DiagramCss = """
#qs-diagram{position:fixed;inset:0;z-index:100010;background:rgba(17,17,27,.35);display:none}
#qs-diagram.open{display:block}
#qs-diagram .qs-dg-box{position:absolute;left:5vw;top:6vh;width:90vw;height:86vh;background:#fff;border-radius:10px;box-shadow:0 18px 50px rgba(0,0,0,.3);display:flex;flex-direction:column;overflow:hidden}
#qs-diagram.max .qs-dg-box{left:0;top:0;width:100vw;height:100vh;border-radius:0}
#qs-diagram .qs-dg-head{display:flex;align-items:center;gap:8px;padding:8px 12px;border-bottom:1px solid #e5e7eb;background:#f8fafc;font:600 14px "Segoe UI",Arial,sans-serif;color:#1e1e2e}
#qs-diagram .qs-dg-head span{flex:1}
#qs-diagram .qs-dg-head button{border:1px solid #d4d4d4;background:#fff;border-radius:6px;padding:4px 10px;cursor:pointer;font:13px "Segoe UI",Arial,sans-serif}
#qs-diagram .qs-dg-head button.primary{background:#2563eb;border-color:#2563eb;color:#fff}
#qs-diagram iframe{flex:1;border:0;width:100%}
#qs-diagram .qs-dg-busy{position:absolute;inset:44px 0 0;display:flex;align-items:center;justify-content:center;background:#fff;font:14px "Segoe UI",Arial,sans-serif;color:#555}
"""
  QoChartUrl = "../../qochart/index.html"

var diagramBox, diagramFrame: Node

proc diagramWindow(): Node =
  if diagramFrame.isNil: Node(0) else: diagramFrame.getNode("contentWindow")

proc diagramReady(): bool =
  let w = diagramWindow()
  if w.isNil: return false
  let ui = w.getNode("editorUi")
  not ui.isNil and ui.getBool("ready")

proc closeDiagram(v: SheetView) =
  if not diagramBox.isNil: diagramBox.removeClass("open")
  v.editor.focus(true)

proc loadDiagramText(text, name: string) =
  ## a .qochart / draw.io document into QoChart (as the workspace opens one)
  let w = diagramWindow()
  if w.isNil or not diagramReady(): toast("QoChart is still loading", "warn"); return
  var doc: JsArg
  let t = text.strip
  if t.startsWith("<"):
    let fmt = w.getNode("PixelMxGraphFormat")
    if fmt.isNil: toast("QoChart cannot read this file", "error"); return
    doc = fmt.invoke("parse", t).toNode
  else: doc = jsJson(t)
  let graph = w.getNode("graph")
  graph.call("fromJSON", doc)
  graph.call("render")
  let ui = w.getNode("editorUi")
  let base = name.split({'/', '\\'})[^1]
  let dot = base.rfind('.')
  ui.call("setDocumentName", if dot > 0: base[0 ..< dot] else: base)
  toast("Opened " & base, "success", 2000)

proc downloadDiagram() =
  let w = diagramWindow()
  if w.isNil or not diagramReady(): return
  let json = w.getNode("graph").invoke("toJSON").toStr
  let xml = w.getNode("PixelMxGraphFormat").invoke("serialize", jsJson(json)).toStr
  let url = createObjectURL(newBlob(xml, "application/vnd.qochart+xml"))
  let a = el("a")
  a.setAttribute("href", url); a.setAttribute("download", "diagram.qochart")
  a.click()
  setTimeout(1000, proc() = revokeObjectURL(url))

proc openDiagram*(v: SheetView) =
  if v.editing: v.endEdit(true)
  if diagramBox.isNil:
    let style = el("style")
    style.setProp("textContent", DiagramCss)
    discard document.query("head").add style
    diagramBox = el("div")
    diagramBox.setAttribute("id", "qs-diagram")
    diagramBox.setProp("innerHTML", "<div class=\"qs-dg-box\"><div class=\"qs-dg-head\"><span>Diagram Editor — QoChart</span>" &
      "<button type=\"button\" class=\"primary qs-dg-open\">Open File</button><button type=\"button\" class=\"qs-dg-save\">Download</button>" &
      "<button type=\"button\" class=\"qs-dg-max\" title=\"Maximise\">▢</button><button type=\"button\" class=\"qs-dg-close\" title=\"Close (Esc)\">✕</button></div>" &
      "<iframe title=\"QoChart\" allow=\"clipboard-read; clipboard-write\"></iframe><div class=\"qs-dg-busy\">Opening QoChart…</div></div>")
    discard document.query("body").add diagramBox
    diagramFrame = diagramBox.query("iframe")
    let busy = diagramBox.query(".qs-dg-busy")
    diagramFrame.setAttribute("src", QoChartUrl)
    var tries = 0
    proc wait() =
      if diagramReady(): busy.style("display", "none"); return
      inc tries
      if tries > 300: busy.setProp("textContent", "QoChart could not finish loading (is /qochart/ served?)"); return
      setTimeout(100, wait)
    setTimeout(100, wait)
    diagramBox.query(".qs-dg-close").on("click", proc(e: Event) = v.closeDiagram())
    diagramBox.query(".qs-dg-max").on("click", proc(e: Event) =
      diagramBox.toggleClass("max", not diagramBox.invoke("classList").toNode.invoke("contains", "max").toBool))
    diagramBox.query(".qs-dg-save").on("click", proc(e: Event) = downloadDiagram())
    diagramBox.query(".qs-dg-open").on("click", proc(e: Event) =
      let input = el("input")
      input.setAttribute("type", "file")
      input.setAttribute("accept", ".qochart,.drawio,.xml,.json")
      input.on("change", proc(e: Event) =
        let file = input.getNode("files").invoke("item", 0).toNode
        if file.isNil: return
        let name = file.getStr("name")
        readBlob(file, brText, proc(ok: bool, data: string) =
          if ok: loadDiagramText(data, name) else: toast("Could not read " & name, "error")))
      input.click())
    diagramBox.on("click", proc(e: Event) = (if e.target.same(diagramBox): v.closeDiagram()))
    document.on("keydown", proc(e: Event) =
      if e.key == "Escape" and diagramBox.invoke("classList").toNode.invoke("contains", "open").toBool: v.closeDiagram())
  diagramBox.addClass("open")
