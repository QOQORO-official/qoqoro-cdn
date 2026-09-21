// Sign-in page. Reads GET /api/session first: an open server (no login)
// or an existing session goes straight to the workspace; a server on its
// first run (setup: true) turns the form into account creation.
const server = VaultClient.serverFromPage();
const vault = new VaultClient(server, {onUnauthorized: () => {}});
const toWorkspace = () => VaultClient.navigate('index.html', server);
const form = document.querySelector('form');
const message = document.querySelector('#message');
const submitButton = form.querySelector('button[type=submit]');
let setup = false, setupToken = '', sessionReady = false;
submitButton.disabled = true;
try { if (!VaultClient.embedded) history.replaceState(null, '', location.pathname); } catch {}

vault.session().then(async (state) => {
  if (state.authenticated) { toWorkspace(); return; }
  setup = !!state.setup;
  setupToken = state.setupToken || '';
  if (setup && !setupToken) throw Error('Setup authorization is missing. Restart the server to create the first account.');
  if (!setup && state.username && !form.username.value) form.username.value = state.username;
  if (setup) {
    document.querySelector('h1').textContent = 'Create your admin account';
    document.querySelector('p.lead').textContent = 'First run: choose a username and a password of at least 12 characters.';
    submitButton.textContent = 'Create account';
    form.password.minLength = 12;
    form.password.autocomplete = 'new-password';
  }
  sessionReady = true;
  submitButton.disabled = false;
  form.dataset.ready = '1';   // the submit handler is live: safe to submit
}).catch((error) => { message.textContent = error.message || 'Cannot connect to the vault server.'; });

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!sessionReady) return;
  submitButton.disabled = true;
  try {
    if (setup) await vault.setup(form.username.value, form.password.value, setupToken);
    else await vault.login(form.username.value, form.password.value);
    try {
      if (window.PasswordCredential && navigator.credentials?.store) await navigator.credentials.store(new PasswordCredential(form));
    } catch (_) {}
    toWorkspace();
  } catch (error) { message.textContent = error.message; }
  finally { submitButton.disabled = false; }
});
