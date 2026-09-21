# qoqoro 1.0.0

```html
<script src="https://cdn.jsdelivr.net/npm/qoqoro@1.0.0/qoqoro.js"></script>
<div id="notes" style="height:100vh"></div>
<script>QOQORO.mount('#notes', { mode: 'editor' });</script>
```

`mode: 'workspace'` with `server: 'https://…'` for the whole app against a
QNote Vault server. Serve every file in this folder together; paths inside
are relative. `.wasm` files must be served as `application/wasm`.
