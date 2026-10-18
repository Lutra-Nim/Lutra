## The host's side of a board's console, which `nim monitor`, `nim capture`
## and the checks run. `lutra/project` builds it the first time it is needed.
##
##   monitor --port=P [--baud=115200] [--reset=COMMAND] [--send=LINE]
##           [--from=TEXT] [--until=TEXT] [--timeout=MS] [--flashed=DIR]
##           [--addr2line=TOOL] [--records] [--out=FILE] [--status=FILE]
##
## prints the console line by line, from the first holding `from`, naming the
## line of the program an address in a panic or a fault is in. It ends at the
## first line holding `until`, at a panic or a fault, which stop the board, or
## after `timeout`. With `--records` it writes the board's records to stdout as
## CSV, and everything else to stderr. It ends with a code of `Exit`, which it
## also writes to `status`, as NimScript's `exec` can't see it.
##
##   monitor --list                   Every serial port, and its device
##   monitor --check=P                Whether P can be opened, and if not why
##   monitor --port=P --note=DIR --elf=FILE
##                                    Notes that FILE went to the board on P

import std/[os, osproc, parseopt, strutils, times]
import serialport, ../framing, ../records, ../tooling
when not defined(windows): import std/posix

var
  port, reset, sendLine, fromText, until, flashed, addr2line, outFile, statusFile, note, elf: string
  baud = 115200
  timeout = 0 # In ms; 0 for none
  recordsMode = false
  output: File

proc finish(code: Exit, message = "") {.noreturn.} =
  if message != "": stderr.writeLine message
  if statusFile != "": writeFile(statusFile, $ord(code))
  if output != nil: output.close()
  quit ord(code)

# Lines

var
  line: string
  started = false # Since the line holding `fromText`
  fault = false

proc named(text: string): string =
  ## A panic's or fault's line with the line of the program its address is in
  if elf == "" or addr2line == "": return text
  if not (text.startsWith("Panic: ") or text.startsWith("Fault: ") or
      text.strip(trailing = false).startsWith("last call from ")):
    return text
  let at = max(text.find(" at 0x"), text.find(" from 0x"))
  if at < 0: return text
  let address = text[at ..< text.len].splitWhitespace[1].strip(chars = {','})
  let where = try: execProcess(addr2line, args = ["-e", elf, address],
    options = {poUsePath}).splitWhitespace()
    except OSError: @[]
  if where.len == 0 or where[0].startsWith("?"): return text
  text & ", " & where[0].lastPathPart.replace(":", "(") & ")"

proc ended() =
  ## A line has come whole
  let shown = named(line.strip(leading = false, chars = {'\r'}))
  line.setLen 0
  if not started and fromText != "" and fromText notin shown: return
  started = true
  let sink = if recordsMode: stderr else: stdout
  sink.writeLine shown
  sink.flushFile()
  if output != nil: output.writeLine shown
  if until != "" and until in shown: finish passed
  if fault or shown.startsWith("Panic: "): finish checkFailed, "\nThe board stopped."
  if shown.startsWith("Fault: "): fault = true # Its next line says where it was called from

proc text(bytes: openArray[byte]) =
  for b in bytes:
    if b == byte('\n'): ended()
    else: line.add char(b)

# Records, which are packets of `framing`. What came since the last zero is a
# packet once a zero ends it, or text if it does not decode, or once the line
# has been quiet a while.

var
  segment: seq[byte]
  replayed: int
  names = "" # Records before the first names are from before the board was reset

type Segment = object # A link that is never sent to, only replayed
proc send(s: static Segment, c: char) = discard
proc poll(s: static Segment): bool = true
proc receive(s: static Segment): char =
  ## The segment again, then the zero that ended it
  result = if replayed < segment.len: char(segment[replayed]) else: '\0'
  inc replayed

