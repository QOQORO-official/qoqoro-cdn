## Files: open, save and download .xlsx/.csv, with reading and writing done
## in a worker so a large workbook never freezes the page.
##
## The worker runs this same module (qw_worker_main(FileWorker)). Messages
## are bytes: one op char, a 4-byte job id, then the payload.
##   page -> worker   'P' id name-len name bytes      parse a file
##                    'X' id kind(char) workbook      write xlsx ('x') / csv ('c', active sheet)
##   worker -> page   'R'                              booted
##                    'W' id workbook | 'E' id message | 'B' id bytes
## The worker is optional and watched:
##   - no worker, or none ready within 10 s: queued and later jobs run on the page;
##   - it fails while working (a corrupt file that traps the parser): the jobs it
##     had fail with an error -- not retried on the page, where the same file
##     would stop the grid -- and later jobs run on the page;
##   - a job unanswered for 120 s fails ("stopped responding") the same way.

import std/[tables, strutils, base64, json]
import ../web/qweb
import model, formula, xlsx

const FileWorker* = 1'i32

type
  JobKind = enum jobParse, jobWrite
  Job = object
    kind: JobKind
    payload: string
    onWorkbook: proc(wb: Workbook)
    onBytes: proc(data: string)
    onError: proc(msg: string)

var worker = 0'i32
var workerReady = false
var workerDead = false
var jobs = initTable[int, Job]()
var nextJob = 1

proc putU32(s: var string, v: int) =
  for shift in [0, 8, 16, 24]: s.add char((v shr shift) and 0xFF)
proc getU32(s: string, at: int): int =
  ord(s[at]) or (ord(s[at + 1]) shl 8) or (ord(s[at + 2]) shl 16) or (ord(s[at + 3]) shl 24)

proc parseFormulaInto(cell: var Cell, text: string) = cell.setFormula(text)

proc parseBytes*(name, data: string): Workbook =
  ## .xlsx or .csv bytes -> workbook; raises on anything else.
  let lower = name.toLowerAscii
  if lower.endsWith(".csv") or lower.endsWith(".txt") or lower.endsWith(".tsv"):
    let base = name.split({'/', '\\'})[^1]
    return readCsv(data, if base.rfind('.') > 0: base[0 ..< base.rfind('.')] else: "Sheet1")
  if data.len >= 4 and data[0 .. 3] == "PK\x03\x04": return readXlsx(data)
  if lower.endsWith(".xlsx") or lower.endsWith(".xlsm"):
    raise newException(XlsxError, name.split({'/'})[^1] & " is not a valid .xlsx file")
  if data.len >= 8 and data[0 .. 7] == "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1":
    raise newException(XlsxError, "Excel 97-2003 (.xls) files are not supported yet: save it as .xlsx")
  # Text without a known extension: try CSV.
  readCsv(data)

proc writeBytes*(wb: Workbook, kind: char): string =
  if kind == 'c': writeCsv(wb, wb.sheets[wb.active]) else: writeXlsx(wb)

proc runOnPage(id: int) =
  let job = jobs.getOrDefault(id)
  jobs.del(id)
  try:
    case job.kind
    of jobParse:
      let n = getU32(job.payload, 0)
      let name = job.payload[4 ..< 4 + n]
      let wb = parseBytes(name, job.payload[4 + n .. ^1])
      recalc(wb)
      job.onWorkbook(wb)
    of jobWrite:
      let wb = deserialize(job.payload[1 .. ^1], parseFormulaInto)
      job.onBytes(writeBytes(wb, job.payload[0]))
  except CatchableError as e:
    job.onError(e.msg)

proc failWorker(reason: string) =
  ## Stop using the worker. Jobs it never started (it was not ready) run on
  ## the page; jobs it was working on fail with `reason`.
  let booted = workerReady
  workerDead = true
  workerReady = false
  var ids: seq[int]
  for id in jobs.keys: ids.add id
  for id in ids:
    if booted:
      let job = jobs.getOrDefault(id)
      jobs.del(id)
      job.onError(reason)
    else: runOnPage(id)

