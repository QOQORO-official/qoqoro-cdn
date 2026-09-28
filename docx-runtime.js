/**
 * docx-runtime.js — client-side DOCX <-> QNote conversion, no server round
 * trip. Loads docx.wasm (compiled from the nimdocx Nim library, see
 * `Nim Docx/src/docx_entry.nim`) and talks to it through the same
 * request/call/output/size ABI qnote-nim-wasm's own auxiliary.wasm uses
 * (see qnote-nim-wasm/nim-src/auxiliary_entry.nim and its
 * auxiliary-runtime.js loader, which this mirrors).
 *
 * docx.wasm is fetched with a plain `fetch()` relative to this script's own
 * URL, so it works unmodified both in the plain web/ tree (served as a
 * static file) and in the packaged CDN build, where pack-cdn.mjs bundles
 * every *.wasm into the encrypted QNote.Resources.dll and injects a fetch
 * interceptor (protected-resources.js) ahead of every other script — no
 * special-casing needed here either way.
 *
 * Exposes globalThis.QNoteDocx = { exportDocx(xml), importDocx(bytes) }.
 * Both load and instantiate the module lazily on first call (~3MB), so a
 * page that never opens the DOCX dialog never pays for the download.
 */
(function () {
  const SCRIPT_URL = document.currentScript && document.currentScript.src;
  const WASM_URL = new URL('docx.wasm', SCRIPT_URL || location.href).href;

  // WASI (preview1) shim, ported from qnote-nim-wasm's wasi-shim.js: this
  // reactor does no real I/O, so every syscall below is either a no-op or a
  // fixed-success stub. Kept dependency-free on purpose.
  const WASI_ESUCCESS = 0, WASI_EBADF = 8;
  class ProcExit extends Error { constructor(code) { super('exit ' + code); this.code = code; } }
  function createWasiShim() {
    let memory = null;
    const u8 = () => new Uint8Array(memory.buffer);
    const dv = () => new DataView(memory.buffer);
    function fdWrite(_fd, iovsPtr, iovsLen, nwrittenPtr) {
      const view = dv();
      let total = 0;
      for (let i = 0; i < iovsLen; i++) total += view.getUint32(iovsPtr + i * 8 + 4, true);
      view.setUint32(nwrittenPtr, total, true);
      return WASI_ESUCCESS;
    }
    const impl = {
      proc_exit(code) { throw new ProcExit(code); },
      fd_write: fdWrite,
      fd_read(_fd, _iovs, _n, nreadPtr) { dv().setUint32(nreadPtr, 0, true); return WASI_ESUCCESS; },
      fd_close() { return WASI_ESUCCESS; },
      fd_seek(_fd, _lo, _hi, _w, newOffPtr) {
        if (typeof newOffPtr === 'number') { dv().setUint32(newOffPtr, 0, true); dv().setUint32(newOffPtr + 4, 0, true); }
        return WASI_ESUCCESS;
      },
      fd_fdstat_get(_fd, buf) {
        const v = dv();
        v.setUint8(buf, 2); v.setUint16(buf + 2, 0, true);
        v.setBigUint64(buf + 8, 0xffffffffffffffffn, true);
        v.setBigUint64(buf + 16, 0xffffffffffffffffn, true);
        return WASI_ESUCCESS;
      },
      fd_prestat_get() { return WASI_EBADF; },
      fd_prestat_dir_name() { return WASI_EBADF; },
      args_sizes_get(a, b) { dv().setUint32(a, 0, true); dv().setUint32(b, 0, true); return WASI_ESUCCESS; },
      args_get() { return WASI_ESUCCESS; },
      environ_sizes_get(a, b) { dv().setUint32(a, 0, true); dv().setUint32(b, 0, true); return WASI_ESUCCESS; },
      environ_get() { return WASI_ESUCCESS; },
      clock_time_get(_id, _precision, timePtr) { dv().setBigUint64(timePtr, BigInt(Date.now()) * 1000000n, true); return WASI_ESUCCESS; },
      clock_res_get(_id, resPtr) { dv().setBigUint64(resPtr, 1000000n, true); return WASI_ESUCCESS; },
      random_get(buf, len) {
        const b = u8().subarray(buf, buf + len);
        if (globalThis.crypto && crypto.getRandomValues) {
          for (let o = 0; o < len; o += 65536) crypto.getRandomValues(b.subarray(o, Math.min(o + 65536, len)));
        } else {
          for (let i = 0; i < len; i++) b[i] = (Math.random() * 256) | 0;
        }
        return WASI_ESUCCESS;
      },
      poll_oneoff(_in, _out, _n, neventsPtr) { dv().setUint32(neventsPtr, 0, true); return WASI_ESUCCESS; },
      sched_yield() { return WASI_ESUCCESS; },
    };
    return { impl, setMemory(mem) { memory = mem; } };
  }

  let callPromise = null;
  function loadCall() {
    if (!callPromise) callPromise = instantiate();
    return callPromise;
  }
  /** Like loadCall(), but tags a failure as `.docxUnavailable` so callers can
   * tell "the module couldn't load" (worth falling back to a server) apart
   * from a genuine conversion error thrown by a later call() (not — retrying
   * the same bad input over the network would just fail the same way). */
  async function loadCallSafe() {
    try { return await loadCall(); }
    catch (error) { error.docxUnavailable = true; throw error; }
  }

  async function instantiate() {
    const bytes = await (await fetch(WASM_URL)).arrayBuffer();
    const module = await WebAssembly.compile(bytes);
    const wasi = createWasiShim();
    const instance = await WebAssembly.instantiate(module, {
      env: {
        bindweb_js_flush() { throw Error('DOCX reactor has no DOM access'); },
        bindweb_js_domain_guard() { return 0; },
      },
      wasi_unstable: wasi.impl,
      wasi_snapshot_preview1: wasi.impl,
    });
    const api = instance.exports;
    wasi.setMemory(api.memory);
    try { api._start(); } catch (error) { if (!(error instanceof ProcExit && error.code === 0)) throw error; }
    const encoder = new TextEncoder(), decoder = new TextDecoder();
    let active = false;
    return function call(data) {
      if (active) throw Error('DOCX reactor does not allow reentrant calls');
      active = true;
      try {
        const req = encoder.encode(JSON.stringify(data));
        const ptr = api.qnote_docx_input(req.length);
        if (!ptr) throw Error('DOCX request exceeds capacity');
        new Uint8Array(api.memory.buffer, ptr >>> 0, req.length).set(req);
        api.qnote_docx_call();
        const result = JSON.parse(decoder.decode(new Uint8Array(api.memory.buffer,
          api.qnote_docx_output() >>> 0, api.qnote_docx_size() >>> 0)));
        if (!result.ok) throw Error(result.error);
        return result.value;
      } finally { active = false; }
    };
  }

  function toBase64(bytes) {
    let binary = '';
    for (let i = 0; i < bytes.length; i += 32768) binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
    return btoa(binary);
  }

  globalThis.QNoteDocx = {
    /** QNote XML -> {data: base64 docx, warnings: string[]} (matches the server's /api/docx/export shape). */
    async exportDocx(xml) {
      const call = await loadCallSafe();
      const value = call({action: 'docxExport', xml});
      return {data: value.dataBase64, warnings: value.warnings || []};
    },
    /** .docx bytes (Uint8Array/ArrayBuffer) -> {xml: QNote XML, count: number}. Caller saves `xml` into the vault. */
    async importDocx(bytes) {
      const call = await loadCallSafe();
      const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
      return call({action: 'docxImport', dataBase64: toBase64(arr)});
    },
  };
})();
