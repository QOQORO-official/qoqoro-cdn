## Custom Program: the app's Luau popup (#scriptOverlay in the page), included
## into view.nim. A port of js/customProgram.js: open / close, the script kept
## in localStorage, the line gutter, templates (load, save, delete), the
## console, autorun on file open, and Run. The Luau VM itself is
## js/sheetLuau.js (window.SheetLuau.run), templates come from
## js/scriptTemplates.js (window.ScriptTemplates).

const
  ScriptKey = "qoqorosheet_luau_script_v1"
  AutorunKey = "qoqorosheet_luau_autorun_v1"

var
  programDirty, programRunning: bool
  programFile: string          ## the last opened file's name, for the program's FileName

proc toast(msg: string, kind = "info", ms = 3000) =
  ## the app's toast (#_toast in index.html)
  var t = byId("_toast")
  if t.isNil:
    t = el("div")
    t.setAttribute("id", "_toast")
    t.setAttribute("style", "position:fixed;bottom:20px;right:20px;z-index:99999;padding:9px 16px;border-radius:7px;font-family:sans-serif;font-size:13px;font-weight:500;color:#11111b;box-shadow:0 8px 24px rgba(0,0,0,.25);transition:opacity .2s")
    discard document.query("body").add t
  t.setProp("textContent", msg)
  t.style("background", case kind
    of "error": "#f38ba8"
    of "warn": "#f9e2af"
    of "success": "#a6e3a1"
    else: "#89b4fa")
  t.style("opacity", "1")
  let shown = t
  setTimeout(float64(ms), proc() = shown.style("opacity", "0"))

proc onClick(n: Node, action: proc()) =
  if not n.isNil: n.on("click", proc(e: Event) = action())

proc scriptLoad(): string = storageGet(ScriptKey)[1]
proc autorunLoad(): bool = storageGet(AutorunKey)[1] == "true"

proc markSaved() =
  programDirty = false
  let dot = byId("scriptSavedDot")
  if not dot.isNil: dot.style("background", "#a6e3a1"); dot.setAttribute("title", "Saved")
proc markDirty() =
  if programDirty: return
  programDirty = true
  let dot = byId("scriptSavedDot")
  if not dot.isNil: dot.style("background", "#f9e2af"); dot.setAttribute("title", "Unsaved changes")

proc scriptSave(code: string) =
  discard storageSet(ScriptKey, code)
  markSaved()

proc conPrint(text: string, cls = "log") =
  let con = byId("consoleOutput")
  if con.isNil: return
  let p = el("p", "con-line " & cls)
  p.setProp("textContent", text)
  discard con.add p
  con.setProp("scrollTop", con.getNum("scrollHeight"))

proc conDivider(label: string) =
  let now = construct("Date").invoke("toLocaleTimeString").toStr
  conPrint("── " & label & " " & now & " ──────────────", "divider")

proc setConsoleDot(state: string) =
  let dot = byId("consoleDot")
  if not dot.isNil: dot.setAttribute("class", "console-dot" & (if state != "idle": " " & state else: ""))

proc updateGutter() =
  let ta = byId("scriptTextarea")
  let gutter = byId("scriptGutter")
  if ta.isNil or gutter.isNil: return
  let lines = max(ta.value.count('\n') + 1, 20)
  var html = ""
  for i in 1 .. lines: html.add "<div class=\"script-gutter-line\">" & $i & "</div>"
  gutter.setProp("innerHTML", html)
  gutter.setProp("scrollTop", ta.getNum("scrollTop"))

proc jsonOf(n: Node): JsonNode =
  ## a JS value, through JSON.stringify
  let text = window.getNode("JSON").invoke("stringify", n).toStr
  try: parseJson(text) except CatchableError: newJNull()

proc whenDone(promise: Node, ok: proc(value: Node), failed: proc(message: string)) =
  ## promise.then(ok, failed)
  if promise.isNil: failed("not available"); return
  promise.call("then",
    callback(proc(e: Event) = ok(e.eventObject)),
    callback(proc(e: Event) =
      let err = e.eventObject
      failed(if err.isNil: "failed" else: (let m = err.getStr("message"); if m.len > 0: m else: err.invoke("toString").toStr))))

proc templates(): Node = window.getNode("ScriptTemplates")

