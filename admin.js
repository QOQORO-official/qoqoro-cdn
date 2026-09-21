const form = document.querySelector('form');
const message = document.querySelector('#message');
const reset=document.createElement('button');reset.type='button';reset.textContent='Delete account, credentials and all vault files';
reset.style.cssText='background:#9b1b30;margin-top:24px';document.querySelector('main').append(reset);
reset.onclick=async()=>{
  const vault=form.vault.value;
  if(!confirm('Permanently delete EVERY FILE inside '+vault+', all document link IDs, backups, trash, settings and saved credentials? This cannot be undone.'))return;
  const confirmation=prompt('Type DELETE ALL to confirm permanent deletion');if(confirmation!=='DELETE ALL')return;
  const password=form.currentPassword.value;
  if(!password){message.textContent='Enter your current password above before resetting.';return;}
  reset.disabled=true;
  try{
    const response=await fetch('/api/reset',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({vault,password,confirmation})});
    const data=await response.json();if(!response.ok)throw Error(data.error||'Reset failed');
    localStorage.clear();sessionStorage.clear();
    document.querySelector('main').replaceChildren(Object.assign(document.createElement('p'),{textContent:'Account and '+data.deleted+' documents deleted. Close this window to clear saved browser credentials. Reopen the app to create a new account.'}));
  }catch(error){message.textContent=error.message;reset.disabled=false;}
};
fetch('/api/settings').then(async r => {
  if (r.status === 401) { location.replace('/auth/login'); return; }
  const data = await r.json();
  form.username.value = data.username; form.vault.value = data.vault;
  document.querySelector('#address').textContent = data.address + ' — localhost only';
}).catch(e => message.textContent = e.message);
form.addEventListener('submit', async event => {
  event.preventDefault();
  if (!confirm('Apply settings and sign in again? Switching vault does not move or copy any documents.')) return;
  const button = form.querySelector('button'); button.disabled = true;
  try {
    const response = await fetch('/api/settings', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(Object.fromEntries(new FormData(form)))});
    const data = await response.json();
    if (!response.ok) throw Error(data.error);
    location.replace('/auth/login');
  } catch(e) { message.textContent = e.message; }
  finally { button.disabled = false; }
});
