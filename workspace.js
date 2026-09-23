// QNote Vault web workspace: the sidebar, the editor iframe bridge and the
// file operations. Derived from the desktop edition's workspace.js; every
// HTTP request goes through VaultClient (vault-client.js), which is the
// page's whole dependency on the server — see docs/API.md.
const server = VaultClient.serverFromPage();
const vault = new VaultClient(server);
const page = (name) => VaultClient.pageUrl(name, server);
const frame = document.querySelector("#editorFrame");
const list = document.querySelector("#fileList");
const search = document.querySelector("#fileSearch");
const status = document.querySelector("#sendStatus");
let files = [],
  folders = [],
  current = "",
  selectedFolder = "",
  ready = false,
  busy = false;
let currentId = "";
let port,
  linkPort,
  requestId = 0;
function connectLinks() {
  linkPort?.close();
  const channel = new MessageChannel();
  linkPort = channel.port1;
  linkPort.onmessage = async event => {
    const data = event.data || {};
    if (!["NAVIGATE_NOTE", "NAVIGATE_PDF"].includes(data.type)) return;
    const value = (value2, value3) => linkPort.postMessage({
      type: data.type + "_RESULT",
      ok: value2,
      error: value3
    });
    if (busy) {
      value(false, "Wait for the current file operation to finish.");
      return;
    }
    busy = true;
    try {
      let value2 = String(data.noteId || data.path || "");
      if (data.fileId) {
        const file = await vault.resolveId(data.fileId);
        value2 = file.path;
      }
      if (data.type === "NAVIGATE_PDF") {
        await openPdf(value2, data.fileId, data.page, new URLSearchParams(String(data.path || "").split("#")[1] || "").get("annotId") || "");
        value(true);
      } else {
        await open(value2, data.fileId);
        value(current === value2, current === value2 ? "" : "Navigation cancelled");
      }
    } catch (error) {
      say(error.message);
      value(false, error.message);
    } finally {
      busy = false;
    }
  };
  frame.contentWindow.postMessage({
    type: "PORT_INIT"
  }, "*", [channel.port2]);
}
const requests = new Map(),
  openFolders = new Set();
