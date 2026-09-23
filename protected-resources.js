(function (config) {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const nativeFetch = globalThis.fetch.bind(globalThis);
  const bytes = value => Uint8Array.from(atob(value), c => c.charCodeAt(0));
  const paths = new Set(config.paths.map(p => new URL(p, base).href));
  const ready = (async () => {
    if (!globalThis.crypto?.subtle) throw Error('Protected resources require HTTPS or localhost.');
    const response = await nativeFetch(new URL('QNote.Resources.dll?v=' + config.digest, base));
    if (!response.ok) throw Error('Cannot load QNote.Resources.dll: ' + response.status);
    const data = new Uint8Array(await response.arrayBuffer());
    if (new TextDecoder().decode(data.slice(0, 4)) !== 'QVR2') throw Error('Invalid resource bundle');
    const key = await crypto.subtle.importKey('raw', bytes(config.key), 'AES-GCM', false, ['decrypt']);
    const sealed = new Uint8Array(data.length - 16);
    sealed.set(data.subarray(32)); sealed.set(data.subarray(16, 32), data.length - 32);
    const compressed = await crypto.subtle.decrypt({name:'AES-GCM', iv:data.slice(4,16)}, key, sealed);
    const stream = new Blob([compressed]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    const entries = JSON.parse(await new Response(stream).text());
    const urls = {};
    for (const [name, value] of Object.entries(entries)) {
      urls[new URL(name, base).href] = URL.createObjectURL(new Blob([bytes(value)], {
        type: name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream'
      }));
    }
    return urls;
  })();
  function installFetch(scope, mapping, known, fallbackBase) {
    const original = scope.fetch.bind(scope);
    scope.fetch = async function(input, options) {
      const url = new URL(input instanceof Request ? input.url : String(input), fallbackBase);
      url.search = ''; url.hash = '';
      if (!known.includes(url.href)) return original(input, options);
      const urls = await mapping;
      const request = input instanceof Request ? new Request(urls[url.href], input) : urls[url.href];
      return original(request, options);
    };
  }
  installFetch(globalThis, ready, [...paths], document.baseURI);
  const NativeWorker = globalThis.Worker;
  if (NativeWorker) {
    globalThis.Worker = class extends NativeWorker {
      constructor(url, options) {
        const target = new URL(String(url), document.baseURI).href;
        const token = 'qoqoro-resources-' + crypto.randomUUID();
        const prelude = `const resourceMap=new Promise(resolve=>{addEventListener('message',function receive(e){if(e.data?.token!==${JSON.stringify(token)})return;e.stopImmediatePropagation();removeEventListener('message',receive);resolve(e.data.urls);});});(${installFetch.toString()})(globalThis,resourceMap,${JSON.stringify([...paths])},${JSON.stringify(document.baseURI)});`;
        const code = options?.type === 'module' ? prelude + `await import(${JSON.stringify(target)});` : prelude + `importScripts(${JSON.stringify(target)});`;
        const wrapper = URL.createObjectURL(new Blob([code], {type:'text/javascript'}));
        super(wrapper, options);
        ready.then(urls => this.postMessage({token, urls}), error => { this.terminate(); console.error(error); });
        // Worker URLs remain valid for the worker lifetime, including delayed startup.
        const terminate = this.terminate.bind(this);
        this.terminate = () => { URL.revokeObjectURL(wrapper); terminate(); };
      }
    };
  }
  ready.catch(error => {
    console.error('[QOQORO resources]', error);
    const show = () => { const p=document.createElement('p');p.setAttribute('role','alert');p.textContent='Unable to load protected resources: '+error.message;document.body.prepend(p); };
    if(document.body)show();else document.addEventListener('DOMContentLoaded',show,{once:true});
  });
})({"key":"5gVjfCofST1A8riSxN/a2A0JQ2YEZXQhcusblnfrQRg=","paths":["qnote/app.wasm","qnote/auxiliary.wasm","qnote/layout.wasm","qnote/nim-runtime/decoder.wasm","qnote/nim-runtime/runtime.bin","qnote/vendor/luau/luau-web.js","recto/app.wasm","stylus/stylus.wasm"],"digest":"38f4bb41f270886990778d99ee42ae321edb3d883a4189a3a01944e27cc9884e"});
