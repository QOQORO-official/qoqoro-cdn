/**
 * qoqoro.js — embed QOQORO in any HTML page with one script tag.
 *
 *   <script src="https://cdn.example.com/qoqoro/qoqoro.js"></script>
 *   <div id="notes" style="height:100vh"></div>
 *   <script>
 *     // just the word processor — no server, Save downloads a .qnote
 *     QOQORO.mount('#notes', { mode: 'editor' });
 *
 *     // the whole app — file list, login/admin, whiteboard, PDF viewer —
 *     // against a QNote Vault server (docs/API.md)
 *     QOQORO.mount('#notes', { mode: 'workspace', server: 'https://notes.example.com' });
 *   </script>
 *
 * The package folder (this file, qnote/, stylus/, recto/, index.html …) can
 * live on any static host or CDN; every path inside it is relative, so it
 * works under any prefix. The pages are not loaded as iframe URLs but
 * fetched as text and mounted with srcdoc, with a <base> pointing back at
 * the package — so CDNs that refuse to render HTML (jsDelivr, unpkg) work
 * too. The server is a separate URL — the Flask edition with CORS enabled,
 * or the same origin when the server also hosts the package.
 *
 * mount() returns a handle:
 *   editor mode     ready (Promise), load(xml), save() → Promise<xml>, destroy()
 *   workspace mode  ready (Promise), destroy()
 *
 * Editor options:
 *   document   initial QNote XML, or a URL to fetch it from
 *   onSave     called with the XML when the user presses Save or Ctrl+S;
 *              without it, Save downloads a .qnote as the stock editor does
 *   filename   name for that download (default document.qnote)
 *   server     a QNote Vault server the editor's Open/Save should use; the
 *              user can also set or change it from the Misc tab (🔌 Server)
 * Both modes:  height (CSS, default 100% of the target), className
 */