proc buildTemplateSelect() =
  ## the <select>: a blank entry, then each template under its group
  let sel = byId("templateSelect")
  if sel.isNil: return
  sel.setProp("innerHTML", "<option value=\"__blank__\">Loading templates…</option>")
  sel.setProp("disabled", true)
  if templates().isNil:
    sel.setProp("innerHTML", "<option value=\"__blank__\">⚠ scriptTemplates.js not loaded</option>"); return
  templates().invoke("load").toNode.whenDone(proc(list: Node) =
    let items = jsonOf(list)
    var groups: seq[(string, string)]           # group -> its options' html
    for t in items.getElems:
      let g = t{"group"}.getStr
      var at = -1
      for i, (name, _) in groups:
        if name == g: at = i
      if at < 0: groups.add (g, ""); at = groups.high
      groups[at][1].add "<option value=\"" & esc(t{"id"}.getStr) & "\">" & esc(t{"name"}.getStr(t{"label"}.getStr)) & "</option>"
    var html = "<option value=\"__blank__\">— choose a template —</option>"
    for (g, opts) in groups: html.add "<optgroup label=\"" & esc(g) & "\">" & opts & "</optgroup>"
    sel.setProp("innerHTML", html)
    sel.setProp("disabled", false),
  proc(msg: string) =
    sel.setProp("innerHTML", "<option value=\"__blank__\">⚠ Failed to load templates</option>"))

proc withTemplate(id: string, use: proc(t: JsonNode)) =
  if templates().isNil: return
  templates().invoke("load").toNode.whenDone(proc(list: Node) =
    for t in jsonOf(list).getElems:
      if t{"id"}.getStr == id: use(t); return,
  proc(msg: string) = toast("Failed to load templates: " & msg, "error"))

proc loadSelectedTemplate() =
  let sel = byId("templateSelect")
  if sel.isNil or sel.value == "__blank__" or sel.getBool("disabled"): return
  withTemplate(sel.value, proc(t: JsonNode) =
    let ta = byId("scriptTextarea")
    let code = t{"code"}.getStr
    ta.setProp("value", code)
    markDirty(); updateGutter(); scriptSave(code)
    ta.focus()
    toast("Template loaded: " & t{"name"}.getStr(t{"id"}.getStr), "success", 2500))

proc saveAsTemplate() =
  let code = byId("scriptTextarea").value
  if code.strip.len == 0: toast("Cannot save empty script", "warn"); return
  let (ok, name) = prompt("Enter a name for this template:")
  if not ok or name.len == 0: return
  templates().invoke("save", name, code).toNode.whenDone(proc(res: Node) =
    let r = jsonOf(res)
    if r{"ok"}.getBool:
      toast("Template saved: " & name, "success")
      templates().invoke("reload").toNode.whenDone(proc(x: Node) = buildTemplateSelect(), proc(m: string) = buildTemplateSelect())
    else: toast("Failed to save template: " & r{"error"}.getStr("Unknown error"), "error"),
  proc(msg: string) = toast("Failed to save template: " & msg, "error"))

proc deleteTemplate() =
  let sel = byId("templateSelect")
  if sel.isNil or sel.value == "__blank__" or sel.getBool("disabled"): return
  withTemplate(sel.value, proc(t: JsonNode) =
    if not t{"isDynamic"}.getBool: toast("Cannot delete built-in templates", "warn"); return
    if not window.invoke("confirm", "Delete template \"" & t{"name"}.getStr & "\"?").toBool: return
    let file = t{"file"}.getStr.split('/')[^1]
    templates().invoke("delete", file).toNode.whenDone(proc(res: Node) =
      let r = jsonOf(res)
      if r{"ok"}.getBool:
        toast("Template deleted", "success")
        templates().invoke("reload").toNode.whenDone(proc(x: Node) = buildTemplateSelect(), proc(m: string) = buildTemplateSelect())
      else: toast("Failed to delete template: " & r{"error"}.getStr("Unknown error"), "error"),
    proc(msg: string) = toast("Failed to delete template: " & msg, "error")))

proc runUserScript(v: SheetView) =
  let code = byId("scriptTextarea").value
  if code.strip.len == 0: conPrint("-- Nothing to run.", "warn"); return
  if programRunning: conPrint("A program is already running.", "warn"); return
  let luau = window.getNode("SheetLuau")
  if luau.isNil: conPrint("✖ The Luau runtime (js/sheetLuau.js) is not loaded", "error"); return
  conDivider("Run")
  setConsoleDot("idle")
  programRunning = true
  # onOutput(level, text): the runtime calls it with two arguments; a Nim
  # callback takes one, so a small adapter packs them
  let say = callback(proc(e: Event) =
    let o = jsonOf(e.eventObject)
    let level = o{"level"}.getStr("log")
    let prefix = case level
      of "warn": "⚠ "
      of "info": "ℹ "
      else: ""
    conPrint(prefix & o{"text"}.getStr, if level == "log": "log" else: level))
  let adapter = construct("Function", "f", "return function (level, text) { f({ level: String(level), text: String(text) }); };")
    .invoke("call", jsNull(), say).toNode
  let opts = construct("Object")
  opts.setProp("fileName", programFile)
  opts.setProp("onOutput", adapter)
  let studio = window.getNode("QoqoroStudioContext")
  if not studio.isNil: opts.setProp("context", window.invoke("QoqoroStudioContext", adapter).toNode)
  luau.invoke("run", code, opts).toNode.whenDone(proc(res: Node) =
    programRunning = false
    let r = jsonOf(res)
    if r.hasKey("result") and r["result"].kind != JNull: conPrint("→ " & $r["result"], "success")
    var parts: seq[string]
    let cells = r{"applied"}{"cells"}.getInt
    let charts = r{"applied"}{"charts"}.getInt
    if cells > 0: parts.add $cells & " cell(s)"
    if charts > 0: parts.add $charts & " chart(s)"
    conPrint("✔ Done" & (if parts.len > 0: " · " & parts.join(", ") else: ""), "success")
    setConsoleDot("ok")
    v.requestDraw(),
  proc(msg: string) =
    programRunning = false
    conPrint("✖ " & msg, "error")
    setConsoleDot("err"))