const say = value => status.textContent = value;
function editor(value, value2 = {}, timeoutMs = 20000) {
  if (!ready) return Promise.reject(Error("The editor is still loading"));
  return new Promise((value3, value4) => {
    const value5 = ++requestId;
    const value6 = setTimeout(() => {
      requests.delete(value5);
      value4(Error("Editor did not respond"));
    }, timeoutMs);
    requests.set(value5, {
      resolve: value3,
      reject: value4,
      timer: value6
    });
    port.postMessage({
      type: value,
      id: value5,
      ...value2
    });
  });
}
frame.addEventListener("load", () => {
  ready = false;
  const channel = new MessageChannel();
  port = channel.port1;
  port.onmessage = event => {
    const message = event.data;
    if (message.type === "READY") {
      ready = true;
      connectLinks();
      say("Choose a note, or create a new one");
      return;
    }
    if (message.type === "REQUEST_SAVE") {
      void run(save);
      return;
    }
    if (message.type === "REQUEST_DOCX") {
      showDocx();
      return;
    }
    const value = requests.get(message.id);
    if (!value) return;
    clearTimeout(value.timer);
    requests.delete(message.id);
    if (message.type === "ERROR") value.reject(Error(message.error));else value.resolve(message);
  };
  frame.contentWindow.postMessage({
    type: "VAULT_CONNECT",
    server: server || location.origin,
    features: {docx: true}
  }, "*", [channel.port2]);
});
async function refresh() {
  const node = await vault.files();
  files = node.files;
  folders = node.folders;
  const file = files.find(data => data.fileId === currentId);
  if (file) {
    current = file.path;
    document.querySelector("#currentNote").textContent = current;
  }
  document.querySelector(".workspace-name").textContent = node.root.split(/[\\/]/).pop() || "Vault";
  document.querySelector(".workspace-name").title = node.root;
  render();
}
function render() {
  list.replaceChildren();
  const value = search.value.toLowerCase();
  const value2 = {
    folders: new Map(),
    files: []
  };
  function draw(path) {
    let node = value2;
    for (const value3 of path.split("/").filter(Boolean)) {
      if (!node.folders.has(value3)) node.folders.set(value3, {
        folders: new Map(),
        files: []
      });
      node = node.folders.get(value3);
    }
    return node;
  }
  if (!value) for (const file of folders) draw(file.path);
  for (const file of files.filter(file2 => file2.path.toLowerCase().includes(value))) {
    const value3 = file.path.split("/");
    value3.pop();
    draw(value3.join("/")).files.push(file);
  }
  function draw2(node, value3, value4 = "") {
    for (const [value5, value6] of [...node.folders].sort(([value7], [value8]) => value7.localeCompare(value8))) {
      const value7 = value4 ? value4 + "/" + value5 : value5;
      const details = document.createElement("details");
      details.className = "tree-folder";
      details.open = openFolders.has(value7) || !!value;
      const summary = document.createElement("summary");
      summary.className = "folder-row";
      const span = document.createElement("span");
      span.className = "file-icon";
      span.textContent = "▸";
      const span2 = document.createElement("span");
      span2.className = "folder-name";
      span2.textContent = value5;
      summary.append(span, span2);
      summary.onclick = () => {
        selectedFolder = value7;
        say("Folder: " + value7);
      };
      summary.oncontextmenu = event => {
        event.preventDefault();
        event.stopPropagation();
        showContext(event, value7, "folder");
      };
      installFolderDrop(summary, value7);
      details.ontoggle = () => {
        if (details.open) openFolders.add(value7);else openFolders.delete(value7);
        span.textContent = details.open ? "▾" : "▸";
      };
      const div = document.createElement("div");
      div.className = "tree-children";
      draw2(value6, div, value7);
      details.append(summary, div);
      value3.append(details);
    }
    for (const file of node.files.sort((value5, value6) => value5.name.localeCompare(value6.name))) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "file-item" + (file.path === current ? " selected" : "");
      const span = document.createElement("span");
      span.className = "file-icon";
      span.textContent = "▤";
      const span2 = document.createElement("span");
      span2.className = "file-name";
      span2.textContent = file.name;
      button.append(span, span2);
      button.title = file.path;
      button.draggable = true;
      button.ondragstart = event => {
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("application/x-qnote-vault-path", file.path);
        event.dataTransfer.setData("text/plain", file.path);
        button.classList.add("dragging");
      };
      button.ondragend = () => button.classList.remove("dragging");
      button.onclick = () => run(() => open(file.path));
      button.oncontextmenu = event => {
        event.preventDefault();
        event.stopPropagation();
        showContext(event, file.path);
      };
      value3.append(button);
    }
  }
  draw2(value2, list);
  if (!files.length && !folders.length) list.textContent = "Empty vault. Click + Note to begin.";
}
const pdfFrame = document.createElement('iframe');
pdfFrame.id = 'pdfFrame';
pdfFrame.title = 'PDF Viewer';
pdfFrame.allow = 'clipboard-read; clipboard-write';
pdfFrame.hidden = true;
frame.parentElement.appendChild(pdfFrame);
const paneNav = document.createElement('div');
paneNav.className = 'iframe-nav';
const hotswap = document.createElement('button');
hotswap.className = 'iframe-nav-arrow';
hotswap.textContent = '⇄';
hotswap.title = 'Switch to previous app';
hotswap.setAttribute('aria-label', hotswap.title);
const paneSelect = document.createElement('select');
paneSelect.className = 'iframe-nav-select';
paneSelect.setAttribute('aria-label', 'Switch app');
for (const [value, label] of [['editor', 'QoWrite'], ['pdf', 'PDF Viewer']]) {
  const option = document.createElement('option');
  option.value = value;
  option.textContent = label;
  paneSelect.appendChild(option);
}
paneNav.append(hotswap, paneSelect);
status.before(paneNav);
let activePane = 'editor',
  previousPane = 'pdf',
  pdfId = '';
