/* QNote's CDN adapter for QSketch (MIT). Native layout owns all coordinates. */
(() => {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const states = new Map(), geometry = new Map(), payloads = new Map();
  let modulePromise, rendererPromise, active, overlay, bar, stroke, frame = 0, penSeen = false, session = 0;
  const styles = ['Blank', 'Dots', 'Grid', 'Lines', 'Lines + red margin'];
  const refresh = () => window.dispatchEvent(new Event('resize'));
  const decode = text => { try { return text.startsWith('QSK1:') ? JSON.parse(text.slice(5)) : {}; } catch { return {}; } };
  const rgba = n => `rgba(${n>>>24},${n>>>16&255},${n>>>8&255},${(n&255)/255})`;
  function path(E, ptr, count) {
    const p = new Path2D();
    if (!ptr || count < 7) return p;
    const a = new Float32Array(E.memory.buffer, ptr, count);
    for (let i=0; i<count;) {
      const n=a[i++]; if(n<3 || i+n*2>count) break;
      p.moveTo(a[i],a[i+1]);
      for(let k=1;k<n;k++) p.lineTo(a[i+k*2],a[i+k*2+1]);
      p.closePath(); i+=n*2;
    }
    return p;
  }
  async function instance(){
    modulePromise ||= fetch(new URL('qsketch/qsketch.wasm',base)).then(r=>{if(!r.ok)throw Error('QSketch could not load ('+r.status+')');return r.arrayBuffer();}).then(WebAssembly.compile);
    const {exports:E}=await WebAssembly.instantiate(await modulePromise,{});E.qs_init();return E;
  }
  function load(E,meta){if(meta.data){const b=Uint8Array.from(atob(meta.data),c=>c.charCodeAt(0)),p=E.qs_alloc(b.length);new Uint8Array(E.memory.buffer,p,b.length).set(b);if(!E.qs_load(p,b.length))throw Error('Invalid sketch data');}}
  async function state(id, payload='') {
    let s=states.get(id);
    if(s?.payload===payload) return s.ready;
    s={id,payload,meta:decode(payload),paths:[],E:null}; states.set(id,s);
    s.ready=(async()=>{
      // One shared decode engine; only the edited sketch retains its own instance.
      if(!s.meta.data){s.loaded=true;return s;}
      rendererPromise ||= instance();s.E=await rendererPromise;load(s.E,s.meta);
      rebuild(s);s.E=null;s.loaded=true;return s;
    })();
    return s.ready;
  }
  function rebuild(s,invalidate=false){if(invalidate||!s.pathMap)s.pathMap=new Map();s.revision=(s.revision||0)+1;s.paths=[];const E=s.E;for(let i=0;i<E.qs_stroke_count();i++)if(E.qs_stroke_alive(i)){let cached=s.pathMap.get(i);if(!cached){cached={p:path(E,E.qs_stroke_outline_ptr(i),E.qs_stroke_outline_count(i)),color:rgba(E.qs_stroke_color(i)>>>0)};s.pathMap.set(i,cached);}s.paths.push(cached);}}
  function paper(c,m,w,h,z){
    const kind=m.paper||0;if(!kind)return;
    const d=24*z;c.save();c.beginPath();c.rect(0,0,w,h);c.clip();c.strokeStyle='#c4d3e4';c.fillStyle='#b4c5d9';c.lineWidth=Math.max(.5,z*.6);c.beginPath();
    if(kind===1){for(let y=d;y<h;y+=d)for(let x=d;x<w;x+=d){c.moveTo(x+z,y);c.arc(x,y,Math.max(.6,z),0,Math.PI*2);}c.fill();}
    else{for(let y=d;y<h;y+=d){c.moveTo(0,y);c.lineTo(w,y);}if(kind===2)for(let x=d;x<w;x+=d){c.moveTo(x,0);c.lineTo(x,h);}c.stroke();}
    if(kind===4){c.strokeStyle='#d65b6c';c.beginPath();c.moveTo(72*z,0);c.lineTo(72*z,h);c.stroke();}c.restore();
  }
  function scales(g,s){return [g.zoom,g.zoom];}
  function paint(c,g,s,live=false,onlyLive=false){c.save();c.translate(g.x,g.y);if(g.id>=0){if(!onlyLive)paper(c,s.meta,g.w,g.h,g.zoom);}const [sx,sy]=scales(g,s);c.scale(sx,sy);if(!onlyLive)for(const v of s.paths){c.fillStyle=v.color;c.fill(v.p);}if(live&&stroke&&!stroke.erase){s.E.qs_live_update();c.fillStyle=stroke.color;c.fill(path(s.E,s.E.qs_live_outline_ptr(),s.E.qs_live_outline_count()));}c.restore();}
  function draw(c,token,x,y){
    if(typeof token!=='string'||!token.startsWith('QSKETCH:'))return false;
    const g=JSON.parse(token.slice(8));Object.assign(g,{x,y,canvas:c.canvas,payload:payloads.get(g.id)||''});
    if(g.id===-2){c.save();c.translate(x,y);paper(c,states.get(-1)?.payload===g.payload?states.get(-1).meta:decode(g.payload),g.w,g.h,g.zoom);c.restore();return true;}
    geometry.set(g.id,g);
    if(active?.id===g.id && active.payload!==g.payload)close(true);
    const s=states.get(g.id);
    if(s?.payload===g.payload&&s.loaded){if(active?.id!==g.id)paint(c,g,s);else schedule();}
    else state(g.id,g.payload).then(()=>{refresh();if(active?.id===g.id)schedule();}).catch(report);
    return true;
  }
  function report(e){console.error(e);if(bar){const el=bar.querySelector('[data-status]');el.textContent=e.message;}}
  function send(){if(!active)return;const s=active,E=s.E,p=E.qs_save_ptr(),b=new Uint8Array(E.memory.buffer,p,E.qs_save_len());let binary='';for(let i=0;i<b.length;i+=8192)binary+=String.fromCharCode(...b.subarray(i,i+8192));s.meta.data=btoa(binary);s.payload='QSK1:'+JSON.stringify(s.meta);const node=document.getElementById('qnote-misc-action');node.value=JSON.stringify({op:'qsketch-save',id:s.id,payload:s.payload});node.dispatchEvent(new Event('change',{bubbles:true}));}
  function schedule(){if(!frame)frame=requestAnimationFrame(()=>{frame=0;if(!active||!overlay)return;const g=geometry.get(active.id);if(!g)return;const r=g.canvas.getBoundingClientRect(),d=devicePixelRatio||1;Object.assign(overlay.style,{left:r.left+'px',top:r.top+'px',width:r.width+'px',height:r.height+'px'});const w=Math.round(r.width*d),h=Math.round(r.height*d);if(overlay.width!==w||overlay.height!==h){overlay.width=w;overlay.height=h;}const c=overlay.getContext('2d');c.setTransform(d,0,0,d,0,0);c.clearRect(0,0,r.width,r.height);const key=[g.x,g.y,g.w,g.h,g.zoom,w,h,active.revision,active.meta.paper].join(':');if(active.layerKey!==key){active.layerKey=key;active.layer ||= document.createElement('canvas');active.layer.width=w;active.layer.height=h;const b=active.layer.getContext('2d');b.setTransform(d,0,0,d,0,0);paint(b,g,active);}c.drawImage(active.layer,0,0,r.width,r.height);if(stroke&&!stroke.erase)paint(c,g,active,true,true);});}
  const touches=new Map();let gesture=null,navFrame=0,pendingNav=null;
  function touch(e){
    if(e.pointerType!=='touch')return false;
    const vertical=document.getElementById('qnote-scrollbar'),horizontal=document.getElementById('qnote-hscrollbar'),slider=document.getElementById('zoom-slider');
    if(e.type==='pointerdown'){
      touches.set(e.pointerId,{x:e.clientX,y:e.clientY});overlay.setPointerCapture(e.pointerId);
      if(touches.size===2||penSeen){finish(true);const a=[...touches.values()],x=a.reduce((n,p)=>n+p.x,0)/a.length,y=a.reduce((n,p)=>n+p.y,0)/a.length;gesture={x,y,sx:horizontal.scrollLeft,sy:vertical.scrollTop,z:Number(slider.value),d:a.length>1?Math.hypot(a[0].x-a[1].x,a[0].y-a[1].y):0};}
    }else if(e.type==='pointermove'){
      if(touches.has(e.pointerId))touches.set(e.pointerId,{x:e.clientX,y:e.clientY});
      if(gesture){const a=[...touches.values()];if(a.length){const x=a.reduce((n,p)=>n+p.x,0)/a.length,y=a.reduce((n,p)=>n+p.y,0)/a.length;
        const z=a.length===2&&gesture.d?Math.max(Number(slider.min),Math.min(Number(slider.max),Math.round(gesture.z*Math.hypot(a[0].x-a[1].x,a[0].y-a[1].y)/gesture.d))):gesture.z;
        pendingNav={...gesture,xNow:x,yNow:y,zNow:z};if(!navFrame)navFrame=requestAnimationFrame(()=>{navFrame=0;const n=pendingNav;if(!active||!n)return;const r=geometry.get(active.id).canvas.getBoundingClientRect(),ratio=n.zNow/n.z;
          if(Number(slider.value)!==n.zNow){slider.value=String(n.zNow);slider.dispatchEvent(new Event('input',{bubbles:true}));}
          requestAnimationFrame(()=>{if(!active)return;horizontal.scrollLeft=(n.sx+n.x-r.left)*ratio-(n.xNow-r.left);vertical.scrollTop=(n.sy+n.y-r.top)*ratio-(n.yNow-r.top);});
        });
      }}
    }else{touches.delete(e.pointerId);if(gesture){if(!touches.size)gesture=null;return true;}}
    if(gesture){e.preventDefault();return true;}return false;
  }
  function point(e){const g=geometry.get(active.id),r=g.canvas.getBoundingClientRect(),[sx,sy]=scales(g,active);return {x:(e.clientX-r.left-g.x)/sx,y:(e.clientY-r.top-g.y)/sy};}
  function feed(e){if(!stroke)return;for(const v of (e.getCoalescedEvents?.().length?e.getCoalescedEvents():[e])){const p=point(v);if(stroke.erase)active.E.qs_erase(p.x,p.y,Number(bar.querySelector('[data-size]').value)*3);else active.E.qs_add_point(p.x,p.y,v.pointerType==='pen'?Math.max(.01,v.pressure):.5,v.timeStamp);}if(stroke.erase)rebuild(active);schedule();}
  function finish(cancel=false){if(!stroke)return;if(stroke.erase)active.E.qs_erase_end();else if(cancel)active.E.qs_cancel_stroke();else active.E.qs_commit_stroke();const changed=!cancel||stroke.erase;stroke=null;rebuild(active);if(changed)send();schedule();}
  function close(discard=false){session++;pendingNav=null;touches.clear();gesture=null;if(discard&&stroke){if(stroke.erase)active.E.qs_erase_end();else active.E.qs_cancel_stroke();stroke=null;}else finish();if(active){active.E=null;active.layer=null;active.layerKey=null;}active=null;overlay?.remove();bar?.remove();overlay=bar=null;refresh();}
  async function open(data){
    if(active?.id===data.id){close();return;}close();const ticket=session;
    try{const selected=await state(data.id,data.payload),E=await instance();if(ticket!==session)return;active=selected;active.E=E;load(active.E,active.meta);if(!geometry.has(data.id)){refresh();await new Promise(r=>setTimeout(r,80));}const g=geometry.get(data.id);if(!g)throw Error('The drawing container is not visible');
      active.meta.width ||= g.w/g.zoom;active.meta.height ||= g.h/g.zoom;
      document.getElementById('qm-input')?.blur();
      bar=document.createElement('section');bar.id='qnote-qsketch-tools';bar.setAttribute('aria-label','Drawing tools');
      bar.style.cssText='position:fixed;bottom:64px;left:50%;transform:translateX(-50%);z-index:9000;display:flex;flex-wrap:wrap;align-items:center;gap:6px;max-width:calc(100vw - 24px);width:max-content;padding:10px;background:var(--q-theme-surface,#fff);color:var(--q-popup-ink,#172033);border:1px solid #ccd3df;border-radius:12px;box-shadow:0 4px 20px #0003;font:14px system-ui';
      bar.innerHTML='<strong data-status></strong><select aria-label="Brush" data-brush><option value="0">Pen</option><option value="1">Calligraphy</option><option value="2">Marker</option><option value="erase">Eraser</option></select><input type="color" value="#202530" aria-label="Ink color" data-color><input type="range" min="1" max="30" value="3" aria-label="Pen width" data-size style="width:75px"><button data-undo>Undo</button><button data-redo>Redo</button><select aria-label="Paper style" data-paper></select><button data-done>Done</button>';
      for(const control of bar.querySelectorAll('button,select,input[type=color]'))control.style.cssText+=';min-height:34px;border:1px solid var(--q-popup-border,#ccd3df);border-radius:6px;background:var(--q-theme-surface,#fff);color:inherit;padding:4px 8px;font:inherit';
      bar.querySelector('[data-status]').textContent=data.id<0?'Drawing Mode':'Anchored sketch';const select=bar.querySelector('[data-paper]');styles.forEach((v,i)=>select.add(new Option(v,String(i))));select.value=String(active.meta.paper||0);select.onchange=()=>{active.meta.paper=Number(select.value);send();schedule();};
      bar.querySelector('[data-undo]').onclick=()=>{finish(true);active.E.qs_undo();rebuild(active,true);send();schedule();};bar.querySelector('[data-redo]').onclick=()=>{active.E.qs_redo();rebuild(active,true);send();schedule();};bar.querySelector('[data-done]').onclick=close;
      overlay=document.createElement('canvas');overlay.id='qnote-qsketch-canvas';overlay.style.cssText='position:fixed;z-index:100;touch-action:none;cursor:crosshair';
      overlay.onpointerdown=e=>{if(touch(e))return;if(stroke)return;const p=point(e);e.preventDefault();if(e.pointerType==='pen')penSeen=true;overlay.setPointerCapture(e.pointerId);const tool=bar.querySelector('[data-brush]').value,hex=bar.querySelector('[data-color]').value;stroke={pointer:e.pointerId,erase:tool==='erase'||e.button===5,color:hex};if(stroke.erase)active.E.qs_erase_begin();else active.E.qs_begin_stroke((parseInt(hex.slice(1),16)*256+(tool==='2'?90:255))>>>0,Number(bar.querySelector('[data-size]').value),.2,1,.4,tool==='1'?1:0,.707,.707,.25,0);feed(e);};
      overlay.onpointermove=e=>{if(touch(e))return;if(stroke?.pointer===e.pointerId){e.preventDefault();feed(e);}};overlay.onpointerup=e=>{if(touch(e))return;if(stroke?.pointer===e.pointerId){feed(e);finish();}};overlay.onpointercancel=e=>{touch(e);finish(true);};overlay.onlostpointercapture=()=>finish(true);
      overlay.onwheel=e=>{e.preventDefault();const g=geometry.get(active.id);g.canvas.dispatchEvent(new WheelEvent('wheel',{deltaX:e.deltaX,deltaY:e.deltaY,ctrlKey:e.ctrlKey,bubbles:true,clientX:e.clientX,clientY:e.clientY}));};
      document.body.append(overlay,bar);schedule();refresh();
    }catch(e){close();console.error(e);alert(e.message);}
  }
  window.addEventListener('resize',schedule);window.addEventListener('scroll',schedule,true);window.addEventListener('keydown',e=>{if(active&&e.key==='Escape'){e.preventDefault();close();}});
  document.addEventListener('change',e=>{if(e.target.id==='qnote-file-buffer'){close(true);states.clear();geometry.clear();}},true);
  document.addEventListener('click',e=>{if(active&&e.target.closest('#btn-print'))close();},true);
  window.QNoteSketch={open,draw,close,payload:(id,text)=>payloads.set(id,text),get target(){if(!active)return null;const g=geometry.get(active.id);return g?{id:g.id,x:g.x,y:g.y,width:g.w,height:g.h,zoom:g.zoom}:null;}};
})();