proc onPageMessage(fromId: int32, data: string, handles: seq[Node]) =
  if fromId != worker or data.len == 0: return
  if data[0] == 'R':
    workerReady = true
    return
  if data.len < 5: return
  let id = getU32(data, 1)
  if not jobs.hasKey(id): return
  let job = jobs[id]
  jobs.del(id)
  try:
    case data[0]
    of 'W':
      let wb = deserialize(data[5 .. ^1], parseFormulaInto)
      recalc(wb)
      job.onWorkbook(wb)
    of 'B': job.onBytes(data[5 .. ^1])
    of 'E': job.onError(data[5 .. ^1])
    else: discard
  except CatchableError as e:
    job.onError(e.msg)

proc ensureWorker() =
  if worker != 0 or workerDead: return
  onMessage = onPageMessage
  onWorkerError = proc(id: int32) =
    if id == worker: failWorker("the file worker failed while reading this file")
  worker = spawnWorker(FileWorker)
  if worker == 0:
    workerDead = true
    return
  setTimeout(10_000, proc() =
    if not workerReady and not workerDead: failWorker("the file worker did not start"))

proc submit(job: Job) =
  let id = nextJob
  inc nextJob
  jobs[id] = job
  ensureWorker()
  if workerDead:
    # Let the page paint the "Opening…" state first.
    setTimeout(0, proc() = runOnPage(id))
    return
  var msg = (if job.kind == jobParse: "P" else: "X")
  msg.putU32(id)
  msg.add job.payload
  postMessage(worker, msg)
  setTimeout(120_000, proc() =
    if jobs.hasKey(id) and not workerDead: failWorker("the file worker stopped responding"))

proc parseInBackground*(name, data: string, onWorkbook: proc(wb: Workbook), onError: proc(msg: string)) =
  var payload = ""
  payload.putU32(name.len)
  payload.add name
  payload.add data
  submit(Job(kind: jobParse, payload: payload, onWorkbook: onWorkbook, onError: onError))

proc writeInBackground*(wb: Workbook, kind: char, onBytes: proc(data: string), onError: proc(msg: string)) =
  submit(Job(kind: jobWrite, payload: $kind & serialize(wb), onBytes: onBytes, onError: onError))

proc usingWorker*(): bool = worker != 0 and workerReady and not workerDead

# ------------------------------------------------------------ worker side --

proc workerMain*() =
  onMessage = proc(fromId: int32, data: string, handles: seq[Node]) =
    if data.len < 5: return
    let id = getU32(data, 1)
    var reply = ""
    try:
      case data[0]
      of 'P':
        let n = getU32(data, 5)
        let name = data[9 ..< 9 + n]
        let wb = parseBytes(name, data[9 + n .. ^1])
        reply = "W"; reply.putU32(id); reply.add serialize(wb)
      of 'X':
        let wb = deserialize(data[6 .. ^1], parseFormulaInto)
        reply = "B"; reply.putU32(id); reply.add writeBytes(wb, data[5])
      else: return
    except CatchableError as e:
      reply = "E"; reply.putU32(id); reply.add e.msg
    postMessage(0, reply)
  postMessage(0, "R")

# --------------------------------------------------------- browser helpers --

proc downloadBytes*(data, fileName, mime: string) =
  let blob = newBlob(data, mime)
  let url = createObjectURL(blob)
  let a = el("a")
  a.setAttribute("href", url)
  a.setAttribute("download", fileName)
  a.style("display", "none")
  discard body.add a
  a.click()
  a.remove()
  setTimeout(5000, proc() = revokeObjectURL(url))

proc mimeFor*(fileName: string): string =
  if fileName.toLowerAscii.endsWith(".csv"): "text/csv"
  else: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

proc saveToServer*(wb: Workbook, path: string, onDone: proc(), onError: proc(msg: string)) =
  ## POST /api/spreadsheet {path, contentBase64}: the vault API of all three servers.
  let lower = path.toLowerAscii
  if lower.endsWith(".xls"):
    onError("Saving as Excel 97-2003 (.xls) is not supported: save the workbook as .xlsx")
    return
  writeInBackground(wb, (if lower.endsWith(".csv"): 'c' else: 'x'), proc(data: string) =
    let body = "{\"path\":" & escapeJson(path) & ",\"contentBase64\":\"" & encode(data) & "\"}"
    fetchPostJson("/api/spreadsheet", body, proc(ok: bool, reply: string) =
      if ok: onDone() else: onError(if reply.len > 0: reply else: "the server refused the file")),
    onError)
