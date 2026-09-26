/* QNote's CDN adapter for QSketch (MIT). Native layout owns all coordinates. */
(() => {
  'use strict';
  const base = new URL('.', document.currentScript.src);
  const states = new Map(), geometry = new Map(), payloads = new Map();
  let modulePromise, rendererPromise, active, overlay, bar, panel, stroke, selection = null;
  let frame = 0, penSeen = false, penDown = false, lastPenAt = -Infinity;
  try { penSeen = localStorage.getItem('qnote.qsketch.penDetected') === '1'; } catch {}
  let session = 0, lastTap = null, pendingTap = null;
  const styles = ['Blank', 'Dots', 'Grid', 'Lines', 'Lines + red margin'];
  const brushDefaults = {
    ballpoint: {size:3,minSize:.70,stabilizer:0,streamline:.08,smoothing:.07,opacity:1,nibAngle:45},
    fountain: {size:5,minSize:.20,stabilizer:0,streamline:.15,smoothing:.12,opacity:1,nibAngle:45},
    calligraphy: {size:14,minSize:.85,stabilizer:.30,streamline:.20,smoothing:.10,opacity:1,nibAngle:45},
    marker: {size:18,minSize:.85,stabilizer:0,streamline:.12,smoothing:.10,opacity:.55,nibAngle:45}
  };
  const settingDefaults = () => ({brush:'fountain',color:'#202530',brushes:structuredClone(brushDefaults),eraserSize:24,pressure:true,curve:0,fingers:'auto',penButtonErase:true,lowLatency:false});
  const settingKey='qnote.qsketch.brush.v1';
  function readSettings(){
    const value=settingDefaults();
    try {const saved=JSON.parse(localStorage.getItem(settingKey)||'{}');
      for(const key of ['brush','color','eraserSize','pressure','curve','fingers','penButtonErase','lowLatency'])if(saved[key]!==undefined)value[key]=saved[key];
      for(const key of Object.keys(brushDefaults))Object.assign(value.brushes[key],saved.brushes?.[key]||{});
    } catch(e){console.warn('QSketch settings unavailable',e);}
    return value;
  }
  let settings=readSettings();
  const persistSettings=()=>{try{localStorage.setItem(settingKey,JSON.stringify(settings));}catch{}};
  const brush=()=>settings.brushes[settings.brush]||settings.brushes.fountain;
  const pressure=p=>Math.pow(Math.max(0,Math.min(1,p)),Math.pow(3,settings.curve));
  const nib=()=>{const a=brush().nibAngle*Math.PI/180;return [Math.cos(a),-Math.sin(a)];};
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
  function setPagePattern(value){
    const paper=Math.max(0,Math.min(4,Number(value)||0));
    if(active?.id===-1){active.meta.paper=paper;send();schedule();return;}
    const meta=decode(payloads.get(-1)||'');meta.paper=paper;
    const node=document.getElementById('qnote-misc-action');
    node.value=JSON.stringify({op:'qsketch-save',id:-1,payload:'QSK1:'+JSON.stringify(meta)});
    node.dispatchEvent(new Event('change',{bubbles:true}));
  }
  function selectBounds(){
    if(!active?.E?.qs_selection_count())return null;
    const E=active.E,p=E.qs_selection_bounds(),a=new Float32Array(E.memory.buffer,p,4);
    return {minx:a[0],miny:a[1],maxx:a[2],maxy:a[3]};
  }
  function updateSelection(){
    selection=selectBounds();
    if(bar){bar.querySelector('[data-delete]').disabled=!selection;bar.querySelector('[data-duplicate]').disabled=!selection;}
    schedule();
  }
  function selectionAction(action){
    if(!active||!selection)return;
    if(action==='delete')active.E.qs_selection_delete();
    if(action==='duplicate')active.E.qs_selection_duplicate(24/geometry.get(active.id).zoom,24/geometry.get(active.id).zoom);
    rebuild(active,true);send();updateSelection();
  }
  const controlStyle='min-height:34px;border:1px solid var(--q-popup-border,#ccd3df);border-radius:6px;background:var(--q-theme-surface,#fff);color:inherit;padding:4px 8px;font:inherit';
  function closeSettings(){panel?.remove();panel=null;bar?.querySelector('[data-settings]')?.setAttribute('aria-expanded','false');}
  function refreshBrushControls(){
    if(!bar)return;
    const tool=bar.querySelector('[data-brush]').value;
    bar.querySelector('[data-size]').value=tool==='erase'?settings.eraserSize:brush().size;
    if(panel){panel.querySelector('[data-current-brush]').textContent=tool==='erase'?'Eraser':bar.querySelector('[data-brush]').selectedOptions[0].text;
      panel.querySelector('[data-nib-row]').style.display=settings.brush==='calligraphy'&&tool!=='erase'?'grid':'none';
      panel.querySelector('[data-row="size"]').style.display=tool==='erase'?'none':'grid';
      panel.querySelector('[data-row="eraserSize"]').style.display=tool==='erase'?'grid':'none';
      for(const input of panel.querySelectorAll('[data-setting]')){
        const key=input.dataset.setting,value=key in settings?settings[key]:brush()[key];
        if(input.type==='checkbox')input.checked=!!value;else input.value=String(value);
        input.closest('label')?.querySelector('output')?.replaceChildren(document.createTextNode(settingLabel(key,value)));
      }
      panel.querySelector('[data-color]').value=settings.color;
      panel.querySelector('[data-finger-note]').textContent=settings.fingers==='auto'?(penSeen?'Pen detected: palm movement is ignored; brief taps can undo. Choose Pan & zoom for deliberate navigation.':'Fingers draw until a pen is detected; then palm movement is ignored.'):settings.fingers==='draw'?'One finger draws when the pen is away; two fingers pan and zoom.':'Fingers pan and zoom when the pen is away.';
      drawPressureCurve();
    }
  }
  function settingLabel(key,value){
    if(key==='stabilizer')return value?Math.round(value*80)+' px':'Off';
    if(key==='nibAngle')return Math.round(value)+'°';
    if(key==='eraserSize'||key==='size')return Math.round(value)+' px';
    if(key==='curve')return Math.abs(value)<.05?'Linear':(value<0?'Soft ':'Firm ')+Math.round(Math.abs(value)*100)+'%';
    return Math.round(value*100)+'%';
  }
  function drawPressureCurve(){
    const canvas=panel?.querySelector('[data-curve-canvas]');if(!canvas)return;
    const c=canvas.getContext('2d'),w=canvas.width,h=canvas.height;
    c.clearRect(0,0,w,h);c.strokeStyle='#526074';c.lineWidth=1;
    for(let i=0;i<=4;i++){const x=i*w/4,y=i*h/4;c.beginPath();c.moveTo(x,0);c.lineTo(x,h);c.moveTo(0,y);c.lineTo(w,y);c.stroke();}
    c.beginPath();c.strokeStyle='#6b86ff';c.lineWidth=3;
    for(let i=0;i<=64;i++){const p=i/64,v=brush().minSize+(1-brush().minSize)*(settings.pressure?pressure(p):1);if(i)c.lineTo(i*w/64,h-v*h);else c.moveTo(0,h-v*h);}c.stroke();
  }
  function openSettings(){
    if(panel){closeSettings();return;}
    panel=document.createElement('aside');panel.id='qnote-qsketch-settings';panel.setAttribute('aria-label','Brush settings');
    panel.style.cssText='position:fixed;z-index:9001;right:12px;top:72px;width:min(350px,calc(100vw - 24px));max-height:calc(100dvh - 145px);overflow:auto;padding:16px;background:var(--q-theme-surface,#fff);color:var(--q-popup-ink,#172033);border:1px solid var(--q-popup-border,#ccd3df);border-radius:12px;box-shadow:0 12px 36px #0004;font:13px system-ui';
    panel.innerHTML=`<div style="display:flex;justify-content:space-between;align-items:center"><strong>Brush · <span data-current-brush></span></strong><button data-close aria-label="Close brush settings">×</button></div>
      <label style="display:grid;gap:5px;margin:12px 0">Ink color<input type="color" data-color aria-label="Ink color"></label>
      <div data-sliders></div>
      <h3 style="font-size:12px;margin:18px 0 8px">PRESSURE</h3>
      <label style="display:flex;justify-content:space-between;gap:8px">Pressure sensitivity<input type="checkbox" data-setting="pressure"></label>
      <canvas data-curve-canvas width="288" height="94" style="display:block;width:100%;height:94px;margin:10px 0;background:#1a1e28;border-radius:6px"></canvas>
      <div style="display:flex;justify-content:space-between">Pen now <span data-pressure-now>—</span></div>
      <progress data-pressure-bar max="1" value="0" style="width:100%;height:5px"></progress>
      <h3 style="font-size:12px;margin:18px 0 8px">TOUCH & PEN</h3>
      <label style="display:grid;gap:5px">Fingers<select data-setting="fingers"><option value="auto">Auto</option><option value="draw">Draw</option><option value="navigate">Pan & zoom</option></select></label>
      <small data-finger-note style="display:block;margin:6px 0 12px;opacity:.7"></small>
      <label style="display:flex;justify-content:space-between;gap:8px;margin:10px 0">Pen button erases<input type="checkbox" data-setting="penButtonErase"></label>
      <label style="display:flex;justify-content:space-between;gap:8px;margin:10px 0">Low latency ink<input type="checkbox" data-setting="lowLatency"></label>
      <small style="display:block;opacity:.7">Low latency applies when the drawing session is reopened. It may flicker on some phones.</small>
      <small style="display:block;margin:12px 0;opacity:.7">Two-finger tap or double-tap to undo · three-finger tap to redo in finger modes. Touch is ignored while the pen is in use.</small>
      <button data-reset style="width:100%;margin-top:8px">Reset brushes & settings</button>`;
    const ranges=[['size','Size','Brush width',1,60,1],['eraserSize','Eraser size','Eraser radius in screen pixels',2,80,1],['stabilizer','Stabilizer','Ink trails the pen on a string',0,1,.01],['streamline','StreamLine','Pulls the line behind the nib',0,1,.01],['smoothing','Smoothing','Evens out the finished path',0,1,.01],['opacity','Opacity','Transparent ink',.05,1,.01],['nibAngle','Nib angle','Edge direction',0,180,1],['curve','Curve','Pressure response',-1,1,.01],['minSize','Min size','Size at the lightest touch',.05,1,.01]];
    const rows=panel.querySelector('[data-sliders]');let pressureAfter=panel.querySelector('[data-pressure-bar]');
    for(const [key,title,description,min,max,step] of ranges){const label=document.createElement('label');label.dataset.row=key;
      if(key==='nibAngle')label.dataset.nibRow='';
      label.style.cssText='display:grid;gap:3px;margin:12px 0';
      label.innerHTML=`<span style="display:flex;justify-content:space-between"><strong>${title}</strong><output></output></span><small style="opacity:.7">${description}</small><input type="range" data-setting="${key}" min="${min}" max="${max}" step="${step}">`;
      if(key==='curve'||key==='minSize'){pressureAfter.insertAdjacentElement('afterend',label);pressureAfter=label;}
      else rows.appendChild(label);
    }
    for(const el of panel.querySelectorAll('button,select,input[type=color]'))el.style.cssText+=';'+controlStyle;
    panel.querySelector('[data-close]').onclick=closeSettings;
    panel.querySelector('[data-reset]').onclick=()=>{const selected=settings.brush;settings=settingDefaults();settings.brush=selected;persistSettings();refreshBrushControls();};
    panel.querySelector('[data-color]').oninput=e=>{settings.color=e.target.value;persistSettings();};
    for(const input of panel.querySelectorAll('[data-setting]')){
      const change=()=>{const key=input.dataset.setting,value=input.type==='checkbox'?input.checked:input.type==='range'?Number(input.value):input.value;
        if(key in settings)settings[key]=value;else brush()[key]=value;
        persistSettings();refreshBrushControls();};
      input.addEventListener(input.type==='range'?'input':'change',change);
    }
    document.body.appendChild(panel);
    bar.querySelector('[data-settings]').setAttribute('aria-expanded','true');
    refreshBrushControls();
  }
  function drawSelection(c,g){
    const z=g.zoom;
    if(selection){const x=g.x+selection.minx*z,y=g.y+selection.miny*z,w=(selection.maxx-selection.minx)*z,h=(selection.maxy-selection.miny)*z;
      c.save();c.strokeStyle='#718aff';c.lineWidth=1.5;c.setLineDash([6,4]);c.strokeRect(x-5,y-5,w+10,h+10);c.setLineDash([]);
      for(const [hx,hy] of [[x+w+5,y+h+5],[x+w/2,y-24]]){c.fillStyle='#fff';c.beginPath();c.arc(hx,hy,6,0,Math.PI*2);c.fill();c.stroke();}c.restore();
    }
    if(stroke?.lasso?.op==='lasso'&&stroke.lasso.points.length){c.save();c.beginPath();stroke.lasso.points.forEach(([x,y],i)=>{if(i)c.lineTo(g.x+x*z,g.y+y*z);else c.moveTo(g.x+x*z,g.y+y*z);});c.strokeStyle='#718aff';c.fillStyle='#718aff22';c.setLineDash([5,4]);c.stroke();c.fill();c.restore();}
    if(stroke?.lasso?.op==='move'&&selection){const p=stroke.lasso,dx=(p.last.x-p.start.x)*z,dy=(p.last.y-p.start.y)*z;c.save();c.strokeStyle='#718aff';c.setLineDash([5,4]);c.strokeRect(g.x+selection.minx*z+dx,g.y+selection.miny*z+dy,(selection.maxx-selection.minx)*z,(selection.maxy-selection.miny)*z);c.restore();}
  }
  function schedule(){if(!frame)frame=requestAnimationFrame(()=>{frame=0;if(!active||!overlay)return;const g=geometry.get(active.id);if(!g)return;const r=g.canvas.getBoundingClientRect(),d=devicePixelRatio||1;Object.assign(overlay.style,{left:r.left+'px',top:r.top+'px',width:r.width+'px',height:r.height+'px'});const w=Math.round(r.width*d),h=Math.round(r.height*d);if(overlay.width!==w||overlay.height!==h){overlay.width=w;overlay.height=h;}const c=overlay.getContext('2d');c.setTransform(d,0,0,d,0,0);c.clearRect(0,0,r.width,r.height);const key=[g.x,g.y,g.w,g.h,g.zoom,w,h,active.revision,active.meta.paper].join(':');if(active.layerKey!==key){active.layerKey=key;active.layer ||= document.createElement('canvas');active.layer.width=w;active.layer.height=h;const b=active.layer.getContext('2d');b.setTransform(d,0,0,d,0,0);paint(b,g,active);}c.drawImage(active.layer,0,0,r.width,r.height);if(stroke&&!stroke.erase&&!stroke.lasso)paint(c,g,active,true,true);drawSelection(c,g);});}
  const touches=new Map(),autoTaps=new Map(),suppressedTouches=new Set();
  let gesture=null,navFrame=0,pendingNav=null,navEpoch=0;
  let autoTapCount=0,autoTapStarted=0,autoTapMoved=false;
  function autoTouch(e){
    e.preventDefault();e.stopPropagation();
    if(e.type==='pointerdown'){
      if(!autoTaps.size){autoTapCount=0;autoTapStarted=performance.now();autoTapMoved=false;}
      autoTaps.set(e.pointerId,{x:e.clientX,y:e.clientY});autoTapCount=Math.max(autoTapCount,autoTaps.size);
      try{overlay.setPointerCapture(e.pointerId);}catch{}
    }else if(e.type==='pointermove'){
      const start=autoTaps.get(e.pointerId);
      if(start&&Math.hypot(e.clientX-start.x,e.clientY-start.y)>12)autoTapMoved=true;
    }else if(autoTaps.has(e.pointerId)){
      autoTaps.delete(e.pointerId);
      if(!autoTaps.size){
        const tap=e.type==='pointerup'&&!autoTapMoved&&performance.now()-autoTapStarted<280;
        if(tap&&autoTapCount===2)doUndo();
        else if(tap&&autoTapCount>=3)doRedo();
        else if(tap&&autoTapCount===1){
          if(lastTap&&performance.now()-lastTap.time<300&&Math.hypot(e.clientX-lastTap.x,e.clientY-lastTap.y)<32){lastTap=null;doUndo();}
          else lastTap={x:e.clientX,y:e.clientY,time:performance.now()};
        }
        autoTapCount=0;
      }
    }
    return true;
  }
  function cancelTouchNavigation(){
    navEpoch++;pendingNav=null;
    if(gesture){const vertical=document.getElementById('qnote-scrollbar'),horizontal=document.getElementById('qnote-hscrollbar'),slider=document.getElementById('zoom-slider');
      if(vertical&&horizontal&&slider){slider.value=String(gesture.z);slider.dispatchEvent(new Event('input',{bubbles:true}));horizontal.scrollLeft=gesture.sx;vertical.scrollTop=gesture.sy;}}
    gesture=null;
    for(const id of touches.keys())suppressedTouches.add(id);
    for(const id of autoTaps.keys())suppressedTouches.add(id);
    touches.clear();
    autoTaps.clear();autoTapCount=0;
    if(stroke?.pointerType==='touch')finish(true);
  }
  function markPen(down=false){
    const first=!penSeen;
    penSeen=true;penDown=penDown||down;lastPenAt=performance.now();
    if(first)try{localStorage.setItem('qnote.qsketch.penDetected','1');}catch{}
    if(touches.size||autoTaps.size||gesture||stroke?.pointerType==='touch')cancelTouchNavigation();
    if(first)refreshBrushControls();
  }
  const penGuard=()=>penDown||performance.now()-lastPenAt<500;
  function doUndo(){if(!active)return;finish(true);if(active.E.qs_undo()){active.E.qs_select_clear();selection=null;rebuild(active,true);send();updateSelection();}}
  function doRedo(){if(!active)return;finish(true);if(active.E.qs_redo()){active.E.qs_select_clear();selection=null;rebuild(active,true);send();updateSelection();}}
  function touch(e){
    if(e.pointerType!=='touch')return false;
    if(e.type==='pointerdown'){
      // A palm is normally reported as a broad touch, but some digitizers
      // report it as a narrow point. The pen guard handles those devices.
      const palm=Math.max(e.width||0,e.height||0)>28;
      if(palm||penGuard()){
        suppressedTouches.add(e.pointerId);e.preventDefault();e.stopPropagation();return true;
      }
    }
    if(suppressedTouches.has(e.pointerId)){
      if(e.type==='pointerup'||e.type==='pointercancel')suppressedTouches.delete(e.pointerId);
      e.preventDefault();e.stopPropagation();return true;
    }
    if(penSeen&&settings.fingers==='auto')return autoTouch(e);
    const vertical=document.getElementById('qnote-scrollbar'),horizontal=document.getElementById('qnote-hscrollbar'),slider=document.getElementById('zoom-slider');
    if(e.type==='pointerdown'){
      touches.set(e.pointerId,{x:e.clientX,y:e.clientY});try{overlay.setPointerCapture(e.pointerId);}catch{}
      if(touches.size>=2||settings.fingers==='navigate'){finish(true);const a=[...touches.values()],x=a.reduce((n,p)=>n+p.x,0)/a.length,y=a.reduce((n,p)=>n+p.y,0)/a.length;gesture={x,y,sx:horizontal.scrollLeft,sy:vertical.scrollTop,z:Number(slider.value),d:a.length>1?Math.hypot(a[0].x-a[1].x,a[0].y-a[1].y):0,start:performance.now(),count:a.length,moved:false};}
    }else if(e.type==='pointermove'){
      if(touches.has(e.pointerId))touches.set(e.pointerId,{x:e.clientX,y:e.clientY});
      if(gesture){const a=[...touches.values()];if(a.length){const x=a.reduce((n,p)=>n+p.x,0)/a.length,y=a.reduce((n,p)=>n+p.y,0)/a.length;
        const z=a.length===2&&gesture.d?Math.max(Number(slider.min),Math.min(Number(slider.max),Math.round(gesture.z*Math.hypot(a[0].x-a[1].x,a[0].y-a[1].y)/gesture.d))):gesture.z;
        if(Math.hypot(x-gesture.x,y-gesture.y)>8||Math.abs(z-gesture.z)>2)gesture.moved=true;
        pendingNav={...gesture,xNow:x,yNow:y,zNow:z,epoch:navEpoch};if(!navFrame)navFrame=requestAnimationFrame(()=>{navFrame=0;const n=pendingNav;if(!active||!n||n.epoch!==navEpoch||penGuard())return;const r=geometry.get(active.id).canvas.getBoundingClientRect(),ratio=n.zNow/n.z;
          if(Number(slider.value)!==n.zNow){slider.value=String(n.zNow);slider.dispatchEvent(new Event('input',{bubbles:true}));}
          requestAnimationFrame(()=>{if(!active||n.epoch!==navEpoch||penGuard())return;horizontal.scrollLeft=(n.sx+n.x-r.left)*ratio-(n.xNow-r.left);vertical.scrollTop=(n.sy+n.y-r.top)*ratio-(n.yNow-r.top);});
        });
      }}
    }else{touches.delete(e.pointerId);if(gesture){if(!touches.size){const tap=!gesture.moved&&performance.now()-gesture.start<280;const count=gesture.count;gesture=null;if(tap&&count===2)doUndo();else if(tap&&count>=3)doRedo();else if(tap&&count===1)lastTap={x:e.clientX,y:e.clientY,time:performance.now()};}return true;}}
    if(gesture){e.preventDefault();return true;}return false;
  }
  function point(e){const g=geometry.get(active.id),r=g.canvas.getBoundingClientRect(),[sx,sy]=scales(g,active);return {x:(e.clientX-r.left-g.x)/sx,y:(e.clientY-r.top-g.y)/sy};}
  function startLasso(e){
    const p=point(e),z=geometry.get(active.id).zoom,near=(x,y)=>Math.hypot(p.x-x,p.y-y)<12/z;
    let op='lasso',pivot=null;
    if(selection){
      const b=selection;
      if(near(b.maxx+5/z,b.maxy+5/z)){op='scale';pivot={x:b.minx,y:b.miny};}
      else if(near((b.minx+b.maxx)/2,b.miny-24/z)){op='rotate';pivot={x:(b.minx+b.maxx)/2,y:(b.miny+b.maxy)/2};}
      else if(p.x>=b.minx-5/z&&p.x<=b.maxx+5/z&&p.y>=b.miny-5/z&&p.y<=b.maxy+5/z){op='move';pivot={x:b.minx,y:b.miny};}
      else {active.E.qs_select_clear();selection=null;updateSelection();}
    }
    stroke={pointer:e.pointerId,pointerType:e.pointerType,startTime:performance.now(),lasso:{op,start:p,last:p,pivot,points:[[p.x,p.y]]}};
  }
  function feed(e){
    if(!stroke)return;
    for(const v of (e.getCoalescedEvents?.().length?e.getCoalescedEvents():[e])){
      const p=point(v);
      if(stroke.lasso){const L=stroke.lasso;L.last=p;if(L.op==='lasso'){const q=L.points.at(-1);if(Math.hypot((p.x-q[0])*geometry.get(active.id).zoom,(p.y-q[1])*geometry.get(active.id).zoom)>3)L.points.push([p.x,p.y]);}}
      else if(stroke.erase)active.E.qs_erase(p.x,p.y,settings.eraserSize/geometry.get(active.id).zoom);
      else {stroke.distance=Math.max(stroke.distance||0,Math.hypot(p.x-stroke.start.x,p.y-stroke.start.y)*geometry.get(active.id).zoom);active.E.qs_add_point(p.x,p.y,v.pointerType==='pen'?pressure(v.pressure):1,v.timeStamp);
        if(v.pointerType==='pen'&&panel){panel.querySelector('[data-pressure-now]').textContent=Math.round(v.pressure*100)+'%';panel.querySelector('[data-pressure-bar]').value=v.pressure;}}
    }
    if(stroke.erase)rebuild(active);schedule();
  }
  function finish(cancel=false){
    if(!stroke)return;
    if(stroke.lasso){
      const L=stroke.lasso;stroke=null;
      if(cancel){schedule();return;}
      if(L.op==='lasso'){
        if(L.points.length>=3){const points=new Float32Array(L.points.flat()),ptr=active.E.qs_alloc(points.length*4);new Float32Array(active.E.memory.buffer,ptr,points.length).set(points);active.E.qs_lasso(ptr,points.length);}
        else active.E.qs_select_clear();
        updateSelection();return;
      }
      const dx=L.last.x-L.start.x,dy=L.last.y-L.start.y;
      let scale=1,angle=0,tx=0,ty=0;
      if(L.op==='move'){tx=dx;ty=dy;}
      if(L.op==='scale'){const ax=L.start.x-L.pivot.x,ay=L.start.y-L.pivot.y;scale=Math.max(.05,Math.min(20,((L.last.x-L.pivot.x)*ax+(L.last.y-L.pivot.y)*ay)/(ax*ax+ay*ay||1)));}
      if(L.op==='rotate')angle=Math.atan2(L.last.y-L.pivot.y,L.last.x-L.pivot.x)-Math.atan2(L.start.y-L.pivot.y,L.start.x-L.pivot.x);
      if(Math.abs(tx)+Math.abs(ty)>1e-3||Math.abs(scale-1)>1e-4||Math.abs(angle)>1e-4){active.E.qs_selection_transform(scale,Math.cos(angle),Math.sin(angle),tx,ty,L.pivot.x,L.pivot.y);rebuild(active,true);send();}
      updateSelection();return;
    }
    if(stroke.pointerType==='touch'&&!stroke.erase&&!cancel&&performance.now()-stroke.startTime<250&&(stroke.distance||0)<8){
      const saved=stroke,ticket=session;stroke=null;
      lastTap={x:saved.clientX,y:saved.clientY,time:performance.now()};
      pendingTap={x:saved.clientX,y:saved.clientY,time:performance.now(),timer:setTimeout(()=>{if(session===ticket&&active){active.E.qs_commit_stroke();rebuild(active);send();schedule();}pendingTap=null;},280)};
      schedule();return;
    }
    if(stroke.erase)active.E.qs_erase_end();else if(cancel)active.E.qs_cancel_stroke();else active.E.qs_commit_stroke();
    const changed=!cancel||stroke.erase;stroke=null;rebuild(active);if(changed)send();schedule();
  }
  function close(discard=false){
    session++;navEpoch++;pendingNav=null;touches.clear();autoTaps.clear();suppressedTouches.clear();gesture=null;penDown=false;closeSettings();
    if(pendingTap){clearTimeout(pendingTap.timer);if(active){if(discard)active.E.qs_cancel_stroke();else {active.E.qs_commit_stroke();rebuild(active);send();}}pendingTap=null;}
    if(discard&&stroke){if(stroke.erase)active.E.qs_erase_end();else if(!stroke.lasso)active.E.qs_cancel_stroke();stroke=null;}else finish();
    if(active){active.E=null;active.layer=null;active.layerKey=null;}active=null;selection=null;overlay?.remove();bar?.remove();overlay=bar=null;refresh();
  }
  async function open(data){
    if(active?.id===data.id){close();return;}close();const ticket=session;
    try{const selected=await state(data.id,data.payload),E=await instance();if(ticket!==session)return;active=selected;active.E=E;load(active.E,active.meta);if(!geometry.has(data.id)){refresh();await new Promise(r=>setTimeout(r,80));}const g=geometry.get(data.id);if(!g)throw Error('The drawing container is not visible');
      active.meta.width ||= g.w/g.zoom;active.meta.height ||= g.h/g.zoom;
      document.getElementById('qm-input')?.blur();
      bar=document.createElement('section');bar.id='qnote-qsketch-tools';bar.setAttribute('aria-label','Drawing tools');
      bar.style.cssText='position:fixed;bottom:64px;left:50%;transform:translateX(-50%);z-index:9000;display:flex;flex-wrap:wrap;align-items:center;gap:6px;max-width:calc(100vw - 24px);width:max-content;padding:10px;background:var(--q-theme-surface,#fff);color:var(--q-popup-ink,#172033);border:1px solid #ccd3df;border-radius:12px;box-shadow:0 4px 20px #0003;font:14px system-ui';
      bar.innerHTML='<strong data-status></strong><select aria-label="Brush" data-brush><option value="ballpoint">Ballpoint</option><option value="fountain">Fountain pen</option><option value="calligraphy">Calligraphy</option><option value="marker">Marker</option><option value="erase">Eraser</option></select><button data-lasso aria-pressed="false">Lasso</button><button data-settings aria-expanded="false" aria-haspopup="dialog">Brush settings</button><input type="range" min="1" max="60" value="5" aria-label="Brush size" data-size style="width:75px"><button data-undo>Undo</button><button data-redo>Redo</button><button data-duplicate disabled>Duplicate</button><button data-delete disabled>Delete</button><button data-done>Done</button>';
      for(const control of bar.querySelectorAll('button,select'))control.style.cssText+=';'+controlStyle;
      bar.querySelector('[data-status]').textContent=data.id<0?'Drawing Mode':'Anchored sketch';
      const brushSelect=bar.querySelector('[data-brush]');brushSelect.value=settings.brush;refreshBrushControls();
      brushSelect.onchange=()=>{if(brushSelect.value!=='erase')settings.brush=brushSelect.value;persistSettings();bar.querySelector('[data-lasso]').setAttribute('aria-pressed','false');active.E.qs_select_clear();selection=null;updateSelection();refreshBrushControls();};
      bar.querySelector('[data-size]').oninput=e=>{if(brushSelect.value==='erase')settings.eraserSize=Number(e.target.value);else brush().size=Number(e.target.value);persistSettings();refreshBrushControls();};
      bar.querySelector('[data-settings]').onclick=openSettings;
      bar.querySelector('[data-lasso]').onclick=e=>{const on=e.currentTarget.getAttribute('aria-pressed')!=='true';e.currentTarget.setAttribute('aria-pressed',String(on));e.currentTarget.style.background=on?'var(--q-theme-selected,#dce6ff)':'var(--q-theme-surface,#fff)';if(!on){active.E.qs_select_clear();selection=null;updateSelection();}};
      bar.querySelector('[data-undo]').onclick=doUndo;bar.querySelector('[data-redo]').onclick=doRedo;
      bar.querySelector('[data-delete]').onclick=()=>selectionAction('delete');bar.querySelector('[data-duplicate]').onclick=()=>selectionAction('duplicate');bar.querySelector('[data-done]').onclick=()=>close();
      overlay=document.createElement('canvas');overlay.id='qnote-qsketch-canvas';overlay.style.cssText='position:fixed;z-index:100;touch-action:none;cursor:crosshair';overlay.getContext('2d',{desynchronized:settings.lowLatency});
      overlay.onpointerdown=e=>{
        if(e.pointerType==='pen')markPen(true);
        if(e.pointerType==='touch'&&(penGuard()||(penSeen&&settings.fingers==='auto')||Math.max(e.width||0,e.height||0)>28)){touch(e);return;}
        if(e.pointerType==='touch'&&lastTap&&performance.now()-lastTap.time<300&&Math.hypot(e.clientX-lastTap.x,e.clientY-lastTap.y)<32){e.preventDefault();lastTap=null;if(pendingTap){clearTimeout(pendingTap.timer);active.E.qs_cancel_stroke();pendingTap=null;}doUndo();return;}
        if(pendingTap){clearTimeout(pendingTap.timer);active.E.qs_commit_stroke();pendingTap=null;rebuild(active);send();}
        if(touch(e))return;if(stroke)return;
        const p=point(e);e.preventDefault();
        try{overlay.setPointerCapture(e.pointerId);}catch{}
        if(bar.querySelector('[data-lasso]').getAttribute('aria-pressed')==='true'){startLasso(e);return;}
        const tool=brushSelect.value,b=brush(),hex=settings.color;
        stroke={pointer:e.pointerId,pointerType:e.pointerType,startTime:performance.now(),start:p,clientX:e.clientX,clientY:e.clientY,erase:tool==='erase'||(settings.penButtonErase&&e.pointerType==='pen'&&(e.button===5||(e.buttons&32)!==0)),color:rgba((parseInt(hex.slice(1),16)*256+Math.round(b.opacity*255))>>>0)};
        if(stroke.erase)active.E.qs_erase_begin();
        else {const [nx,ny]=nib();active.E.qs_begin_stroke((parseInt(hex.slice(1),16)*256+Math.round(b.opacity*255))>>>0,b.size,settings.pressure?b.minSize:1,b.smoothing*3,b.streamline,tool==='calligraphy'?1:0,nx,ny,.15,b.stabilizer*80/geometry.get(active.id).zoom);}
        feed(e);
      };
      overlay.onpointermove=e=>{if(e.pointerType==='pen')markPen();if(touch(e))return;if(stroke?.pointer===e.pointerId){e.preventDefault();feed(e);}};
      overlay.onpointerup=e=>{if(e.pointerType==='pen'){penDown=false;lastPenAt=performance.now();}if(touch(e))return;if(stroke?.pointer===e.pointerId){feed(e);finish();}};
      overlay.onpointercancel=e=>{if(e.pointerType==='pen'){penDown=false;lastPenAt=performance.now();}touch(e);finish(true);};overlay.onlostpointercapture=()=>finish(true);
      overlay.onwheel=e=>{e.preventDefault();if(penGuard())return;const g=geometry.get(active.id);g.canvas.dispatchEvent(new WheelEvent('wheel',{deltaX:e.deltaX,deltaY:e.deltaY,ctrlKey:e.ctrlKey,bubbles:true,clientX:e.clientX,clientY:e.clientY}));};
      overlay.addEventListener('gesturestart',e=>e.preventDefault(),{passive:false});
      document.body.append(overlay,bar);schedule();refresh();
    }catch(e){close();console.error(e);alert(e.message);}
  }
  window.addEventListener('resize',schedule);window.addEventListener('scroll',schedule,true);window.addEventListener('keydown',e=>{if(!active)return;if(e.target.closest?.('input,select,textarea')&&e.key!=='Escape')return;if(e.key==='Escape'){e.preventDefault();if(panel)closeSettings();else if(selection){active.E.qs_select_clear();updateSelection();}else close();}else if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();if(e.shiftKey)doRedo();else doUndo();}else if((e.key==='Delete'||e.key==='Backspace')&&selection){e.preventDefault();selectionAction('delete');}});
  document.addEventListener('change',e=>{if(e.target.id==='qnote-file-buffer'){close(true);states.clear();geometry.clear();}},true);
  document.addEventListener('click',e=>{if(active&&e.target.closest('#btn-print'))close();},true);
  window.QNoteSketch={open,draw,close,payload:(id,text)=>payloads.set(id,text),setPagePattern,get pagePattern(){return Number(decode(payloads.get(-1)||'').paper)||0;},get selectionCount(){return active?.E?.qs_selection_count()||0;},get target(){if(!active)return null;const g=geometry.get(active.id);return g?{id:g.id,x:g.x,y:g.y,width:g.w,height:g.h,zoom:g.zoom}:null;}};
})();
