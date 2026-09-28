// URL workers cannot be constructed across a CDN origin. A local blob entry
// imports the CDN script; QGraph's boot message supplies its original base URL.
(() => {
  if(!window.Worker)return;const Original=window.Worker;
  window.Worker=new Proxy(Original,{construct(target,args){
    const url=new URL(String(args[0]),document.baseURI);
    if(url.protocol==='blob:'||url.origin===location.origin)return Reflect.construct(target,args);
    const src=args[1]?.type==='module'?'import '+JSON.stringify(url.href)+';':'importScripts('+JSON.stringify(url.href)+');';
    const blob=URL.createObjectURL(new Blob([src],{type:'text/javascript'}));
    try{const w=Reflect.construct(target,[blob,args[1]]),end=w.terminate.bind(w);w.terminate=()=>{URL.revokeObjectURL(blob);end();};return w;}catch(e){URL.revokeObjectURL(blob);throw e;}
  }});
})();
