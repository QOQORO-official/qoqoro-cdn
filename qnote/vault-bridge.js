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
  // Workspace owns branding when it also owns file navigation. Editor-only
  // embeds retain their brand; connecting a server alone does not hide it.
  function updateBrand() {
    const brand = document.querySelector('#tab-strip .brand');
    if (!brand) return false;
    if (brand.textContent !== 'QOQORO 書く') brand.textContent = 'QOQORO 書く';
    document.documentElement.classList.toggle('qoqoro-vault-host', features.fileList === true);
    return true;
  }
  const brandStyle = document.createElement('style');
  brandStyle.textContent = '.qoqoro-vault-host #tab-strip .brand{display:none!important}';
  document.head.append(brandStyle);
  const findBrand = new MutationObserver(() => {
    if (!updateBrand()) return;
    findBrand.disconnect();
    new MutationObserver(updateBrand).observe(document.querySelector('#tab-strip'), {childList:true,subtree:true,characterData:true});
  });
  findBrand.observe(document.documentElement, {childList:true,subtree:true});
  updateBrand();
  const send = value => port?.postMessage(value);
  const status = text => { const el = document.getElementById('qnote-status-text'); if (el) el.textContent = text; window.dispatchEvent(new Event('qoqoro-document-state')); };

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
    const downloadCopy = () => send({type:'REQUEST_DOWNLOAD',filename:standalone.path.split(/[\\/]/).pop()||undefined});
    const requestSave = () => {
      if(!connected()&&!features.vaultSave){downloadCopy();return;}
      if(document.getElementById('qoqoro-save-dialog'))return;
      const dialog=document.createElement('dialog');dialog.id='qoqoro-save-dialog';
      dialog.setAttribute('aria-label','Save document');
      dialog.style.cssText='box-sizing:border-box;width:min(320px,calc(100vw - 24px));padding:16px;border:1px solid #cbd5e1;border-radius:12px;background:#fff;color:#0f172a;font:14px system-ui;box-shadow:0 16px 48px #0003';
      const heading=document.createElement('h2');heading.textContent='Save document';heading.style.cssText='font-size:16px;margin:0 0 12px';dialog.append(heading);
      for(const [label,action] of [['Save to server',()=>connected()?void saveToServer():send({type:'REQUEST_SAVE'})],['Download copy',downloadCopy],['Cancel',()=>{}]]){
        const button=document.createElement('button');button.type='button';button.textContent=label;
        button.style.cssText='display:block;width:100%;min-height:44px;margin-top:6px;padding:8px 12px;border:1px solid #cbd5e1;border-radius:7px;background:#f8fafc;color:#0f172a;font:inherit;text-align:left;cursor:pointer';
        button.onclick=()=>{dialog.close();action();};dialog.append(button);
      }
      dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();}});
      dialog.onclose=()=>dialog.remove();document.body.append(dialog);dialog.showModal();
    };
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
        else if (msg.type === 'SAVE_OPTIONS') { requestSave(); send({type:'SAVE_OPTIONS_SHOWN',id:msg.id}); }
        else if (msg.type === 'SAVE') captureDoc().then(doc => send({type: 'SAVED', id: msg.id, doc}), e => send({type: 'ERROR', id: msg.id, error: e.message}));
        // The Luau engine lives in this page. The host page (and through it a
        // Flask or Node server) asks for a run without opening the dialog.
        else if (msg.type === 'RUN_PROGRAM') {
          if (!globalThis.QNoteAutomation) throw Error('This editor build has no automation API');
          runWithDirectives(String(msg.source || ''), msg.apply !== false)
            .then(result => send({type: 'PROGRAM_RESULT', id: msg.id, ...result}),
                  e => send({type: 'ERROR', id: msg.id, error: e.message, output: e.output || []}));
        }
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
    // ── the editor's own Misc actions, driven without its dialog ──
    // QNote applies templates, programs and "save in document" through a
    // hidden textarea and answers on another. `api: true` is what its own
    // automation API sends: no dialog session to match.
    const miscData = document.getElementById('qnote-misc-data');
    const miscAction = document.getElementById('qnote-misc-action');
    const miscWaiters = [];
    if (miscData) {
      const own = Object.getOwnPropertyDescriptor(miscData, 'value') ||
                  Object.getOwnPropertyDescriptor(Object.getPrototypeOf(miscData), 'value');
      Object.defineProperty(miscData, 'value', {configurable: true, get() { return own.get.call(this); }, set(value) {
        own.set.call(this, value);
        let data; try { data = JSON.parse(value); } catch { return; }
        if (data?.mode === 'result' && miscWaiters.length) miscWaiters.shift()(data);
      }});
    }
    const runMisc = (data, timeoutMs = 20000) => new Promise((resolve, reject) => {
      if (!miscData || !miscAction) return reject(Error('This editor build cannot be driven from outside'));
      const timer = setTimeout(() => { const i = miscWaiters.indexOf(done); if (i >= 0) miscWaiters.splice(i, 1); reject(Error('The editor did not answer in time')); }, timeoutMs);
      function done(result) {
        clearTimeout(timer);
        // QNote reports "Saved" for save/remove; other actions close the dialog on success.
        const ok = ['save', 'remove'].includes(data.op) ? result.message === 'Saved' : result.close === true;
        ok ? resolve(result) : reject(Error(result.message || 'The editor refused ' + data.op));
      }
      miscWaiters.push(done);
      miscAction.value = JSON.stringify({...data, api: true});
      miscAction.dispatchEvent(new Event('change', {bubbles: true}));
    });

    // ── the server library (library_bp.py) and plugins (plugins_bp.py) ──
    // Both live only on a server: with none there is simply no Library.
    const libraryClient = () => standalone.client ||
      (typeof server === 'string' && typeof VaultClient === 'function' ? new VaultClient(server, {onUnauthorized: () => {}}) : null);
    const templateKeys = source => [...new Set([...String(source).matchAll(/\{\{(.*?)\}\}/g)].map(m => m[1].trim()))];
    const templateVariables = (source, given) => {
      const vars = {};
      for (const key of templateKeys(source)) vars[key] = given && given[key] != null ? String(given[key]) : '';
      return vars;
    };
    async function insertTemplate(source, variables) {
      const vars = templateVariables(source, variables);
      // Newer editors insert XML objects (images, tables, …) too.
      if (globalThis.QNoteAutomation?.applyTemplate) return globalThis.QNoteAutomation.applyTemplate(source, vars);
      await runMisc({op: 'template', source, variables: JSON.stringify(vars)});
    }
    // QNote's Templates dialog lists the server's templates beside its own
    // when this is set; without a server there is none, and it shows only
    // the built-in and in-document ones.
    Object.defineProperty(globalThis, 'QNoteTemplateLibrary', {configurable: true, get() {
      const client = libraryClient();
      if (!client) return null;
      return {
        list: () => client.get('/api/library/templates'),
        get: id => client.get('/api/library/templates', {id}),
        save: (name, source) => client.post('/api/library/templates', {name, source}),
        remove: id => client.request('DELETE', '/api/library/templates', {query: {id}}),
      };
    }});
    // A program file holds Luau, or a JSON wrapper {"language":"lua","source"}
    // (how QNote saves one in a document), or the older JSON command list.
    const programEntry = source => {
      try {
        const data = JSON.parse(source);
        if (data && data.language === 'lua' && typeof data.source === 'string') return {language: 'lua', source: data.source};
        return {language: 'json', source};
      } catch { return {language: 'lua', source}; }
    };
    async function runProgramSource(entry, apply = true) {
      if (entry.language === 'json') {
        if (apply) await runMisc({op: 'run', source: entry.source});
        return {ok: true, applied: apply, commands: 0, output: []};
      }
      return globalThis.QNoteAutomation.run(entry.source, {apply});
    }
    // QoChart's "QNote template" block compiles to a directive line inside the
    // Luau it sends: `--@qnote-template {"id": ..., "variables": {...}}`. Being
    // a Luau comment, it is harmless to an older bridge. Here the program is
    // cut at each directive: Luau before it runs, the template goes in, and so
    // on in order -- each piece is its own undo step.
    async function runWithDirectives(source, apply) {
      const lines = source.split('\n');
      if (!lines.some(line => line.startsWith('--@qnote-template '))) return globalThis.QNoteAutomation.run(source, {apply});
      const total = {ok: true, applied: false, commands: 0, output: [], status: '', templates: 0};
      let chunk = [];
      const flush = async () => {
        const text = chunk.join('\n'); chunk = [];
        if (!text.split('\n').some(line => line.trim() && !line.trim().startsWith('--'))) return;
        const result = await globalThis.QNoteAutomation.run(text, {apply});
        total.commands += result.commands || 0;
        total.output.push(...(result.output || []));
        total.applied = total.applied || !!result.applied;
      };
      for (const line of lines) {
        if (!line.startsWith('--@qnote-template ')) { chunk.push(line); continue; }
        await flush();
        let directive;
        try { directive = JSON.parse(line.slice('--@qnote-template '.length)); }
        catch { throw Error('A QNote template block sent an unreadable request'); }
        const client = libraryClient();
        if (!client) throw Error('Inserting a QNote template needs a QNote Vault server');
        const item = await client.get('/api/library/templates', {id: String(directive.id || '')});
        if (apply) { await insertTemplate(item.source, directive.variables); total.applied = true; }
        total.templates++;
      }
      await flush();
      total.status = total.templates + ' template(s) and ' + total.commands + ' command(s) applied';
      return total;
    }

    // Templates and programs saved inside this document, from its XML.
    async function documentItems() {
      const xml = await captureDoc();
      const doc = new DOMParser().parseFromString(xml, 'application/xml').querySelector('doc');
      let meta = {};
      try { meta = JSON.parse(doc?.getAttribute('qnote-meta') || '{}'); } catch {}
      const pick = list => (Array.isArray(list) ? list : []).filter(i => i && typeof i.name === 'string' && typeof i.source === 'string');
      return {templates: pick(meta.templates), programs: pick(meta.programs)};
    }

    function libraryDialog() {
      document.getElementById('qoqoro-library-dialog')?.remove();
      const dialog = document.createElement('dialog'); dialog.id = 'qoqoro-library-dialog';
      dialog.setAttribute('aria-label', 'Library');
      dialog.style.cssText = 'box-sizing:border-box;width:min(620px,calc(100vw - 24px));max-height:86vh;padding:0;border:1px solid #cbd5e1;border-radius:12px;background:#fff;color:#0f172a;font:13px Inter,"Segoe UI",system-ui,sans-serif;box-shadow:0 16px 48px #0003';
      const el = (tag, css, text) => { const n = document.createElement(tag); if (css) n.style.cssText = css; if (text != null) n.textContent = text; return n; };
      const btn = (text, onclick, primary) => { const b = el('button', 'padding:6px 10px;min-height:32px;border-radius:6px;font:inherit;cursor:pointer;border:1px solid ' + (primary ? '#2563eb;background:#2563eb;color:#fff' : '#cbd5e1;background:#f8fafc;color:#0f172a'), text); b.type = 'button'; b.onclick = onclick; return b; };
      const head = el('div', 'display:flex;align-items:center;gap:8px;padding:14px 16px;border-bottom:1px solid #e2e8f0');
      head.append(el('strong', 'font-size:16px;flex:1', 'Library'));
      const tabs = {};
      for (const [kind, label] of [['templates', 'Templates'], ['programs', 'Programs']]) {
        tabs[kind] = btn(label, () => show(kind)); head.append(tabs[kind]);
      }
      const body = el('div', 'max-height:62vh;overflow:auto;padding:12px 16px');
      const message = el('p', 'min-height:18px;margin:0;padding:8px 16px;color:#334155;border-top:1px solid #e2e8f0');
      message.setAttribute('role', 'status');
      const foot = el('div', 'display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end;padding:10px 16px;border-top:1px solid #e2e8f0');
      dialog.append(head, body, message, foot);
      const say = (text, error) => { message.textContent = text; message.style.color = error ? '#b91c1c' : '#334155'; };
      const client = libraryClient();
      if (client) foot.append(btn('Manage plugins…', () => window.open((client.base || '') + '/plugins', '_blank', 'noopener')));
      foot.append(btn('Close', () => dialog.close()));

      let current = 'templates', library = null, inDocument = null;
      const section = title => { const s = el('section', 'margin:0 0 14px'); s.append(el('h3', 'margin:4px 0 8px;font-size:12px;letter-spacing:.04em;text-transform:uppercase;color:#64748b', title)); body.append(s); return s; };
      const row = (parent, name, detail, actions) => {
        const r = el('div', 'display:flex;gap:8px;align-items:center;flex-wrap:wrap;padding:8px 10px;border:1px solid #e2e8f0;border-radius:8px;margin-bottom:6px');
        const text = el('div', 'flex:1;min-width:160px');
        text.append(el('div', 'font-weight:600', name));
        if (detail) text.append(el('div', 'color:#64748b;font-size:12px', detail));
        r.dataset.name = name; r.append(text, ...actions); parent.append(r);
      };
      async function askVariables(source) {
        const keys = templateKeys(source);
        if (!keys.length) return {};
        return new Promise(resolve => {
          const form = el('form', 'display:grid;gap:8px;padding:10px;margin:0 0 12px;border:1px solid #bfdbfe;background:#eff6ff;border-radius:8px');
          form.append(el('strong', '', 'Fill in the template'));
          const inputs = keys.map(key => {
            const label = el('label', 'display:grid;gap:3px;font-weight:600', key);
            const input = el('input', 'padding:7px;border:1px solid #cbd5e1;border-radius:6px;font:inherit;font-weight:400');
            label.append(input); form.append(label); return [key, input];
          });
          const actions = el('div', 'display:flex;gap:8px;justify-content:flex-end');
          actions.append(btn('Cancel', () => { form.remove(); resolve(null); }), btn('Insert', () => form.requestSubmit(), true));
          form.append(actions);
          form.onsubmit = e => { e.preventDefault(); form.remove(); resolve(Object.fromEntries(inputs.map(([k, i]) => [k, i.value]))); };
          body.prepend(form); inputs[0][1].focus();
        });
      }
      const guard = async (label, work) => {
        try { say(label + '…'); await work(); }
        catch (e) { say(e.message, true); }
      };
      function show(kind) {
        current = kind;
        for (const [k, b] of Object.entries(tabs)) { b.style.background = k === kind ? '#2563eb' : '#f8fafc'; b.style.color = k === kind ? '#fff' : '#0f172a'; }
        body.replaceChildren();
        const serverPart = section('On the server');
        if (!client) serverPart.append(el('p', 'color:#64748b;margin:0', 'No QNote Vault server is connected, so there is no server library or plugins here. ' +
          (features.serverSettings ? 'Connect one with Misc → Server.' : '') + ' Templates and programs can still be kept in this document (Misc → Templates / Programs).'));
        else if (!library) serverPart.append(el('p', 'color:#64748b;margin:0', 'Loading…'));
        else if (!library[kind].length) serverPart.append(el('p', 'color:#64748b;margin:0', 'Nothing here yet. Upload one from this document below, or install a plugin.'));
        else for (const item of library[kind]) {
          const detail = [item.origin === 'plugin' ? 'Plugin · ' + item.plugin : 'Server', item.description].filter(Boolean).join(' · ');
          const actions = [];
          const fetchItem = () => client.get('/api/library/' + kind, {id: item.id});
          if (kind === 'templates') actions.push(btn('Insert', () => guard('Inserting ' + item.name, async () => {
            const full = await fetchItem(); const vars = await askVariables(full.source);
            if (vars === null) { say(''); return; }
            await insertTemplate(full.source, vars); say('Inserted ' + item.name);
          }), true));
          else actions.push(btn('Run', () => guard('Running ' + item.name, async () => {
            const full = await fetchItem();
            const result = await runProgramSource({language: full.language || 'lua', source: full.source});
            say((result.output || []).join('\n') || 'Ran ' + item.name + (result.commands ? ' · ' + result.commands + ' command(s)' : ''));
          }), true));
          actions.push(btn('Save in document', () => guard('Saving ' + item.name + ' in this document', async () => {
            const full = await fetchItem();
            const source = kind === 'programs' && (full.language || 'lua') === 'lua' ? JSON.stringify({language: 'lua', source: full.source}) : full.source;
            await runMisc({op: 'save', kind, name: item.name, source});
            inDocument = null; say('Saved ' + item.name + ' in this document'); load();
          })));
          if (!item.readonly) actions.push(btn('Delete', () => guard('Deleting ' + item.name, async () => {
            if (!confirm('Delete "' + item.name + '" from the server library?')) { say(''); return; }
            await client.request('DELETE', '/api/library/' + kind, {query: {id: item.id}});
            library = null; say('Deleted ' + item.name); load();
          })));
          row(serverPart, item.name, detail, actions);
        }
        const docPart = section('In this document');
        if (!inDocument) docPart.append(el('p', 'color:#64748b;margin:0', 'Reading this document…'));
        else if (!inDocument[kind].length) docPart.append(el('p', 'color:#64748b;margin:0', 'None saved in this document (Misc → ' + (kind === 'templates' ? 'Templates' : 'Programs') + ' → Save in document).'));
        else for (const item of inDocument[kind]) {
          const actions = client ? [btn('Upload to server', () => guard('Uploading ' + item.name, async () => {
            const entry = kind === 'programs' ? programEntry(item.source) : {source: item.source};
            await client.post('/api/library/' + kind, {name: item.name, source: entry.source, language: entry.language});
            library = null; say('Uploaded ' + item.name + ' to the server library'); load();
          }))] : [];
          row(docPart, item.name, 'Saved in this .qnote file', actions);
        }
      }
      async function load() {
        show(current);
        if (client && !library) {
          try { library = await client.get('/api/library'); }
          catch (e) { library = {templates: [], programs: []}; say(e.status === 404 ? 'This server has no library (update the server).' : 'Could not load the server library: ' + e.message, true); }
        }
        if (!inDocument) { try { inDocument = await documentItems(); } catch (e) { inDocument = {templates: [], programs: []}; say('Could not read this document: ' + e.message, true); } }
        show(current);
      }
      dialog.onclose = () => dialog.remove();
      document.body.append(dialog); dialog.showModal();
      load();
    }
    const misc = document.getElementById('tab-misc');
    if (misc && !document.getElementById('btn-qoqoro-library')) {
      const sep = document.createElement('span'); sep.className = 'sep';
      const b = document.createElement('button'); b.id = 'btn-qoqoro-library'; b.className = 'tool-text'; b.type = 'button';
      b.title = 'Templates and programs on the server, from plugins, and in this document'; b.textContent = '📚 Library';
      b.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); libraryDialog(); });
      misc.append(sep, b);
    }

    // Programmatic access for the host page (qoqoro.js) and tests.
    globalThis.__qoqoroBridge = {captureDoc, loadDoc, serverDialog, libraryDialog, insertTemplate, standalone, get connected() { return connected(); }};
    window.dispatchEvent(new Event('qoqoro-document-state'));
    send({type: 'READY'});
    return true;
  }
  addEventListener('message', event => {
    if (event.source !== parent || event.data?.type !== 'VAULT_CONNECT' || !event.ports[0] || port) return;
    port = event.ports[0]; port.start();
    server = typeof event.data.server === 'string' ? event.data.server.replace(/\/+$/, '') : null;
    features = event.data.features || {};
    updateBrand();
    if (install()) return;
    const observer = new MutationObserver(() => { if (install()) observer.disconnect(); });
    observer.observe(document.documentElement, {childList: true, subtree: true});
  });
})();
