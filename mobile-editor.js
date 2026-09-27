(() => {
  'use strict';
  const small=matchMedia('(max-width: 600px)');
  const byId=id=>document.getElementById(id);
  let installed=false, expanded=false;
  const css=document.createElement('style');
  css.textContent=`
.qm-bar{display:none}
.qm-selection-handle{position:fixed;z-index:1200;width:44px;height:44px;padding:0;border:0;background:transparent;touch-action:none;transform:translate(-50%,0)}
.qm-selection-handle::before{content:'';display:block;width:16px;height:22px;margin:auto;background:#2563eb;border:2px solid white;border-radius:3px 12px 12px 12px;box-shadow:0 1px 4px #0005}
#qm-selection-menu{position:fixed;z-index:1300;display:flex;max-width:calc(100vw - 16px);overflow:auto;padding:4px;background:#fff;color:#172033;border:1px solid #cbd5e1;border-radius:10px;box-shadow:0 4px 20px #0003}
#qm-selection-menu button{min-height:44px;padding:0 12px;white-space:nowrap;border:0;border-radius:6px;background:transparent;color:inherit;font:14px system-ui}
.qm-selection-handle[hidden],#qm-selection-menu[hidden]{display:none!important}
#qm-input{display:none!important;position:fixed!important;left:0!important;top:0!important;width:1px!important;height:1px!important;min-width:0!important;min-height:0!important;max-width:1px!important;max-height:1px!important;padding:0!important;border:0!important;opacity:0!important;pointer-events:none!important;resize:none!important;overflow:hidden!important}
@media(max-width:600px){
html,body{overflow:hidden!important;overscroll-behavior:none}
#qnote-root{height:var(--qm-height,100dvh)!important;grid-template-rows:48px auto minmax(0,1fr) auto auto minmax(52px,auto)!important;position:relative}
.qm-bar{display:flex;align-items:center;gap:4px;background:var(--q-theme-surface,#fff);color:var(--q-popup-ink,#172033);padding:2px 8px;min-width:0}
#qm-top{grid-row:1;border-bottom:1px solid #cbd5e1}
#qnote-root.qm-vault-hosted{grid-template-rows:0 auto minmax(0,1fr) auto auto minmax(52px,auto)!important}
#qnote-root.qm-vault-hosted #qm-top{display:none}
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
@media(min-width:601px){
.qm-locked #qm-quick{display:flex;position:fixed;right:12px;bottom:12px;z-index:1000;background:var(--q-theme-surface,#fff);border:1px solid #cbd5e1;border-radius:8px}
.qm-locked #qm-quick button{display:none}
.qm-locked #qm-quick #qm-edit-lock{display:block;min-width:44px;min-height:44px}
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
    const title=document.createElement('strong');title.id='qm-document-title';title.textContent='Online mode';top.append(title);
    button(top,'Undo','↶',()=>click('btn-undo'));button(top,'Redo','↷',()=>click('btn-redo'));button(top,'Save','Save',()=>click('btn-save'));
    const more=button(quick,'Show formatting ribbon','Aa ▴',()=>{expanded=!expanded;input.blur();update();});more.setAttribute('aria-controls','toolbar-container');
    for(const [id,label,text] of [['btn-bold','Bold','B'],['btn-italic','Italic','I'],['btn-underline','Underline','U']])button(quick,label,text,()=>click(id));
    button(quick,'List formatting','≡',()=>{expanded=true;click('tab-main-btn');update();byId('list-select')?.focus();});
    button(quick,'Fit page width','Fit',()=>click('btn-zoom-fit'));
    const keyboard=button(quick,'Show keyboard','⌨',()=>input.focus({preventScroll:true}));
    let locked=false,selectionDispatch=false;
    const lock=button(quick,'Lock editing','🔓',()=>{locked=!locked;applyLock();});lock.id='qm-edit-lock';
    function applyLock(){
      lock.textContent=locked?'🔒':'🔓';
      lock.title=locked?'Unlock editing':'Lock editing';lock.setAttribute('aria-label',lock.title);
      lock.setAttribute('aria-pressed',String(locked));root.classList.toggle('qm-locked',locked);
      input.value='';input.disabled=locked;keyboard.disabled=locked;
      for(const bar of [top,quick])for(const b of bar.querySelectorAll('button'))
        b.disabled=locked&&b!==lock&&!['Save','Fit page width'].includes(b.getAttribute('aria-label'));
      for(const id of ['toolbar-container','tab-strip','qnote-ruler'])if(byId(id))byId(id).inert=locked;
      if(locked){input.value='';input.blur();canvas.blur();expanded=false;}
      update();
    }
    // Capture before the canvas/runtime handlers: locking also covers hardware
    // keyboards, paste, mouse/stylus editing and object/context-menu actions.
    for(const type of ['keydown','beforeinput','input','paste','cut','drop','mousedown','mousemove','mouseup','click','dblclick','contextmenu','pointerdown','pointermove','pointerup'])
      window.addEventListener(type,e=>{
        if(!locked)return;
        if(selectionDispatch&&['mousedown','mousemove','mouseup'].includes(type))return;
        if(e.target.closest?.('.qm-selection-handle,#qm-selection-menu'))return;
        if(e.target.closest?.('#qoqoro-save-dialog'))return;
        if(e.target.closest?.('.qm-bar')&&type!=='keydown')return;
        if(type==='keydown'&&e.target===lock&&['Enter',' '].includes(e.key))return;
        if(e.target.closest?.('#btn-save')&&type==='click')return;
        if(e.target===byId('zoom-slider')&&type==='input')return;
        if(e.target===canvas&&e.pointerType==='touch')return; // retain pan/pinch
        if(type==='keydown'&&(e.ctrlKey||e.metaKey)&&['a','c','s'].includes(e.key.toLowerCase()))return;
        if(e.target===document.body||e.target===document.documentElement||root.contains(e.target)||type==='keydown'){
          e.preventDefault();e.stopImmediatePropagation();
        }
      },{capture:true,passive:false});
    function updateTitle(){
      const bridge=globalThis.__qoqoroBridge;
      let name=bridge?.connected?(bridge.standalone.path||'Untitled.qnote'):'Online mode';
      try { const label=window.frameElement?.id==='editorFrame'&&parent.document.querySelector('#currentNote');
        if(label&&label.textContent!=='No vault note selected')name=label.textContent;
      } catch {}
      title.textContent=name.split(/[\\/]/).pop();title.title=name;
    }
    window.addEventListener('qoqoro-document-state',updateTitle);
    try { const label=window.frameElement?.id==='editorFrame'&&parent.document.querySelector('#currentNote');
      if(label)new MutationObserver(updateTitle).observe(label,{childList:true,subtree:true,characterData:true});
    } catch {}
    updateTitle();
    // The vault already provides the document title and Save. Keep one header
    // and move editing actions into the thumb-reachable formatting strip.
    try {
      if (window.frameElement?.id === 'editorFrame') {
        root.classList.add('qm-vault-hosted');
        const undo=top.querySelector('[aria-label="Undo"]'),redo=top.querySelector('[aria-label="Redo"]');
        more.after(undo,redo);
      }
    } catch { /* Cross-origin standalone embeds retain their own header. */ }
    function key(name){if(locked)return;for(const type of ['keydown','keyup'])canvas.dispatchEvent(new KeyboardEvent(type,{key:name,bubbles:true}));}
    function text(value){if(locked||!value)return;const action=byId('qnote-misc-action');action.value=JSON.stringify({op:'clipboard-text-paste',text:value});action.dispatchEvent(new Event('change',{bubbles:true}));}
    input.addEventListener('keydown',e=>e.stopPropagation());
    input.addEventListener('beforeinput',e=>{if(e.isComposing)return;if(e.inputType==='deleteContentBackward'||e.inputType==='deleteContentForward'){e.preventDefault();key(e.inputType==='deleteContentBackward'?'Backspace':'Delete');}else if(e.inputType==='insertLineBreak'||e.inputType==='insertParagraph'){e.preventDefault();key('Enter');}});
    input.addEventListener('input',e=>{if(e.isComposing)return;text(input.value);input.value='';});
    input.addEventListener('compositionend',()=>{text(input.value);input.value='';});
    // Touch navigation is separate from text input and table commands.
    document.addEventListener('pointerdown',e=>{
      if(e.target.closest?.('#btn-add-row,#btn-remove-row,#btn-add-col,#btn-remove-col,.qnote-table-menu'))input.blur();
    },true);
    const points=new Map();let gesture=null,lastTap=null,zoomFrame=0,pendingZoom=null,holdTimer;
    const slider=byId('zoom-slider'),vertical=byId('qnote-scrollbar'),horizontal=byId('qnote-hscrollbar');
    let selectionPoints=null,handleDrag=null,localCopy=null;
    const selectionMenu=document.createElement('div');selectionMenu.id='qm-selection-menu';selectionMenu.hidden=true;selectionMenu.setAttribute('role','toolbar');selectionMenu.setAttribute('aria-label','Text selection');document.body.append(selectionMenu);
    const handles=['Start','End'].map((label,index)=>{
      const h=document.createElement('button');h.type='button';h.className='qm-selection-handle';h.hidden=true;h.setAttribute('aria-label',label+' of text selection');document.body.append(h);
      h.addEventListener('pointerdown',e=>{
        if(!selectionPoints)return;e.preventDefault();e.stopPropagation();h.setPointerCapture(e.pointerId);selectionMenu.hidden=true;
        handleDrag={index,id:e.pointerId};const opposite=screenPoint(selectionPoints[1-index]);mouse('mousedown',opposite.x,opposite.y,1,true);
      });
      h.addEventListener('pointermove',e=>{
        if(handleDrag?.id!==e.pointerId)return;e.preventDefault();
        const r=canvas.getBoundingClientRect();const y=Math.max(r.top+2,Math.min(r.bottom-2,e.clientY-12));
        if(e.clientY<r.top+28)vertical.scrollTop-=12;else if(e.clientY>r.bottom-28)vertical.scrollTop+=12;
        mouse('mousemove',e.clientX,y,1,true);selectionPoints[index]=documentPoint(e.clientX,y);positionSelection();
      });
      const end=e=>{if(handleDrag?.id!==e.pointerId)return;const p=screenPoint(selectionPoints[index]);mouse('mouseup',p.x,p.y,0,true);handleDrag=null;if(h.hasPointerCapture(e.pointerId))h.releasePointerCapture(e.pointerId);showSelectionMenu(p.x,p.y);};
      h.addEventListener('pointerup',end);h.addEventListener('pointercancel',end);return h;
    });
    function mouse(type,x,y,buttons=0,selectionOnly=false){selectionDispatch=selectionOnly;try{canvas.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,clientX:x,clientY:y,button:0,buttons}));}finally{selectionDispatch=false;}}
    function documentPoint(x,y){const r=canvas.getBoundingClientRect(),z=Number(slider.value)/100;return{x:(x-r.left+horizontal.scrollLeft)/z,y:(y-r.top+vertical.scrollTop)/z};}
    function screenPoint(p){const r=canvas.getBoundingClientRect(),z=Number(slider.value)/100;return{x:r.left+p.x*z-horizontal.scrollLeft,y:r.top+p.y*z-vertical.scrollTop};}
    function hideSelection(){selectionPoints=null;selectionMenu.hidden=true;handles.forEach(h=>h.hidden=true);}
    function positionSelection(){
      if(!selectionPoints||!small.matches){handles.forEach(h=>h.hidden=true);return;}
      const r=canvas.getBoundingClientRect();handles.forEach((h,i)=>{const p=screenPoint(selectionPoints[i]);h.hidden=p.x<r.left||p.x>r.right||p.y<r.top||p.y>r.bottom;h.style.left=p.x+'px';h.style.top=(p.y+4)+'px';});
    }
    const selectedText=()=>canvas.getAttribute('data-qnote-copy')||'';
    const selectedRich=()=>canvas.getAttribute('data-qnote-rich-copy')||'';
    function showSelectionMenu(x,y){
      if(!small.matches||(!selectedText()&&!selectedRich())){hideSelection();return;}
      selectionMenu.hidden=false;
      for(const b of selectionMenu.querySelectorAll('button'))b.disabled=locked&&['Cut','Paste'].includes(b.textContent);
      selectionMenu.style.left=Math.max(8,Math.min(x-selectionMenu.offsetWidth/2,innerWidth-selectionMenu.offsetWidth-8))+'px';
      selectionMenu.style.top=Math.max(8,Math.min(y-selectionMenu.offsetHeight-24,innerHeight-selectionMenu.offsetHeight-8))+'px';positionSelection();
    }
    async function copySelection(){const value={text:selectedText(),source:selectedRich()};await navigator.clipboard.writeText(value.text);localCopy=value;}
    for(const [label,action] of [
      ['Copy',copySelection],
      ['Cut',async()=>{await copySelection();if(!locked)key('Backspace');hideSelection();}],
      ['Paste',async()=>{const value=await navigator.clipboard.readText();if(locked)return;const field=byId('qnote-misc-action');field.value=JSON.stringify(localCopy&&localCopy.text===value&&localCopy.source?{op:'clipboard-paste',source:localCopy.source}:{op:'clipboard-text-paste',text:value});field.dispatchEvent(new Event('change',{bubbles:true}));hideSelection();}],
      ['Select all',()=>{canvas.dispatchEvent(new KeyboardEvent('keydown',{key:'a',ctrlKey:true,bubbles:true}));hideSelection();showSelectionMenu(innerWidth/2,canvas.getBoundingClientRect().top+70);}]
    ]){const b=document.createElement('button');b.type='button';b.textContent=label;b.onpointerdown=e=>e.preventDefault();b.onclick=async()=>{try{await action();}catch{b.title='Clipboard access was denied by the browser';b.textContent='Clipboard unavailable';setTimeout(()=>b.textContent=label,2000);}};selectionMenu.append(b);}
    for(const area of [vertical,horizontal])area.addEventListener('scroll',()=>{positionSelection();selectionMenu.hidden=true;},{passive:true});
    window.addEventListener('resize',()=>{positionSelection();selectionMenu.hidden=true;});
    input.addEventListener('input',hideSelection);
    document.addEventListener('keydown',e=>{if(e.key==='Escape')hideSelection();});
    document.addEventListener('pointerdown',e=>{if(!e.target.closest?.('#qm-selection-menu,.qm-selection-handle')&&e.target!==canvas)selectionMenu.hidden=true;},true);
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
      clearTimeout(holdTimer);
      if(points.size===1){
        gesture={x:e.clientX,y:e.clientY,sx:horizontal.scrollLeft,sy:vertical.scrollTop,moved:false,pinch:false};
        holdTimer=setTimeout(()=>{
          if(!gesture||gesture.moved||points.size!==1||!small.matches)return;
          hideSelection();mouse('mousemove',gesture.x,gesture.y,0,true);
          const cursor=canvas.dataset.cursor||getComputedStyle(canvas).cursor;
          const textHit=cursor==='text';if(locked&&!textHit)return;
          gesture.hold=true;gesture.textHit=textHit;gesture.endX=gesture.x;gesture.endY=gesture.y;
          mouse('mousedown',gesture.x,gesture.y,1,textHit);
          if(textHit){gesture.endX+=12;mouse('mousemove',gesture.endX,gesture.y,1,true);}
        },400);
      }
      if(points.size===2){if(gesture.hold)mouse('mouseup',gesture.endX,gesture.endY,0,gesture.textHit);hideSelection();const m=midpoint();gesture={...gesture,hold:false,pinch:true,moved:true,d:m.d,z:zoom()};}
    },true);
    canvas.addEventListener('pointermove',e=>{
      if(!points.has(e.pointerId))return;e.preventDefault();e.stopImmediatePropagation();points.set(e.pointerId,{x:e.clientX,y:e.clientY});
      if(points.size>=2){const m=midpoint();setZoom(gesture.z*m.d/Math.max(1,gesture.d),m.x,m.y);return;}
      if(gesture.pinch)return;
      if(gesture.hold){gesture.endX=e.clientX;gesture.endY=e.clientY;mouse('mousemove',e.clientX,e.clientY,1,gesture.textHit);return;}
      const dx=e.clientX-gesture.x,dy=e.clientY-gesture.y;
      if(Math.hypot(dx,dy)>8){gesture.moved=true;clearTimeout(holdTimer);selectionMenu.hidden=true;}
      if(gesture.moved){horizontal.scrollLeft=gesture.sx-dx;vertical.scrollTop=gesture.sy-dy;}
    },true);
    function endTouch(e){
      if(!points.has(e.pointerId))return;e.preventDefault();e.stopImmediatePropagation();points.delete(e.pointerId);
      if(canvas.hasPointerCapture(e.pointerId))canvas.releasePointerCapture(e.pointerId);
      if(points.size)return;
      clearTimeout(holdTimer);
      if(gesture.hold){
        mouse('mouseup',gesture.endX,gesture.endY,0,gesture.textHit);
        if(e.type!=='pointercancel'){
          if(gesture.textHit&&selectedText())selectionPoints=[documentPoint(gesture.x,gesture.y),documentPoint(gesture.endX,gesture.endY)];
          if(gesture.textHit)showSelectionMenu(gesture.endX,gesture.endY);
          else {
            // Nim opens its object menu from a right mouse-down, not from
            // the browser contextmenu event (which the runtime suppresses).
            canvas.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,clientX:gesture.endX,clientY:gesture.endY,button:2,buttons:2}));
          }
        }else hideSelection();
        gesture=null;lastTap=null;return;
      }
      const tap=e.type!=='pointercancel'&&!gesture.moved&&!gesture.pinch;gesture=null;
      if(!tap){lastTap=null;return;}
      const now=performance.now();
      if(lastTap&&now-lastTap.time<280&&Math.hypot(e.clientX-lastTap.x,e.clientY-lastTap.y)<30){setZoom(zoom()<1.5?2:1,e.clientX,e.clientY);lastTap=null;return;}
      lastTap={time:now,x:e.clientX,y:e.clientY};
      if(locked)return;
      hideSelection();
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
    size();applyLock();fit();
  }
  const observer=new MutationObserver(()=>{if(install())observer.disconnect();});
  observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['data-i']});install();
})();
