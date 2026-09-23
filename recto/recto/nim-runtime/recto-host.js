/**
 * recto-host.js — the browser adapter for the Nim viewer.
 *
 * Nim (app.wasm, nim-src/main.nim) owns every decision: page geometry and
 * the render window, zoom, the outline, the annotation model and ink
 * painting. This file does only what the WASM module cannot reach through
 * BindWeb:
 *
 *   - pdf.js: open documents, render page bitmaps and text layers, read the
 *     outline (with every destination resolved to a page number) and the
 *     Subject metadata that stores annotations;
 *   - pdf-lib + the server protocol: write the annotation JSON back into the
 *     PDF and POST it, `#fetchpdf=` hash opens, postMessage API, PDF tags;
 *   - pointer/touch capture: ink samples with pressure, pinch, pan, ctrl+wheel;
 *   - presentation that needs layout measurement: the context menu, bookmark
 *     drag/resize gestures, text-selection rectangles, the eraser ring,
 *     clipboard and html2canvas capture.
 *
 * Protocol (see nim-src/host.nim): Nim calls `recto_host_command(json)`;
 * the host answers with events written to the hidden #recto-host-event
 * textarea, parking payloads over 3.5 KB and sending a sentinel instead.
 */
import * as pdfjsLib from "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.0.379/pdf.min.mjs";
pdfjsLib.GlobalWorkerOptions.workerSrc = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.0.379/pdf.worker.min.mjs";

const HOST_VALUE_SENTINEL = "\x01recto-host-value";
const EVENT_INLINE_LIMIT = 3500;
const SAMPLE_PDF = "https://mozilla.github.io/pdf.js/web/compressed.tracemonkey-pldi-09.pdf";

