(() => {
  'use strict';
  const small=matchMedia('(max-width: 600px)');
  const byId=id=>document.getElementById(id);
  let installed=false, expanded=false;
  const css=document.createElement('style');
  css.textContent=`
.qm-bar{display:none}
#qm-input{display:none!important;position:fixed!important;left:0!important;top:0!important;width:1px!important;height:1px!important;min-width:0!important;min-height:0!important;max-width:1px!important;max-height:1px!important;padding:0!important;border:0!important;opacity:0!important;pointer-events:none!important;resize:none!important;overflow:hidden!important}
@media(max-width:600px){
html,body{overflow:hidden!important;overscroll-behavior:none}
#qnote-root{height:var(--qm-height,100dvh)!important;grid-template-rows:48px auto minmax(0,1fr) auto auto minmax(52px,auto)!important;position:relative}
.qm-bar{display:flex;align-items:center;gap:4px;background:var(--q-theme-surface,#fff);color:var(--q-popup-ink,#172033);padding:2px 8px;min-width:0}
#qm-top{grid-row:1;border-bottom:1px solid #cbd5e1}
#qm-top strong{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:15px}
.qm-bar button{flex:none;min-width:44px;min-height:44px;border:0;border-radius:7px;background:transparent;color:inherit;font:inherit;touch-action:manipulation}
.qm-bar button[aria-pressed=true]{background:var(--q-theme-accent,#9b1b30);color:white}
#qm-quick{grid-row:6;overflow-x:auto;border-top:1px solid #cbd5e1;padding-bottom:env(safe-area-inset-bottom,0px)}
#qnote-root #qnote-ruler{grid-row:2}
#qnote-root #qnote-canvas-stage{grid-row:3}
#qnote-root #tab-strip{grid-row:4;display:none;overflow-x:auto;align-items:center;min-width:0;padding:0 6px}
#qnote-root #tab-strip .brand{display:none}
#qnote-root #toolbar-container{grid-row:5;display:none;max-height:min(32dvh,230px);overflow:auto}
#qnote-root.qm-expanded #tab-strip{display:flex}
#qnote-root.qm-expanded #toolbar-container{display:block}
#qnote-root .tab-btn{flex:none;min-height:44px}
#qnote-root .tab-content.active{flex-wrap:wrap;min-width:0;gap:4px;padding:8px}
#qnote-root .tool,#qnote-root .tool-text,#qnote-root select{min-height:44px}
#qnote-root #qnote-status{display:none}
#qnote-root .toolbar-popup{position:fixed!important;inset:auto 8px 56px!important;max-width:calc(100vw - 16px);max-height:55dvh;overflow:auto}
#qm-input{display:block!important;font-size:16px;z-index:-1}
.qnote-dialog{max-width:calc(100vw - 16px)!important;max-height:calc(100dvh - 16px)!important}
}
@media print{.qm-bar,#qm-input{display:none!important}}
`;
  document.head.append(css);
  function install(){
    const root=byId('qnote-root'),canvas=byId('qnote-canvas');
    if(!root||!canvas||!byId('qnote-scrollbar')?.dataset.i)return false;
    if(installed)return true;installed=true;
    const click=id=>byId(id)?.click();
    const top=document.createElement('header');top.id='qm-top';top.className='qm-bar';
    const quick=document.createElement('nav');quick.id='qm-quick';quick.className='qm-bar';quick.setAttribute('aria-label','Quick formatting');
    const input=document.createElement('textarea');input.id='qm-input';input.setAttribute('aria-label','Type in document');input.autocapitalize='sentences';input.autocomplete='off';input.spellcheck=false;
    root.append(top,quick,input);
    const button=(parent,label,text,action)=>{const b=document.createElement('button');b.type='button';b.title=label;b.setAttribute('aria-label',label);b.textContent=text;b.addEventListener('pointerdown',e=>e.preventDefault());b.onclick=action;parent.append(b);return b;};
    button(top,'Done editing','Done',()=>{input.blur();expanded=false;update();});
    const title=document.createElement('strong');title.textContent='QNote';top.append(title);
    button(top,'Undo','↶',()=>click('btn-undo'));button(top,'Redo','↷',()=>click('btn-redo'));button(top,'Save','Save',()=>click('btn-save'));
    const more=button(quick,'Show formatting ribbon','Aa ▴',()=>{expanded=!expanded;input.blur();update();});more.setAttribute('aria-controls','toolbar-container');
    for(const [id,label,text] of [['btn-bold','Bold','B'],['btn-italic','Italic','I'],['btn-underline','Underline','U']])button(quick,label,text,()=>click(id));
    button(quick,'List formatting','≡',()=>{expanded=true;click('tab-main-btn');update();byId('list-select')?.focus();});
    button(quick,'Fit page width','Fit',()=>click('btn-zoom-fit'));
    button(quick,'Show keyboard','⌨',()=>input.focus({preventScroll:true}));
    function key(name){for(const type of ['keydown','keyup'])canvas.dispatchEvent(new KeyboardEvent(type,{key:name,bubbles:true}));}
    function text(value){if(!value)return;const action=byId('qnote-misc-action');action.value=JSON.stringify({op:'clipboard-text-paste',text:value});action.dispatchEvent(new Event('change',{bubbles:true}));}
    input.addEventListener('keydown',e=>e.stopPropagation());
    input.addEventListener('beforeinput',e=>{if(e.isComposing)return;if(e.inputType==='deleteContentBackward'||e.inputType==='deleteContentForward'){e.preventDefault();key(e.inputType==='deleteContentBackward'?'Backspace':'Delete');}else if(e.inputType==='insertLineBreak'||e.inputType==='insertParagraph'){e.preventDefault();key('Enter');}});
    input.addEventListener('input',e=>{if(e.isComposing)return;text(input.value);input.value='';});
    input.addEventListener('compositionend',()=>{text(input.value);input.value='';});
    // Touch navigation is separate from text input and table commands.
    document.addEventListener('pointerdown',e=>{
      if(e.target.closest?.('#btn-add-row,#btn-remove-row,#btn-add-col,#btn-remove-col,.qnote-table-menu'))input.blur();
    },true);
    const points=new Map();let gesture=null,lastTap=null,zoomFrame=0,pendingZoom=null;
    const slider=byId('zoom-slider'),vertical=byId('qnote-scrollbar'),horizontal=byId('qnote-hscrollbar');
    const zoom=()=>Number(slider.value)/100;
    const midpoint=()=>{const [a,b]=[...points.values()];return {x:(a.x+b.x)/2,y:(a.y+b.y)/2,d:Math.hypot(a.x-b.x,a.y-b.y)};};
    function setZoom(value,x,y){
      pendingZoom={value,x,y};if(zoomFrame)return;
      zoomFrame=requestAnimationFrame(()=>{
        zoomFrame=0;const next=pendingZoom;pendingZoom=null;
        const before=zoom(),after=Math.max(Number(slider.min)/100,Math.min(Number(slider.max)/100,next.value));
        const rect=canvas.getBoundingClientRect(),fx=next.x-rect.left,fy=next.y-rect.top;
        const sx=horizontal.scrollLeft,sy=vertical.scrollTop;
        slider.value=String(Math.round(after*100));slider.dispatchEvent(new Event('input',{bubbles:true}));
        requestAnimationFrame(()=>{horizontal.scrollLeft=(sx+fx)*after/before-fx;vertical.scrollTop=(sy+fy)*after/before-fy;});
      });
    }
    canvas.addEventListener('pointerdown',e=>{
      if(e.pointerType!=='touch')return;
      e.preventDefault();e.stopImmediatePropagation();canvas.setPointerCapture(e.pointerId);
      points.set(e.pointerId,{x:e.clientX,y:e.clientY});input.blur();
      if(points.size===1)gesture={x:e.clientX,y:e.clientY,sx:horizontal.scrollLeft,sy:vertical.scrollTop,moved:false,pinch:false};
      if(points.size===2){const m=midpoint();gesture={...gesture,pinch:true,moved:true,d:m.d,z:zoom()};}
    },true);
    canvas.addEventListener('pointermove',e=>{
      if(!points.has(e.pointerId))return;e.preventDefault();e.stopImmediatePropagation();points.set(e.pointerId,{x:e.clientX,y:e.clientY});
      if(points.size>=2){const m=midpoint();setZoom(gesture.z*m.d/Math.max(1,gesture.d),m.x,m.y);return;}
      if(gesture.pinch)return;
      const dx=e.clientX-gesture.x,dy=e.clientY-gesture.y;
      if(Math.hypot(dx,dy)>8)gesture.moved=true;
      if(gesture.moved){horizontal.scrollLeft=gesture.sx-dx;vertical.scrollTop=gesture.sy-dy;}
    },true);
    function endTouch(e){
      if(!points.has(e.pointerId))return;e.preventDefault();e.stopImmediatePropagation();points.delete(e.pointerId);
      if(canvas.hasPointerCapture(e.pointerId))canvas.releasePointerCapture(e.pointerId);
      if(points.size)return;
      const tap=e.type!=='pointercancel'&&!gesture.moved&&!gesture.pinch;gesture=null;
      if(!tap){lastTap=null;return;}
      const now=performance.now();
      if(lastTap&&now-lastTap.time<280&&Math.hypot(e.clientX-lastTap.x,e.clientY-lastTap.y)<30){setZoom(zoom()<1.5?2:1,e.clientX,e.clientY);lastTap=null;return;}
      lastTap={time:now,x:e.clientX,y:e.clientY};
      for(const type of ['mousemove','mousedown','mouseup'])canvas.dispatchEvent(new MouseEvent(type,{bubbles:true,clientX:e.clientX,clientY:e.clientY,button:0,buttons:type==='mousedown'?1:0}));
      // Table edge/menu actions and object handles must not request a keyboard.
      const cursor=canvas.dataset.cursor||getComputedStyle(canvas).cursor;
      if(small.matches&&cursor==='text'&&!document.querySelector('.qnote-table-menu'))input.focus({preventScroll:true});
    }
    canvas.addEventListener('pointerup',endTouch,true);canvas.addEventListener('pointercancel',endTouch,true);
    canvas.addEventListener('gesturestart',e=>e.preventDefault(),{passive:false});

    function update(){root.classList.toggle('qm-expanded',small.matches&&expanded);more.setAttribute('aria-expanded',String(expanded));more.textContent=expanded?'Aa ▾':'Aa ▴';if(!small.matches)input.blur();window.dispatchEvent(new Event('resize'));}
    let fitTimer;
    const fit=()=>{clearTimeout(fitTimer);fitTimer=setTimeout(()=>{if(small.matches)click('btn-zoom-fit');},180);};
    const size=()=>{root.style.setProperty('--qm-height',Math.min(innerHeight,visualViewport?.height||innerHeight)+'px');};
    visualViewport?.addEventListener('resize',size);window.addEventListener('resize',size);
    small.addEventListener('change',()=>{update();fit();});window.addEventListener('orientationchange',fit);
    size();update();fit();
  }
  const observer=new MutationObserver(()=>{if(install())observer.disconnect();});
  observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['data-i']});install();
})();
