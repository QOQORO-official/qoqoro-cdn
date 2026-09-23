/**
 * stylus-host.js — the browser side of nim-src/stylus_host.nim.
 *
 * The stock BindWeb runtime speaks mouse events without pressure, one
 * pointer at a time, and events no larger than 4 KB. A stylus app needs
 * pressure and pointer type, two fingers, and strings the size of a picture.
 * These imports fill that gap. They are host plumbing only — every decision
 * about what a sample means is made in Nim.
 *
 * Wired in by bindweb-runtime.js: createStylusHost(ctx) returns extra env
 * imports; ctx exposes the runner's memory (a getter, since it is set on
 * connect), its element/context/image tables and its update trigger.
 *
 * Two-call strings: a producing call parks text in `hostText`; Nim asks
 * stylus_host_text(null, 0) for its size and stylus_host_text(ptr, size)
 * for the bytes. The inbox works the same way, one message per pair of
 * calls, as "tag\tpayload".
 */
function createStylusHost(ctx) {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  const str = (ptr, len) => decoder.decode(new Uint8Array(ctx.memory.buffer, ptr, len));

  // ── strings out ──────────────────────────────────────────────────────
  let hostText = null;              // Uint8Array, consumed by stylus_host_text
  const inbox = [];                 // encoded messages, oldest first
  const park = (text) => { hostText = encoder.encode(String(text ?? '')); };
  const post = (...parts) => { inbox.push(encoder.encode(parts.join('\t'))); ctx.trigger(); };
  const twoCall = (bytes, ptr, cap, consume) => {
    if (!bytes) return 0;
    if (!ptr) return bytes.length;
    if (cap < bytes.length) return 0;
    new Uint8Array(ctx.memory.buffer, ptr, bytes.length).set(bytes);
    consume();
    return bytes.length;
  };

  // ── pointer samples ──────────────────────────────────────────────────
  // Eight float lanes per sample: phase, id, type, x, y, pressure, button,
  // modifiers. Phase: 0 down, 1 move, 2 up, 3 cancel, 4 wheel, 5 contextmenu.
  const LANES = 8, MAX_QUEUE = 4096;
  let queue = new Float32Array(LANES * 256), queued = 0;
  const typeCode = (t) => t === 'pen' ? 1 : t === 'touch' ? 2 : 0;
  function push(phase, e, x, y, pressure, button) {
    if (queued >= MAX_QUEUE) { queue.copyWithin(0, LANES); queued--; }
    if ((queued + 1) * LANES > queue.length) { const g = new Float32Array(queue.length * 2); g.set(queue); queue = g; }
    const b = queued * LANES;
    queue[b] = phase; queue[b + 1] = e.pointerId ?? 0; queue[b + 2] = typeCode(e.pointerType);
    queue[b + 3] = x; queue[b + 4] = y; queue[b + 5] = pressure; queue[b + 6] = button;
    queue[b + 7] = (e.ctrlKey ? 1 : 0) | (e.shiftKey ? 2 : 0);
    queued++;
  }
  function attach(canvas) {
    const local = (e) => { const r = canvas.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    canvas.addEventListener('pointerdown', (e) => {
      if (e.pointerType === 'mouse' && e.button !== 0 && e.button !== 2) return;
      if (e.button === 2) return; // contextmenu carries the right button
      e.preventDefault();
      try { canvas.setPointerCapture(e.pointerId); } catch (_) {}
      const [x, y] = local(e);
      push(0, e, x, y, e.pressure, e.button);
      ctx.trigger();
    });
    canvas.addEventListener('pointermove', (e) => {
      // Coalesced events carry every sample the pen produced since the last
      // frame; the dispatched event is only the newest.
      const list = (typeof e.getCoalescedEvents === 'function' && e.getCoalescedEvents().length)
        ? e.getCoalescedEvents() : [e];
      const r = canvas.getBoundingClientRect();
      for (const c of list) push(1, e, c.clientX - r.left, c.clientY - r.top, c.pressure, -1);
    });
    const finish = (phase) => (e) => {
      const [x, y] = local(e);
      push(phase, e, x, y, e.pressure, e.button);
      try { if (canvas.hasPointerCapture(e.pointerId)) canvas.releasePointerCapture(e.pointerId); } catch (_) {}
      ctx.trigger();
    };
    canvas.addEventListener('pointerup', finish(2));
    canvas.addEventListener('pointercancel', finish(3));
    canvas.addEventListener('wheel', (e) => {
      if (!e.ctrlKey) return;
      e.preventDefault();
      const [x, y] = local(e);
      push(4, e, x, y, e.deltaY, 0);
      ctx.trigger();
    }, { passive: false });
    canvas.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      const [x, y] = local(e);
      push(5, e, x, y, 0, 2);
      ctx.trigger();
    });
    canvas.addEventListener('dragstart', (e) => e.preventDefault());
  }

  // ── pictures ─────────────────────────────────────────────────────────
  // Same preparation as the JavaScript app: scale to at most 1200px and
  // re-encode as JPEG so a note stays a reasonable size.
  function importBlob(blob, x, y) {
    const reader = new FileReader();
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        const MAX = 1200; let w = img.width, h = img.height;
        if (w > MAX || h > MAX) { const r = Math.min(MAX / w, MAX / h); w *= r; h *= r; }
        const c = document.createElement('canvas'); c.width = Math.max(1, Math.round(w)); c.height = Math.max(1, Math.round(h));
        c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
        post('image', c.toDataURL('image/jpeg', 0.85), x == null ? '' : String(x), y == null ? '' : String(y));
      };
      img.src = String(reader.result || '');
    };
    reader.readAsDataURL(blob);
  }
  function pickFile(accept, onFile) {
    const input = document.createElement('input');
    input.type = 'file'; input.accept = accept; input.hidden = true;
    document.body.appendChild(input);
    input.onchange = () => { const f = input.files && input.files[0]; input.remove(); if (f) onFile(f); };
    input.click();
  }

  // ── fetch, reported through the inbox so a note of any size gets back ─
  let fetchId = 0;
  function request(method, url, body) {
    const id = ++fetchId;
    const init = { method, cache: 'no-store' };
    if (method !== 'GET') { init.body = body; init.headers = { 'Content-Type': 'application/json' }; }
    fetch(url, init)
      .then((r) => r.text().then((t) => post('fetch', id, r.ok ? 1 : 0, r.status, t)))
      .catch((e) => post('fetch', id, 0, 0, String((e && e.message) || e)));
    return id;
  }

  // ── links: the embedding page opens them, or we navigate ─────────────
  function openLink(path, fileType) {
    const embedded = (() => { try { return window.parent && window.parent !== window; } catch (_) { return false; } })();
    const href = (() => {
      try {
        if (embedded) {
          const p = new URL(window.parent.location.href);
          if (/main page\.html$/i.test(decodeURIComponent(p.pathname))) { p.hash = 'fetchnote=' + encodeURIComponent(path); return p.toString(); }
        }
      } catch (_) {}
      try { const u = new URL('../main%20page.html', window.location.href); u.hash = 'fetchnote=' + encodeURIComponent(path); return u.toString(); } catch (_) {}
      return 'main%20page.html#fetchnote=' + encodeURIComponent(path);
    })();
    let postedToHost = false;
    try {
      if (embedded) {
        let hostPage = false;
        try { hostPage = /main page\.html$/i.test(decodeURIComponent(new URL(window.parent.location.href).pathname)); } catch (_) {}
        window.parent.postMessage({ type: 'whiteboard-open-link', path, fileType, href }, '*');
        postedToHost = hostPage;
      }
    } catch (_) {}
    if (embedded) return;
    setTimeout(() => { if (!postedToHost) window.location.href = href; }, 120);
  }

  // The embedding page can push a note in, or ask us to fetch one.
  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.type !== 'whiteboard-open-note') return;
    const path = String(msg.path || '').replace(/\\/g, '/').trim();
    if (!path) return;
    if (msg.doc !== undefined) post('note', path, typeof msg.doc === 'string' ? msg.doc : JSON.stringify(msg.doc));
    else post('notepath', path);
  });

  const stage = () => document.getElementById('canvas-container');
  const rect = () => { const s = stage(); return s ? s.getBoundingClientRect() : { left: 0, top: 0, width: innerWidth, height: innerHeight }; };
  const canvasOf = (h) => ctx.elements[h];

  return {
    stylus_attach: (h) => { const c = canvasOf(h); if (c) attach(c); },
    stylus_pointer_poll: (ptr, cap) => {
      const n = Math.min(queued, cap);
      if (n > 0) new Float32Array(ctx.memory.buffer, ptr, n * LANES).set(queue.subarray(0, n * LANES));
      if (n < queued) queue.copyWithin(0, n * LANES, queued * LANES);
      queued -= n;
      return n;
    },
    stylus_dpr: () => window.devicePixelRatio || 1,
    stylus_stage_width: () => rect().width,
    stylus_stage_height: () => rect().height,
    stylus_stage_left: () => rect().left,
    stylus_stage_top: () => rect().top,
    stylus_canvas_set_line_dash: (h, a, b) => { const c = ctx.contexts[h]; if (c) c.setLineDash(a === 0 && b === 0 ? [] : [a, b]); },
    stylus_canvas_draw_canvas: (h, src, dx, dy, dw, dh) => {
      const c = ctx.contexts[h], s = canvasOf(src);
      if (!c || !s) return;
      if (dw > 0 && dh > 0) c.drawImage(s, dx, dy, dw, dh); else c.drawImage(s, dx, dy);
    },
    stylus_canvas_to_data_url: (h, jpeg, quality) => {
      const c = canvasOf(h);
      try { park(c ? c.toDataURL(jpeg ? 'image/jpeg' : 'image/png', quality) : ''); } catch (_) { park(''); }
    },
    stylus_element_style: (h, ptr, len) => { const el = canvasOf(h); if (el) el.style.cssText = str(ptr, len); },
    stylus_host_text: (ptr, cap) => twoCall(hostText, ptr, cap, () => { hostText = null; }),
    stylus_inbox_poll: (ptr, cap) => twoCall(inbox[0], ptr, cap, () => { inbox.shift(); }),
    stylus_image_ready: (h) => { const i = ctx.images[h]; return (i && i.complete && i.naturalWidth > 0) ? 1 : 0; },
    stylus_image_width: (h) => { const i = ctx.images[h]; return i ? i.naturalWidth : 0; },
    stylus_image_height: (h) => { const i = ctx.images[h]; return i ? i.naturalHeight : 0; },
    stylus_image_import: () => pickFile('image/*', (f) => importBlob(f)),
    stylus_image_paste: async (x, y) => {
      try {
        const items = await navigator.clipboard.read();
        for (const item of items) {
          const type = item.types.find((t) => t.startsWith('image/'));
          if (type) { importBlob(await item.getType(type), x, y); return; }
        }
        alert('No image found in clipboard.');
      } catch (_) { alert('Clipboard access denied. Use the Import button instead.'); }
    },
    stylus_note_open: () => pickFile('.qoscribe,.json,application/json', (f) => {
      const r = new FileReader(); r.onload = () => post('file', String(r.result || '')); r.readAsText(f);
    }),
    stylus_download: (np, nl, dp, dl, mp, ml) => {
      const name = str(np, nl), data = str(dp, dl), mime = str(mp, ml);
      const a = document.createElement('a');
      let url = data, revoke = false;
      if (mime !== 'url') { url = URL.createObjectURL(new Blob([data], { type: mime })); revoke = true; }
      a.href = url; a.download = name; a.click();
      if (revoke) setTimeout(() => URL.revokeObjectURL(url), 1000);
    },
    stylus_storage_get: (kp, kl, ptr, cap) => {
      let v = null; try { v = localStorage.getItem(str(kp, kl)); } catch (_) {}
      if (v == null) return 0;
      return twoCall(encoder.encode(v), ptr, cap, () => {});
    },
    stylus_prompt: (mp, ml, dp, dl) => {
      const answer = window.prompt(str(mp, ml), str(dp, dl));
      if (answer == null) return -1;
      park(answer); return hostText.length;
    },
    stylus_confirm: (mp, ml) => window.confirm(str(mp, ml)) ? 1 : 0,
    stylus_alert: (mp, ml) => { window.alert(str(mp, ml)); },
    stylus_open_link: (pp, pl, tp, tl) => openLink(str(pp, pl), str(tp, tl)),
    stylus_post_message: (ptr, len) => {
      try { if (window.parent && window.parent !== window) window.parent.postMessage(JSON.parse(str(ptr, len)), '*'); } catch (_) {}
    },
    stylus_fetch: (mp, ml, up, ul, bp, bl) => request(str(mp, ml), str(up, ul), str(bp, bl)),
  };
}
