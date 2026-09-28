// One diagram per workspace. HTTP stays behind VaultClient so Flask and other
// frameworks implement the same /api/qochart contract.
window.VaultChart = class {
  constructor(vault,container,changed){
    this.vault=vault;this.path='';this.fileId='';this.baseline=null;this.changed=changed;
    this.frame=document.createElement('iframe');this.frame.id='chartFrame';this.frame.title='QoChart';this.frame.hidden=true;this.frame.allow='clipboard-read; clipboard-write';container.append(this.frame);
    this.busy=document.createElement('div');this.busy.className='chart-loading';this.busy.hidden=true;
    this.busy.innerHTML='<div class="chart-loading-card"><strong role="status">Opening QoChart…</strong><progress max="100" aria-label="Opening QoChart"></progress></div>';
    container.append(this.busy);
    this.frame.addEventListener('load',()=>{
      const w=this.frame.contentWindow;
      w.addEventListener('keydown',e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='s'){e.preventDefault();e.stopImmediatePropagation();this.chooseSave();}},true);
      w.addEventListener('click',e=>{const b=e.target.closest?.('button,[role="menuitem"]');const label=(b?.getAttribute('aria-label')||b?.getAttribute('title')||b?.textContent||'').trim();if(/^Save(?:\s*Ctrl\+S)?$/i.test(label)){e.preventDefault();e.stopImmediatePropagation();this.chooseSave();}},true);
    });
  }
  // Every open, save, rename, move and delete goes through `path`, so the
  // diagram's name in QoChart's topbar follows the vault file it came from.
  get path(){return this._path||'';}
  set path(value){this._path=value||'';this.showName();}
  showName(){
    const name=(this._path.split('/').pop()||'').replace(/\.qochart$/i,'')||'Untitled diagram';
    try{this.frame?.contentWindow?.editorUi?.setDocumentName?.(name);}catch{}
  }
  async ready(){
    if(!this.loading)this.loading=(async()=>{
      // srcdoc supports script-tag/CDN embeds where HTML is served as text/plain.
      const html=await VaultClient.frameDocument('qochart/index.html');this.frame.srcdoc=html;
      for(let i=0;i<300;i++){try{if(this.frame.contentWindow.editorUi?.ready){this.frame.contentWindow.QOQORO_WORKSPACE_BRIDGE=true;this.baseline=this.snapshot();this.showName();return;}}catch{}await new Promise(r=>setTimeout(r,100));}
      throw Error('QoChart could not finish loading');
    })().catch(e=>{this.loading=null;throw e;});
    return this.loading;
  }
  snapshot(){return this.frame.contentWindow.graph.toJSON();}
  get dirty(){return this.baseline!==null&&this.baseline!==this.snapshot();}
  async replaceCheck(){
    if(!this.dirty)return true;
    return new Promise(resolve=>this.dialog('Unsaved diagram',[
      ['Save and continue',async()=>{await this.save();resolve(true);}],
      ['Discard changes',()=>resolve(true)],['Cancel',()=>resolve(false)]
    ],()=>resolve(false)));
  }
  async open(path,id){
    if(path===this.path&&(!id||id===this.fileId))return true;
    if(!await this.replaceCheck())return false;
    this.busy.hidden=false;this.busy.querySelector('progress').removeAttribute('value');
    this.busy.querySelector('strong').textContent='Loading '+path.split('/').pop()+'…';
    try {
    const data=await this.vault.chart(path,id);await this.ready();
    this.busy.querySelector('progress').value=70;
    this.busy.querySelector('strong').textContent='Preparing diagram…';
    await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
    const w=this.frame.contentWindow,source=data.doc;
    let doc=source;
    if(typeof source==='string'&&source.trim().startsWith('<')){
      const xml=new DOMParser().parseFromString(source,'application/xml');
      const empty=xml.documentElement.tagName==='mxGraphModel'&&!xml.querySelector('parsererror')&&!xml.querySelector('mxCell[vertex="1"],mxCell[edge="1"]');
      doc=empty?{items:[]}:w.PixelMxGraphFormat.parse(source);
    }
    w.graph.fromJSON(doc);w.graph.render();
    this.busy.querySelector('progress').value=100;
    await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
    this.path=data.noteId;this.fileId=data.fileId;this.baseline=this.snapshot();this.changed('Opened '+this.path);return true;
    } finally { this.busy.hidden=true; }
  }
  xml(){const w=this.frame.contentWindow;return w.PixelMxGraphFormat.serialize(JSON.parse(this.snapshot()));}
  async save(){
    if(!this.path){
      let name=prompt('Save diagram to vault as','Untitled.qochart');
      if(!name)throw Error('Save cancelled.');
      if(!/\.qochart$/i.test(name))name+='.qochart';
      await this.vault.create(name);
      const identity=await this.vault.fileId(name);this.path=identity.path;this.fileId=identity.fileId;
    }
    const before=this.snapshot();const result=await this.vault.saveChart(this.path,this.xml(),this.fileId);
    this.path=result.noteId;this.fileId=result.fileId;this.baseline=before;this.changed('Saved '+this.path);
  }
  download(){const url=URL.createObjectURL(new Blob([this.xml()],{type:'application/vnd.qochart+xml'}));const a=document.createElement('a');a.href=url;a.download=this.path.split('/').pop()||'diagram.qochart';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  chooseSave(){this.dialog('Save diagram',[['Save to server',()=>this.save()],['Download copy',()=>this.download()],['Cancel',()=>{}]]);}
  dialog(title,choices,cancel=()=>{}){
    if(document.querySelector('#chart-dialog'))return;
    const d=document.createElement('dialog');d.id='chart-dialog';d.className='vault-dialog';d.setAttribute('aria-label',title);
    const h=document.createElement('h2');h.textContent=title;d.append(h);
    const message=document.createElement('p');message.setAttribute('role','status');
    for(const [label,action] of choices){const b=document.createElement('button');b.textContent=label;b.type='button';b.onclick=async()=>{const buttons=[...d.querySelectorAll('button')];buttons.forEach(x=>x.disabled=true);try{const pending=action();if(pending?.then)await pending;d.close();d.remove();}catch(e){message.textContent=e.message;buttons.forEach(x=>x.disabled=false);}};d.append(b);}
    d.append(message);d.oncancel=cancel;d.onclose=()=>d.remove();d.onclick=e=>{const r=d.getBoundingClientRect();if(e.target===d&&(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)){cancel();d.close();}};document.body.append(d);d.showModal();
  }
};
