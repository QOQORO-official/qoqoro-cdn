# Patches applied to luau-web 1.4.0

The upstream package is two ES modules; QNote loads the VM inside a Blob
worker with `importScripts`, which only takes classic scripts. `scripts/vendor-luau.mjs`
rewrites exactly six things and nothing else — the WebAssembly payload, the
compiler and the VM are untouched.

1. `Luau.Web.Asyncify.js`: the Node-only `createRequire(import.meta.url)` shim
   becomes `var require=undefined`. `import.meta` cannot be parsed in a classic
   script, and a worker never reaches that branch anyway.
2. `Luau.Web.Asyncify.js`: `var _scriptName=import.meta.url` becomes the
   worker's own `self.location.href`. Emscripten uses it to find side files;
   this build has none, the WebAssembly is inside the JavaScript.
3. `Luau.Web.Asyncify.js`: the build-time assertion
   `assert(!ENVIRONMENT_IS_WORKER, "worker environment detected but not enabled …")`
   is removed. The package is built with `-sENVIRONMENT=web,node`, but the
   worker branch right beside it is complete and identical for this build —
   the WebAssembly is embedded, so nothing is ever fetched. QNote runs every
   script in a worker, which is what keeps a runaway program off the UI thread.
4. `Luau.Web.Asyncify.js`: `export default Module` becomes
   `self.LuauWebModule = Module`.
5. `src/index.js`: the `await import(...)` that chooses between the JSPI and
   Asyncify builds becomes `const InternalLuauWasmModule = self.LuauWebModule`.
   Only the Asyncify build is shipped: it needs no browser flags.
6. `src/index.js`: `export { ... }` becomes `self.LuauWeb = { ... }`.

Only the Asyncify build is vendored, so `Luau.Web.JSPI.js` is not shipped.