(function () {
  'use strict';
  const script = document.currentScript;
  const BASE = script && script.src ? new URL('.', script.src).href : new URL('.', location.href).href;
  const ORIGIN = new URL(BASE).origin;
  const EMPTY = '<?xml version="1.0"?><qnote v="1"><doc><qotext></qotext></doc></qnote>';
  const pages = new Map();

  /**
   * A page of the package as an HTML string ready for iframe.srcdoc: a
   * <base> so its relative assets load from the package, its own CSP widened
   * to allow that origin (the editor ships a strict one), and any script the
   * mode needs injected first. Inline scripts are left byte-for-byte, so the
   * CSP's hashes for them still match.
   */
  async function pageDocument(relPath, inject = '') {
    const url = BASE + relPath;
    if (!pages.has(url)) pages.set(url, fetch(url, {mode: 'cors', cache: 'default'}).then((res) => {
      if (!res.ok) throw new Error('QOQORO: could not load ' + url + ' (' + res.status + ')');
      return res.text();
    }));
    const dir = new URL('.', url).href;
    let html = await pages.get(url);
    html = html.replace(/<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]*)"\s*\/?>/i, (m, csp) => {
      const widened = csp.replace(/base-uri 'none'/, 'base-uri ' + dir).replace(/'self'/g, "'self' " + ORIGIN);
      return '<meta http-equiv="Content-Security-Policy" content="' + widened + '">';
    });
    return html.replace(/<head[^>]*>/i, (m) => m + '<base href="' + dir + '">' + inject);
  }
  /** Mount a package page into an iframe; resolves on its load event. */
  function showPage(iframe, relPath, inject = '') {
    return pageDocument(relPath, inject).then((html) => new Promise((ok, no) => {
      iframe.addEventListener('load', () => ok(), {once: true});
      iframe.addEventListener('error', () => no(new Error('QOQORO: page failed to load')), {once: true});
      iframe.srcdoc = html;
    }));
  }

  function resolveTarget(target) {
    const el = typeof target === 'string' ? document.querySelector(target) : target;
    if (!el) throw new Error('QOQORO.mount: target not found: ' + target);
    return el;
  }
  function frameFor(el, options) {
    const iframe = document.createElement('iframe');
    iframe.name = options.mode === 'workspace' ? 'qoqoro-workspace' : 'qoqoro-editor';
    iframe.title = options.mode === 'workspace' ? 'QOQORO workspace' : 'QOQORO editor';
    iframe.allow = 'clipboard-read; clipboard-write';
    iframe.style.cssText = 'display:block;width:100%;height:' + (options.height || '100%') + ';border:0;background:#f2f3f4';
    if (options.className) iframe.className = options.className;
    el.appendChild(iframe);
    return iframe;
  }

  // ── editor: the word processor alone, driven over a MessageChannel ────
  function mountEditor(el, options) {
    const iframe = frameFor(el, options);
    let port = null, requestId = 0, ready = false, destroyed = false;
    const pending = new Map();
    let readyResolve, readyReject;
    const readyPromise = new Promise((ok, no) => { readyResolve = ok; readyReject = no; });

    const ask = (type, extra = {}, timeoutMs = 20000) => new Promise((ok, no) => {
      if (!ready) return no(new Error('QOQORO editor is still loading'));
      const id = ++requestId;
      const timer = setTimeout(() => { pending.delete(id); no(new Error('QOQORO editor did not respond')); }, timeoutMs);
      pending.set(id, {ok, no, timer});
      port.postMessage({type, id, ...extra});
    });
    const load = async (doc) => {
      let xml = doc == null ? EMPTY : String(doc);
      if (/^(https?:)?\/\/|^\.{0,2}\//.test(xml) || (!xml.trimStart().startsWith('<') && !xml.trimStart().startsWith('{') && !xml.trimStart().startsWith('['))) {
        const res = await fetch(xml, {cache: 'no-store'});
        if (!res.ok) throw new Error('QOQORO: could not fetch ' + xml + ' (' + res.status + ')');
        xml = await res.text();
      }
      await ask('LOAD', {doc: xml});
    };
    const save = async () => (await ask('SAVE')).doc;
    const download = (xml) => {
      const url = URL.createObjectURL(new Blob([xml], {type: 'application/vnd.qnote+xml'}));
      const a = document.createElement('a');
      a.href = url; a.download = options.filename || 'document.qnote'; a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    };

    const connect = () => {
      if (destroyed) return;
      ready = false;
      const channel = new MessageChannel();
      port = channel.port1;
      port.onmessage = async (event) => {
        const msg = event.data || {};
        if (msg.type === 'READY') {
          ready = true;
          try { if (options.document != null) await load(options.document); readyResolve(handle); }
          catch (e) { readyReject(e); }
          return;
        }
        if (msg.type === 'REQUEST_SAVE') {
          try {
            const xml = await save();
            if (typeof options.onSave === 'function') await options.onSave(xml, handle); else download(xml);
          } catch (e) { console.error('[QOQORO] save failed:', e); }
          return;
        }
        const req = pending.get(msg.id);
        if (!req) return;
        clearTimeout(req.timer); pending.delete(msg.id);
        if (msg.type === 'ERROR') req.no(new Error(msg.error)); else req.ok(msg);
      };
      // The bridge inside the editor accepts the handshake from its parent
      // whatever the parent's origin; the port itself is the credential.
      iframe.contentWindow.postMessage({
        type: 'VAULT_CONNECT',
        server: options.server ? String(options.server).replace(/\/+$/, '') : null,
        features: {docx: false, serverSettings: options.serverSettings !== false},
      }, '*', [channel.port2]);
    };
    showPage(iframe, 'qnote/index.html', '<script>window.QOQORO_EMBED=true;</script>').then(connect, readyReject);

    const handle = {
      mode: 'editor', iframe, ready: readyPromise, load, save,
      // Run a Luau program against this editor. qoqoro-luau.js wraps this in
      // a friendlier API, but it works on its own:
      //   await handle.runProgram('Selection:TypeText("hi")')
      // The first run also boots the Luau VM in a worker, so this waits
      // longer than an ordinary request.
      runProgram: (source, opts = {}) =>
        ask('RUN_PROGRAM', {source: String(source || ''), apply: opts.apply !== false},
            opts.timeoutMs || 120000),
      destroy() { destroyed = true; port?.close(); iframe.remove(); },
    };
    return handle;
  }

  // ── workspace: the whole app, pointed at a server ─────────────────────
  function mountWorkspace(el, options) {
    const iframe = frameFor(el, options);
    let server = String(options.server || '').replace(/\/+$/, '');
    // The workspace, login and admin pages navigate between each other. As
    // srcdoc documents they cannot follow links themselves, so they ask the
    // loader, which mounts the requested page in the same frame.
    const inject = () => '<script>window.QOQORO_EMBED=true;window.QOQORO_SERVER=' + JSON.stringify(server) + ';window.QOQORO_PACKAGE=' + JSON.stringify(BASE) + ';</script>';
    const onMessage = (event) => {
      if (event.source !== iframe.contentWindow || event.data?.type !== 'QOQORO_NAVIGATE') return;
      const page = String(event.data.page || 'index.html').replace(/[^a-z0-9._-]/gi, '');
      if (!/^(index|login|admin)\.html$/.test(page)) return;
      if (typeof event.data.server === 'string') server = event.data.server.replace(/\/+$/, '');
      showPage(iframe, page, inject()).catch((e) => console.error('[QOQORO]', e));
    };
    window.addEventListener('message', onMessage);
    const ready = showPage(iframe, 'index.html', inject()).then(() => handle);
    let programId = 0;
    const programs = new Map();
    const handle = {mode: 'workspace', iframe, ready, get server() { return server; },
      // The workspace owns the editor frame, so a program is relayed through
      // it: the page answers with QOQORO_PROGRAM_RESULT.
      runProgram(source, opts = {}) {
        return new Promise((ok, no) => {
          const id = ++programId;
          const timer = setTimeout(() => { programs.delete(id); no(new Error('QOQORO: the workspace did not answer')); }, 30000);
          programs.set(id, {ok, no, timer});
          iframe.contentWindow.postMessage({type: 'QOQORO_RUN_PROGRAM', id,
            source: String(source || ''), apply: opts.apply !== false, save: opts.save !== false,
            path: opts.path ? String(opts.path) : '', fileId: opts.fileId ? String(opts.fileId) : ''}, '*');
        });
      },
      destroy() { window.removeEventListener('message', onMessage); iframe.remove(); }};
    window.addEventListener('message', (event) => {
      if (event.source !== iframe.contentWindow || event.data?.type !== 'QOQORO_PROGRAM_RESULT') return;
      const request = programs.get(event.data.id);
      if (!request) return;
      clearTimeout(request.timer); programs.delete(event.data.id);
      if (event.data.error) request.no(new Error(event.data.error));
      else request.ok(event.data.result || {});
    });
    return handle;
  }

  const QOQORO = {
    version: '1.0.0',
    base: BASE,
    EMPTY_DOCUMENT: EMPTY,
    /** Everything mount() has returned, newest last. */
    mounted: [],
    mount(target, options = {}) {
      const el = resolveTarget(target);
      const mode = options.mode || 'editor';
      if (mode !== 'editor' && mode !== 'workspace') throw new Error('QOQORO.mount: mode must be "editor" or "workspace"');
      const handle = mode === 'editor' ? mountEditor(el, options) : mountWorkspace(el, options);
      // The workspace exposes `server` as a getter of its own; only the
      // editor handle needs to remember where it was pointed.
      if (mode === 'editor') handle.server = options.server ? String(options.server).replace(/\/+$/, '') : '';
      QOQORO.mounted.push(handle);
      return handle;
    },
  };
  window.QOQORO = QOQORO;
})();