export function createRectoHost() {
  const encoder = new TextEncoder(), decoder = new TextDecoder();
  const $ = id => document.getElementById(id);
  const parked = [];
  let memory = null;

  // ── Nim → host ───────────────────────────────────────────────────────────
  const envImports = {
    recto_host_command(ptr, len) {
      const text = decoder.decode(new Uint8Array(memory.buffer, ptr >>> 0, len >>> 0));
      let data;
      try { data = JSON.parse(text); } catch { console.warn("bad host command", text); return 0; }
      try { handleCommand(data); } catch (e) { console.error("host command failed", data.op, e); }
      return 1;
    },
    recto_host_load(ptr, capacity) {
      if (!parked.length) return 0;
      const bytes = parked[0];
      if (!ptr) return bytes.length;
      if (capacity < bytes.length) return 0;
      new Uint8Array(memory.buffer, ptr >>> 0, bytes.length).set(bytes);
      parked.shift();
      return bytes.length;
    },
  };

  // ── host → Nim ───────────────────────────────────────────────────────────
  function sendEvent(obj) {
    const el = $("recto-host-event");
    if (!el) return;
    const text = JSON.stringify(obj);
    if (text.length > EVENT_INLINE_LIMIT) { parked.push(encoder.encode(text)); el.value = HOST_VALUE_SENTINEL; }
    else el.value = text;
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }

  // ── viewer state mirrored from Nim ───────────────────────────────────────
  const state = {
    pdf: null, pages: [], scale: 1, dpr: Math.min(window.devicePixelRatio || 1, 2),
    filename: "", fileId: "", dirty: false, annotsJson: "[]",
    ink: { active: false, tool: "pen", penOnly: true, eraserSize: 14 },
    saving: false, saveQueued: false,
  };
  window._rectoHost = state;

  const viewerEl = () => $("viewer");
  const pageEl = n => $("page-" + n);

  function viewportEvent(extra = {}) {
    const v = viewerEl();
    if (!v) return;
    sendEvent({ type: "viewport", top: v.scrollTop, left: v.scrollLeft, w: v.clientWidth, h: v.clientHeight, dpr: state.dpr, ...extra });
  }

  // ── commands ─────────────────────────────────────────────────────────────
  function handleCommand(data) {
    switch (data.op) {
      case "shell-ready": bindShell(); break;
      case "open-file": $("file-input")?.click(); break;
      case "open-demo": openSource(SAMPLE_PDF, "tracemonkey-pldi-09.pdf (sample)"); break;
      case "render": renderPage(data.page, data.scale); break;
      case "unrender": unrenderPage(data.page); break;
      case "scale": applyCssScale(data.scale); break;
      case "scroll": {
        const v = viewerEl(); if (!v) break;
        if (data.smooth) v.scrollTo({ top: data.top, left: data.left ?? v.scrollLeft, behavior: "smooth" });
        else { v.scrollTop = data.top; v.scrollLeft = data.left ?? v.scrollLeft; }
        break;
      }
      case "ink-config": Object.assign(state.ink, { active: !!data.active, tool: data.tool, penOnly: !!data.penOnly, eraserSize: +data.eraserSize || 14 });
        state.scale = +data.scale || state.scale; if (!state.ink.active || state.ink.tool !== "eraser") hideEraserCursor(); break;
      case "prefs": try { localStorage.setItem("recto_ink_prefs", JSON.stringify({ pen: data.pen, highlighter: data.highlighter, eraser: data.eraser, penOnly: data.penOnly })); } catch {} break;
      case "save": state.dirty = true; state.annotsJson = data.annots || "[]"; try { window.currentAnnotations = JSON.parse(state.annotsJson); } catch {} triggerSave(); break;
      default: console.warn("unknown host command", data.op);
    }
  }

  // ── document lifecycle ───────────────────────────────────────────────────
  async function openSource(source, label, initialPage, fileId = "") {
    await flush();
    state.fileId = fileId;
    sendEvent({ type: "loading" });
    try {
      teardown();
      const pdf = await pdfjsLib.getDocument(source).promise;
      state.pdf = pdf;
      const pageObjs = await Promise.all(Array.from({ length: pdf.numPages }, (_, i) => pdf.getPage(i + 1)));
      state.pages = pageObjs.map((page, i) => {
        const vp = page.getViewport({ scale: 1 });
        return { num: i + 1, page, baseW: vp.width, baseH: vp.height, canvas: null, renderTask: null, pendingScale: null, renderedScale: null, textLayer: null, textLayerDiv: null };
      });
      state.filename = label || "";
      window.currentFilename = state.filename;
      const v = viewerEl();
      sendEvent({ type: "loaded", filename: state.filename, initialPage: initialPage || 1, dpr: state.dpr,
        viewport: { w: v?.clientWidth || 0, h: v?.clientHeight || 0 }, pages: state.pages.map(p => ({ w: p.baseW, h: p.baseH })) });
      loadOutline(pdf);
      loadAnnotationsFromPDF(pdf);
    } catch (e) {
      console.error(e);
      sendEvent({ type: "load-failed", message: String(e?.message || e) });
    }
  }

  function teardown() {
    for (const p of state.pages) { try { p.renderTask?.cancel(); } catch {} try { p.textLayer?.cancel(); } catch {} }
    if (state.pdf) { try { state.pdf.destroy(); } catch {} }
    state.pdf = null; state.pages = [];
  }

  // ── rendering ────────────────────────────────────────────────────────────
  async function renderPage(n, targetScale) {
    const p = state.pages[n - 1]; const container = pageEl(n);
    if (!p || !container) return;
    if (p.renderedScale === targetScale && p.canvas) { sendEvent({ type: "rendered", page: n, scale: targetScale }); return; }
    if (p.renderTask) { if (p.pendingScale === targetScale) return; try { p.renderTask.cancel(); } catch {} }
    if (p.textLayer) { try { p.textLayer.cancel(); } catch {} p.textLayer = null; }
    if (p.textLayerDiv) { p.textLayerDiv.remove(); p.textLayerDiv = null; }
    p.pendingScale = targetScale;
    const viewport = p.page.getViewport({ scale: targetScale });
    const prevCanvas = p.canvas;
    // Render off-screen and swap: assigning width on the live canvas clears
    // it to black for a frame, the swap never shows a blank page.
    const canvas = document.createElement("canvas");
    canvas.className = "pdf-bitmap";
    canvas.style.width = viewport.width + "px"; canvas.style.height = viewport.height + "px";
    canvas.width = Math.floor(viewport.width * state.dpr); canvas.height = Math.floor(viewport.height * state.dpr);
    const ctx = canvas.getContext("2d", { alpha: false });
    p.renderTask = p.page.render({ canvasContext: ctx, viewport, transform: state.dpr !== 1 ? [state.dpr, 0, 0, state.dpr, 0, 0] : null });
    try {
      await p.renderTask.promise;
      if (p.pendingScale !== targetScale) return;
      if (!pageEl(n)) return; // document changed underneath
      if (prevCanvas === null || prevCanvas.parentNode === null) container.insertBefore(canvas, container.firstChild);
      else prevCanvas.replaceWith(canvas);
      p.canvas = canvas; p.renderedScale = targetScale;
      sendEvent({ type: "rendered", page: n, scale: targetScale });
      renderTextLayer(p, viewport, targetScale);
    } catch (e) {
      if (e?.name !== "RenderingCancelledException") console.error("Render failed for page", n, e);
    } finally {
      p.renderTask = null; p.pendingScale = null;
    }
  }

  async function renderTextLayer(p, viewport, targetScale) {
    try {
      const textContent = await p.page.getTextContent();
      if (p.renderedScale !== targetScale) return;
      const container = pageEl(p.num); if (!container) return;
      const div = document.createElement("div");
      div.className = "textLayer";
      div.style.setProperty("--scale-factor", viewport.scale);
      div.style.width = viewport.width + "px"; div.style.height = viewport.height + "px";
      container.appendChild(div);
      p.textLayerDiv = div;
      p.textLayer = pdfjsLib.renderTextLayer({ textContentSource: textContent, container: div, viewport });
      await p.textLayer.promise;
    } catch (e) {
      if (e?.name !== "AbortException" && e?.message !== "TextLayer task cancelled.") console.warn("Text layer failed for page", p.num, e);
    }
  }

  function unrenderPage(n) {
    const p = state.pages[n - 1]; if (!p) return;
    if (p.renderTask) { try { p.renderTask.cancel(); } catch {} }
    if (p.textLayer) { try { p.textLayer.cancel(); } catch {} p.textLayer = null; }
    if (p.textLayerDiv) { p.textLayerDiv.remove(); p.textLayerDiv = null; }
    if (p.canvas) { p.canvas.remove(); p.canvas.width = 0; p.canvas.height = 0; p.canvas = null; }
    p.renderedScale = null;
  }

  function applyCssScale(newScale) {
    state.scale = newScale;
    for (const p of state.pages) {
      if (!p.canvas || p.renderedScale == null) continue;
      const ratio = newScale / p.renderedScale;
      const vp = p.page.getViewport({ scale: p.renderedScale });
      const w = vp.width * ratio, h = vp.height * ratio;
      p.canvas.style.width = w + "px"; p.canvas.style.height = h + "px";
      if (p.textLayerDiv) {
        p.textLayerDiv.style.transform = `scale(${ratio})`; p.textLayerDiv.style.transformOrigin = "0 0";
        p.textLayerDiv.style.width = w + "px"; p.textLayerDiv.style.height = h + "px";
      }
    }
  }

  // ── outline & annotations ────────────────────────────────────────────────
  async function loadOutline(pdf) {
    try {
      const outline = await pdf.getOutline();
      const items = [];
      const walk = async (nodes, depth) => {
        for (const item of nodes || []) {
          let page = 0;
          try {
            let dest = item.dest;
            if (typeof dest === "string") dest = await pdf.getDestination(dest);
            if (dest && dest[0]) page = (await pdf.getPageIndex(dest[0])) + 1;
          } catch {}
          items.push({ title: item.title || "", depth, page, hasChildren: !!(item.items && item.items.length) });
          if (item.items?.length) await walk(item.items, depth + 1);
        }
      };
      await walk(outline, 0);
      if (state.pdf !== pdf) return;
      sendEvent({ type: "outline", items });
    } catch (err) {
      console.error("Outline error:", err);
      sendEvent({ type: "outline", items: "error" });
    }
  }

  async function loadAnnotationsFromPDF(pdf) {
    let json = "[]";
    try {
      const meta = await pdf.getMetadata();
      const subject = meta.info?.Subject || "";
      if (subject.startsWith("JSON_ANNOTS:")) json = subject.slice(12);
    } catch {}
    if (state.pdf !== pdf) return;
    state.annotsJson = json;
    try { window.currentAnnotations = JSON.parse(json); } catch { window.currentAnnotations = []; }
    sendEvent({ type: "annots", json });
  }

  // ── saving (server) ──────────────────────────────────────────────────────
  function resolveBase() {
    const candidates = [];
    try { if (/^https?:$/i.test(window.location.protocol)) candidates.push(window.location.origin); } catch {}
    try { if (window.parent !== window && /^https?:$/i.test(window.parent.location.protocol)) candidates.push(window.parent.location.origin); } catch {}
    try { const s = (localStorage.getItem("urladdress") || "").trim(); if (s) candidates.push(s); } catch {}
    for (const raw of candidates) {
      try {
        const url = new URL(raw, window.location.href);
        if (!/^https?:$/i.test(url.protocol)) continue;
        const norm = url.origin.replace(/\/+$/, "");
        try { localStorage.setItem("urladdress", norm); } catch {}
        return norm;
      } catch {}
    }
    return "";
  }

  window.triggerAnnotationSave = triggerSave;
  async function triggerSave() {
    if (!state.filename || state.saving) { if (state.saving) state.saveQueued = true; return; }
    if (typeof window.PDFLib === "undefined") { showToast("PDF save library is unavailable; changes are not saved", 0); return; }
    state.saving = true;
    showToast("Saving…", 0);
    try {
      const base = resolveBase();
      if (!base) { showToast("No server — annotations in memory only", 2500); return; }
      const bytes = await fetch(state.fileId ? `${base}/api/pdf/${encodeURIComponent(state.fileId)}` : `${base}/get_file_content?filename=${encodeURIComponent(state.filename)}&t=${Date.now()}`).then(r => { if (!r.ok) throw Error("Cannot read PDF: HTTP " + r.status); return r.arrayBuffer(); });
      const savingJson = state.annotsJson;
      const { PDFDocument } = window.PDFLib;
      const pdfDoc = await PDFDocument.load(bytes);
      pdfDoc.setSubject("JSON_ANNOTS:" + savingJson);
      const out = await pdfDoc.save();
      let r;
      if (state.fileId) {
        r = await fetch(`${base}/api/pdf/${encodeURIComponent(state.fileId)}`, { method: "POST", headers: { "Content-Type": "application/pdf" }, body: out });
      } else {
        const b64 = await new Promise(res => { const reader = new FileReader(); reader.onloadend = () => res(reader.result.split(",")[1]); reader.readAsDataURL(new Blob([out], { type: "application/pdf" })); });
        r = await fetch(`${base}/save_file`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ filename: state.filename, content: b64 }) });
      }
      if (!r.ok) throw Error("PDF save failed: HTTP " + r.status);
      if (savingJson === state.annotsJson) state.dirty = false;
      showToast("Saved!", 2000);
    } catch (err) {
      console.error("Save error:", err);
      showToast("Save error: " + err.message, 2500);
    } finally {
      state.saving = false;
      if (state.saveQueued) { state.saveQueued = false; triggerSave(); }
    }
  }

  async function flush() {
    while (state.saving) await new Promise(resolve => setTimeout(resolve, 50));
    if (state.dirty) await triggerSave();
    while (state.saving) await new Promise(resolve => setTimeout(resolve, 50));
    if (state.dirty) throw Error("PDF annotations have not saved. Please retry before opening another PDF.");
  }
  window.addEventListener("beforeunload", event => { if (state.dirty || state.saving) { event.preventDefault(); event.returnValue = ""; } });
  function citationUrl(page, annotId = "") {
    const params = new URLSearchParams({fetchpdf: state.filename, page: String(page)});
    if (state.fileId) params.set("fileId", state.fileId);
    if (annotId) params.set("annotId", annotId);
    return "#" + params;
  }
  function copyBookmarkLink(page, annotId) {
    const label = `${shortName(state.filename)}, p.${page}`;
    copyRichText(label, `<a data-pdf-file-id="${escHtml(state.fileId)}" data-pdf-title="${escHtml(state.filename)}" data-pdf-page="${page}" href="${escHtml(citationUrl(page, annotId))}">${escHtml(label)}</a>`);
    showToast("Link copied!");
  }
  // ── presentation helpers ─────────────────────────────────────────────────
  let toastTimer;
  function showToast(msg, duration = 2200) {
    const t = $("toast"); if (!t) return;
    t.textContent = msg; t.classList.add("show");
    clearTimeout(toastTimer);
    if (duration > 0) toastTimer = setTimeout(() => t.classList.remove("show"), duration);
  }
  function hideEraserCursor() { const c = $("eraser-cursor"); if (c) c.style.display = "none"; }

  function copyPlainText(text) {
    const ta = document.createElement("textarea");
    ta.style.cssText = "position:fixed;top:-9999px;left:0;opacity:0;"; ta.value = text;
    document.body.appendChild(ta); ta.focus(); ta.select();
    try { document.execCommand("copy"); } catch {}
    document.body.removeChild(ta);
  }
  function copyRichText(plain, html) {
    if (state.fileId) {
      const parsed = new DOMParser().parseFromString(html, "text/html");
      const citation = parsed.querySelector("[data-pdf-file-id]");
      if (citation) {
        const page = Math.max(1,Number(citation.dataset.pdfPage)||1);
        const href = citation.getAttribute("href") || citationUrl(page,citation.dataset.pdfAnnotId);
        const annotId = new URLSearchParams(href.split("#")[1]||"").get("annotId");
        const target = state.filename + (annotId ? "#annotId="+encodeURIComponent(annotId) : "");
        const escape = text => String(text).replace(/\\/g,"\\\\").replace(/\n/g,"\\n").replace(/\t/g,"\\t");
        const style = "11\t0\t0\t#0f172a\tArial\t\t0\t0";
        const displayedCitation = citation.textContent || plain || `${shortName(state.filename)}, p.${page}`;
        const plainPrefix = plain.endsWith(displayedCitation)
          ? plain.slice(0, plain.length - displayedCitation.length)
          : "";
        const assets = [], img = parsed.querySelector("img");
        const lines = ["QNOTE-NIM\t2"];
        let nextId = 1;
        if (img && /^data:image\/png;base64,/.test(img.getAttribute("src")||"")) {
          const token = "recto-clipboard-image";
          const width = Math.min(480, Number(citation.dataset.originalWidth)||320);
          const height = width*(Number(citation.dataset.originalHeight)||200)/(Number(citation.dataset.originalWidth)||320);
          assets.push({token,node:{tag:"image",attrs:{src:img.getAttribute("src"),w:String(width),h:String(height),wrap:"inline"},children:[]}});
          lines.push(["I",nextId++,token,0,0,width,height,style,"rgba(0,0,0,0)","rgba(0,0,0,0)","inline",-1,-1].join("\t"));
          lines.push("L\t"+(nextId++)+"\t"+style);
        }
        for (const character of plainPrefix) {
          if (character === "\r") continue;
          if (character === "\n") lines.push("L\t"+(nextId++)+"\t"+style);
          else lines.push("C\t"+(nextId++)+"\t"+escape(character)+"\t"+style);
        }
        const citationId = nextId++;
        lines.push("C\t"+citationId+"\t"+escape(displayedCitation)+"\t"+style);
        const links = [{id:citationId,kind:"pdf",target,fileId:state.fileId,page,label:displayedCitation}];
        lines.splice(1,0,"X\t0\t"+escape(JSON.stringify({version:1,links})));
        html = `<div data-qnote-fragment="${encodeURIComponent(JSON.stringify({format:1,source:lines.join("\n")+"\n",assets}))}">${html}</div>`;
      }
    }
    const div = document.createElement("div");
    div.contentEditable = "true"; div.style.cssText = "position:fixed;top:-9999px;left:0;opacity:0;white-space:pre-wrap;"; div.innerHTML = html;
    document.body.appendChild(div);
    const range = document.createRange(); range.selectNodeContents(div);
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
    const onCopy = event => { event.clipboardData.setData("text/plain", plain); event.clipboardData.setData("text/html", html); event.preventDefault(); };
    document.addEventListener("copy", onCopy, true);
    try { document.execCommand("copy"); } catch { copyPlainText(plain); }
    finally { document.removeEventListener("copy", onCopy, true); }
    sel.removeAllRanges(); document.body.removeChild(div);
  }
  const escHtml = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const shortName = fn => fn.split(/[/\\]/).pop().slice(0, 18) + "…";
  const buildCiteHtml = (text, fn, page) => `${escHtml(text)} <a data-pdf-file-id="${escHtml(state.fileId)}" data-pdf-title="${escHtml(fn)}" data-pdf-page="${page}" href="${escHtml(citationUrl(page))}">[${escHtml(shortName(fn))}, p.${page}]</a>`;
  const buildCitePlain = (text, fn, page) => `${text} [${shortName(fn)}, p.${page}]`;

  // ── context menu ─────────────────────────────────────────────────────────
  function showCtxMenu(clientX, clientY, items) {
    const ctxMenu = $("ctx-menu"); if (!ctxMenu) return;
    ctxMenu.innerHTML = "";
    for (const item of items) {
      if (item === "sep") { const s = document.createElement("div"); s.className = "ctx-sep"; ctxMenu.appendChild(s); continue; }
      const d = document.createElement("div");
      d.className = "ctx-item" + (item.red ? " red" : "");
      if (item.submenu) {
        d.innerHTML = `<span>${item.icon || ""}</span><span>${item.label}</span><span class="ctx-arrow">▶</span>`;
        const sub = document.createElement("div"); sub.className = "ctx-submenu";
        for (const si of item.submenu) {
          const sd = document.createElement("div"); sd.className = "ctx-item" + (si.red ? " red" : "");
          sd.innerHTML = `<span>${si.icon || ""}</span><span>${si.label}</span>`;
          sd.addEventListener("click", ev => { ev.stopPropagation(); hideCtxMenu(); si.action?.(); });
          sub.appendChild(sd);
        }
        d.appendChild(sub);
      } else {
        d.innerHTML = `<span>${item.icon || ""}</span><span>${item.label}</span>`;
        d.addEventListener("click", ev => { ev.stopPropagation(); hideCtxMenu(); item.action?.(); });
      }
      ctxMenu.appendChild(d);
    }
    ctxMenu.style.display = "block"; ctxMenu.style.visibility = "hidden";
    const mw = ctxMenu.offsetWidth || 200, mh = ctxMenu.offsetHeight || 100;
    ctxMenu.style.visibility = "";
    ctxMenu.style.left = `${Math.min(clientX, window.innerWidth - mw - 6)}px`;
    ctxMenu.style.top = `${Math.min(clientY, window.innerHeight - mh - 6)}px`;
  }
  function hideCtxMenu() { const m = $("ctx-menu"); if (m) m.style.display = "none"; }

  let storedSelection = null, lastContextMenuEvent = null;

  function pageRectOf(pageElement) { return pageElement.getBoundingClientRect(); }

  function addHighlight(text, color, pageElement, pageNum) {
    if (!storedSelection || storedSelection.rangeCount === 0) return;
    const wRect = pageRectOf(pageElement);
    const rects = Array.from(storedSelection.getRangeAt(0).getClientRects())
      .filter(r => r.width > 0 && r.height > 0)
      .map(r => ({ left: (r.left - wRect.left) / wRect.width, top: (r.top - wRect.top) / wRect.height, width: r.width / wRect.width, height: r.height / wRect.height }));
    if (!rects.length) return;
    sendEvent({ type: "ctx", action: "highlight", page: pageNum, color, text, rects });
    window.getSelection().removeAllRanges();
  }

  function highlightMenu(e, div, pageNum) {
    const text = div.dataset.text || "";
    showCtxMenu(e.clientX, e.clientY, [
      { icon: "🔗", label: "Copy Bookmark Link", action: () => copyBookmarkLink(pageNum, div.dataset.annotId) },
      { icon: "📋", label: "Copy Text", action: () => { copyPlainText(text); showToast("Copied!"); } },
      { icon: "🔗", label: "Copy and Cite", action: () => { copyRichText(buildCitePlain(text, state.filename, pageNum), buildCiteHtml(text, state.filename, pageNum)); showToast("Copied with citation!"); } },
      "sep",
      { icon: "🗑", label: "Delete Highlight", red: true, action: () => sendEvent({ type: "ctx", action: "delete", id: div.dataset.annotId, page: pageNum }) },
    ]);
  }

  // ── bookmark areas: drag/resize gestures on Nim-rendered overlays ────────
  function overlayRect(div) {
    return { left: Math.max(0, parseFloat(div.style.left) / 100), top: Math.max(0, parseFloat(div.style.top) / 100),
      width: Math.max(0.01, parseFloat(div.style.width) / 100), height: Math.max(0.01, parseFloat(div.style.height) / 100) };
  }
  function enterResizeMode(div, pageElement) {
    div.classList.add("resize-mode");
    const lbl = document.createElement("div"); lbl.className = "bm-resize-label"; lbl.textContent = "Resize  •  dbl-click or right-click to save"; div.appendChild(lbl);
    div.addEventListener("mousedown", function onDown(e) {
      if (e.button !== 0 || e.target.classList.contains("bm-handle")) return;
      e.preventDefault();
      const sx = e.clientX, sy = e.clientY, sl = parseFloat(div.style.left), st = parseFloat(div.style.top), w = parseFloat(div.style.width), h = parseFloat(div.style.height);
      const wW = pageElement.clientWidth, wH = pageElement.clientHeight;
      const onMove = e => { const dx = (e.clientX - sx) / wW * 100, dy = (e.clientY - sy) / wH * 100; div.style.left = `${Math.max(0, Math.min(100 - w, sl + dx))}%`; div.style.top = `${Math.max(0, Math.min(100 - h, st + dy))}%`; };
      const onUp = () => { document.removeEventListener("mousemove", onMove); document.removeEventListener("mouseup", onUp); };
      document.addEventListener("mousemove", onMove); document.addEventListener("mouseup", onUp);
    });
    div.querySelectorAll(".bm-handle").forEach(handle => handle.addEventListener("mousedown", e => {
      if (e.button !== 0) return;
      e.preventDefault(); e.stopPropagation();
      const dir = handle.dataset.dir, sx = e.clientX, sy = e.clientY;
      const sl = parseFloat(div.style.left), st = parseFloat(div.style.top), sw = parseFloat(div.style.width), sh = parseFloat(div.style.height);
      const wW = pageElement.clientWidth, wH = pageElement.clientHeight, MIN = 2;
      const onMove = e => {
        const dx = (e.clientX - sx) / wW * 100, dy = (e.clientY - sy) / wH * 100;
        let l = sl, t = st, w = sw, h = sh;
        if (dir.includes("e")) w = Math.max(MIN, sw + dx);
        if (dir.includes("s")) h = Math.max(MIN, sh + dy);
        if (dir.includes("w")) { w = Math.max(MIN, sw - dx); l = sl + (sw - w); }
        if (dir.includes("n")) { h = Math.max(MIN, sh - dy); t = st + (sh - h); }
        div.style.left = `${Math.max(0, l)}%`; div.style.top = `${Math.max(0, t)}%`; div.style.width = `${w}%`; div.style.height = `${h}%`;
      };
      const onUp = () => { document.removeEventListener("mousemove", onMove); document.removeEventListener("mouseup", onUp); };
      document.addEventListener("mousemove", onMove); document.addEventListener("mouseup", onUp);
    }));
  }
  function exitResizeMode(div, pageNum) {
    div.classList.remove("resize-mode");
    div.querySelectorAll(".bm-resize-label").forEach(l => l.remove());
    sendEvent({ type: "ctx", action: "bookmark-rect", id: div.dataset.annotId, page: pageNum, rect: overlayRect(div) });
  }
  function bookmarkMenu(e, div, pageElement, pageNum) {
    showCtxMenu(e.clientX, e.clientY, [
      { icon: "🔗", label: "Copy Bookmark Link", action: () => copyBookmarkLink(pageNum, div.dataset.annotId) },
      { icon: "📷", label: "Copy Image", action: () => captureBookmarkArea(div, pageElement, pageNum) },
      "sep",
      { icon: "🗑", label: "Delete Area", red: true, action: () => sendEvent({ type: "ctx", action: "delete", id: div.dataset.annotId, page: pageNum }) },
    ]);
  }

  function createTempBookmark(pageNum) {
    const pageElement = pageEl(pageNum); if (!pageElement) return;
    const wRect = pageRectOf(pageElement);
    const div = document.createElement("div"); div.className = "bm-temp";
    if (lastContextMenuEvent) {
      const lx = lastContextMenuEvent.clientX - wRect.left - 75, ly = lastContextMenuEvent.clientY - wRect.top - 50;
      div.style.left = `${Math.max(0, Math.min(wRect.width - 150, lx))}px`; div.style.top = `${Math.max(0, Math.min(wRect.height - 100, ly))}px`;
    } else { div.style.left = "10px"; div.style.top = "10px"; }
    const hint = document.createElement("div"); hint.className = "bm-temp-hint"; hint.textContent = "Drag to place  •  Right-click to discard"; div.appendChild(hint);
    pageElement.appendChild(div);
    const commit = () => {
      sendEvent({ type: "ctx", action: "bookmark", page: pageNum, rect: { left: div.offsetLeft / pageElement.clientWidth, top: div.offsetTop / pageElement.clientHeight, width: div.offsetWidth / pageElement.clientWidth, height: div.offsetHeight / pageElement.clientHeight } });
      div.remove();
    };
    let dragging = false, hasDragged = false, startX, startY, startL, startT;
    div.addEventListener("mousedown", e => { if (e.button !== 0) return; dragging = true; hasDragged = false; startX = e.clientX; startY = e.clientY; startL = div.offsetLeft; startT = div.offsetTop; e.preventDefault(); e.stopPropagation(); });
    document.addEventListener("mousemove", e => { if (!dragging) return; hasDragged = true; div.style.left = `${Math.max(0, Math.min(pageElement.clientWidth - div.offsetWidth, startL + e.clientX - startX))}px`; div.style.top = `${Math.max(0, Math.min(pageElement.clientHeight - div.offsetHeight, startT + e.clientY - startY))}px`; });
    document.addEventListener("mouseup", function onUp() { if (!dragging) return; dragging = false; document.removeEventListener("mouseup", onUp); if (hasDragged) commit(); });
    div.addEventListener("contextmenu", e => { e.preventDefault(); e.stopPropagation(); if (dragging) return; showCtxMenu(e.clientX, e.clientY, [{ icon: "💾", label: "Save Bookmark", action: commit }, "sep", { icon: "🗑", label: "Discard", red: true, action: () => div.remove() }]); });
  }

  async function captureBookmarkArea(div, pageElement, pageNum) {
    if (typeof html2canvas === "undefined") { showToast("html2canvas not loaded"); return; }
    showToast("Capturing…", 0);
    const rect = div.getBoundingClientRect(), pRect = pageElement.getBoundingClientRect();
    div.style.display = "none";
    try {
      await new Promise(r => setTimeout(r, 80));
      const canvas = await html2canvas(pageElement, { x: rect.left - pRect.left, y: rect.top - pRect.top, width: rect.width, height: rect.height, scale: window.devicePixelRatio * 2, logging: false, useCORS: true, ignoreElements: el => el === div || el.id === "ctx-menu" || el.classList?.contains("bm-overlay") });
      const b64 = canvas.toDataURL("image/png", 1.0);
      const html = `<div class="pdf-image-container" data-pdf-file-id="${escHtml(state.fileId)}" data-pdf-annot-id="${escHtml(div.dataset.annotId)}" data-pdf-title="${escHtml(state.filename)}" data-pdf-page="${pageNum}" data-original-width="${canvas.width}" data-original-height="${canvas.height}"><img src="${b64}"></div>`;
      copyRichText(`${shortName(state.filename)}, p.${pageNum}`, html);
      showToast("Image and source link copied!",2500);
    } catch (err) { showToast("Capture failed", 2500); console.error(err); }
    finally { div.style.display = ""; }
  }

  // ── shell bindings (once Nim has built the DOM) ──────────────────────────
  let bound = false;
  function bindShell() {
    if (bound) return; bound = true;
    const v = viewerEl();

    async function openLocal(file) {
      if (location.pathname.startsWith("/recto/")) {
        await flush();
        let name = file.name;
        for (;;) {
          const response = await fetch("/api/upload?path="+encodeURIComponent(name),{method:"POST",headers:{"Content-Type":"application/pdf"},body:file});
          if (response.status === 409) {name=prompt("A file already has this name. Choose a new name:",name);if(!name)return;continue;}
          const result=await response.json();if(!response.ok)throw Error(result.error||"Upload failed");
          location.hash="#fileId="+encodeURIComponent(result.fileId)+"&page=1";
          parentMsg({type:"VAULT_FILES_CHANGED"});return;
        }
      }
      await openSource({data:await file.arrayBuffer()},file.name);
    }
    $("file-input").addEventListener("change", async e => {
      const file=e.target.files?.[0];if(!file)return;
      try{await openLocal(file);}catch(error){showToast(error.message,0);}finally{e.target.value="";}
    });
    ["dragenter","dragover"].forEach(ev=>v.addEventListener(ev,e=>e.preventDefault()));
    v.addEventListener("drop",async e=>{e.preventDefault();const file=e.dataTransfer.files?.[0];if(!file||!file.name.toLowerCase().endsWith(".pdf"))return;try{await openLocal(file);}catch(error){showToast(error.message,0);}});

    // Scroll and size, rAF-throttled: Nim recomputes the current page and
    // the render window from these.
    let scrollRaf = null;
    v.addEventListener("scroll", () => { hideCtxMenu(); if (scrollRaf) return; scrollRaf = requestAnimationFrame(() => { scrollRaf = null; viewportEvent(); }); }, { passive: true });
    new ResizeObserver(() => viewportEvent()).observe(v);
    window.addEventListener("resize", () => viewportEvent());

    // Ctrl/Cmd + wheel zoom
    v.addEventListener("wheel", e => {
      if (!(e.ctrlKey || e.metaKey)) return;
      e.preventDefault();
      const r = v.getBoundingClientRect();
      sendEvent({ type: "wheel-zoom", factor: Math.exp(-e.deltaY * 0.0015), x: e.clientX - r.left, y: e.clientY - r.top });
    }, { passive: false });

    // Touch: pinch to zoom, one finger pans.
    let pinch = null, touch1Pan = null;
    const pinchDist = (a, b) => Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
    v.addEventListener("touchstart", e => {
      if (ink.stroke) return;
      if (e.touches.length === 2) { touch1Pan = null; pinch = { startDist: pinchDist(e.touches[0], e.touches[1]) }; sendEvent({ type: "pinch-start" }); e.preventDefault(); }
      else if (e.touches.length === 1 && !pinch) touch1Pan = { startX: e.touches[0].clientX + v.scrollLeft, startY: e.touches[0].clientY + v.scrollTop };
    }, { passive: false });
    v.addEventListener("touchmove", e => {
      if (ink.stroke) return;
      if (pinch && e.touches.length >= 2) {
        e.preventDefault();
        const d = pinchDist(e.touches[0], e.touches[1]); if (d < 1) return;
        const r = v.getBoundingClientRect();
        sendEvent({ type: "pinch", ratio: d / pinch.startDist, x: (e.touches[0].clientX + e.touches[1].clientX) / 2 - r.left, y: (e.touches[0].clientY + e.touches[1].clientY) / 2 - r.top });
      } else if (touch1Pan && e.touches.length === 1 && !pinch) {
        v.scrollLeft = touch1Pan.startX - e.touches[0].clientX; v.scrollTop = touch1Pan.startY - e.touches[0].clientY;
      }
    }, { passive: false });
    const endPinch = e => { if (!e.touches || e.touches.length < 2) pinch = null; if (!e.touches || e.touches.length === 0) touch1Pan = null; };
    v.addEventListener("touchend", endPinch, { passive: true }); v.addEventListener("touchcancel", endPinch, { passive: true });
    for (const g of ["gesturestart", "gesturechange", "gestureend"]) v.addEventListener(g, e => e.preventDefault());

    // Keyboard shortcuts; typing in a field never reaches the viewer.
    document.addEventListener("keydown", e => {
      if (["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName)) return;
      const mod = e.ctrlKey || e.metaKey, k = e.key.toLowerCase();
      const handled = (mod && ["z", "y", "+", "=", "-", "0"].includes(k)) || ["ArrowRight", "ArrowLeft", "PageDown", "PageUp", "Home", "End"].includes(e.key);
      if (!handled) return;
      if (mod) e.preventDefault();
      sendEvent({ type: "key", key: e.key, ctrl: mod, shift: e.shiftKey });
    });

    // Mouse drag-to-pan when not annotating over a page or selecting text.
    let isPanning = false, panStart = { x: 0, y: 0 };
    v.addEventListener("mousedown", e => {
      if (e.button !== 0) return;
      if (state.ink.active && e.target.closest(".page")) return;
      if (e.target.closest(".textLayer") || e.target.closest(".bm-overlay") || e.target.closest(".bm-temp")) return;
      isPanning = true; panStart = { x: e.clientX + v.scrollLeft, y: e.clientY + v.scrollTop }; v.classList.add("panning"); e.preventDefault();
    });
    document.addEventListener("mousemove", e => { if (!isPanning) return; v.scrollLeft = panStart.x - e.clientX; v.scrollTop = panStart.y - e.clientY; });
    const endPan = () => { if (isPanning) { isPanning = false; v.classList.remove("panning"); } };
    document.addEventListener("mouseup", endPan); document.addEventListener("mouseleave", endPan);

    // Outline panel: row clicks and click-outside close.
    $("outline-body").addEventListener("click", e => {
      const part = e.target.closest("[data-part]"); if (!part) return;
      e.stopPropagation();
      sendEvent({ type: "outline-click", index: +part.dataset.index, part: part.dataset.part });
    });
    v.addEventListener("click", () => { if ($("outline-panel").classList.contains("open")) sendEvent({ type: "close-outline" }); });
    $("annot-colors").addEventListener("click", e => { const s = e.target.closest("[data-color]"); if (s) sendEvent({ type: "swatch", color: s.dataset.color }); });

    // Overlays rendered by Nim: delegated gestures.
    v.addEventListener("contextmenu", e => {
      if (ink.stroke) { e.preventDefault(); return; }
      const hl = e.target.closest(".annot-hl");
      if (hl) { e.preventDefault(); e.stopPropagation(); highlightMenu(e, hl, +hl.closest(".page").dataset.pageNum); return; }
      const bm = e.target.closest(".bm-overlay");
      if (bm) {
        e.preventDefault(); e.stopPropagation();
        const pageElement = bm.closest(".page"), pageNum = +pageElement.dataset.pageNum;
        if (bm.classList.contains("resize-mode")) exitResizeMode(bm, pageNum); else bookmarkMenu(e, bm, pageElement, pageNum);
        return;
      }
      if (e.target.closest(".bm-temp")) return;
      const pageElement = e.target.closest(".page"); if (!pageElement) return;
      e.preventDefault();
      lastContextMenuEvent = { clientX: e.clientX, clientY: e.clientY };
      storedSelection = window.getSelection();
      const selectedText = storedSelection?.toString().trim() || "";
      const pageNum = +pageElement.dataset.pageNum;
      const items = [];
      if (selectedText) {
        items.push({ icon: "📋", label: "Copy", action: () => { copyPlainText(selectedText); showToast("Copied!"); } });
        items.push({ icon: "✍", label: "Highlight", submenu: [
          { icon: "🟡", label: "Yellow", action: () => addHighlight(selectedText, "rgba(255,220,0,0.45)", pageElement, pageNum) },
          { icon: "🩷", label: "Pink", action: () => addHighlight(selectedText, "rgba(255,105,180,0.45)", pageElement, pageNum) },
          { icon: "🟣", label: "Purple", action: () => addHighlight(selectedText, "rgba(160,32,240,0.45)", pageElement, pageNum) },
          { icon: "🟢", label: "Green", action: () => addHighlight(selectedText, "rgba(80,200,100,0.45)", pageElement, pageNum) },
        ] });
        items.push({ icon: "🔗", label: "Copy and Cite", action: () => { copyRichText(buildCitePlain(selectedText, state.filename, pageNum), buildCiteHtml(selectedText, state.filename, pageNum)); showToast("Copied with citation!"); } });
        items.push("sep");
      }
      items.push({ icon: "🔖", label: "Add Bookmark Area", action: () => createTempBookmark(pageNum) });
      if (selectedText) { items.push("sep"); items.push({ icon: "🔍", label: "Search Google", action: () => window.open(`https://www.google.com/search?q=${encodeURIComponent(selectedText)}`, "_blank") }); }
      showCtxMenu(e.clientX, e.clientY, items);
    });
    v.addEventListener("dblclick", e => {
      const bm = e.target.closest(".bm-overlay"); if (!bm) return;
      e.preventDefault(); e.stopPropagation();
      const pageElement = bm.closest(".page"), pageNum = +pageElement.dataset.pageNum;
      if (bm.classList.contains("resize-mode")) exitResizeMode(bm, pageNum);
      else {
        document.querySelectorAll(".bm-overlay.resize-mode").forEach(other => { if (other !== bm) exitResizeMode(other, +other.closest(".page").dataset.pageNum); });
        enterResizeMode(bm, pageElement);
      }
    });
    document.addEventListener("click", hideCtxMenu);
    document.addEventListener("scroll", hideCtxMenu, true);

    bindInk(v);
    // Saved tool preferences, then the first viewport.
    try {
      const p = JSON.parse(localStorage.getItem("recto_ink_prefs") || "null");
      if (p) sendEvent({ type: "prefs", pen: p.pen, highlighter: p.highlighter, eraser: p.eraser, penOnly: p.penOnly });
    } catch {}
    viewportEvent();
    bindServerProtocol();
    setTimeout(handleHashOpen, 0);
  }

  // ── ink pointer capture ──────────────────────────────────────────────────
  const ink = { stroke: null };
  window.__inkDrawing = false;
  function bindInk(v) {
    const eraserCursor = $("eraser-cursor");
    const toPage = (s, ev) => [
      Math.max(0, Math.min(s.baseW, (ev.clientX - s.rect.left) / s.rect.width * s.baseW)),
      Math.max(0, Math.min(s.baseH, (ev.clientY - s.rect.top) / s.rect.height * s.baseH)),
      (!ev.pressure || ev.pointerType === "mouse") ? 0.5 : ev.pressure,
    ];
    const finish = commit => {
      const s = ink.stroke; if (!s) return;
      ink.stroke = null; window.__inkDrawing = false;
      try { v.releasePointerCapture(s.pointerId); } catch {}
      sendEvent({ type: "ink", phase: commit ? "up" : "cancel", page: s.page });
    };
    v.addEventListener("pointerdown", e => {
      if (!state.ink.active) return;
      if (ink.stroke) {
        // Second touch during a finger stroke is a pinch: cancel. A touch
        // during a pen stroke is a palm: ignore.
        if (e.pointerType === "touch" && ink.stroke.ptype === "touch") finish(false);
        return;
      }
      if (e.pointerType === "touch" && state.ink.penOnly) return;
      if (e.pointerType === "mouse" && e.button !== 0) return;
      const pageElement = e.target.closest(".page"); if (!pageElement) return;
      const page = +pageElement.dataset.pageNum, p = state.pages[page - 1]; if (!p) return;
      e.preventDefault(); hideCtxMenu();
      window.__inkDrawing = true;
      try { v.setPointerCapture(e.pointerId); } catch {}
      ink.stroke = { pointerId: e.pointerId, ptype: e.pointerType, page, rect: pageElement.getBoundingClientRect(), baseW: p.baseW, baseH: p.baseH };
      sendEvent({ type: "ink", phase: "down", page, ptype: e.pointerType, pts: [toPage(ink.stroke, e)] });
    });
    v.addEventListener("pointermove", e => {
      if (state.ink.active && state.ink.tool === "eraser") {
        const overPage = ink.stroke ? true : !!e.target.closest?.(".page");
        if (overPage) {
          const d = state.ink.eraserSize * 2 * state.scale;
          eraserCursor.style.display = "block"; eraserCursor.style.width = eraserCursor.style.height = d + "px";
          eraserCursor.style.left = e.clientX + "px"; eraserCursor.style.top = e.clientY + "px";
        } else eraserCursor.style.display = "none";
      }
      const s = ink.stroke;
      if (!s || e.pointerId !== s.pointerId) return;
      e.preventDefault();
      // Coalesced samples when the browser has them; the event itself
      // otherwise (synthetic and some older pointer events report none).
      let evts = e.getCoalescedEvents ? e.getCoalescedEvents() : [];
      if (!evts.length) evts = [e];
      sendEvent({ type: "ink", phase: "move", page: s.page, pts: evts.map(ev => toPage(s, ev)) });
    });
    v.addEventListener("pointerup", e => { if (ink.stroke && e.pointerId === ink.stroke.pointerId) finish(true); });
    v.addEventListener("pointercancel", e => { if (ink.stroke && e.pointerId === ink.stroke.pointerId) finish(false); });
    v.addEventListener("pointerleave", () => { eraserCursor.style.display = "none"; });
  }

  // ── server protocol: hash opens, postMessage, tags ───────────────────────
  function parentMsg(msg) { try { if (window.parent && window.parent !== window) window.parent.postMessage(msg, "*"); } catch {} }

  async function openFromServer(path, page) {
    if (location.pathname.startsWith("/recto/")) {
      const response = await fetch("/api/file-id?path="+encodeURIComponent(path));
      if (!response.ok) { showToast("The linked PDF is missing from this vault",0); return; }
      const identity = await response.json();
      location.hash = "#fileId="+encodeURIComponent(identity.fileId)+"&page="+(Number(page)||1);
      return;
    }
    const base = resolveBase();
    if (!base) { console.warn("No server base URL"); return; }
    const filename = path.split("/").pop() || path;
    parentMsg({ type: "show-file-dl", filename, sub: "Loading PDF…", path });
    try {
      const buf = await new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", `${base}/get_file_content?filename=${encodeURIComponent(path)}&t=${Date.now()}`, true);
        xhr.responseType = "arraybuffer";
        xhr.onprogress = e => parentMsg(e.lengthComputable ? { type: "update-file-dl", pct: Math.round(e.loaded / e.total * 100), loaded: e.loaded, total: e.total } : { type: "update-file-dl", pct: -1, loaded: e.loaded, total: 0 });
        xhr.onload = () => {
          if (xhr.status >= 200 && xhr.status < 300) { parentMsg({ type: "update-file-dl", pct: 100, loaded: xhr.response.byteLength, total: xhr.response.byteLength }); setTimeout(() => parentMsg({ type: "hide-file-dl" }), 350); resolve(xhr.response); }
          else { parentMsg({ type: "hide-file-dl" }); reject(new Error("HTTP " + xhr.status)); }
        };
        xhr.onerror = () => { parentMsg({ type: "hide-file-dl" }); reject(new Error("Network error")); };
        xhr.send();
      });
      await openSource({ data: buf }, path, page ? parseInt(page) : null);
    } catch (err) { parentMsg({ type: "hide-file-dl" }); console.error("openFromServer failed:", err); }
  }

  function parseFetchHash(hash) {
    const raw = (hash || "").replace(/^#/, ""); if (!raw) return null;
    const p = new URLSearchParams(raw); const path = p.get("fetchpdf"); if (!path) return null;
    const pg = p.get("page");
    return { path, page: pg && /^\d+$/.test(pg) ? parseInt(pg) : null };
  }
  async function handleHashOpen() {
    try {
      await flush();
      const params = new URLSearchParams(location.hash.slice(1)), id = params.get("fileId");
      if (!id) { const t = parseFetchHash(location.hash); if(t?.path) await openFromServer(t.path,t.page); return; }
      const response = await fetch("/api/resolve-id/" + encodeURIComponent(id));
      if (!response.ok) throw Error("The linked PDF is missing from this vault");
      const record = await response.json();
      const page = Math.max(1, Number(params.get("page")) || 1);
      const pdf = await fetch("/api/pdf/" + encodeURIComponent(id));
      if (!pdf.ok) throw Error("Could not open PDF");
      await openSource({data: await pdf.arrayBuffer()}, record.path, page, id);
      const annotId = params.get("annotId");
      if (annotId) {
        let attempts = 0;
        const focus = () => { const overlay = Array.from(document.querySelectorAll("[data-annot-id]")).find(el => el.dataset.annotId === annotId);
          if (overlay) { overlay.scrollIntoView({block:"center"}); overlay.animate([{outline:"3px solid #9b1b30"},{outline:"3px solid transparent"}],{duration:1800}); }
          else if (++attempts < 30) setTimeout(focus,100);
        }; focus();
      }
    } catch (error) { showToast(error.message,0); }
  }

  let pdfTags = [];
  function bindServerProtocol() {
    window.addEventListener("hashchange", handleHashOpen);
    window.addEventListener("message", async event => {
      if (event.origin !== location.origin || event.source !== window.parent) return;
      const msg = event.data; if (!msg || typeof msg !== "object") return;
      const page = Number.isFinite(Number(msg.page)) && Number(msg.page) > 0 ? Number(msg.page) : null;
      if (msg.type === "OPEN_PDF_BUFFER") {
        if (!msg.buffer || !(msg.buffer instanceof ArrayBuffer)) return;
        await openSource({ data: msg.buffer }, msg.filename || "", page);
      } else if (msg.type === "OPEN_PDF") {
        const path = String(msg.path || msg.pdfPath || "").trim(); if (!path) return;
        try { const nextHash = "#fetchpdf=" + encodeURIComponent(path) + (page ? "&page=" + page : ""); if (window.location.hash !== nextHash) window.location.hash = nextHash; } catch {}
        openFromServer(path, page);
      } else if (msg.type === "updateFilename" && msg.filename) { state.filename = msg.filename; window.currentFilename = msg.filename; }
    });
    document.addEventListener("click", ev => {
      const a = ev.target?.closest?.("a[href]"); if (!a) return;
      const href = a.getAttribute("href") || ""; if (!href.includes("#fetchpdf=")) return;
      ev.preventDefault();
      try { if (window.parent !== window) window.parent.postMessage({ type: "updateUrl", url: href }, "*"); } catch {}
    }, true);
    window._pdfTagEditor = {
      async load() { if (!state.filename) return; const base = resolveBase(); if (!base) return; try { const r = await fetch(`${base}/api/pdf_tags?path=${encodeURIComponent(state.filename)}`); if (r.ok) { const d = await r.json(); pdfTags = Array.isArray(d.tags) ? d.tags : []; } } catch {} },
      async save() { if (!state.filename) return; const base = resolveBase(); if (!base) return; try { const r = await fetch(`${base}/api/pdf_tags`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ path: state.filename, tags: pdfTags }) }); if (r.ok) { const d = await r.json(); pdfTags = d.tags || pdfTags; try { window.parent.postMessage({ type: "PDF_TAGS_UPDATED", path: state.filename }, "*"); } catch {} } } catch (e) { console.error("Tag save error:", e); } },
      getTags: () => pdfTags,
    };
  }

  return {
    envImports,
    flush,
    navigate: handleHashOpen,
    setMemory(m) { memory = m; },
    openSource,
    sendEvent,
    state,
  };
}
