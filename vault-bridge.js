// vault-bridge.js — injected into the editor iframe by scripts/build-web.mjs.
//
// Two jobs, both keeping the WASM editor itself untouched:
//
//  1. Parent bridge. Links the editor's Save / Open to the page that embeds
//     it (the workspace shell, or a host page using qoqoro.js) over a
//     MessageChannel. The parent may be on another origin — the package is
//     served from a CDN — so the handshake trusts the window that embedded
//     us and the port it hands over, not an origin string.
//
//  2. Standalone server (editor-only embeds). A "Server" button in the Misc
//     tab opens a dialog for the server address (IP:port or domain) and
//     credentials. Once connected, the editor's own Open and Save buttons
//     read and write notes on that server through VaultClient, instead of
//     the file picker and the download. The parent enables this with
//     features.serverSettings in the handshake; the workspace shell, which
//     has its own server setting, leaves it off.
//
// Derived from the desktop edition's bridge.js.
(() => {
  const STORAGE_KEY = 'qoqoro-server';
  let port, pendingSave = null, exporting = false, vaultDownloads = 0, server = null, features = {};
  const send = value => port?.postMessage(value);
  const status = text => { const el = document.getElementById('qnote-status-text'); if (el) el.textContent = text; };

  // ── theme preferences follow the user when the server stores them ──
  if (typeof Storage !== 'undefined') {
    const keys = ['qnote-theme', 'qnote-workspace-background', 'qnote-toolbar-settings'];
    const set = Storage.prototype.setItem; let preferencesTimer;
    Storage.prototype.setItem = function (key, value) {
      set.call(this, key, value);
      if (this === localStorage && keys.includes(key)) {
        clearTimeout(preferencesTimer); preferencesTimer = setTimeout(() => {
          const target = standalone.client ? standalone.client.base : server;
          if (target === null || target === undefined) return;
          const prefs = Object.fromEntries(keys.map(k => [k, localStorage.getItem(k)]).filter(([, v]) => v !== null));
          const headers = {'Content-Type': 'application/json'};
          if (standalone.client?.token) headers.Authorization = 'Bearer ' + standalone.client.token;
          fetch(target + '/api/preferences', {method: 'POST', headers, credentials: 'include', body: JSON.stringify(prefs)}).catch(() => {});
        }, 200);
      }
    };
  }

  // ── standalone server state ──
  const standalone = {client: null, path: '', fileId: '', username: ''};
  const connected = () => !!standalone.client;

  function install() {
    const buffer = document.getElementById('qnote-file-buffer');
    const save = document.getElementById('btn-save');
    if (!buffer || !save || !globalThis.__qnoteFileCompat) return false;
    const docx = document.querySelector('#tab-file button:not([id])');
    if (features.docx) docx?.addEventListener('click', event => { event.preventDefault(); send({type: 'REQUEST_DOCX'}); });

    // The runtime clicks a detached anchor, which never reaches document's
    // event listeners. Intercept that method, scoped to our queued saves.
    const anchorClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function (...args) {
      if (vaultDownloads > 0 && this.download.toLowerCase().endsWith('.qnote') && this.href.startsWith('blob:')) { vaultDownloads--; return; }
      return anchorClick.apply(this, args);
    };
    // The editor serializes into this textarea when Save is pressed; a
    // pending capture picks the document up from the setter.
    const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(buffer), 'value');
    Object.defineProperty(buffer, 'value', {configurable: true, get() { return descriptor.get.call(this); }, set(value) {
      descriptor.set.call(this, value);
      if (pendingSave) {
        const request = pendingSave; pendingSave = null; clearTimeout(request.timer);
        queueMicrotask(() => {
          try { request.resolve(globalThis.__qnoteFileCompat.exportToXml(String(value))); }
          catch (e) { request.reject(e); }
        });
      }
    }});
    /** Current document as QNote XML, via the editor's own Save path. */
    const captureDoc = () => new Promise((resolve, reject) => {
      if (pendingSave) return reject(Error('Save already in progress'));
      const timer = setTimeout(() => { pendingSave = null; exporting = false; reject(Error('Editor save timed out; nothing was written.')); }, 15000);
      pendingSave = {resolve, reject, timer};
      exporting = true; vaultDownloads++;
      try { save.click(); } finally { exporting = false; }
    });
    const loadDoc = (doc) => {
      if (pendingSave) throw Error('Wait for the current save to finish');
      const source = typeof doc === 'string' ? doc : JSON.stringify(doc);
      buffer.value = globalThis.__qnoteFileCompat.importToNim(source);
      buffer.dispatchEvent(new Event('change', {bubbles: true}));
    };

    // ── Save / Ctrl+S: the connected server first, else the parent ──
    const requestSave = () => { if (connected()) void saveToServer(); else send({type: 'REQUEST_SAVE'}); };
    document.addEventListener('click', event => {
      if (exporting && event.target.closest?.('a[download="document.qnote"]')) event.preventDefault();
      if (event.target.closest?.('#btn-save') && !exporting) { event.preventDefault(); event.stopImmediatePropagation(); requestSave(); }
      if (connected() && event.target.closest?.('#btn-open')) { event.preventDefault(); event.stopImmediatePropagation(); void openFromServer(); }
    }, true);
    document.addEventListener('keydown', event => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's') { event.preventDefault(); event.stopImmediatePropagation(); requestSave(); }
    }, true);

    // ── parent protocol ──
    port.onmessage = event => {
      const msg = event.data || {};
      try {
        if (msg.type === 'LOAD') { loadDoc(msg.doc); send({type: 'LOADED', id: msg.id}); }
        else if (msg.type === 'SAVE') captureDoc().then(doc => send({type: 'SAVED', id: msg.id, doc}), e => send({type: 'ERROR', id: msg.id, error: e.message}));
      } catch (e) { send({type: 'ERROR', id: msg.id, error: e.message}); }
    };

    // ── standalone server: the Misc-tab button and its dialog ──
    async function saveToServer(asNew = false) {
      const client = standalone.client;
      try {
        let path = standalone.path;
        if (!path || asNew) {
          path = prompt('Save on the server as (Folder/Name.qnote):', path || 'Untitled.qnote');
          if (!path) return;
          path = path.replace(/\\/g, '/').replace(/^\/+/, '');
          if (!/\.qnote$/i.test(path)) path += '.qnote';
          try { await client.create(path); } catch (e) { if (e.status !== 409) throw e; }
        }
        status('Saving to server…');
        const xml = await captureDoc();
        const result = await client.saveNoteChunked(path, xml, {fileId: standalone.fileId || undefined});
        standalone.path = result.noteId || path; standalone.fileId = result.fileId || standalone.fileId;
        status('Saved ' + standalone.path + ' on ' + client.base);
      } catch (e) { status('Save failed: ' + e.message); alert('Save failed: ' + e.message); }
    }
    async function openFromServer() {
      const client = standalone.client;
      let listing;
      try { listing = await client.files({include: 'qnote'}); }
      catch (e) { alert('Could not list notes: ' + e.message); return; }
      const dialog = document.createElement('dialog'); dialog.id = 'qoqoro-open-dialog';
      dialog.style.cssText = 'width:min(520px,92vw);max-height:80vh;padding:0;border:1px solid #cbd5e1;border-radius:10px;font:13px Inter,"Segoe UI",system-ui,sans-serif;color:#0f172a';
      const head = document.createElement('div'); head.style.cssText = 'padding:12px 16px;border-bottom:1px solid #e2e8f0;font-weight:600';
      head.textContent = 'Open from ' + client.base;
      const list = document.createElement('div'); list.style.cssText = 'max-height:56vh;overflow:auto;padding:8px';
      const files = listing.files.filter(f => f.ext === '.qnote').sort((a, b) => a.path.localeCompare(b.path));
      if (!files.length) { const p = document.createElement('p'); p.style.cssText = 'padding:12px;color:#64748b'; p.textContent = 'No notes on this server yet. Save one first.'; list.appendChild(p); }
      for (const f of files) {
        const b = document.createElement('button'); b.type = 'button'; b.textContent = f.path;
        b.style.cssText = 'display:block;width:100%;text-align:left;padding:8px 10px;border:0;border-radius:6px;background:transparent;cursor:pointer;font:inherit';
        b.onmouseenter = () => b.style.background = '#eff6ff'; b.onmouseleave = () => b.style.background = 'transparent';
        b.onclick = async () => {
          try {
            const data = await client.note(f.path, f.fileId);
            const doc = Array.isArray(data.doc) && data.doc.length === 0 ? '<?xml version="1.0"?><qnote v="1"><doc><qotext></qotext></doc></qnote>' : data.doc;
            loadDoc(doc);
            standalone.path = data.noteId || f.path; standalone.fileId = data.fileId || f.fileId || '';
            status('Opened ' + standalone.path + ' from ' + client.base);
            dialog.close();
          } catch (e) { alert('Could not open ' + f.path + ': ' + e.message); }
        };
        list.appendChild(b);
      }
      const foot = document.createElement('div'); foot.style.cssText = 'padding:10px 16px;border-top:1px solid #e2e8f0;text-align:right';
      const close = document.createElement('button'); close.type = 'button'; close.textContent = 'Cancel'; close.style.cssText = 'padding:7px 12px;font:inherit';
      close.onclick = () => dialog.close();
      foot.appendChild(close); dialog.append(head, list, foot);
      dialog.onclose = () => dialog.remove();
      document.body.appendChild(dialog); dialog.showModal();
    }
    function serverDialog() {
      document.getElementById('qoqoro-server-dialog')?.remove();
      const dialog = document.createElement('dialog'); dialog.id = 'qoqoro-server-dialog';
      dialog.style.cssText = 'width:min(440px,92vw);padding:20px 22px;border:1px solid #cbd5e1;border-radius:10px;font:13px Inter,"Segoe UI",system-ui,sans-serif;color:#0f172a';
      const field = (label, name, type, value, placeholder) => {
        const l = document.createElement('label'); l.style.cssText = 'display:grid;gap:4px;margin:0 0 10px;font-weight:600';
        const i = document.createElement('input'); i.name = name; i.type = type; i.value = value || ''; i.placeholder = placeholder || '';
        i.style.cssText = 'padding:8px;border:1px solid #cbd5e1;border-radius:5px;font:inherit;font-weight:400';
        if (type === 'password') i.autocomplete = 'current-password'; if (name === 'username') i.autocomplete = 'username';
        l.append(label, i); return i;
      };
      const h = document.createElement('h2'); h.style.cssText = 'margin:0 0 4px;font-size:17px'; h.textContent = 'Server';
      const lead = document.createElement('p'); lead.style.cssText = 'margin:0 0 14px;color:#64748b';
      lead.textContent = 'Open and Save use this QNote Vault server when connected. IP address with port, or a domain.';
      dialog.append(h, lead);
      const address = field('Server address', 'server', 'url', standalone.client?.base || localStorage.getItem(STORAGE_KEY) || server || '', 'http://192.168.1.10:5000 or https://notes.example.com');
      const username = field('Username', 'username', 'text', standalone.username, '');
      const password = field('Password', 'password', 'password', '', '');
      for (const el of [address, username, password]) dialog.appendChild(el.parentElement);
      const message = document.createElement('p'); message.style.cssText = 'min-height:20px;margin:0 0 10px;color:#334155';
      const refresh = () => { message.textContent = connected() ? 'Connected to ' + standalone.client.base + (standalone.username ? ' as ' + standalone.username : '') + (standalone.path ? ' · ' + standalone.path : '') : 'Not connected — Open and Save work with local files.'; };
      refresh(); dialog.appendChild(message);
      const row = document.createElement('div'); row.style.cssText = 'display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end';
      const button = (text, primary, onclick) => { const b = document.createElement('button'); b.type = 'button'; b.textContent = text;
        b.style.cssText = 'padding:8px 12px;border-radius:6px;font:inherit;cursor:pointer;border:1px solid ' + (primary ? '#2563eb;background:#2563eb;color:#fff' : '#cbd5e1;background:#f8fafc');
        b.onclick = onclick; row.appendChild(b); return b; };
      button('Connect', true, async () => {
        const base = address.value.trim().replace(/\/+$/, '');
        if (!/^https?:\/\//i.test(base)) { message.textContent = 'Enter the address with http:// or https://'; return; }
        message.textContent = 'Connecting…';
        try {
          const client = new VaultClient(base, {onUnauthorized: () => {}});
          let state = await client.session();
          if (!state.authenticated) {
            if (!username.value) { message.textContent = 'This server needs a username and password.'; return; }
            await client.login(username.value.trim(), password.value);
            state = await client.session();
            if (!state.authenticated) throw Error('Signed in, but the server still reports no session');
          }
          standalone.client = client; standalone.username = username.value.trim() || state.username || '';
          localStorage.setItem(STORAGE_KEY, base);
          password.value = '';
          status('Connected to ' + base + ' · Open and Save now use the server');
          refresh();
        } catch (e) { message.textContent = 'Could not connect: ' + e.message; }
      });
      button('Save as new note…', false, async () => { if (!connected()) { message.textContent = 'Connect first.'; return; } dialog.close(); await saveToServer(true); });
      button('Disconnect', false, async () => {
        if (!connected()) return;
        try { await standalone.client.logout(); } catch {}
        standalone.client = null; standalone.path = ''; standalone.fileId = '';
        status('Disconnected · Open and Save use local files');
        refresh();
      });
      button('Close', false, () => dialog.close());
      dialog.appendChild(row);
      dialog.onclose = () => dialog.remove();
      document.body.appendChild(dialog); dialog.showModal();
      address.focus();
    }
    if (features.serverSettings && typeof VaultClient === 'function') {
      const misc = document.getElementById('tab-misc');
      if (misc && !document.getElementById('btn-qoqoro-server')) {
        const sep = document.createElement('span'); sep.className = 'sep';
        const b = document.createElement('button'); b.id = 'btn-qoqoro-server'; b.className = 'tool-text'; b.type = 'button';
        b.title = 'Connect Open and Save to a QNote Vault server'; b.textContent = '🔌 Server';
        b.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); serverDialog(); });
        misc.append(sep, b);
      }
      // A server named by the host page connects on its own when it lets us in without a login.
      const remembered = server || localStorage.getItem(STORAGE_KEY);
      if (remembered) {
        const client = new VaultClient(remembered, {onUnauthorized: () => {}});
        client.session().then(state => { if (state.authenticated) { standalone.client = client; standalone.username = state.username || ''; status('Connected to ' + remembered + ' · Open and Save use the server'); } }).catch(() => {});
      }
    }
    // Programmatic access for the host page (qoqoro.js) and tests.
    globalThis.__qoqoroBridge = {captureDoc, loadDoc, serverDialog, standalone, get connected() { return connected(); }};
    send({type: 'READY'});
    return true;
  }
  addEventListener('message', event => {
    if (event.source !== parent || event.data?.type !== 'VAULT_CONNECT' || !event.ports[0] || port) return;
    port = event.ports[0]; port.start();
    server = typeof event.data.server === 'string' ? event.data.server.replace(/\/+$/, '') : null;
    features = event.data.features || {};
    if (install()) return;
    const observer = new MutationObserver(() => { if (install()) observer.disconnect(); });
    observer.observe(document.documentElement, {childList: true, subtree: true});
  });
})();
