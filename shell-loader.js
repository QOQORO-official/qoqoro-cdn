// Generated deployment loader; application source lives in shell-src/.
(function (config) {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const ready = (async () => {
    const get = async name => {
      const r = await fetch(new URL(name + '?v=' + config.build, base));
      if (!r.ok) throw Error('Cannot load ' + name + ': ' + r.status);
      return new Uint8Array(await r.arrayBuffer());
    };
    const resource = await get('QOQORO.Shell.dll');
    if (resource.length < 8 || String.fromCharCode(...resource.subarray(0,4)) !== 'QSH1')
      throw Error('Invalid workspace resource DLL');
    const wasmSize = new DataView(resource.buffer, resource.byteOffset, resource.byteLength).getUint32(4,true);
    const payloadStart = 8 + wasmSize;
    if (!wasmSize || wasmSize > 1024*1024 || resource.length - payloadStart < 12 || resource.length - payloadStart > 2*1024*1024)
      throw Error('Invalid workspace resource DLL size');
    const wasm = resource.subarray(8,payloadStart), data = resource.subarray(payloadStart);
    const {instance} = await WebAssembly.instantiate(wasm, {});
    const e = instance.exports;
    e.NimMain();
    const p = e.payload_buffer(data.length);
    if (!p) throw Error('Invalid workspace payload size');
    const bytes = new Uint8Array(e.memory.buffer, p, data.length);
    try {
      bytes.set(data);
      const n = e.payload_decode(data.length);
      if (n !== data.length - 12) throw Error('Workspace bundle integrity check failed. Reload the page.');
      return JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(bytes.subarray(12)));
    } finally { bytes.fill(0); resource.fill(0); }
  })();
  // Attach a handler immediately; the first script job supplies the visible error.
  ready.catch(() => {});
  const done = new Set();
  globalThis.__qoqoroLoadShell = async function load(name) {
    if (done.has(name)) return;
    if (name === 'admin.js') await load('admin-i18n.js');
    const sources = await ready;
    if (typeof sources[name] !== 'string') throw Error('Unknown workspace script: ' + name);
    const url = URL.createObjectURL(new Blob([sources[name]], {type:'text/javascript'}));
    const script = document.createElement('script');
    script.dataset.source = new URL(name, base).href;
    script.src = url;
    try {
      await new Promise((resolve, reject) => {
        script.onload = resolve;
        script.onerror = () => reject(Error('Cannot start workspace script: ' + name));
        document.head.append(script);
      });
      done.add(name);
      delete sources[name];
    } finally { script.remove(); URL.revokeObjectURL(url); }
  };
})({"build":"f8b626991e4a2d92"});