proc openProgram*(v: SheetView) =
  if v.editing: v.endEdit(true)
  let overlay = byId("scriptOverlay")
  let ta = byId("scriptTextarea")
  if overlay.isNil or ta.isNil: return
  ta.setProp("value", scriptLoad())
  updateGutter()
  markSaved()
  byId("autorunToggle").toggleClass("active", autorunLoad())
  overlay.addClass("open")
  setTimeout(60, proc() = ta.focus())

proc closeProgram(v: SheetView) =
  let overlay = byId("scriptOverlay")
  if overlay.isNil: return
  if programDirty: scriptSave(byId("scriptTextarea").value)
  overlay.removeClass("open")
  v.editor.focus(true)

proc programAfterOpen*(v: SheetView, fileName: string) =
  ## autorun: the saved program runs when a file is opened
  programFile = fileName
  if not autorunLoad() or scriptLoad().strip.len == 0: return
  toast("▶ Running autorun script…", "info", 2000)
  setTimeout(500, proc() =
    let ta = byId("scriptTextarea")
    if not ta.isNil: ta.setProp("value", scriptLoad())
    v.runUserScript())

proc bindProgram(v: SheetView) =
  let overlay = byId("scriptOverlay")
  let ta = byId("scriptTextarea")
  if overlay.isNil or ta.isNil: return
  buildTemplateSelect()
  let sel = byId("templateSelect")
  sel.on("change", proc(e: Event) =
    let id = sel.value
    let desc = byId("templateDesc")
    if desc.isNil: return
    desc.setProp("textContent", "")
    withTemplate(id, proc(t: JsonNode) = desc.setProp("textContent", t{"description"}.getStr)))
  onClick(byId("templateLoadBtn"), proc() = loadSelectedTemplate())
  onClick(byId("templateSaveBtn"), proc() = saveAsTemplate())
  onClick(byId("templateDeleteBtn"), proc() = deleteTemplate())
  onClick(byId("openScriptEditor"), proc() = v.openProgram())
  onClick(byId("scriptCloseBtn"), proc() = v.closeProgram())
  overlay.on("click", proc(e: Event) = (if e.target.same(overlay): v.closeProgram()))
  onClick(byId("scriptRunBtn"), proc() = v.runUserScript())
  var saveTimer: int32 = 0
  ta.on("keydown", proc(e: Event) =
    e.stopPropagation()
    if (e.ctrlKey or e.metaKey) and e.key == "Enter":
      e.preventDefault(); scriptSave(ta.value); v.runUserScript(); return
    if e.key == "Tab":
      e.preventDefault()
      let a = int(ta.getNum("selectionStart"))
      let b = int(ta.getNum("selectionEnd"))
      let t = ta.value
      ta.setProp("value", t.substr(0, a - 1) & "  " & t.substr(b))
      ta.setProp("selectionStart", a + 2); ta.setProp("selectionEnd", a + 2)
      updateGutter()
    if e.key == "Escape": v.closeProgram())
  ta.on("input", proc(e: Event) =
    markDirty(); updateGutter()
    clearTimeout(saveTimer)
    saveTimer = setTimeout(800, proc() = scriptSave(ta.value)))
  ta.on("scroll", proc(e: Event) =
    let g = byId("scriptGutter")
    if not g.isNil: g.setProp("scrollTop", ta.getNum("scrollTop")))
  onClick(byId("consoleClearBtn"), proc() =
    byId("consoleOutput").setProp("innerHTML", "<p class=\"con-line info\">// Console cleared.</p>")
    setConsoleDot("idle"))
  let autorun = byId("autorunToggle")
  onClick(autorun, proc() =
    let on = not autorun.invoke("classList").toNode.invoke("contains", "active").toBool
    autorun.toggleClass("active", on)
    discard storageSet(AutorunKey, $on)
    toast(if on: "Autorun enabled" else: "Autorun disabled", if on: "success" else: "warn", 2000))
  document.on("keydown", proc(e: Event) =
    if e.key == "Escape" and overlay.invoke("classList").toNode.invoke("contains", "open").toBool: v.closeProgram())
  # the toolbar button shows a saved program
  let open = byId("openScriptEditor")
  if not open.isNil and scriptLoad().strip.len > 0:
    open.addClass("has-script"); open.setAttribute("title", "Custom script saved — click to edit")
  updateGutter()
