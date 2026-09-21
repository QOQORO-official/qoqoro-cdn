/* nim-runtime/boot.js — loads stylus.wasm and runs it with the BindWeb runtime.
 * The single-file build sets window.__STYLUS_WASM_BYTES__ instead of a URL. */
(async () => {
  const out = document.getElementById('app');
  const consoleEl = document.getElementById('nim-console');
  const onLog = (msg, kind) => {
    if (!consoleEl) return;
    if (kind !== 'stderr' && kind !== 'error') return; // keep the page quiet unless something is wrong
    const span = document.createElement('span');
    span.className = 'stderr';
    span.textContent = msg + '\n';
    consoleEl.appendChild(span);
  };
  try {
    let bytes = globalThis.__STYLUS_WASM_BYTES__;
    if (bytes) delete globalThis.__STYLUS_WASM_BYTES__;
    else {
      const res = await fetch(window.__APP_WASM_URL__ || 'stylus.wasm', { cache: 'no-store' });
      if (!res.ok) throw new Error('stylus.wasm: HTTP ' + res.status);
      bytes = await res.arrayBuffer();
    }
    const result = await runWasmApp({ wasmBytes: bytes, outputEl: out, onLog, createBindwebRunner, createWasiShim, ProcExit });
    if (!result.ok) throw new Error(result.error || 'WASM start failed');
    globalThis.__STYLUS_READY__ = true;
  } catch (e) {
    onLog('failed to start: ' + ((e && e.message) || e), 'error');
  }
})();
