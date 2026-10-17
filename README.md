# QOQORO

**A word processor, whiteboard, PDF viewer and diagram editor that runs entirely in the browser.**
Add one `<script>` tag and your page has a Word-style editor. No install, no
plugins, no backend required.

QOQORO is written in [Nim](https://nim-lang.org) and compiled to WebAssembly, so the
whole editor (layout, equations, Word import and export) runs on the visitor's
device.

```html
<script src="https://cdn.jsdelivr.net/gh/QOQORO-official/qoqoro-cdn@main/qoqoro.js"></script>
<div id="notes" style="height:100vh"></div>
<script>QOQORO.mount('#notes', { mode: 'editor' });</script>
```

## Features

**Writing**
- Ribbon in the style of Word: *File, Main, Objects, Tables, Layout, Misc*
- Fonts, sizes, bold / italic / underline / strike, colours, headings, numbered and bulleted lists
- Japanese typesetting and fonts (Yu Gothic, Yu Mincho, Meiryo, BIZ UDPGothic, MS Mincho, …)
- Paged layout with page size, margins, headers and footers
- Undo / redo, outline and navigation pane

**Objects**
- Tables with merged cells, column widths, borders and fills
- Pictures and text boxes, inline or floating with text wrapping
- Equations
- Templates studio for reusable document layouts

**Drawing**
- Pen, finger and stylus drawing on the page: ballpoint, fountain pen, calligraphy and marker
- Pressure, colours, sizes, eraser (partial or whole stroke), lasso select
- Stickers, made from any selection
- A separate infinite whiteboard (`.qoscribe`) in the workspace

**Word compatibility**
- Open and save **.docx**: text formatting, lists, tables, pictures, text boxes, headers and footers, equations
- Older Word pictures (WMF / EMF, for example MathType equations and charts) are converted to sharp SVG on import

**Everywhere**
- Desktop, tablet and phone layouts (touch, pinch zoom, on-screen keyboard)
- Light and dark themes, and custom themes
- Works offline in editor mode: Save downloads a `.qnote` file, Open reads one

**Automation**
- Script documents in [Luau](https://luau.org) with Word's object model: `ActiveDocument`, `Selection`, `Paragraphs`, `Tables`, …
- Each program is one undoable step, and it can't reach the network or the page

## Two ways to embed

| `mode` | What you get | Server needed? |
|---|---|---|
| `editor` | The word processor on its own | No. Save downloads a `.qnote`; you can read the document from JavaScript |
| `workspace` | The whole app: file tree, folders, login, editor, whiteboard, PDF viewer, diagrams | Yes, a QNote Vault server |

### Editor

```js
const editor = QOQORO.mount('#notes', {
  mode: 'editor',
  document: 'https://example.com/report.qnote',  // QNote XML, or a URL to fetch it from (optional)
  filename: 'report.qnote',                      // download name when the user saves
  height: '600px',                               // defaults to 100% of the target
});

await editor.ready;
await editor.load(xml);            // replace the document
const xml = await editor.save();   // the current document as QNote XML
editor.destroy();
```

Store the XML wherever you like: your database, an API, `localStorage`. Users
can also connect the editor to a server themselves from **Misc → Server**.

### Workspace

```js
QOQORO.mount('#notes', { mode: 'workspace', server: 'https://notes.example.com' });
```

The workspace signs in to the server, lists its notes and folders, and opens
notes, whiteboards, PDFs and diagrams. The server is anything that speaks the
small QNote Vault HTTP API: notes, folders, uploads, login.

## Automation with Luau

```html
<script src="https://cdn.jsdelivr.net/gh/QOQORO-official/qoqoro-cdn@main/qoqoro.js"></script>
<script src="https://cdn.jsdelivr.net/gh/QOQORO-official/qoqoro-cdn@main/qoqoro-luau.js"></script>
<script>
  const result = await QOQORO.luau.run(`
    local doc = ActiveDocument
    Selection:InsertHeading("Summary", wdStyleHeading2)
    for index, paragraph in doc.Paragraphs do
      Selection:TypeText(\`{index}: {paragraph.Text}\n\`)
    end
  `);
  // { ok: true, applied: true, status: 'Program ran · … command(s)', output: [...] }

  await QOQORO.luau.run(source, { apply: false });   // dry run: report, change nothing
</script>
```

## API reference

```ts
QOQORO.version                 // "1.0.0"
QOQORO.base                    // where the package was loaded from
QOQORO.EMPTY_DOCUMENT          // an empty QNote document
QOQORO.mount(target, options)  // → handle

handle.mode                    // 'editor' | 'workspace'
handle.iframe                  // the editor's frame, for sizing or focus
handle.ready                   // Promise<handle>
handle.destroy()

// editor mode
handle.load(xmlOrUrl)          // Promise
handle.save()                  // Promise<string>  QNote XML

// with qoqoro-luau.js
QOQORO.luau.run(source, { apply?: boolean, path?: string })
```

## File formats

| Extension | What it is |
|---|---|
| `.qnote` | Documents: plain XML, readable and diffable |
| `.docx` | Microsoft Word: import and export |
| `.qoscribe` | Whiteboards (stylus ink) |
| `.qochart` | Diagrams (QoChart) |
| `.pdf` | Viewed in the built-in PDF viewer |

## Versions

`@main` always serves the latest release. To stay on one release, use a
commit instead:

```html
<script src="https://cdn.jsdelivr.net/gh/QOQORO-official/qoqoro-cdn@<commit>/qoqoro.js"></script>
```

## Browser support

Tested on current Chrome and Edge, on desktop and Android. Other current
browsers with WebAssembly support should work.

## License

[Apache License 2.0](LICENSE). Third-party components and their licenses are
listed in [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt).