function switchPane(id) {
  if (id !== activePane) {
    previousPane = activePane;
    activePane = id;
  }
  frame.hidden = id !== 'editor';
  pdfFrame.hidden = id !== 'pdf';
  paneSelect.value = id;
  if (id === 'pdf' && !pdfFrame.getAttribute('src')) pdfFrame.src = 'recto/index.html';
}
paneSelect.onchange = () => switchPane(paneSelect.value);
hotswap.onclick = () => switchPane(previousPane);
async function openPdf(path, id, page = 1, annotId = "") {
  if (!pdfViewer) throw Error('This deployment has no PDF viewer; download the file from its folder instead');
  const identity = id ? await vault.resolveId(id) : await vault.fileId(path);
  if (identity.ext !== '.pdf') throw Error('The linked document is not a PDF');
  await pdfFrame.contentWindow?.__rectoHost?.flush();
  const hash = '#fileId=' + encodeURIComponent(identity.fileId) + '&page=' + Math.max(1, Math.floor(Number(page) || 1)) + (annotId ? '&annotId=' + encodeURIComponent(annotId) : '');
  if (pdfId === identity.fileId && pdfFrame.contentWindow?.__rectoHost) {
    if(pdfFrame.contentWindow.location.hash===hash)await pdfFrame.contentWindow.__rectoHost.navigate();
    else pdfFrame.contentWindow.location.hash = hash;
  } else pdfFrame.src = 'recto/index.html' + hash;
  pdfId = identity.fileId;
  switchPane('pdf');
  say('Opened ' + identity.path);
}
async function open(path, value = "") {
  if (/\.pdf$/i.test(path)) {
    await openPdf(path, value);
    return;
  }
  if (path === current && (!value || value === currentId)) {
    switchPane("editor");
    return;
  }
  if (current && !confirm("Save the current note before opening another? Cancel keeps this note open.")) return;
  if (current) await save();
  const data = await vault.note(path, value || undefined);
  // An older server may hand back a legacy empty JSON list for a note it
  // created; the editor only opens QNote XML, so give it an empty document.
  const doc = Array.isArray(data.doc) && data.doc.length === 0
    ? '<?xml version="1.0"?><qnote v="1"><doc><qotext></qotext></doc></qnote>' : data.doc;
  await editor("LOAD", {
    doc
  });
  current = data.noteId;
  currentId = data.fileId;
  path = current;
  switchPane("editor");
  selectedFolder = path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "";
  document.querySelector("#currentNote").textContent = path;
  render();
  say("Opened " + path);
}
async function save() {
  await pdfFrame.contentWindow?.__rectoHost?.flush();
  if (!current) {
    say("Create or open a vault note before saving.");
    return;
  }
  const path = current;
  say("Saving…");
  const value = await editor("SAVE");
  const data = await vault.saveNoteChunked(path, value.doc, {fileId: currentId || undefined});
  current = data.noteId;
  currentId = data.fileId;
  say("Saved " + path);
  await refresh();
}
async function run(value) {
  if (busy) return;
  busy = true;
  try {
    await value();
  } catch (error) {
    say(error.message);
    alert(error.message);
  } finally {
    busy = false;
  }
}
function newPath(value) {
  return selectedFolder ? selectedFolder + "/" + value : value;
}
document.querySelector("#newNoteHeaderBtn").onclick = () => run(async () => {
  let path = prompt("New note name (in " + (selectedFolder || "vault root") + ")", "Untitled.qnote");
  if (!path) return;
  if (!path.endsWith(".qnote")) path += ".qnote";
  const value = newPath(path);
  await vault.create(value);
  await refresh();
  await open(value);
});
document.querySelector("#newFolderHeaderBtn").onclick = () => run(async () => {
  const value = prompt("New folder name (in " + (selectedFolder || "vault root") + ")");
  if (!value) return;
  await vault.createFolder(newPath(value));
  await refresh();
});
document.querySelector("#saveVault").onclick = () => run(async()=>{
  if(activePane==='pdf'){await pdfFrame.contentWindow?.__rectoHost?.flush();say('PDF annotations saved');}
  else await save();
});
document.querySelector("#refreshVault").onclick = () => run(refresh);
// Where the API lives: an IP address with port, or a domain. Remembered for
// this package origin and passed along as ?server= so login.html agrees.
document.querySelector("#serverSettings").onclick = () => {
  document.getElementById("qoqoro-server-dialog")?.remove();
  const dialog = document.createElement("dialog");
  dialog.id = "qoqoro-server-dialog";
  dialog.style.cssText = "width:min(440px,92vw);padding:20px 22px;border:1px solid #cbd5e1;border-radius:10px;font:13px Inter,'Segoe UI',system-ui,sans-serif;color:#0f172a";
  const h = document.createElement("h2"); h.style.cssText = "margin:0 0 4px;font-size:17px"; h.textContent = "Server";
  const lead = document.createElement("p"); lead.style.cssText = "margin:0 0 14px;color:#64748b";
  lead.textContent = "The QNote Vault server this workspace reads and writes. Leave empty to use the address this page was loaded from.";
  const label = document.createElement("label"); label.style.cssText = "display:grid;gap:4px;font-weight:600;margin-bottom:12px";
  const input = document.createElement("input"); input.type = "url"; input.placeholder = "http://192.168.1.10:5000 or https://notes.example.com";
  input.value = server; input.style.cssText = "padding:8px;border:1px solid #cbd5e1;border-radius:5px;font:inherit;font-weight:400";
  label.append("Server address", input);
  const current = document.createElement("p"); current.style.cssText = "margin:0 0 12px;color:#334155";
  current.textContent = "Currently: " + (server || location.origin + " (this page's origin)");
  const row = document.createElement("div"); row.style.cssText = "display:flex;gap:8px;justify-content:flex-end";
  const button = (text, primary, onclick) => { const b = document.createElement("button"); b.type = "button"; b.textContent = text;
    b.style.cssText = "padding:8px 12px;border-radius:6px;font:inherit;cursor:pointer;border:1px solid " + (primary ? "#2563eb;background:#2563eb;color:#fff" : "#cbd5e1;background:#f8fafc");
    b.onclick = onclick; row.appendChild(b); return b; };
  button("Use this server", true, async () => {
    const base = input.value.trim().replace(/\/+$/, "");
    if (base && !/^https?:\/\//i.test(base)) { current.textContent = "Enter the address with http:// or https://"; return; }
    if (current && !confirm("Switch server? Save the current note first if you need it.")) return;
    VaultClient.rememberServer(base);
    VaultClient.navigate("index.html", base);
  });
  button("Cancel", false, () => dialog.close());
  dialog.append(h, lead, label, current, row);
  dialog.onclose = () => dialog.remove();
  document.body.appendChild(dialog); dialog.showModal(); input.focus();
};
document.querySelector("#vaultRoot").onclick = () => {
  selectedFolder = "";
  say("New items will be created in the vault root");
};
let pdfViewer = false;
(async () => {
  try { const r = await fetch(new URL('recto/index.html', VaultClient.packageBase), {method: 'HEAD', cache: 'no-store'}); pdfViewer = r.ok && /text\/html/.test(r.headers.get('content-type') || '') && !VaultClient.embedded; } catch {}
  if (!pdfViewer) { paneNav.hidden = true; }
  document.querySelector("#adminLink").hidden = !(await vault.supports('settings'));
})();
document.querySelector("#adminLink").onclick = async event => {
  event.preventDefault();
  await run(async () => {
    await pdfFrame.contentWindow?.__rectoHost?.flush();
    if (current) {
      if (!confirm("Save this note and open vault settings?")) return;
      await save();
    }
    VaultClient.navigate("admin.html", server);
  });
};
document.querySelector("#logout").onclick = () => run(async () => {
  await pdfFrame.contentWindow?.__rectoHost?.flush();
  if (current) {
    if (!confirm("Save this note and sign out?")) return;
    await save();
  }
  await vault.logout();
  VaultClient.navigate("login.html", server);
});
search.oninput = render;
addEventListener("keydown", event => {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
    event.preventDefault();
    void run(save);
  }
});
const context = document.querySelector("#context");
async function showDocx() {
  if (busy) return;
  if (!(await vault.supports('docx'))) { alert('This server does not provide DOCX conversion. Use File → Save to download the .qnote instead.'); return; }
  document.getElementById("vault-docx-dialog")?.remove();
  const dialog = document.createElement("dialog");
  dialog.id = "vault-docx-dialog";
  dialog.style.cssText = "width:min(480px,90vw);padding:24px;border:1px solid #9b1b30;border-radius:10px;font:14px Segoe UI";
  const h = document.createElement("h2");
  h.textContent = "Word documents";
  dialog.appendChild(h);
  const p = document.createElement("p");
  p.textContent = "Import a DOCX as a new QNote, or export the current editor document. Some Word-specific content may need adjustment after conversion.";
  dialog.appendChild(p);
  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".docx";
  input.hidden = true;
  dialog.appendChild(input);
  const value = (value2, value3) => {
    const button = document.createElement("button");
    button.textContent = value2;
    button.style.cssText = "padding:9px 12px;margin:4px";
    button.onclick = value3;
    dialog.appendChild(button);
    return button;
  };
  value("Import DOCX", () => input.click());
  input.onchange = () => {
    const value2 = input.files[0];
    if (!value2) return;
    dialog.close();
    void run(async () => {
      if (value2.size > 32 * 1024 * 1024) throw Error("Choose a DOCX under 32 MB");
      const value3 = prompt("Import as a new vault note", newPath(value2.name.replace(/\.docx$/i, ".qnote")));
      if (!value3) return;
      const data = await vault.importDocx(value3, value2);
      await refresh();
      await open(data.path, data.fileId);
      say("Imported " + data.path);
    });
  };
  value("Export DOCX", () => {
    dialog.close();
    void run(async () => {
      const value2 = await editor("SAVE");
      const event = await vault.exportDocx(value2.doc);
      const value3 = Uint8Array.from(atob(event.data), value5 => value5.charCodeAt(0));
      const value4 = URL.createObjectURL(new Blob([value3], {
        type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      }));
      const a = window.document.createElement("a");
      a.href = value4;
      a.download = (current.split("/").pop() || "document.qnote").replace(/\.qnote$/i, ".docx");
      a.click();
      setTimeout(() => URL.revokeObjectURL(value4), 1e3);
      say("DOCX exported");
      if (event.warnings?.length) alert("DOCX exported with these adjustments:\n\n" + event.warnings.join("\n"));
    });
  });
  value("Cancel", () => dialog.close());
  dialog.onclose = () => dialog.remove();
  document.body.appendChild(dialog);
  dialog.showModal();
}
function showContext(value, path, value2 = "file") {
  context.replaceChildren();
  const value3 = value2 === "folder" ? path : value2 === "root" ? "" : path.split("/").slice(0, -1).join("/");
  const value4 = async value6 => {
    let path2 = prompt(value6 === "note" ? "New note name" : "New folder name", value6 === "note" ? "Untitled.qnote" : "");
    if (!path2) return;
    if (value6 === "note" && !path2.endsWith(".qnote")) path2 += ".qnote";
    const value7 = value3 ? value3 + "/" + path2 : path2;
    if (value6 === "note") await vault.create(value7); else await vault.createFolder(value7);
    if (value3) openFolders.add(value3);
    await refresh();
    if (value6 === "note") await open(value7);
  };
  const value5 = [["New note", () => value4("note")], ["New folder", () => value4("folder")], ["Upload QNote / PDF", () => chooseUpload(value3)], ["Refresh", refresh]];
  if (path) value5.push(["Copy relative path", async () => {
    await navigator.clipboard.writeText(path);
    say("Path copied");
  }]);
  if (value2 === "folder") value5.push(["Expand / collapse", async () => {
    if (openFolders.has(path)) openFolders.delete(path);else openFolders.add(path);
    render();
  }]);
  if (value2 === "root") value5.push(["Collapse all folders", async () => {
    openFolders.clear();
    render();
  }]);
  if (value2 === "file") value5.unshift(["Open", () => open(path)], ["Duplicate", async () => {
    if (current === path) await save();
    let path2 = prompt("Duplicate note as", path.replace(/\.qnote$/i, " copy.qnote"));
    if (!path2) return;
    if (!path2.endsWith(".qnote")) path2 += ".qnote";
    await vault.duplicate(path, path2);
    await refresh();
  }], ["Download copy", async () => {
    if (current === path) await save();
    const value6 = await vault.note(path);
    const value7 = URL.createObjectURL(new Blob([typeof value6.doc === "string" ? value6.doc : JSON.stringify(value6.doc)], {
      type: "application/octet-stream"
    }));
    const a = document.createElement("a");
    a.href = value7;
    a.download = path.split("/").pop();
    a.click();
    setTimeout(() => URL.revokeObjectURL(value7), 1e3);
  }], ["Rename / move", async () => {
    const value6 = prompt("New vault-relative path", path);
    if (!value6 || value6 === path) return;
    if (current === path) await save();
    await vault.move(path, value6);
    if (current === path) {
      current = value6;
      document.querySelector("#currentNote").textContent = value6;
    }
    await refresh();
  }], ["Move to Trash", async () => {
    if (!confirm("Move " + path + " to recoverable vault trash?")) return;
    await vault.remove(path);
    if (current === path) {
      current = "";
      currentId = "";
      document.querySelector("#currentNote").textContent = "No vault note selected";
    }
    await refresh();
    say("Moved to the vault trash");
  }]);
  for (const [value6, value7] of value5) {
    if (/\.pdf$/i.test(path) && ["Duplicate", "Download copy"].includes(value6)) continue;
    const button = document.createElement("button");
    button.textContent = value6;
    button.onclick = () => {
      context.hidden = true;
      void run(value7);
    };
    context.append(button);
  }
  context.hidden = false;
  context.style.left = Math.max(0, Math.min(value.clientX, innerWidth - context.offsetWidth)) + "px";
  context.style.top = Math.max(0, Math.min(value.clientY, innerHeight - context.offsetHeight)) + "px";
  context.querySelector("button")?.focus();
}
list.oncontextmenu = event => {
  event.preventDefault();
  showContext(event, "", "root");
};
context.onkeydown = event => {
  const value = [...context.querySelectorAll("button")],
    value2 = value.indexOf(document.activeElement);
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    value[(value2 + (event.key === "ArrowDown" ? 1 : value.length - 1)) % value.length]?.focus();
  }
};
document.addEventListener("pointerdown", value => {
  if (!context.contains(value.target)) context.hidden = true;
});
document.addEventListener("keydown", value => {
  if (value.key === "Escape") context.hidden = true;
});
const divider = document.querySelector("#paneDivider");
divider.onpointerdown = value => {
  divider.setPointerCapture(value.pointerId);
};
divider.onpointermove = value => {
  if (divider.hasPointerCapture(value.pointerId)) document.querySelector(".sidebar").style.width = Math.max(180, Math.min(650, value.clientX)) + "px";
};
void run(async () => {
  const state = await vault.session();
  if (!state.authenticated) { VaultClient.navigate('login.html', server); return; }
  document.querySelector('#logout').hidden = state.username === 'local' && !state.setup && !(await vault.supports('settings'));
  await refresh();
  // Only a signed-in window serves the automation API.
  void automationLoop();
});
let focusTimer;
addEventListener("focus", () => {
  clearTimeout(focusTimer);
  focusTimer = setTimeout(() => {
    if (!busy && ready) void run(refresh);
  }, 250);
});
// Embedded (qoqoro.js): the editor page is fetched and mounted as srcdoc so a
// CDN that will not render HTML still works; served normally, a plain src.
if (VaultClient.embedded) VaultClient.frameDocument("qnote/index.html", "<script>window.QOQORO_EMBED=true;</script>").then((html) => { frame.srcdoc = html; }, (e) => say(e.message));
else frame.src = "qnote/index.html";
const uploadInput = document.createElement('input');
uploadInput.type = 'file';
uploadInput.accept = '.pdf,.qnote';
uploadInput.multiple = true;
uploadInput.hidden = true;
document.body.appendChild(uploadInput);
const uploadButton = document.querySelector('#uploadHeaderBtn');
uploadButton.title = 'Upload PDF or QNote into the selected folder';
let uploadDestination = '';
function chooseUpload(destination = selectedFolder) {
  uploadDestination = destination;
  uploadInput.click();
}
uploadButton.onclick = () => chooseUpload(selectedFolder);
async function uploadFiles(incoming, destination = selectedFolder) {
  let count = 0;
  const errors = [];
  for (const file of incoming) {
    if (!/\.(pdf|qnote)$/i.test(file.name)) {
      errors.push(file.name + ': only PDF and QNote files are supported');
      continue;
    }
    if (file.size > 128 * 1024 * 1024) {
      errors.push(file.name + ': maximum size is 128 MB');
      continue;
    }
    let name = file.name;
    while (files.some(f => f.path.toLowerCase() === (destination ? destination + '/' + name : name).toLowerCase())) {
      name = prompt('A file named ' + name + ' already exists. Enter a different filename:', name);
      if (!name) break;
    }
    if (!name) continue;
    if (/[\\/]/.test(name) || !name.toLowerCase().endsWith(file.name.slice(file.name.lastIndexOf('.')).toLowerCase())) {
      errors.push(file.name + ': keep its extension and use a filename without folders');
      continue;
    }
    try {
      say('Uploading ' + name + '…');
      await vault.upload(destination ? destination + '/' + name : name, file);
      count++;
      await refresh();
    } catch (e) {
      errors.push(file.name + ': ' + e.message);
    }
  }
  if (destination) openFolders.add(destination);
  render();
  say('Uploaded ' + count + ' file(s)' + (errors.length ? ' — ' + errors.join('; ') : ''));
  if (errors.length) alert(errors.join('\n'));
}
uploadInput.onchange = () => {
  const selected = Array.from(uploadInput.files);
  const destination = uploadDestination;
  uploadInput.value = '';
  void run(() => uploadFiles(selected, destination));
};
list.addEventListener('dragover', event => {
  if (event.dataTransfer.types.includes('Files') || event.dataTransfer.types.includes('application/x-qnote-vault-path')) {
    event.preventDefault();
    event.dataTransfer.dropEffect = event.dataTransfer.types.includes('Files') ? 'copy' : 'move';
  }
});
list.addEventListener('drop', event => {
  if (event.dataTransfer.files.length) {
    event.preventDefault();
    void run(() => uploadFiles(Array.from(event.dataTransfer.files), ''));
    return;
  }
  const source = event.dataTransfer.getData('application/x-qnote-vault-path');
  if (source) {
    event.preventDefault();
    void run(() => moveVaultFile(source, ''));
  }
});

