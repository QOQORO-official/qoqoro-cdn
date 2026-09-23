(() => {
  'use strict';
  const small=matchMedia('(max-width: 600px)');
  const byId=id=>document.getElementById(id);
  let installed=false, expanded=false;
  const css=document.createElement('style');
  css.textContent=`
.qm-bar{display:none}
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
#qm-input{position:fixed;left:10px;top:50px;width:2px;height:2px;opacity:.01;font-size:16px;z-index:-1}
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
    canvas.addEventListener('pointerup',e=>{if(small.matches&&e.pointerType==='touch')input.focus({preventScroll:true});});
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
