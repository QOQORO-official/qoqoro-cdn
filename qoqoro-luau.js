/**
 * qoqoro-luau.js — run Luau programs against an embedded QOQORO editor.
 *
 *   <script src="https://cdn.example.com/qoqoro/qoqoro.js"></script>
 *   <script src="https://cdn.example.com/qoqoro/qoqoro-luau.js"></script>
 *   <div id="notes" style="height:100vh"></div>
 *   <script>
 *     QOQORO.mount('#notes', {mode: 'workspace', server: 'http://127.0.0.1:5000'});
 *
 *     // in the page: the program runs in the editor you can see
 *     const result = await QOQORO.luau.run(`
 *       local doc = ActiveDocument
 *       Selection:InsertHeading(\`Report {doc.Now:sub(1, 10)}\`, wdStyleHeading2)
 *       for index, paragraph in doc.Paragraphs do
 *         Selection:TypeText(\`{index}: {paragraph.Text}\n\`)
 *       end
 *     `);
 *     // {ok: true, applied: true, commands: 9, output: [...], status: 'Program ran · 9 command(s)'}
 *
 *     // on the server: queued through the host, run by whichever window is open
 *     await QOQORO.luau.onServer('notes/report.qnote', source);
 *   </script>
 *
 * The language is Luau — Roblox's typed Lua — and the object model is Word's:
 * ActiveDocument, Selection, Font, ParagraphFormat, Paragraphs, Tables, Fields,
 * Content.Find, PageSetup, plus the wd* constants. See the editor's
 * MISC-TOOLS.md. Programs cannot reach the DOM, the network or a file system,
 * and everything one does lands in the document as a single undoable step.
 */
(function () {
  'use strict';
  if (!window.QOQORO) throw new Error('qoqoro-luau.js: load qoqoro.js first');

  /** The handle a call applies to: the one given, or the last one mounted. */
  function target(handle) {
    if (handle && typeof handle.runProgram === 'function') return handle;
    const mounted = window.QOQORO.mounted || [];
    for (let i = mounted.length - 1; i >= 0; i--) {
      if (typeof mounted[i].runProgram === 'function') return mounted[i];
    }
    throw new Error('QOQORO.luau: mount an editor or workspace first');
  }

  function serverOf(handle, options) {
    const server = options.server || handle.server || '';
    if (!server) throw new Error('QOQORO.luau: no server address — pass {server} or mount with one');
    return String(server).replace(/\/+$/, '');
  }

  const luau = {
    language: 'luau',

    /**
     * Run a program in the mounted editor.
     * @param {string} source
     * @param {{handle?: object, apply?: boolean, save?: boolean, path?: string}} options
     *        apply:false reports what the program would do and changes nothing;
     *        save:false (workspace only) leaves the change unsaved;
     *        path opens that vault document first (workspace only).
     */
    async run(source, options = {}) {
      const handle = target(options.handle);
      await handle.ready;
      return handle.runProgram(String(source || ''), options);
    },

    /** What a program would see: text, selection, paragraphs, fields, page setup. */
    async snapshot(options = {}) {
      const handle = target(options.handle);
      await handle.ready;
      const result = await handle.runProgram('return nil', {apply: false});
      return result.snapshot || result;
    },

    /**
     * Hand the program to the server instead, which gives it to whichever
     * QOQORO window is open. Use this from a page that is not the editor, or
     * to reach a document nobody has opened. The server needs the program API
     * (servers/flask and the Nim web edition have it).
     */
    async onServer(path, source, options = {}) {
      const handle = options.handle || (window.QOQORO.mounted || [])[0] || {};
      const base = serverOf(handle, options);
      const response = await fetch(base + '/api/program', {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          ...(options.token ? {'X-QNote-Automation': options.token} : {}),
        },
        body: JSON.stringify({
          path: path || '', fileId: options.fileId || '',
          source: String(source || ''),
          apply: options.apply !== false, save: options.save !== false,
          timeoutMs: options.timeoutMs || 60000,
        }),
      });
      const text = await response.text();
      let data;
      try { data = text ? JSON.parse(text) : {}; } catch { data = {raw: text}; }
      if (!response.ok) throw Object.assign(new Error(data.error || response.statusText), {status: response.status, data});
      return data;
    },
  };

  window.QOQORO.luau = luau;
})();