function installFolderDrop(element, destination) {
  element.addEventListener('dragover', event => {
    if (!event.dataTransfer.types.includes('Files') && !event.dataTransfer.types.includes('application/x-qnote-vault-path')) return;
    event.preventDefault();
    event.stopPropagation();
    event.dataTransfer.dropEffect = event.dataTransfer.types.includes('Files') ? 'copy' : 'move';
  });
  element.addEventListener('drop', event => {
    event.preventDefault();
    event.stopPropagation();
    selectedFolder = destination;
    if (event.dataTransfer.files.length) {
      void run(() => uploadFiles(Array.from(event.dataTransfer.files), destination));
      return;
    }
    const source = event.dataTransfer.getData('application/x-qnote-vault-path');
    if (source) void run(() => moveVaultFile(source, destination));
  });
}

async function moveVaultFile(source, destination) {
  const name = source.split('/').pop();
  const target = destination ? destination + '/' + name : name;
  if (target === source) {
    say(source + ' is already in this folder');
    return;
  }
  if (files.some(file => file.path.toLowerCase() === target.toLowerCase()))
    throw Error('A file named ' + name + ' already exists in ' + (destination || 'the vault root'));
  await pdfFrame.contentWindow?.__rectoHost?.flush();
  if (current === source) await save();
  await vault.move(source, target);
  if (current === source) {
    current = target;
    document.querySelector('#currentNote').textContent = target;
  }
  if (destination) openFolders.add(destination);
  selectedFolder = destination;
  await refresh();
  say('Moved ' + name + ' to ' + (destination || 'vault root'));
}
window.addEventListener("message", event => {
  if (event.origin === location.origin && event.source === pdfFrame.contentWindow && event.data?.type === "VAULT_FILES_CHANGED") void run(refresh);
});