proc packetEnded() =
  if segment.len == 0: return
  replayed = 0
  var packet: array[4096, byte]
  let length = Segment().receiveFrame(packet)
  if length < 1: text(segment)
  elif packet[0] == namesKind:
    var header = ""
    for b in packet[1 ..< length]: header.add char(b)
    if header != names: stdout.writeLine header # They come again every hundredth record
    names = header
  elif packet[0] == valuesKind and names != "":
    var (at, row) = (1, "")
    while at < length:
      if row.len > 0: row.add ','
      row.add $packet.toOpenArray(0, length - 1).getVarint(at)
    stdout.writeLine row
  stdout.flushFile()
  segment.setLen 0

proc received(bytes: openArray[byte]) =
  if not recordsMode:
    text(bytes)
    return
  for b in bytes:
    if b == 0: packetEnded() else: segment.add b

proc quiet() =
  ## Nothing has come for a while
  if recordsMode:
    text(segment)
    segment.setLen 0

# Reading

proc resetBoard() =
  let (said, code) = execCmdEx(reset)
  if code != 0: finish noBoard, said & "\nThe board on " & port & " could not be reset."

proc monitor() =
  var link = try: openPort(port, baud)
    except OSError as e: finish noBoard, "Error: " & e.msg & "."
  # What was sent before is dropped: a debug probe keeps it until the port is
  # opened, and hands it over as it is read
  var buffer: array[4096, byte]
  let opened = epochTime()
  while epochTime() - opened < 0.2:
    try: discard link.read(buffer, 50)
    except OSError: finish noBoard, "\nThe board on " & port & " could not be read."
  if reset != "":
    when defined(windows):
      # A port is opened by one program at a time, and the reset may need it.
      # What the board says straight after the reset is lost.
      link.close()
      resetBoard()
      link = try: openPort(port, baud)
        except OSError as e: finish noBoard, "Error: " & e.msg & "."
    else:
      # The port stays open, so that nothing the board says is lost
      resetBoard()
      link.setBaud(baud)

  let start = epochTime()
  var sendAt = if sendLine == "": Inf elif reset != "": start + 1 else: start # For the program to be running
  while true:
    let now = epochTime()
    if now >= sendAt:
      link.write(sendLine & "\r\n")
      sendAt = Inf
    if timeout > 0 and now - start >= timeout / 1000:
      if line.len > 0: ended()
      if until != "":
        finish checkFailed, "\nThe board did not print " & until & " within " & $(timeout div 1000) & " s."
      finish passed
    let n = try: link.read(buffer, 50)
      except OSError: finish noBoard, "\nThe board on " & port & " could not be read."
    if n == 0: quiet()
    else: received(buffer.toOpenArray(0, n - 1))

proc noteFile(dir: string): string =
  ## Where the name of the program last written to the board on `port` is kept
  dir / canonical(port).lastPathPart

for kind, key, value in getopt():
  case key
  of "port": port = value
  of "baud": baud = value.parseInt
  of "reset": reset = value
  of "send": sendLine = value
  of "from": fromText = value
  of "until": until = value
  of "timeout": timeout = value.parseInt
  of "flashed": flashed = value
  of "addr2line": addr2line = value
  of "records": recordsMode = true
  of "out": outFile = value
  of "status": statusFile = value
  of "note": note = value
  of "elf": elf = value
  of "list":
    for (name, device) in ports(): echo name, "\t", device
    quit 0
  of "check":
    try: openPort(value, 115200).close()
    except OSError as e:
      var why = e.msg & "."
      when not defined(windows):
        if e.errorCode == EACCES.int32:
          why = "You can't open it. Join its group, " & group(value) & ", with `sudo usermod -aG " &
            group(value) & " $USER`, then log in again."
      echo why
      quit ord(noBoard)
    quit 0
  else: finish buildFailed, "Error: monitor does not know --" & key & "."

if port == "": finish buildFailed, "Error: which port? Give --port."
if note != "":
  createDir note
  writeFile(noteFile(note), elf)
  quit 0
if flashed != "" and fileExists(noteFile(flashed)): elf = readFile(noteFile(flashed))
if outFile != "": output = open(outFile, fmWrite)
monitor()
