/* boot.js — load app.wasm, attach the recto host adapter and run the Nim app. */
import { createWasiShim, ProcExit } from "./wasi-shim.js";
import { createBindwebRunner } from "./bindweb-runtime.js";
import { runWasmApp } from "./run-wasm.js";
import { createRectoHost } from "./recto-host.js";

(async () => {
  const consoleEl = document.getElementById("nim-console");
  const onLog = (msg, kind) => {
    if (kind === "error" || kind === "stderr") console.error("[nim]", msg);
    if (!consoleEl || (kind !== "error" && kind !== "stderr")) return;
    consoleEl.hidden = false;
    consoleEl.textContent += msg + "\n";
  };
  const host = createRectoHost();
  window.__rectoHost = host;
  try {
    const res = await fetch(window.__APP_WASM_URL__ || "app.wasm", { cache: "no-store" });
    if (!res.ok) throw new Error("app.wasm: HTTP " + res.status);
    const bytes = new Uint8Array(await res.arrayBuffer());
    const result = await runWasmApp({
      wasmBytes: bytes,
      outputEl: document.getElementById("app"),
      onLog,
      createWasiShim,
      ProcExit,
      createBindwebRunner: (el) => {
        // The generic runner plus the host's own imports; memory is handed
        // to the host the moment the instance connects, before _start runs.
        const runner = createBindwebRunner(el);
        Object.assign(runner.imports.env, host.envImports);
        return { ...runner, connect(instance) { host.setMemory(instance.exports.memory); return runner.connect(instance); } };
      },
    });
    if (!result.ok) throw new Error(result.error || "WASM start failed");
  } catch (e) {
    onLog(String(e?.message || e), "error");
  }
})();