// ── Luau programs, from the host page and from the server ───────────────────
// The engine lives in the editor frame, so every route into it passes through
// here: QOQORO.runProgram() from the embedding page, and the server's
// /api/program queue for callers that have no page at all (Flask, a cron job).
async function runProgramHere(job) {
  const source = String(job.source || "");
  if (!source.trim()) throw Error("The program is empty");
  if (job.path) await open(String(job.path), String(job.fileId || ""));
  if (!current) throw Error("Open a vault note first");
  // Booting the Luau VM on the first run takes longer than a poke.
  const outcome = await editor("RUN_PROGRAM", {source, apply: job.apply !== false}, 120000);
  const saved = job.save !== false && job.apply !== false;
  if (saved) await save();
  return {ok: true, applied: !!outcome.applied, commands: outcome.commands || 0,
    output: outcome.output || [], status: outcome.status || "", result: outcome.result,
    saved, path: current, fileId: currentId};
}

window.addEventListener("message", async event => {
  if (event.source !== window.parent || event.data?.type !== "QOQORO_RUN_PROGRAM") return;
  const {id} = event.data;
  const reply = (result, error) =>
    window.parent.postMessage({type: "QOQORO_PROGRAM_RESULT", id, result, error}, "*");
  try {
    reply(await runProgramHere(event.data));
  } catch (error) {
    reply(null, error.message || String(error));
  }
});

