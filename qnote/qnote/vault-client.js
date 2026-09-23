/**
 * vault-client.js — the browser side of the QNote Vault API v1.
 *
 * One method per endpoint in docs/API.md, in the same order. This is the only
 * file in the web app that talks HTTP, so a server implementer can read it as
 * the exact set of requests the page will make, and a page author can call it
 * without knowing the wire format.
 *
 *   const vault = new VaultClient();          // same origin
 *   const vault = new VaultClient('https://notes.example.com');
 *   const {files, folders} = await vault.files({include: ['qnote', 'pdf']});
 *
 * Every method resolves to the parsed JSON body and rejects with a VaultError
 * carrying `status` and the server's `error` message. A 401 also calls
 * `onUnauthorized` (default: navigate to /login.html) so the page can bounce
 * to the sign-in screen without each caller checking.
 *
 * Optional endpoints (see API.md §8) reject with status 404 when the server
 * does not provide them; `supports(name)` probes and caches that once.
 *
 * Cross-origin servers: when `base` is another origin the browser will not
 * reliably keep a session cookie (third-party cookies), so the client asks
 * for a bearer token at login (`{"token": true}` in the body), stores it in
 * sessionStorage under the server's origin, and sends it as
 * `Authorization: Bearer …` on every request. Same-origin servers keep
 * working with cookies alone.
 */
class VaultError extends Error {
  constructor(status, message, body) { super(message); this.status = status; this.body = body; }
}

class VaultClient {
  constructor(base = '', options = {}) {
    this.base = String(base || '').replace(/\/+$/, '');
    // An embedded page has no URL of its own (about:srcdoc), so "the same
    // origin" means the page that embeds it — which is also whose origin the
    // browser sends to the server.
    if (!this.base && VaultClient.embedded) { try { this.base = window.parent.location.origin; } catch {} }
    this.onUnauthorized = options.onUnauthorized || (() => { VaultClient.navigate('login.html', this.base); });
    this.fetch = options.fetch || ((url, init) => fetch(url, init));
    this._supports = new Map();
    this.crossOrigin = !!this.base && new URL(this.base, this.base).origin !== location.origin;
  }

