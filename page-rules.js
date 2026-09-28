// Shared, accessible default + page-exception forms for CDN page settings.
(() => {
  let serial=0;
  const style=document.createElement('style');style.textContent=`.page-rule-card{border:1px solid #cbd5e1;border-radius:8px;padding:12px;margin:10px 0}.page-rule-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:10px}.page-rule-card label{display:grid;gap:4px;font-size:13px}.page-rule-card input,.page-rule-card select{box-sizing:border-box;width:100%;min-height:36px;padding:6px;font:inherit;color:inherit;background:transparent;border:1px solid #94a3b8;border-radius:5px}.page-rule-card input[type=checkbox]{width:18px;min-height:18px}.page-rule-card h3{margin:0 0 10px;font-size:14px}.page-rule-card button,.page-rule-add{min-height:36px;margin-top:10px;padding:6px 12px}.page-rule-error{color:#b91c1c;white-space:pre-wrap}.page-rule-scope{display:flex;align-items:center;gap:8px}@media(pointer:coarse){.page-rule-card input,.page-rule-card select,.page-rule-card button,.page-rule-add{min-height:44px}}`;
  document.head.append(style);
  const patterns=[['0','Blank'],['1','Dots'],['2','Grid'],['3','Lines (ruled notebook)'],['4','Lines + red margin']];
  function field(parent,label,value,options){
    const wrap=document.createElement('label');wrap.textContent=label;
    const input=document.createElement(options?'select':'input');input.id='page-rule-'+(++serial);
    if(options)for(const [v,text] of options){const o=document.createElement('option');o.value=v;o.textContent=text;input.append(o);}
    else {input.type='number';input.step='0.5';input.required=true;}
    input.value=String(value);wrap.append(input);parent.append(wrap);return input;
  }
  function check(input,min,max){input.min=String(min);input.max=String(max);return input;}
  function controls(parent,value,kind){
    const grid=document.createElement('div');grid.className='page-rule-grid';parent.append(grid);
    if(kind==='paper'){
      const pattern=field(grid,'Page pattern',value.pattern??0,patterns);
      const align=field(grid,'Line alignment',value.align||'manual',[['manual','Manual spacing'],['body','Align to body text (ignore floats)']]);
      const spacing=check(field(grid,'Line / dot spacing (px)',value.spacing??24),4,240);
      const offset=check(field(grid,'Vertical position / offset (px)',value.offset??0),-500,500);
      const note=document.createElement('small');note.textContent='Body alignment follows actual laid-out text baselines, including mixed font sizes. Spacing is used on empty pages and for horizontal dot spacing; offset moves the pattern up/down.';parent.append(note);
      return ()=>({pattern:Number(pattern.value),align:align.value,spacing:Number(spacing.value),offset:Number(offset.value)});
    }
    const columns=field(grid,'Columns',value.columns??1,[['1','1 column'],['2','2 columns'],['3','3 columns']]);
    const gap=check(field(grid,'Column gap (px)',value.gap??24),0,400);
    const rule=field(grid,'Line between columns',value.rule?'yes':'no',[['no','No'],['yes','Yes']]);
    return ()=>({columns:Number(columns.value),gap:Number(gap.value),rule:rule.value==='yes'});
  }
  function form(parent,defaults,rules,currentPage,kind){
    const scope=document.createElement('label');scope.className='page-rule-scope';const all=document.createElement('input');all.type='checkbox';all.checked=!rules.length;scope.append(all,'Apply to all pages');parent.append(scope);
    const base=document.createElement('section');base.className='page-rule-card';const heading=document.createElement('h3');base.append(heading);parent.append(base);const readDefault=controls(base,defaults,kind);
    const exceptions=document.createElement('section');parent.append(exceptions);const rows=document.createElement('div');exceptions.append(rows);
    let entries=[];
    const add=(value)=>{
      const row=document.createElement('section');row.className='page-rule-card';rows.append(row);
      const page=check(field(row,'Page number (1-based)',value.page??currentPage),1,100000);page.step='1';
      const read=controls(row,value,kind),entry={row,page,read};entries.push(entry);
      const remove=document.createElement('button');remove.type='button';remove.textContent='Remove page rule';remove.onclick=()=>{row.remove();entries=entries.filter(x=>x!==entry);};row.append(remove);
    };
    for(const row of rules)add(row);
    const button=document.createElement('button');button.type='button';button.className='page-rule-add';button.textContent='Add page rule';button.onclick=()=>{let page=currentPage;const used=new Set(entries.map(e=>Number(e.page.value)));while(used.has(page)&&page<100000)page++;add({...readDefault(),page});};exceptions.append(button);
    const sync=()=>{exceptions.hidden=all.checked;heading.textContent=all.checked?'All pages':'Default for unspecified pages';if(!all.checked&&!entries.length)add({...readDefault(),page:currentPage});};all.onchange=sync;sync();
    const error=document.createElement('p');error.className='page-rule-error';error.setAttribute('role','alert');parent.append(error);
    return {read(){
      error.textContent='';const seen=new Set();
      try{
        for(const input of parent.querySelectorAll('input[type=number]'))if(!input.closest('[hidden]')&&!input.checkValidity()){input.reportValidity();throw Error('Enter valid spacing, offset and page numbers.');}
        const result=[];
        if(!all.checked){if(!entries.length)throw Error('Add at least one page rule, or choose all pages.');for(const entry of entries){const page=Number(entry.page.value);if(seen.has(page))throw Error('Page '+page+' has more than one rule.');seen.add(page);result.push({page,...entry.read()});}}
        return {defaults:readDefault(),rules:result};
      }catch(e){error.textContent=e.message;throw e;}
    }};
  }
  window.QNotePageRules={
    paper(parent){const stored=window.QNoteSketch?.pageSettings||{};const current=Number(document.querySelector('#status-cursor')?.textContent.match(/Page\s+(\d+)/)?.[1])||1;return form(parent,stored.defaults||{pattern:window.QNoteSketch?.pagePattern||0},Array.isArray(stored.rules)?stored.rules:[],current,'paper');},
    columns(parent,settings,current){
      const legacy=settings.columnsAllPages===false&&!Array.isArray(settings.columnOverrides);
      const base={columns:legacy?1:settings.columns||1,gap:settings.columnGap??24,rule:!!settings.columnRule};
      const rules=settings.columnOverrides|| (legacy?(settings.columnPages||[]).map(page=>({page,columns:settings.columns,gap:settings.columnGap,rule:settings.columnRule})):[]);
      const ui=form(parent,base,rules,current,'columns');return {read(){const v=ui.read();return {columns:v.defaults.columns,columnGap:v.defaults.gap,columnRule:v.defaults.rule,columnOverrides:v.rules,columnsAllPages:!v.rules.length,columnPages:[]};}};
    }
  };
})();
