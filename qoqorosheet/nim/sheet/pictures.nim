## Pictures over the grid, included into view.nim: Insert > Pictures
## (imageCtrl.js in Luckysheet): a picture from a file lands at the active
## cell; click selects it (an outline and a corner handle), drag moves it,
## the corner resizes it (Shift keeps the shape), Delete removes it. Each
## change is undoable and saved with the workbook.

var
  picLayer: Node
  picSelected = -1
  picShown = "-"

proc picturesKey(v: SheetView): string =
  let s = v.sheet
  result = $v.wb.active & "|" & $picSelected & "|" & $s.pictures.len
  for p in s.pictures: result.add "|" & $p.x & "," & $p.y & "," & $p.w & "," & $p.h & "," & $p.src.len

proc renderPictures(v: SheetView)

proc changePictures(v: SheetView, body: proc()) =
  v.structural(body)
  picShown = "-"
  v.renderPictures()

proc renderPictures(v: SheetView) =
  if picLayer.isNil:
    picLayer = el("div")
    picLayer.setAttribute("id", "qs-pictures")
    picLayer.setAttribute("style", "position:absolute;left:0;top:0;width:0;height:0;z-index:25")
    discard v.cellMain.add picLayer
  let key = v.picturesKey()
  if key == picShown: return
  picShown = key
  picLayer.dropChildren()
  let s = v.sheet
  for i_1, p_1 in s.pictures:
    let i_0 = i_1
    let p_0 = p_1
    closureScope:
      let i = i_0
      let p = p_0
      let box = el("div", "qs-pic luckysheet-mousedown-cancel")
      box.setAttribute("style", "position:absolute;left:" & px(p.x) & ";top:" & px(p.y) & ";width:" & px(p.w) & ";height:" & px(p.h) &
        ";cursor:move;" & (if i == picSelected: "outline:1px solid #0188fb;" else: ""))
      let img = el("img", "luckysheet-mousedown-cancel")
      img.setAttribute("src", p.src)
      img.setAttribute("draggable", "false")
      img.setAttribute("style", "width:100%;height:100%;display:block;pointer-events:none;user-select:none")
      discard box.add img
      var handle = Node(0)
      if i == picSelected:
        handle = el("div", "luckysheet-mousedown-cancel")
        handle.setAttribute("style", "position:absolute;right:-5px;bottom:-5px;width:9px;height:9px;background:#fff;border:1px solid #0188fb;cursor:nwse-resize")
        discard box.add handle
      discard picLayer.add box
      # move / resize with the mouse; the change lands on mouseup
      box.on("mousedown", proc(e: Event) =
        e.preventDefault(); e.stopPropagation()
        if v.editing: v.endEdit(true)
        if picSelected != i:
          picSelected = i; v.renderPictures()
        let resizing = not handle.isNil and e.target.same(handle)
        let (sx, sy) = (e.clientX, e.clientY)
        let start = v.sheet.pictures[i]
        var cur = start
        let el2 = picLayer.queryAll(".qs-pic")[i]
        var moveL, upL: int32
        moveL = document.on("mousemove", proc(m: Event) =
          let (dx, dy) = (m.clientX - sx, m.clientY - sy)
          if resizing:
            cur.w = max(10.0, start.w + dx)
            cur.h = if m.shiftKey: cur.w * start.h / max(start.w, 1.0) else: max(10.0, start.h + dy)
          else:
            cur.x = max(0.0, start.x + dx); cur.y = max(0.0, start.y + dy)
          el2.style("left", px(cur.x)); el2.style("top", px(cur.y))
          el2.style("width", px(cur.w)); el2.style("height", px(cur.h)))
        upL = document.on("mouseup", proc(m: Event) =
          off(moveL); off(upL)
          if cur != start:
            let s2 = v.sheet
            v.changePictures(proc() = s2.pictures[i] = cur)
          v.editor.focus(true)))

proc deleteSelectedPicture(v: SheetView): bool =
  ## Delete with a picture selected removes it
  if picSelected < 0 or picSelected >= v.sheet.pictures.len: return false
  let i = picSelected
  let s = v.sheet
  picSelected = -1
  v.changePictures(proc() = s.pictures.delete(i))
  true

proc deselectPicture(v: SheetView) =
  if picSelected >= 0:
    picSelected = -1; v.renderPictures()

proc addPictureFile(v: SheetView, file: Node) =
  ## a picture file (chosen, pasted or dropped) at the active cell, at most 400 px wide
  readBlob(file, brDataUrl, proc(ok: bool, url: string) =
    if not ok: v.tooltipInfo("Insert Picture", "The picture could not be read."); return
    if v.sheet.protected: v.protectedMessage(); return
    let probe = el("img")
    probe.on("load", proc(e: Event) =
      var w = probe.getNum("naturalWidth")
      var h = probe.getNum("naturalHeight")
      if w > 400: h = h * 400 / w; w = 400
      let (x, y, _, _) = v.cellBox(v.ar, v.ac)
      let s = v.sheet
      v.changePictures(proc() = s.pictures.add Picture(src: url, x: x, y: y, w: w, h: h))
      picSelected = s.pictures.high
      picShown = "-"; v.renderPictures())
    probe.setAttribute("src", url))

proc imageIn(data: Node): Node =
  ## the first picture file a clipboard or drop carries
  if data.isNil: return Node(0)
  let files = data.getNode("files")
  if not files.isNil:
    for i in 0 ..< int(files.getNum("length")):
      let f = files.invoke("item", i).toNode
      if not f.isNil and f.getStr("type").startsWith("image/"): return f
  let items = data.getNode("items")
  if not items.isNil:
    for i in 0 ..< int(items.getNum("length")):
      let it = items.invoke("item", i).toNode
      if not it.isNil and it.getStr("kind") == "file" and it.getStr("type").startsWith("image/"):
        return it.invoke("getAsFile").toNode
  Node(0)

proc bindPictureDrop(v: SheetView) =
  ## a picture file dropped on the grid lands at the cell under it (Excel)
  v.gridContainer.on("dragover", proc(e: Event) =
    let dt = e.dataTransfer
    if not dt.isNil and dt.getNode("types").invoke("includes", "Files").toBool:
      e.preventDefault())
  v.gridContainer.on("drop", proc(e: Event) =
    let file = imageIn(e.dataTransfer)
    if file.isNil: return
    e.preventDefault()
    let (x, y) = v.contentPoint(e)
    let (r, c) = v.hitCell(x, y)
    v.extraRanges.setLen(0)
    v.ar = r; v.ac = c; v.cr = r; v.cc = c
    v.showSelection()
    v.addPictureFile(file))

proc insertPicture*(v: SheetView) =
  let input = el("input")
  input.setAttribute("type", "file")
  input.setAttribute("accept", "image/*")
  input.on("change", proc(e: Event) =
    let file = input.getNode("files").invoke("item", 0).toNode
    if file.isNil: return
    v.addPictureFile(file))
  input.click()