// A server that implements /api/program hands out jobs posted by anything
// that can reach it; a server that does not simply never answers, and this
// backs off to one poll a minute.
async function automationLoop() {
  let quiet = 0;
  for (;;) {
    let job = null;
    try {
      job = await vault.get("/api/program/next");
      quiet = 0;
    } catch (error) {
      // Signed out: stop, rather than bounce this page to the login form.
      if (error?.status === 401 || error?.status === 403) return;
      // A server without the program API answers 404 once and is left alone.
      quiet = error?.status === 404 || error?.status === 501
        ? 60000 : Math.min(30000, (quiet || 3000) * 2);
    }
    if (quiet) await new Promise(done => setTimeout(done, quiet));
    if (!job || !job.id) continue;
    let result;
    try {
      say("Running a program from the automation API…");
      result = await runProgramHere(job);
      say(result.status || "Program ran");
    } catch (error) {
      result = {ok: false, error: error.message || String(error)};
      say("Automation: " + result.error);
    }
    try {
      await vault.post("/api/program/result", {id: job.id, ...result});
    } catch {}
  }
}

window.addEventListener('message',event=>{
  if(event.origin!==location.origin||event.source!==pdfFrame.contentWindow||event.data?.type!=='updateUrl')return;
  const params=new URLSearchParams(String(event.data.url||'').split('#')[1]||'');
  if(params.get('fileId')||params.get('fetchpdf'))void run(()=>openPdf(params.get('fetchpdf')||'',params.get('fileId'),params.get('page'),params.get('annotId')||''));
});
