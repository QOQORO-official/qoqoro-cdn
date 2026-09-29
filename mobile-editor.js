(() => {
  'use strict';
  // QNote on a phone, laid out the way Word and LibreOffice do it: an app bar
  // with the document and its mode, the page fitted to the screen, one row of
  // formatting commands above the keyboard, and the full ribbon as a bottom
  // sheet opened from "Format". Reading mode hides every editing control and
  // leaves a single Edit button. All commands drive the editor's own controls,
  // so desktop and phone never disagree about what a command does.
  // ── which layout: phone or desktop ──
  // Automatic uses the original QNote's device detection (js/config.js,
  // main.js): a Windows PC keeps the desktop ribbon at any width; a phone or
  // tablet (Android, iOS, other mobile browsers) and a Linux desktop switch to
  // the phone layout below 750 CSS px. Theme -> Buttons -> Layout can force
  // Phone or Desktop instead; that choice is kept in qnote-theme.layout.
  const device=(()=>{
    const ua=navigator.userAgent||'',platform=navigator.userAgentData?.platform||navigator.platform||'';
    const android=/Android/i.test(ua);
    const ios=/iPhone|iPad|iPod/i.test(ua)||(/Mac/i.test(platform)&&navigator.maxTouchPoints>1);
    const windows=(/Win/i.test(platform)||/Windows/i.test(ua))&&!android;
    const mobile=android||ios||/webOS|BlackBerry|IEMobile|Opera Mini|Mobile/i.test(ua);
    const linux=/Linux/i.test(platform)&&!android&&!windows;
    const name=android?'Android':ios?'iPhone / iPad':windows?'Windows PC':linux?'Linux':mobile?'mobile device':/Mac/i.test(platform)?'Mac':'computer';
    return {android,ios,windows,mobile,linux,name};
  })();
  const layoutPreference=()=>{try{const v=JSON.parse(localStorage.getItem('qnote-theme')||'{}').layout;return ['phone','desktop'].includes(v)?v:'auto';}catch{return 'auto';}};
  const autoPhone=()=>!device.windows&&(device.mobile||device.linux)&&innerWidth<750;
  const small=new EventTarget();
  let phone=false;
  Object.defineProperty(small,'matches',{get:()=>phone});
  function decideLayout(){
    const pref=layoutPreference();
    const next=pref==='phone'||(pref==='auto'&&autoPhone());
    document.documentElement.classList.toggle('qm-phone',next);
    document.documentElement.dataset.qnoteDevice=device.name;
    if(next===phone&&phoneCss.media)return;
    phone=next;
    phoneCss.media=phone?'all':'not all';desktopCss.media=phone?'not all':'all';
    small.dispatchEvent(new Event('change'));
  }
  // The Theme dialog asks for this to label "Automatic (…)".
  globalThis.QNoteLayout={device,get phone(){return phone;},preference:layoutPreference,auto:autoPhone,refresh:decideLayout};

  const byId=id=>document.getElementById(id);
  let installed=false, expanded=false;
  const ICONS={
    undo:'<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
    redo:'<path d="m15 14 5-5-5-5"/><path d="M20 9H9.5a5.5 5.5 0 0 0 0 11H13"/>',
    bold:'<path d="M7 5h6.5a3.5 3.5 0 0 1 0 7H7z" stroke-width="2.3"/><path d="M7 12h7.5a3.5 3.5 0 0 1 0 7H7z" stroke-width="2.3"/>',
    italic:'<path d="M19 4h-9"/><path d="M14 20H5"/><path d="M15 4 9 20"/>',
    underline:'<path d="M6 4v6a6 6 0 0 0 12 0V4"/><path d="M4 21h16"/>',
    strike:'<path d="M16 5H10a3.5 3.5 0 0 0-2.5 6"/><path d="M14.5 12A3.5 3.5 0 0 1 14 19H7"/><path d="M4 12h16"/>',
    color:'<path d="m5.5 17 5-13h3l5 13"/><path d="M8 12h8"/>',
    highlight:'<path d="m9 11-5 5v3h6l2-2"/><path d="m21 10-5.2 5.2a1.5 1.5 0 0 1-2.1 0l-4.9-4.9a1.5 1.5 0 0 1 0-2.1L14 3"/>',
    bullets:'<path d="M9 6h11M9 12h11M9 18h11"/><path d="M4.5 6h.01M4.5 12h.01M4.5 18h.01" stroke-width="3"/>',
    numbers:'<path d="M10 6h10M10 12h10M10 18h10"/><path d="M4 4.5h1.2V9M3.8 9h2.6"/><path d="M6.4 19.5H3.8c0-1.3 2.6-1.8 2.6-3.2 0-.8-.6-1.3-1.3-1.3S3.8 15.4 3.8 16"/>',
    left:'<path d="M3 6h18M3 12h12M3 18h16"/>',center:'<path d="M3 6h18M6 12h12M4 18h16"/>',
    right:'<path d="M3 6h18M9 12h12M5 18h16"/>',justify:'<path d="M3 6h18M3 12h18M3 18h18"/>',
    outdent:'<path d="M21 6H11M21 12H11M21 18H11"/><path d="m7 8-4 4 4 4"/>',indent:'<path d="M21 6H11M21 12H11M21 18H11"/><path d="m3 8 4 4-4 4"/>',
    style:'<path d="M4 7V5h16v2"/><path d="M12 5v14"/><path d="M9 19h6"/>',
    format:'<path d="M3 19 8 5h2l5 14"/><path d="M5 14h8"/><path d="M15.5 12.5a3 3 0 1 1 0 6.2 3 3 0 0 1 0-6.2zM18.5 12v7"/>',
    keyboard:'<rect x="2" y="6" width="20" height="12" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10" stroke-width="1.9"/>',
    hidekb:'<rect x="2" y="3" width="20" height="11" rx="2"/><path d="M6 7h.01M10 7h.01M14 7h.01M18 7h.01M7 10.5h10" stroke-width="1.9"/><path d="m9 18 3 3 3-3"/>',
    edit:'<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>',
    read:'<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    more:'<path d="M12 5h.01M12 12h.01M12 19h.01" stroke-width="3"/>',
    down:'<path d="m6 9 6 6 6-6"/>',up:'<path d="m6 15 6-6 6 6"/>',close:'<path d="M18 6 6 18M6 6l12 12"/>',
    save:'<path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><path d="M17 21v-8H7v8M7 3v5h8"/>',
    open:'<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    export:'<path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/>',
    print:'<path d="M6 9V3h12v6"/><rect x="3" y="9" width="18" height="8" rx="2"/><path d="M7 14h10v7H7z"/>',
    find:'<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
    pages:'<rect x="4" y="3" width="12" height="15" rx="1.5"/><path d="M8 21h11a1 1 0 0 0 1-1V7"/>',
    page:'<rect x="5" y="3" width="14" height="18" rx="1.5"/><path d="M8 7h8M8 11h8M8 15h5"/>',
    header:'<rect x="5" y="3" width="14" height="18" rx="1.5"/><path d="M8 6.5h8M8 17.5h8"/>',
    templates:'<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 17.5h7M17.5 14v7"/>',
    settings:'<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    resizeH:'<path d="M3.5 12h17"/><path d="m7.5 8-4 4 4 4M16.5 8l4 4-4 4"/>',
    resizeNWSE:'<path d="M6 6l12 12"/><path d="M6 11.5V6h5.5M18 12.5V18h-5.5"/>',
    resizeNESW:'<path d="M18 6 6 18"/><path d="M12.5 6H18v5.5M11.5 18H6v-5.5"/>',
    resizeV:'<path d="M12 3.5v17"/><path d="m8 7.5 4-4 4 4M8 16.5l4 4 4-4"/>',
    move:'<path d="M12 3v18M3 12h18"/><path d="m9 6 3-3 3 3M9 18l3 3 3-3M6 9l-3 3 3 3M18 9l3 3-3 3"/>',
    fit:'<path d="M8 3H5a2 2 0 0 0-2 2v3M21 8V5a2 2 0 0 0-2-2h-3M3 16v3a2 2 0 0 0 2 2h3M16 21h3a2 2 0 0 0 2-2v-3"/>',
  };
  const svg=name=>`<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]||''}</svg>`;
  const css=document.createElement('style');
  css.textContent=`
.qm-bar,#qm-edit-fab,.qm-pop{display:none}
.qm-tile-label{display:none}
#qm-sheet-close[hidden]{display:none!important}
.qm-selection-handle{position:fixed;z-index:1200;width:44px;height:44px;padding:0;border:0;background:transparent;touch-action:none;transform:translate(-50%,0)}
.qm-selection-handle::before{content:'';display:block;width:16px;height:22px;margin:auto;background:var(--q-theme-accent,#2563eb);border:2px solid #fff;border-radius:3px 12px 12px 12px;box-shadow:0 1px 4px #0005}
#qm-selection-menu{position:fixed;z-index:1300;display:flex;max-width:calc(100vw - 16px);overflow:auto;padding:0;background:#1f2937;color:#fff;border-radius:10px;box-shadow:0 6px 24px #0004}
#qm-selection-menu button{min-height:42px;padding:0 14px;white-space:nowrap;border:0;border-right:1px solid #ffffff22;background:transparent;color:inherit;font:500 14px system-ui}
#qm-selection-menu button:last-child{border-right:0}
#qm-selection-menu button:disabled{opacity:.4}
.qm-selection-handle[hidden],#qm-selection-menu[hidden]{display:none!important}
#qm-input{display:none!important;position:fixed!important;left:0!important;top:0!important;width:1px!important;height:1px!important;min-width:0!important;min-height:0!important;max-width:1px!important;max-height:1px!important;padding:0!important;border:0!important;opacity:0!important;pointer-events:none!important;resize:none!important;overflow:hidden!important}
.qm-bar button,.qm-pop button,#qm-edit-fab{-webkit-tap-highlight-color:transparent;touch-action:manipulation;font:inherit;color:inherit}
.qm-icon{display:inline-flex;align-items:center;justify-content:center;flex:none;width:44px;height:44px;padding:0;border:0;border-radius:10px;background:transparent;cursor:pointer}
.qm-icon:disabled{opacity:.38}
#qm-edit-fab{position:fixed;right:16px;bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:1100;align-items:center;gap:8px;height:52px;padding:0 20px 0 16px;border:0;border-radius:16px;background:var(--q-theme-accent,#9b1b30);color:#fff!important;font:600 15px system-ui;box-shadow:0 6px 20px #0004}
.qm-locked #qm-edit-fab{display:inline-flex}
/* Touch handles for the active image, text box, drawing or table cell. */
#qm-touch{position:fixed;inset:0;z-index:1150;pointer-events:none}
.qm-th{position:fixed;width:44px;height:44px;margin:-22px 0 0 -22px;padding:0;border:0;background:transparent;pointer-events:auto;touch-action:none;-webkit-tap-highlight-color:transparent}
.qm-th[hidden]{display:none!important}
.qm-th::before{content:'';position:absolute;left:50%;top:50%;width:18px;height:18px;margin:-9px 0 0 -9px;border-radius:50%;background:#fff;border:2px solid var(--q-theme-accent,#2563eb);box-shadow:0 1px 4px #0006;box-sizing:border-box}
/* Border and edge handles: a round badge with a double-headed arrow on the
   line it moves -- the resize affordance people already know. */
.qm-th.qm-th-arrow::before{display:none}
.qm-th-badge{position:absolute;left:50%;top:50%;display:flex;align-items:center;justify-content:center;width:28px;height:28px;margin:-14px 0 0 -14px;border-radius:50%;box-sizing:border-box;
  background:var(--q-theme-surface,#fff);color:var(--q-theme-accent,#2563eb);border:1px solid var(--q-popup-border,#d8dee9);box-shadow:0 1px 5px #0000002e}
.qm-th-badge svg{width:18px;height:18px}
.qm-th.qm-th-small .qm-th-badge{width:24px;height:24px;margin:-12px 0 0 -12px}
.qm-th.qm-th-small .qm-th-badge svg{width:15px;height:15px}
.qm-th.qm-dragging .qm-th-badge{background:var(--q-theme-accent,#2563eb);color:#fff;border-color:transparent}
.qm-th.qm-th-move{width:auto;height:36px;margin:0;transform:translate(-50%,0);display:flex;align-items:center;gap:6px;padding:0 14px 0 10px;border-radius:18px;
  background:var(--q-theme-surface,#fff);color:var(--q-popup-ink,#1e293b);border:1px solid var(--q-popup-border,#d8dee9);box-shadow:0 2px 10px #0003;font:600 13px system-ui}
.qm-th.qm-th-move::before{display:none}
.qm-th.qm-dragging{opacity:.85}
@media print{.qm-bar,#qm-input,#qm-edit-fab{display:none!important}}
`;
  document.head.append(css);
  // Phone-layout rules and desktop-only rules, switched as a whole by the
  // layout decision below (device detection or the user's Theme choice).
  const phoneCss=document.createElement('style');phoneCss.id='qm-phone-css';phoneCss.textContent=`
html,body{overflow:hidden!important;overscroll-behavior:none}
#qnote-root,.qm-pop,#qm-selection-menu{--qm-surface:var(--q-theme-surface,#fff);--qm-ink:var(--q-popup-ink,#1e293b);--qm-line:var(--q-popup-border,#d8dee9);--qm-accent:var(--q-theme-accent,#9b1b30);
  --qm-soft:color-mix(in srgb,var(--qm-surface) 92%,var(--qm-ink));--qm-muted:color-mix(in srgb,var(--qm-ink) 60%,var(--qm-surface));--qm-pressed:color-mix(in srgb,var(--qm-accent) 16%,var(--qm-surface));
  font:14px system-ui,-apple-system,'Segoe UI',sans-serif}
#qnote-root{height:var(--qm-height,100dvh)!important;grid-template-rows:56px 0 minmax(0,1fr) auto auto auto!important;position:relative}
.qm-bar [hidden]{display:none!important}
.qm-bar{display:flex;align-items:center;background:var(--qm-surface);color:var(--qm-ink);min-width:0}
.qm-bar .qm-icon:active,.qm-pop button:active{background:var(--qm-soft)}
.qm-bar .qm-icon[aria-pressed=true]{background:var(--qm-pressed);color:var(--qm-accent)}
#qm-top{grid-row:1;gap:2px;padding:0 4px 0 16px;border-bottom:1px solid var(--qm-line)}
#qm-top .qm-title{flex:1;min-width:0;display:flex;flex-direction:column;line-height:1.2}
#qm-top .qm-title strong{font-size:16px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#qm-top .qm-title small{font-size:12px;color:var(--qm-muted)}
#qnote-root.qm-vault-hosted{grid-template-rows:0 0 minmax(0,1fr) auto auto auto!important}
#qnote-root.qm-vault-hosted #qm-top{display:none}
#qnote-root #qnote-ruler{grid-row:2;display:none!important}
#qnote-root #qnote-canvas-stage{grid-row:3}
#qnote-root #qnote-canvas-stage #qnote-scrollbar{width:6px!important;background:transparent!important;scrollbar-width:none!important}
#qnote-root #qnote-canvas-stage #qnote-scrollbar::-webkit-scrollbar{display:none}
#qnote-root #qnote-canvas-stage #qnote-hscrollbar{height:6px!important;background:transparent!important;scrollbar-width:none!important}
#qnote-root #qnote-canvas-stage #qnote-hscrollbar::-webkit-scrollbar{display:none}
#qnote-root #qnote-status{display:none}
/* Drawing mode: only the document and the drawing toolbar. */
html.qm-drawing #qm-quick,html.qm-drawing #tab-strip,html.qm-drawing #toolbar-container,html.qm-drawing #qm-touch{display:none!important}
html.qm-drawing #qm-top .qm-icon{visibility:hidden}
/* Formatting bar: fixed ends, scrolling middle, over the keyboard. */
#qm-quick{grid-row:6;height:calc(52px + env(safe-area-inset-bottom,0px));padding:0 4px env(safe-area-inset-bottom,0px);border-top:1px solid var(--qm-line);gap:2px}
#qm-quick .qm-scroll{flex:1;min-width:0;display:flex;align-items:center;gap:2px;overflow-x:auto;scrollbar-width:none;
  -webkit-mask-image:linear-gradient(90deg,transparent,#000 10px,#000 calc(100% - 18px),transparent);mask-image:linear-gradient(90deg,transparent,#000 10px,#000 calc(100% - 18px),transparent);padding:0 8px}
#qm-quick .qm-scroll::-webkit-scrollbar{display:none}
#qm-quick .qm-divider{flex:none;width:1px;height:24px;margin:0 4px;background:var(--qm-line)}
#qm-format{width:auto!important;gap:2px;padding:0 8px 0 6px!important;font-weight:600}
#qm-format[aria-expanded=true]{background:var(--qm-pressed)}
.qm-swatch{position:relative}
.qm-swatch::after{content:'';position:absolute;left:12px;right:12px;bottom:8px;height:3.5px;border-radius:2px;background:var(--qm-swatch,currentColor)}
.qm-swatch svg{margin-top:-4px}
.qm-locked #qm-quick,.qm-locked #tab-strip,.qm-locked #toolbar-container,.qm-locked #qm-top .qm-mode{display:none!important}
/* The ribbon as a bottom sheet above the formatting bar. */
#qnote-root #tab-strip{grid-row:4;display:none;align-items:center;gap:6px;min-width:0;overflow-x:auto;scrollbar-width:none;padding:18px 12px 8px;
  background:var(--qm-surface);border-top:1px solid var(--qm-line);border-radius:16px 16px 0 0;box-shadow:0 -8px 24px #0000001f;position:relative}
#qnote-root #tab-strip::before{content:'';position:absolute;left:50%;top:6px;width:36px;height:4px;margin-left:-18px;border-radius:2px;background:var(--qm-line)}
#qnote-root #tab-strip::-webkit-scrollbar{display:none}
#qnote-root #tab-strip .brand{display:none}
#qnote-root #tab-strip .tab-btn{flex:none;height:36px;min-height:0;padding:0 14px;border:1px solid var(--qm-line)!important;border-radius:18px;background:transparent!important;color:var(--qm-ink)!important;font:500 14px system-ui}
#qnote-root #tab-strip .tab-btn.active{background:var(--qm-pressed)!important;border-color:var(--qm-accent)!important;color:var(--qm-ink)!important;font-weight:600}
#qnote-root #toolbar-container{grid-row:5;display:none;height:auto!important;min-height:0!important;max-height:min(40dvh,300px);overflow:auto;background:var(--qm-surface);padding:4px 12px 12px;border:0!important}
#qnote-root.qm-expanded #tab-strip{display:flex}
/* The keyboard and the ribbon sheet each take the bottom edge on their own:
   no formatting bar underneath to hit by accident, and more room for both. */
#qnote-root.qm-typing #qm-quick,#qnote-root.qm-expanded #qm-quick{display:none}
/* One fixed height for every tab: switching Home <-> Insert must not make the
   sheet (and the page above it) jump. Short tabs leave space, long ones scroll. */
#qnote-root.qm-expanded #toolbar-container{padding-bottom:calc(12px + env(safe-area-inset-bottom,0px));height:min(48dvh,380px)!important;max-height:none;overscroll-behavior:contain}
#qm-sheet-close{position:sticky;right:0;margin-left:auto;flex:none;width:40px!important;height:40px!important;border-radius:20px!important;background:var(--qm-soft)!important;color:var(--qm-ink)!important;box-shadow:-14px 0 12px var(--qm-surface),0 0 0 4px var(--qm-surface),16px 0 0 4px var(--qm-surface)}
#qnote-root.qm-expanded #toolbar-container{display:block}
#qnote-root #toolbar-container .tab-content.active{display:flex!important;flex-wrap:wrap;align-items:center;gap:8px;padding:0;min-width:0;height:auto!important;max-height:none!important;overflow:visible!important}
/* Undo and Redo live in the app bar (or the formatting bar in the vault). */
#qnote-root #toolbar-container #btn-undo,#qnote-root #toolbar-container #btn-redo,#qnote-root #toolbar-container #btn-redo+.sep{display:none!important}
#qnote-root #toolbar-container .sep{flex:0 0 100%;height:1px;margin:4px 0;background:var(--qm-line);border:0;width:auto}
#qnote-root #toolbar-container .tool{width:44px;height:44px;min-height:44px;border-radius:10px;border:1px solid var(--qm-line)}
#qnote-root #toolbar-container .tool-text{height:44px;min-height:44px;padding:0 14px;border-radius:10px;border:1px solid var(--qm-line);font:500 14px system-ui}
#qnote-root #toolbar-container .tool.active{background:var(--qm-pressed)!important;color:var(--qm-accent)!important;border-color:var(--qm-accent)}
#qnote-root #toolbar-container select{flex:1 1 150px;height:44px;min-height:44px;border-radius:10px;font-size:15px}
#qnote-root #toolbar-container input:not([type=color]){height:44px;min-height:44px;border-radius:10px;font-size:15px}
#qnote-root #toolbar-container .color-chip{width:44px;height:44px;border-radius:10px}
#qnote-root #toolbar-container .qm-tile-label{display:inline;margin-left:8px;font:500 14px system-ui;white-space:nowrap}
#qnote-root #toolbar-container .qnote-icon-button:has(.qm-tile-label){width:auto;padding:0 14px 0 12px;display:inline-flex;align-items:center}
#qnote-root #toolbar-container .hint{flex:0 0 100%;color:var(--qm-muted);font-size:12px}
#qnote-root .toolbar-popup{position:fixed!important;inset:auto 0 0 0!important;max-width:none;max-height:60dvh;overflow:auto;border-radius:16px 16px 0 0!important;padding:16px 16px calc(16px + env(safe-area-inset-bottom,0px))!important}
/* Menus and sheets. */
.qm-pop{position:fixed;z-index:1400;flex-direction:column;min-width:200px;padding:6px;background:var(--qm-surface);color:var(--qm-ink);border:1px solid var(--qm-line);border-radius:12px;box-shadow:0 10px 32px #0003}
.qm-pop.open{display:flex}
.qm-pop button{display:flex;align-items:center;gap:12px;min-height:44px;padding:0 12px;border:0;border-radius:8px;background:transparent;text-align:left;font-size:15px}
.qm-pop button[aria-checked=true]{color:var(--qm-accent);font-weight:600}
.qm-pop.sheet{left:0!important;right:0;bottom:0!important;top:auto!important;border-radius:16px 16px 0 0;padding:10px 8px calc(10px + env(safe-area-inset-bottom,0px));max-height:75dvh;overflow:auto}
.qm-pop.sheet::before{content:'';align-self:center;width:36px;height:4px;margin:0 0 8px;border-radius:2px;background:var(--qm-line)}
.qm-pop .qm-pop-label{padding:6px 12px 4px;font-size:12px;color:var(--qm-muted)}
.qm-scrim{position:fixed;inset:0;z-index:1350;background:#0000004d;display:none}
.qm-scrim.open{display:block}
#qm-input{display:block!important;font-size:16px;z-index:-1}
/* Dialogs become bottom sheets. */
dialog.qnote-dialog:not(.qt-studio):not(.qnote-theme-dialog){position:fixed;inset:auto 0 0 0;margin:0;width:100vw!important;max-width:100vw!important;max-height:88dvh!important;border-radius:16px 16px 0 0!important;padding:20px 16px calc(16px + env(safe-area-inset-bottom,0px))!important}
.qnote-dialog .qnote-dialog-actions{position:sticky;bottom:-16px;background:inherit;padding-bottom:4px}
.qnote-dialog .qnote-dialog-actions button{flex:1 1 auto;min-height:44px}
`;
  const desktopCss=document.createElement('style');desktopCss.id='qm-desktop-css';desktopCss.textContent=`
#qm-touch{display:none}
.qm-locked #qm-edit-fab{display:inline-flex}
`;
  document.head.append(phoneCss,desktopCss);
  decideLayout();
  for(const type of ['resize','orientationchange','qnote-theme-applied','storage'])window.addEventListener(type,decideLayout);
  function install(){
    const root=byId('qnote-root'),canvas=byId('qnote-canvas');
    if(!root||!canvas||!byId('qnote-scrollbar')?.dataset.i)return false;
    if(installed)return true;installed=true;
    const click=id=>byId(id)?.click();
    const top=document.createElement('header');top.id='qm-top';top.className='qm-bar';
    const quick=document.createElement('nav');quick.id='qm-quick';quick.className='qm-bar';quick.setAttribute('aria-label','Formatting');
    const input=document.createElement('textarea');input.id='qm-input';input.setAttribute('aria-label','Type in document');input.autocapitalize='sentences';input.autocomplete='off';input.spellcheck=false;
    const scrim=document.createElement('div');scrim.className='qm-scrim';
    const pop=document.createElement('div');pop.className='qm-pop';pop.setAttribute('role','menu');
    const fab=document.createElement('button');fab.type='button';fab.id='qm-edit-fab';fab.innerHTML=svg('edit')+'<span>Edit</span>';fab.setAttribute('aria-label','Edit document');
    root.append(top,quick,input);document.body.append(scrim,pop,fab);
    const button=(parent,label,icon,action,id)=>{
      const b=document.createElement('button');b.type='button';b.className='qm-icon';b.title=label;b.setAttribute('aria-label',label);
      b.innerHTML=svg(icon);if(id)b.id=id;
      b.addEventListener('pointerdown',e=>e.preventDefault());b.onclick=action;parent.append(b);return b;
    };
    const divider=parent=>{const d=document.createElement('span');d.className='qm-divider';parent.append(d);};

    // ── menus: small anchored pop-ups and full-width action sheets ──
    function closePop(){pop.classList.remove('open','sheet');scrim.classList.remove('open');pop.replaceChildren();}
    function openPop(anchor,items,{sheet=false,label=''}={}){
      closePop();
      if(label){const l=document.createElement('div');l.className='qm-pop-label';l.textContent=label;pop.append(l);}
      for(const item of items){
        const b=document.createElement('button');b.type='button';b.setAttribute('role',item.checked===undefined?'menuitem':'menuitemradio');
        if(item.checked!==undefined)b.setAttribute('aria-checked',String(!!item.checked));
        b.innerHTML=(item.icon?svg(item.icon):'')+'<span></span>';b.lastChild.textContent=item.label;
        if(item.style)b.lastChild.style.cssText=item.style;
        b.disabled=!!item.disabled;
        b.addEventListener('pointerdown',e=>e.preventDefault());
        b.onclick=()=>{closePop();item.action();};pop.append(b);
      }
      pop.classList.add('open');if(sheet){pop.classList.add('sheet');scrim.classList.add('open');return;}
      const r=anchor.getBoundingClientRect();
      pop.style.top='';pop.style.left=Math.max(8,Math.min(r.left+r.width/2-pop.offsetWidth/2,innerWidth-pop.offsetWidth-8))+'px';
      pop.style.top=Math.max(8,r.top-pop.offsetHeight-8)+'px';
    }
    scrim.addEventListener('click',closePop);
    document.addEventListener('pointerdown',e=>{if(pop.classList.contains('open')&&!pop.contains(e.target))closePop();},true);

    // ── app bar ──
    const titleBox=document.createElement('div');titleBox.className='qm-title';
    const title=document.createElement('strong');title.id='qm-document-title';title.textContent='Untitled document';
    const subtitle=document.createElement('small');subtitle.textContent='Editing';
    titleBox.append(title,subtitle);top.append(titleBox);
    const undoTop=button(top,'Undo','undo',()=>click('btn-undo'));
    const redoTop=button(top,'Redo','redo',()=>click('btn-redo'));
    const modeTop=button(top,'Reading view','read',()=>{locked=!locked;applyLock();});modeTop.classList.add('qm-mode');
    const docxButton=()=>document.querySelector('#tab-file button:not([id])');
    const overflow=button(top,'More options','more',()=>openPop(overflow,[
      {icon:'save',label:'Save',action:()=>click('btn-save')},
      {icon:'open',label:'Open…',action:()=>click('btn-open')},
      {icon:'export',label:'Export as Word (.docx)',action:()=>docxButton()?.click(),disabled:!docxButton()},
      {icon:'print',label:'Print',action:()=>click('btn-print')},
      {icon:'find',label:'Find',action:()=>click('btn-navigation-find')},
      {icon:'pages',label:'Pages and outline',action:()=>click('btn-navigation-pages')},
      {icon:'page',label:'Page setup',action:()=>click('btn-page-layout')},
      {icon:'header',label:'Header and footer',action:()=>click('btn-header-footer')},
      {icon:'templates',label:'Templates',action:()=>click('btn-template-editor')},
      {icon:'fit',label:'Fit page to screen',action:()=>click('btn-zoom-fit')},
      {icon:'settings',label:'Toolbar settings',action:()=>click('btn-settings-popup')},
    ],{sheet:true,label:title.textContent}));

    // ── formatting bar ──
    const format=document.createElement('button');format.type='button';format.id='qm-format';format.className='qm-icon';
    format.innerHTML=svg('format')+svg('up');format.lastChild.setAttribute('width','16');format.lastChild.setAttribute('height','16');
    format.title='Format: all commands';format.setAttribute('aria-label','Format: all commands');format.setAttribute('aria-controls','toolbar-container');
    format.addEventListener('pointerdown',e=>e.preventDefault());
    format.onclick=()=>{expanded=!expanded;if(expanded){input.blur();if(!document.querySelector('#tab-strip .tab-btn.active'))click('tab-main-btn');}update();};
    const more=format;quick.append(format);
    const strip=document.createElement('div');strip.className='qm-scroll';quick.append(strip);
    const hostedUndo=button(strip,'Undo','undo',()=>click('btn-undo'));const hostedRedo=button(strip,'Redo','redo',()=>click('btn-redo'));
    const hostedDivider=document.createElement('span');hostedDivider.className='qm-divider';strip.append(hostedDivider);
    for(const node of [hostedUndo,hostedRedo,hostedDivider])node.hidden=true;
    const mirrors=[];
    const toggle=(label,icon,id)=>{const b=button(strip,label,icon,()=>{click(id);syncSoon();});mirrors.push([b,id]);return b;};
    toggle('Bold','bold','btn-bold');toggle('Italic','italic','btn-italic');toggle('Underline','underline','btn-underline');toggle('Strikethrough','strike','btn-strike');
    divider(strip);
    const swatch=(label,icon,id,fallback)=>{const b=button(strip,label,icon,()=>byId(id)?.click());b.classList.add('qm-swatch');b.dataset.picker=id;b.dataset.fallback=fallback;return b;};
    const colorButton=swatch('Text color','color','font-color-picker','#111827');
    const highlightButton=swatch('Highlight','highlight','highlight-color-picker','#fde047');
    divider(strip);
    const listSelect=()=>byId('list-select');
    const setList=value=>{const s=listSelect();if(!s)return;s.value=s.value===value?'':value;s.dispatchEvent(new Event('change',{bubbles:true}));syncSoon();};
    const bullets=button(strip,'Bulleted list','bullets',()=>setList('list-ul-dot'));
    const numbers=button(strip,'Numbered list','numbers',()=>setList('list-ol-num'));
    divider(strip);
    const aligns=[['align-left','Align left','left'],['align-center','Center','center'],['align-right','Align right','right'],['align-justify','Justify','justify']];
    const alignButton=button(strip,'Alignment','left',()=>openPop(alignButton,aligns.map(([id,label,icon])=>({icon,label,checked:byId(id)?.classList.contains('active'),action:()=>{click(id);syncSoon();}}))));
    const styleButton=button(strip,'Paragraph style','style',()=>{
      const s=byId('heading-select');if(!s)return;
      const looks={normal:'font-size:15px',title:'font-size:20px;font-weight:600',h1:'font-size:18px;font-weight:600',h2:'font-size:16px;font-weight:600',h3:'font-size:15px;font-weight:600'};
      openPop(styleButton,[...s.options].map(o=>({label:o.textContent,style:looks[o.value]||'',checked:s.value===o.value,
        action:()=>{s.value=o.value;s.dispatchEvent(new Event('change',{bubbles:true}));syncSoon();}})),{label:'Paragraph style'});
    });
    divider(strip);
    button(strip,'Decrease indent','outdent',()=>click('btn-promote-list'));
    button(strip,'Increase indent','indent',()=>click('btn-demote-list'));
    const keyboard=button(quick,'Show keyboard','keyboard',()=>{
      if(document.activeElement===input){input.blur();}else{expanded=false;update();input.focus({preventScroll:true});}
    });
    // An on-screen keyboard takes the bottom edge on its own, so the
    // formatting bar steps aside while one is showing. A hardware keyboard
    // shows nothing on screen: then the bar stays, or there would be no way
    // back to it. The software keyboard is recognised by what it does -- the
    // visible viewport (the top page's, when QNote runs in a frame) loses
    // more than 120px of height at an unchanged width and zoom.
    const screenView=(()=>{try{return window.top.visualViewport||window.visualViewport;}catch{return window.visualViewport;}})();
    let fullView={w:0,h:0};
    function softKeyboardUp(){
      const v=screenView;if(!v)return false;
      if(Math.abs(v.width-fullView.w)>2)fullView={w:v.width,h:v.height};
      else if(v.scale<=1.01)fullView.h=Math.max(fullView.h,v.height);
      return v.scale<=1.01&&v.height<fullView.h-120;
    }
    softKeyboardUp();
    let typingTimer=0;
    function syncTyping(){root.classList.toggle('qm-typing',document.activeElement===input&&softKeyboardUp());}
    screenView?.addEventListener('resize',()=>{if(document.activeElement===input){clearTimeout(typingTimer);syncTyping();}else softKeyboardUp();});
    input.addEventListener('focus',()=>{
      clearTimeout(typingTimer);syncTyping();
      keyboard.innerHTML=svg('hidekb');keyboard.title='Hide keyboard';keyboard.setAttribute('aria-label','Hide keyboard');
      if(expanded){expanded=false;update();}
    });
    // A tap on the page blurs and refocuses the input in one gesture: only
    // bring the bar back once focus has stayed away for a moment.
    input.addEventListener('blur',()=>{
      keyboard.innerHTML=svg('keyboard');keyboard.title='Show keyboard';keyboard.setAttribute('aria-label','Show keyboard');
      clearTimeout(typingTimer);typingTimer=setTimeout(syncTyping,350);
    });

    // Mirror the editor's formatting state onto the bar.
    let syncTimer=0;
    function sync(){
      for(const [b,id] of mirrors)b.setAttribute('aria-pressed',String(!!byId(id)?.classList.contains('active')));
      for(const b of [colorButton,highlightButton])b.style.setProperty('--qm-swatch',byId(b.dataset.picker)?.value||b.dataset.fallback);
      const list=listSelect()?.value||'';
      bullets.setAttribute('aria-pressed',String(list.startsWith('list-ul')));numbers.setAttribute('aria-pressed',String(list.startsWith('list-ol')));
      const align=aligns.find(([id])=>byId(id)?.classList.contains('active'))||aligns[0];
      alignButton.innerHTML=svg(align[2]);alignButton.setAttribute('aria-label','Alignment: '+align[1]);
    }
    function syncSoon(){clearTimeout(syncTimer);syncTimer=setTimeout(sync,60);}
    const tabMain=byId('tab-main');
    if(tabMain)new MutationObserver(syncSoon).observe(tabMain,{subtree:true,attributes:true,attributeFilter:['class','value']});
    for(const id of ['font-color-picker','highlight-color-picker','list-select','heading-select'])byId(id)?.addEventListener('change',syncSoon);
    for(const type of ['pointerup','keyup'])canvas.addEventListener(type,syncSoon);
    input.addEventListener('input',syncSoon);

    // Ribbon tabs read like Word's on a phone.
    const tabNames={'tab-main-btn':'Home','tab-objects-btn':'Insert','tab-tables-btn':'Tables','tab-layout-btn':'Layout','tab-misc-btn':'Tools','tab-file-btn':'File'};
    const tabOriginal={};
    for(const id in tabNames){const b=byId(id);if(b)tabOriginal[id]=b.textContent;}
    function nameTabs(){for(const id in tabNames){const b=byId(id);if(b)b.textContent=small.matches?tabNames[id]:tabOriginal[id];}
      const strip=byId('tab-strip'),file=byId('tab-file-btn');if(small.matches&&strip&&file)strip.append(file,...(byId('qm-sheet-close')?[byId('qm-sheet-close')]:[]));}
    nameTabs();small.addEventListener('change',nameTabs);
    // With the formatting bar hidden under the sheet, the sheet closes itself.
    const sheetClose=button(byId('tab-strip')||quick,'Close formatting','down',()=>{expanded=false;update();},'qm-sheet-close');
    sheetClose.hidden=!small.matches;small.addEventListener('change',()=>{sheetClose.hidden=!small.matches;});nameTabs();
    // Insert and Tools are icon-only on the desktop ribbon; on a phone every
    // tile says what it does.
    for(const b of document.querySelectorAll('#tab-objects .qnote-icon-button,#tab-misc .qnote-icon-button,#tab-layout .qnote-icon-button')){
      const text=(b.getAttribute('aria-label')||b.dataset.tip||b.title||'').replace(/\s*\(.*\)$/,'');
      if(!text||b.querySelector('.qm-tile-label')||b.textContent.trim().length>2)continue;
      const span=document.createElement('span');span.className='qm-tile-label';span.textContent=text;b.append(span);
    }
    // The app is the viewport: nothing may scroll the page itself (a focused
    // field or a keyboard opening would otherwise slide the whole editor up).
    window.addEventListener('scroll',()=>{if(small.matches&&(scrollX||scrollY))scrollTo(0,0);},{passive:true});

    let locked=false,selectionDispatch=false;
    fab.onclick=()=>{locked=false;applyLock();};
    function applyLock(){
      root.classList.toggle('qm-locked',locked);document.body.classList.toggle('qm-locked',locked);
      subtitle.textContent=locked?'Reading view':'Editing';
      modeTop.innerHTML=svg(locked?'edit':'read');modeTop.title=locked?'Edit':'Reading view';modeTop.setAttribute('aria-label',modeTop.title);
      input.value='';input.disabled=locked;keyboard.disabled=locked;
      for(const b of [undoTop,redoTop])b.disabled=locked;
      for(const id of ['toolbar-container','tab-strip','qnote-ruler'])if(byId(id))byId(id).inert=locked;
      if(locked){input.value='';input.blur();canvas.blur();expanded=false;closePop();}
      update();if(touchLayer)renderTouch();
    }
    // Capture before the canvas/runtime handlers: reading view also covers
    // hardware keyboards, paste, mouse/stylus editing and object menus.
    for(const type of ['keydown','beforeinput','input','paste','cut','drop','mousedown','mousemove','mouseup','click','dblclick','contextmenu','pointerdown','pointermove','pointerup'])
      window.addEventListener(type,e=>{
        if(!locked)return;
        if(selectionDispatch&&['mousedown','mousemove','mouseup'].includes(type))return;
        if(e.target.closest?.('.qm-selection-handle,#qm-selection-menu,#qm-edit-fab,.qm-pop,.qm-scrim'))return;
        if(e.target.closest?.('#qoqoro-save-dialog'))return;
        if(e.target.closest?.('.qm-bar')&&type!=='keydown')return;
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
      let name=bridge?.connected?(bridge.standalone.path||'Untitled document'):'Untitled document';
      try { const label=window.frameElement?.id==='editorFrame'&&parent.document.querySelector('#currentNote');
        if(label&&label.textContent!=='No vault note selected')name=label.textContent;
      } catch {}
      title.textContent=name.split(/[\\/]/).pop().replace(/\.qnote$/i,'');title.title=name;
    }
    window.addEventListener('qoqoro-document-state',updateTitle);
    try { const label=window.frameElement?.id==='editorFrame'&&parent.document.querySelector('#currentNote');
      if(label)new MutationObserver(updateTitle).observe(label,{childList:true,subtree:true,characterData:true});
    } catch {}
    updateTitle();
    // The vault already provides the document title and Save. Keep one header
    // and bring Undo/Redo and the mode switch into the formatting bar.
    try {
      if (window.frameElement?.id === 'editorFrame') {
        root.classList.add('qm-vault-hosted');
        for(const node of [hostedUndo,hostedRedo,hostedDivider])node.hidden=false;
        const hostedMode=button(quick,'Reading view','read',()=>{locked=true;applyLock();});quick.insertBefore(hostedMode,keyboard);
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
    // Mouse selection/object drags continue over editor chrome. Scroll only
    // for a drag that began on the document, never for toolbar/zoom gestures.
    let edgeDrag=null, edgeFrame=0, edgeTime=0;
    function stopEdgeDrag(){edgeDrag=null;cancelAnimationFrame(edgeFrame);edgeFrame=0;edgeTime=0;}
    function edgePoint(){
      const r=canvas.getBoundingClientRect();
      return {r,x:Math.max(r.left+2,Math.min(r.right-20,edgeDrag.x)),
        y:Math.max(r.top+32,Math.min(r.bottom-32,edgeDrag.y))};
    }
    function edgeTick(time){
      edgeFrame=0;
      if(!edgeDrag||locked||document.hidden){stopEdgeDrag();return;}
      const {r,x,y}=edgePoint();
      const distance=edgeDrag.y<r.top?edgeDrag.y-r.top:edgeDrag.y>r.bottom?edgeDrag.y-r.bottom:0;
      if(!distance){edgeTime=0;return;}
      const dt=edgeTime?Math.min(32,time-edgeTime):16;edgeTime=time;
      const before=vertical.scrollTop;
      vertical.scrollTop+=Math.sign(distance)*Math.min(1000,180+Math.abs(distance)*5)*dt/1000;
      if(vertical.scrollTop!==before){
        // Synchronize the WASM viewport before extending the drag at its edge.
        vertical.dispatchEvent(new Event('scroll'));
        mouse('mousemove',x,y,1);
      }
      edgeFrame=requestAnimationFrame(edgeTick);
    }
    window.addEventListener('pointerdown',e=>{
      if(!e.isTrusted||e.target!==canvas||e.pointerType!=='mouse'||e.button!==0||locked)return;
      edgeDrag={x:e.clientX,y:e.clientY,startX:e.clientX,startY:e.clientY};
    },true);
    window.addEventListener('pointermove',e=>{
      if(!e.isTrusted||!edgeDrag)return;
      if(!(e.buttons&1)){stopEdgeDrag();return;}
      edgeDrag.x=e.clientX;edgeDrag.y=e.clientY;
      if(Math.hypot(e.clientX-edgeDrag.startX,e.clientY-edgeDrag.startY)<4)return;
      const {r}=edgePoint();
      if(e.clientY<r.top||e.clientY>r.bottom){
        e.preventDefault();e.stopImmediatePropagation();
        if(!edgeFrame)edgeFrame=requestAnimationFrame(edgeTick);
      }
    },true);
    window.addEventListener('pointerup',e=>{
      if(!e.isTrusted||!edgeDrag)return;
      if(e.target!==canvas){const {x,y}=edgePoint();mouse('mouseup',x,y,0);}
      stopEdgeDrag();
    },true);
    window.addEventListener('blur',stopEdgeDrag);
    window.addEventListener('pointercancel',stopEdgeDrag);
    document.addEventListener('visibilitychange',()=>{if(document.hidden)stopEdgeDrag();});
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
    // Built by the editor on request (qnotePrepareCopy), not on every selection change.
    const selectedRich=()=>{globalThis.qnotePrepareCopy?.();return canvas.getAttribute('data-qnote-rich-copy')||'';};
    function showSelectionMenu(x,y){
      if(!small.matches||(!selectedText()&&!selectedRich())){hideSelection();return;}
      selectionMenu.hidden=false;
      for(const b of selectionMenu.querySelectorAll('button'))b.disabled=locked&&['Cut','Paste'].includes(b.textContent);
      selectionMenu.style.left=Math.max(8,Math.min(x-selectionMenu.offsetWidth/2,innerWidth-selectionMenu.offsetWidth-8))+'px';
      selectionMenu.style.top=Math.max(8,Math.min(y-selectionMenu.offsetHeight-24,innerHeight-selectionMenu.offsetHeight-8))+'px';positionSelection();
    }
    // QNoteClipboard (the runtime's) works on plain http too, where the
    // browser offers no navigator.clipboard; localCopy keeps the objects.
    async function copySelection(){const value={text:selectedText(),source:selectedRich()};localCopy=value;
      if(globalThis.QNoteClipboard)await QNoteClipboard.write(value.text);else await navigator.clipboard.writeText(value.text);}
    for(const [label,action] of [
      ['Copy',copySelection],
      ['Cut',async()=>{await copySelection();if(!locked)key('Backspace');hideSelection();}],
      ['Paste',async()=>{const value=globalThis.QNoteClipboard?(await QNoteClipboard.read()).text:await navigator.clipboard.readText();if(locked)return;const field=byId('qnote-misc-action');field.value=JSON.stringify(localCopy&&localCopy.text===value&&localCopy.source?{op:'clipboard-paste',source:localCopy.source}:{op:'clipboard-text-paste',text:value});field.dispatchEvent(new Event('change',{bubbles:true}));hideSelection();}],
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


    // ── touch handles: images, text boxes, drawings and table cells ──
    // The editor publishes the active object's canvas geometry (data-qnote-
    // touch). Finger-sized handles sit on its resize points; a drag on one is
    // replayed as the mouse drag the editor already handles at that point:
    // the eight resize handles of a picture or text box, moving a floating
    // object, a column's right border and a row's bottom border.
    const touchLayer=document.createElement('div');touchLayer.id='qm-touch';document.body.append(touchLayer);
    const handleSpecs=[['nw','qm-th-arrow qm-th-small','Resize from the top-left corner'],['n','qm-th-arrow qm-th-small','Resize from the top edge'],['ne','qm-th-arrow qm-th-small','Resize from the top-right corner'],
      ['e','qm-th-arrow qm-th-small','Resize from the right edge'],['se','qm-th-arrow qm-th-small','Resize from the bottom-right corner'],['s','qm-th-arrow qm-th-small','Resize from the bottom edge'],
      ['sw','qm-th-arrow qm-th-small','Resize from the bottom-left corner'],['w','qm-th-arrow qm-th-small','Resize from the left edge'],
      ['col','qm-th-arrow','Drag to change the column width'],['row','qm-th-arrow','Drag to change the row height'],['move','qm-th-move','Drag to move']];
    const arrowOf={n:'resizeV',s:'resizeV',row:'resizeV',e:'resizeH',w:'resizeH',col:'resizeH',nw:'resizeNWSE',se:'resizeNWSE',ne:'resizeNESW',sw:'resizeNESW'};
    const touchHandles={};
    let touchInfo=null,touchDrag=null;
    for(const [role,cls,label] of handleSpecs){
      const h=document.createElement('button');h.type='button';h.className='qm-th '+cls;h.hidden=true;h.dataset.role=role;
      h.setAttribute('aria-label',label);h.title=label;
      if(role==='move')h.innerHTML=svg('move')+'<span>Move</span>';
      else if(arrowOf[role])h.innerHTML='<span class="qm-th-badge">'+svg(arrowOf[role])+'</span>';
      h.addEventListener('pointerdown',e=>{
        const p=grabPoint(role);if(!p||locked)return;
        e.preventDefault();e.stopPropagation();h.setPointerCapture(e.pointerId);h.classList.add('qm-dragging');
        hideSelection();input.blur();
        const r=canvas.getBoundingClientRect();
        touchDrag={id:e.pointerId,role,sx:e.clientX,sy:e.clientY,px:r.left+p.x,py:r.top+p.y,handle:h};
        mouse('mousemove',touchDrag.px,touchDrag.py,0);mouse('mousedown',touchDrag.px,touchDrag.py,1);
      });
      h.addEventListener('pointermove',e=>{
        if(touchDrag?.id!==e.pointerId)return;e.preventDefault();
        mouse('mousemove',touchDrag.px+e.clientX-touchDrag.sx,touchDrag.py+e.clientY-touchDrag.sy,1);
      });
      const end=e=>{
        if(touchDrag?.id!==e.pointerId)return;
        mouse('mouseup',touchDrag.px+e.clientX-touchDrag.sx,touchDrag.py+e.clientY-touchDrag.sy,0);
        h.classList.remove('qm-dragging');if(h.hasPointerCapture(e.pointerId))h.releasePointerCapture(e.pointerId);
        touchDrag=null;syncSoon();renderTouch();
      };
      h.addEventListener('pointerup',end);h.addEventListener('pointercancel',end);
      touchLayer.append(h);touchHandles[role]=h;
    }
    // Where the editor must see the mouse go down for each handle (canvas px).
    function grabPoint(role){
      const t=touchInfo;if(!t)return null;
      if(t.kind==='cell')return role==='col'?{x:t.colEdge,y:t.y+t.h/2}:role==='row'?{x:t.x+t.w/2,y:t.rowEdge}:null;
      // Grab 2px inside the edge: an inline picture's bottom edge is also the
      // top of the next text line, which would otherwise win the hit test.
      const {x,y,w,h}=t,i=2;
      const points={nw:[x+i,y+i],n:[x+w/2,y+i],ne:[x+w-i,y+i],e:[x+w-i,y+h/2],se:[x+w-i,y+h-i],s:[x+w/2,y+h-i],sw:[x+i,y+h-i],w:[x+i,y+h/2]};
      if(points[role])return {x:points[role][0],y:points[role][1]};
      // A text box's middle is its text; it is picked up by its frame.
      if(role==='move')return t.kind==='textbox'?{x:x+Math.max(14,Math.min(w/4,40)),y:y+3}:{x:x+w/2,y:y+h/2};
      return null;
    }
    function renderTouch(){
      let t=null;try{t=JSON.parse(canvas.getAttribute('data-qnote-touch')||'null');}catch{}
      touchInfo=t;
      const r=canvas.getBoundingClientRect();
      // A table's row/column menu is open: it owns the gesture, handles wait.
      const menuOpen=[...document.querySelectorAll('.qnote-table-menu')].some(m=>m.getClientRects().length);
      const active=!!t&&small.matches&&!locked&&!menuOpen;
      // Small objects keep only the corners, so the handles stay tappable.
      const compact=active&&t.kind!=='cell'&&(t.w<72||t.h<72);
      for(const [role] of handleSpecs){
        const h=touchHandles[role];
        let show=active&&(t.kind==='cell'?['col','row'].includes(role):!['col','row'].includes(role));
        if(show&&role==='move'&&t.inline)show=false;
        if(show&&compact&&['n','e','s','w'].includes(role))show=false;
        let p=show?grabPoint(role):null;
        if(p&&t.kind!=='cell'&&role!=='move'){const e={nw:[0,0],n:[.5,0],ne:[1,0],e:[1,.5],se:[1,1],s:[.5,1],sw:[0,1],w:[0,.5]}[role];p={x:t.x+t.w*e[0],y:t.y+t.h*e[1]};}
        if(p&&role==='move'){
          // The grip rides just below the object (above it near the bottom).
          const below=r.top+t.y+t.h+14;p={x:t.x+t.w/2,y:(below+40<r.bottom?below:r.top+t.y-50)-r.top};
        }
        const sx=p?r.left+p.x:0,sy=p?r.top+p.y:0;
        const inside=!!p&&sx>=r.left-4&&sx<=r.right+4&&sy>=r.top&&sy<=r.bottom;
        if(!inside&&touchDrag?.handle!==h){h.hidden=true;continue;}
        h.hidden=false;h.style.left=sx+'px';h.style.top=sy+'px';
      }
    }
    new MutationObserver(renderTouch).observe(canvas,{attributes:true,attributeFilter:['data-qnote-touch']});
    new MutationObserver(renderTouch).observe(document.body,{childList:true});
    for(const area of [vertical,horizontal])area.addEventListener('scroll',renderTouch,{passive:true});
    window.addEventListener('resize',renderTouch);
    small.addEventListener('change',renderTouch);
    // Drawing mode owns the screen: the formatting bar, the ribbon sheet and
    // the object handles step aside, and the app bar only names the mode.
    window.addEventListener('qnote-drawing',e=>{
      const on=!!e.detail?.active;
      document.documentElement.classList.toggle('qm-drawing',on);
      subtitle.textContent=on?'Drawing':(locked?'Reading view':'Editing');
      if(on){expanded=false;input.blur();closePop();hideSelection();update();}
      renderTouch();
    });

    function update(){
      root.classList.toggle('qm-expanded',small.matches&&expanded&&!locked);
      format.setAttribute('aria-expanded',String(expanded));
      format.lastElementChild.innerHTML=ICONS[expanded?'down':'up'];
      if(!small.matches)input.blur();
      sync();
      window.dispatchEvent(new Event('resize'));
    }
    let fitTimer;
    const fit=()=>{clearTimeout(fitTimer);fitTimer=setTimeout(()=>{if(small.matches)click('btn-zoom-fit');},180);};
    const size=()=>{root.style.setProperty('--qm-height',Math.min(innerHeight,visualViewport?.height||innerHeight)+'px');};
    visualViewport?.addEventListener('resize',size);window.addEventListener('resize',size);
    small.addEventListener('change',()=>{closePop();update();fit();});window.addEventListener('orientationchange',fit);
    // The sheet changes the page's visible height: keep the page fitted.
    new ResizeObserver(()=>{positionSelection();reportInsets();renderTouch();}).observe(byId('qnote-canvas-stage'));
    // Tell the host page which parts of this frame our chrome covers, so its
    // own floating controls (the vault's files handle) stay on the page area.
    let lastInsets='';
    function reportInsets(){
      if(window.parent===window)return;
      const stage=byId('qnote-canvas-stage').getBoundingClientRect();
      const height=visualViewport?.height||innerHeight;
      const insets={top:Math.round(Math.max(0,stage.top)),bottom:Math.round(Math.max(0,innerHeight-Math.min(stage.bottom,height)))};
      const key=insets.top+':'+insets.bottom;if(key===lastInsets)return;lastInsets=key;
      try{parent.postMessage({type:'QOQORO_FRAME_INSETS',...insets},location.origin);}catch{}
    }
    visualViewport?.addEventListener('resize',reportInsets);window.addEventListener('resize',reportInsets);
    size();applyLock();fit();
  }
  const observer=new MutationObserver(()=>{if(install())observer.disconnect();});
  observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['data-i']});install();
})();