  /** True inside a page that qoqoro.js mounted (srcdoc, no URL of its own). */
  static get embedded() { return !!globalThis.QOQORO_EMBED; }
  /** The server this page should talk to: what the loader injected, then
   *  ?server= in the URL, then the address remembered by the Server dialog,
   *  else the page's own origin. */
  static serverFromPage() {
    const q = VaultClient.embedded ? '' : new URLSearchParams(location.search).get('server');
    let remembered = ''; try { remembered = localStorage.getItem('qoqoro-server') || ''; } catch {}
    return (globalThis.QOQORO_SERVER || q || remembered || '').replace(/\/+$/, '');
  }
  /** Remember a server address for this package origin (the Server dialog). */
  static rememberServer(base) {
    try { if (base) localStorage.setItem('qoqoro-server', base); else localStorage.removeItem('qoqoro-server'); } catch {}
  }
  /** Where the package lives: the loader tells an embedded page, otherwise the page's own folder. */
  static get packageBase() { return globalThis.QOQORO_PACKAGE || new URL('.', document.baseURI).href; }
  /** A sibling page of the package (login.html, index.html), keeping ?server=. */
  static pageUrl(name, base) {
    const url = new URL(name, VaultClient.packageBase);
    if (base) url.searchParams.set('server', base);
    return url.href;
  }
  /** Go to a sibling page. Embedded pages cannot navigate (the CDN may not
   *  render HTML), so they ask the loader to mount the page instead. */
  static navigate(name, base) {
    if (VaultClient.embedded && window.parent !== window) window.parent.postMessage({type: 'QOQORO_NAVIGATE', page: name, server: base || ''}, '*');
    else location.replace(VaultClient.pageUrl(name, base));
  }
  /** A package page as srcdoc HTML, for nested frames (the workspace's editor). Same rewrite as qoqoro.js. */
  static async frameDocument(relPath, inject = '') {
    const url = new URL(relPath, VaultClient.packageBase).href;
    const res = await fetch(url, {mode: 'cors'});
    if (!res.ok) throw new VaultError(res.status, 'Could not load ' + relPath);
    const dir = new URL('.', url).href, origin = new URL(url).origin;
    let html = await res.text();
    html = html.replace(/<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]*)"\s*\/?>/i, (m, csp) =>
      '<meta http-equiv="Content-Security-Policy" content="' + csp.replace(/base-uri 'none'/, 'base-uri ' + dir).replace(/'self'/g, "'self' " + origin) + '">');
    return html.replace(/<head[^>]*>/i, (m) => m + '<base href="' + dir + '">' + inject);
  }
  get tokenKey() { return 'qoqoro-token:' + (this.base || location.origin); }
  get token() { try { return sessionStorage.getItem(this.tokenKey) || ''; } catch { return ''; } }
  set token(value) { try { if (value) sessionStorage.setItem(this.tokenKey, value); else sessionStorage.removeItem(this.tokenKey); } catch {} }

  // ── transport ──────────────────────────────────────────────────────────
  static encodePath(path) {
    return String(path).replace(/\\/g, '/').replace(/^\/+/, '').split('/').map(encodeURIComponent).join('/');
  }
  async request(method, path, {json, body, type, query} = {}) {
    const url = new URL(this.base + path, this.base || location.href);
    for (const [k, v] of Object.entries(query || {})) if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, v);
    const init = {method, headers: {}, credentials: 'include', cache: 'no-store'};
    if (this.token) init.headers.Authorization = 'Bearer ' + this.token;
    if (json !== undefined) { init.body = JSON.stringify(json); init.headers['Content-Type'] = 'application/json'; }
    else if (body !== undefined) { init.body = body; init.headers['Content-Type'] = type || 'application/octet-stream'; }
    const res = await this.fetch(url, init);
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : {}; } catch { data = {raw: text}; }
    if (res.status === 401) { this.onUnauthorized(); throw new VaultError(401, (data && data.error) || 'Please sign in', data); }
    if (!res.ok) throw new VaultError(res.status, (data && data.error) || res.statusText || 'Request failed', data);
    return data;
  }
  get(path, query) { return this.request('GET', path, {query}); }
  post(path, json) { return this.request('POST', path, {json}); }

  /** True when the server answers an optional endpoint with anything but 404. Cached. */
  async supports(name) {
    if (this._supports.has(name)) return this._supports.get(name);
    const probes = {
      duplicate: ['POST', '/api/fs/duplicate', {json: {}}],
      deleteFolder: ['POST', '/api/fs/delete-folder', {json: {}}],
      chunked: ['GET', '/api/notes-chunked/probe.qnote', {query: {uploadId: 'probe'}}],
      preferences: ['GET', '/api/preferences'],
      tags: ['GET', '/api/tags'],
      search: ['GET', '/api/search'],
      contentSearch: ['POST', '/api/content-search', {json: {q: ''}}],
      pdf: ['GET', '/api/pdf/probe'],
      docx: ['POST', '/api/docx/export', {body: '', type: 'application/vnd.qnote+xml'}],
      settings: ['GET', '/api/settings'],
      bgSettings: ['GET', '/api/bg-settings'],
    };
    const probe = probes[name];
    if (!probe) return false;
    let ok = true;
    try { await this.request(probe[0], probe[1], probe[2] || {}); }
    catch (e) { if (e instanceof VaultError && (e.status === 404 || e.status === 405)) ok = false; }
    this._supports.set(name, ok);
    return ok;
  }

  // ── §2 session ─────────────────────────────────────────────────────────
  session() { return this.get('/api/session'); }
  async login(username, password, extra = {}) {
    const result = await this.post('/api/login', {username, password, token: true, ...extra});
    if (result && typeof result.token === 'string') this.token = result.token;
    return result;
  }
  setup(username, password, token) { return this.post('/api/setup', {username, password, token}); }
  async logout() { try { return await this.post('/api/logout', {}); } finally { this.token = ''; } }

  // ── §3 listing ─────────────────────────────────────────────────────────
  /** @param {{include?: string[]|string, q?: string, tag?: string}} [o] */
  files(o = {}) {
    const include = Array.isArray(o.include) ? o.include.join(',') : o.include;
    return this.get('/api/files', {include, q: o.q, tag: o.tag});
  }

  // ── §4 notes ───────────────────────────────────────────────────────────
  note(path, fileId) { return this.get('/api/notes/' + VaultClient.encodePath(path), {fileId}); }
  saveNote(path, xml, fileId) {
    return this.request('POST', '/api/notes/' + VaultClient.encodePath(path), {body: xml, type: 'application/vnd.qnote+xml', query: {fileId}});
  }
  /** Chunked upload for very large notes; falls back to saveNote when the server lacks it. */
  async saveNoteChunked(path, xml, {chunkSize = 4 * 1024 * 1024, fileId} = {}) {
    if (xml.length <= chunkSize || !(await this.supports('chunked'))) return this.saveNote(path, xml, fileId);
    const uploadId = 'u' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
    const total = Math.ceil(xml.length / chunkSize);
    let result;
    for (let index = 0; index < total; index++) {
      result = await this.post('/api/notes-chunked/' + VaultClient.encodePath(path), {uploadId, index, total, data: xml.slice(index * chunkSize, (index + 1) * chunkSize)});
    }
    return result;
  }

  // ── §5 filesystem ──────────────────────────────────────────────────────
  create(path, overwrite = false) { return this.post('/api/fs/create', {path, overwrite}); }
  createFolder(path) { return this.post('/api/fs/create-folder', {path}); }
  move(from, to) { return this.post('/api/fs/move', {path: from, from, to}); }
  remove(path) { return this.post('/api/fs/delete', {path}); }
  removeFolder(path) { return this.post('/api/fs/delete-folder', {path}); }
  /** Copies a note. Emulated with note()+create()+saveNote() when the server lacks /api/fs/duplicate. */
  async duplicate(from, to) {
    try { return await this.post('/api/fs/duplicate', {path: from, to}); }
    catch (e) {
      if (!(e instanceof VaultError) || e.status !== 404) throw e;
      const source = await this.note(from);
      await this.create(to);
      return this.saveNote(to, typeof source.doc === 'string' ? source.doc : JSON.stringify(source.doc));
    }
  }
  upload(path, blob) { return this.request('POST', '/api/upload', {body: blob, type: 'application/octet-stream', query: {path}}); }

  // ── §6 identity ────────────────────────────────────────────────────────
  fileId(path) { return this.get('/api/file-id', {path}); }
  resolveId(fileId) { return this.get('/api/resolve-id/' + encodeURIComponent(fileId)); }

  // ── §7 whiteboard ──────────────────────────────────────────────────────
  whiteboard(path) { return this.get('/api/whiteboard-notes/' + VaultClient.encodePath(path)); }
  saveWhiteboard(path, doc) { return this.post('/api/whiteboard-notes/' + VaultClient.encodePath(path), {doc}); }
  presets() { return this.get('/api/whiteboard-presets'); }
  savePresets(presets) { return this.post('/api/whiteboard-presets', {presets}); }

  // ── §8 optional ────────────────────────────────────────────────────────
  pdfUrl(fileId) { return this.base + '/api/pdf/' + encodeURIComponent(fileId); }
  savePdf(fileId, bytes) { return this.request('POST', '/api/pdf/' + encodeURIComponent(fileId), {body: bytes, type: 'application/pdf'}); }
  preferences() { return this.get('/api/preferences'); }
  savePreferences(prefs) { return this.post('/api/preferences', prefs); }
  tags() { return this.get('/api/tags'); }
  search({q, tags, type} = {}) {
    const url = new URL(this.base + '/api/search', location.href);
    if (q) url.searchParams.set('q', q);
    for (const t of tags || []) url.searchParams.append('tag', t);
    if (type) url.searchParams.set('type', Array.isArray(type) ? type.join(',') : type);
    return this.request('GET', url.pathname + url.search);
  }
  contentSearch(options) { return this.post('/api/content-search', options); }
  importDocx(path, blob) {
    return this.request('POST', '/api/docx/import', {body: blob, type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', query: {path}});
  }
  exportDocx(xml) { return this.request('POST', '/api/docx/export', {body: xml, type: 'application/vnd.qnote+xml'}); }
  settings() { return this.get('/api/settings'); }
  saveSettings(body) { return this.post('/api/settings', body); }
  bgSettings() { return this.get('/api/bg-settings'); }
  saveBgSettings(body) { return this.post('/api/bg-settings', body); }
}

globalThis.VaultClient = VaultClient;
globalThis.VaultError = VaultError;
