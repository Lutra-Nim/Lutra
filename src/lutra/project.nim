## The host side of a Lutra project. In `config.nims`:
##
##   import lutra/project
##   board "esp32c3_devkitm1"
##
## selects the board, and with it the compiler, its flags and these tasks:
##
##   nim build hello.nim      Compile, link and check the result
##   nim flash hello.nim      Build, and write to the board
##   nim monitor              Read the board's console
##   nim capture > data.csv   Reset the board, and write its records as CSV
##   nim size hello.nim       Build, and show what each memory region holds
##   nim selfcheck            Run the board's hardware self-check
##   nim doctor               Check that this machine has what the board needs
##
## The serial port is found when only one board of the kind is attached.
## Otherwise name it with `-d:port=/dev/ttyUSB1` before the task, or in
## `LUTRA_PORT`. `-d:board=...` builds for another board than the one
## `config.nims` names.
##
## `monitor` reads until stopped, or the board stops at a panic or a fault. It
## takes, before the task's name:
##
##   -d:reset            Reset the board before reading
##   -d:send=AT+GMR      Send a line, ended by CR LF: at once, or a second after the reset
##   -d:until=PASS       End at the first line holding PASS
##   -d:timeout=30s      End after 30 s, or 500ms, or 2m. With `until`, a failure
##   -d:baud=921600      Read at another rate than 115200
##
## Every task ends with one of the codes of `Exit`, in `lutra/tooling`.

import std/[macros, os, strutils, algorithm]
import tooling
export tooling

const
  namedPort {.strdefine: "port".} = ""
  otherBoard {.strdefine: "board".} = ""
  baud {.intdefine.} = 115200
  resetFirst {.booldefine: "reset".} = false
  send {.strdefine.} = ""
  until {.strdefine.} = ""
  timeout {.strdefine.} = ""
  source = currentSourcePath().parentDir.parentDir ## Holds lutra.nim

macro importBoard(name: static string) =
  let file = source / "lutra/boards" / name
  if not fileExists(file & ".nim"):
    error "There is no board named '" & name & "' in " & file.parentDir
  newTree(nnkImportStmt, newLit(file))

proc arguments(): tuple[switches, task, program: string] =
  ## Splits `nim -d:x flash hello.nim` into "-d:x", "flash" and "hello.nim"
  var positional: seq[string]
  for i in 1..paramCount():
    if paramStr(i).startsWith("-"): result.switches.add paramStr(i) & " "
    else: positional.add paramStr(i)
  if positional.len > 0: result.task = positional[0]
  if positional.len > 1: result.program = positional[1]

proc program*(): string =
  result = arguments().program
  if result == "": quit "Which program? For example: nim " & arguments().task & " hello.nim"

proc buildDir*(): string = thisDir() / "build"
  ## Next to the project's config.nims

proc elf*(program: string): string =
  buildDir() / program.lastPathPart.changeFileExt("elf")

proc compile*(program: string, switches = "") =
  try: selfExec arguments().switches & switches & " c " & quoteShell(program)
  except OSError: quit ord(buildFailed) # The compiler has said why

var portNames: seq[string] ## How the host names the port of the board's console

proc serialPorts*(): seq[string] =
  ## Every port the board could be on, in order
  for file in listFiles("/dev"):
    for prefix in portNames:
      if file.extractFilename.startsWith(prefix): result.add file
  result.sort()

proc serialPort*(): string =
  result = if namedPort != "": namedPort else: getEnv("LUTRA_PORT")
  if result == "":
    let found = serialPorts()
    if found.len != 1:
      fail noBoard, "Expected one serial port and found " & $found.len & " " & $found &
        ". Name the board's with -d:port=... or LUTRA_PORT."
    result = found[0]
  elif gorgeEx("test -e " & quoteShell(result)).exitCode != 0: # A device is no file to `fileExists`
    fail noBoard, "There is no serial port " & result & "."

proc console(port, resetCommand, reader: string): string =
  ## A shell command that reads a board's console. The port is opened once and
  ## held, so that nothing sent after a reset is lost before reading starts.
  ## What was sent before is dropped: a debug probe keeps it until the port is
  ## opened.
  let mode = "stty " & $baud & " raw -echo -hupcl <&3; "
  "exec 3<>" & port & "; " & mode & "timeout 0.2 cat <&3 >/dev/null; " & resetCommand & "; " &
    mode & "{ " & reader & "; } <&3"

proc seconds(duration: string): string =
  ## `-d:timeout` as `timeout` the command takes it
  try:
    if duration.endsWith("ms"): return $(duration[0..^3].parseInt / 1000)
    if duration[^1] in {'s', 'm'}: return $duration[0..^2].parseInt & duration[^1]
  except ValueError: discard
  fail buildFailed, "Error: -d:timeout=" & duration & " should be as 30s, 500ms or 2m."

const monitorReader = """
  # Prints the console, naming the line of the program an address of a panic
  # or a fault is in. Ends with 0 at `until`, 2 at a panic or a fault, which
  # stop the board, and 1 if the port closes.
  BEGIN { until = ENVIRON["LUTRA_UNTIL"]; elf = ENVIRON["LUTRA_ELF"]; tool = ENVIRON["LUTRA_ADDR2LINE"] }
  { sub(/\r$/, "") }
  elf != "" && /^(Panic|Fault): |^ +last call from / && match($0, /(at|from) 0x[0-9a-f]+/) {
    address = substr($0, RSTART, RLENGTH); sub(/.* /, "", address)
    where = ""; command = tool " -e " elf " " address; command | getline where; close(command)
    sub(/ .*/, "", where); sub(/.*\//, "", where)
    if (where !~ /^\?/ && sub(/:/, "(", where)) $0 = $0 ", " where ")"
  }
  { print; fflush() }
  until != "" && index($0, until) { done = 1; exit 0 }
  fault || /^Panic: / { done = 1; exit 2 }
  /^Fault: / { fault = 1 }
  END { if (!done) exit 1 }
"""

proc flashedRecord(port: string): string =
  ## Where `flash` notes which program went to the board on `port`
  buildDir() / "flashed" / gorge("readlink -f " & quoteShell(port)).lastPathPart

proc monitorCommand(port, addr2line: string): string =
  ## What `nim monitor` runs, whose status is the reader's
  putEnv("LUTRA_SEND", send)
  putEnv("LUTRA_UNTIL", until)
  putEnv("LUTRA_READER", monitorReader)
  putEnv("LUTRA_ADDR2LINE", addr2line)
  putEnv("LUTRA_ELF", if addr2line != "" and fileExists(flashedRecord(port)): readFile(flashedRecord(port)) else: "")
  # After a reset the line waits a second, for the program to be running
  if send != "": result = (if resetFirst: "sleep 1; " else: "") & "printf '%s\\r\\n' \"$LUTRA_SEND\" >&3; "
  if timeout != "": result.add "timeout " & seconds(timeout) & " "
  result.add "env LC_ALL=C awk \"$LUTRA_READER\"" # Bytes, whatever they are

proc captureCommand*(port, resetCommand, first, last: string, seconds = 120): string =
  ## A shell command that resets a board and prints what it prints, from the
  ## line containing `first` to the one containing `last`
  putEnv("LUTRA_FIRST", first)
  putEnv("LUTRA_LAST", last)
  # Each line is flushed, so that a board that stops half way still shows how far it got
  let reader = "timeout " & $seconds & " awk 'index($0, ENVIRON[\"LUTRA_FIRST\"]) { on = 1 } " &
    "on { print; fflush() } on && index($0, ENVIRON[\"LUTRA_LAST\"]) { exit }'"
  "sh -c " & quoteShell(console(port, resetCommand, reader))

proc capture*(port, resetCommand, first, last: string, seconds = 120): string =
  gorge(captureCommand(port, resetCommand, first, last, seconds)).replace("\r", "")

proc problems(compiler, flasher: Tool): seq[string] =
  ## What `nim doctor` finds missing, printing what it checks as it goes
  proc line(good: bool, what, detail: string) =
    echo (if good: "  ok       " else: "  MISSING  "), what, (if detail != "": "  " & detail else: "")
  proc note(what: string) = echo "  note     ", what
  let nimOk = (NimMajor, NimMinor, NimPatch) >= (2, 2, 6)
  line nimOk, "Nim " & NimVersion, (if nimOk: "" else: "Lutra needs 2.2.6 or later.")
  if not nimOk: result.add "Nim"
  for tool in [compiler, flasher]:
    line tool.path != "", tool.name, (if tool.path != "": tool.path else: tool.install)
    if tool.path == "": result.add tool.name
  for exe in ["sh", "stty", "awk", "timeout"]:
    if findExe(exe) == "":
      line false, exe, "The tasks need it, and so Linux for now."
      result.add exe
  let ports = serialPorts()
  if ports.len == 0: note "No board attached"
  for port in ports:
    let usable = gorgeEx("test -r " & port & " -a -w " & port).exitCode == 0
    line usable, port, (if usable: "" else: "You can't open it. Join its group, " &
      gorge("stat -c %G " & port) & ", with `sudo usermod -aG " & gorge("stat -c %G " & port) &
      " $USER`, then log in again.")
    if not usable: result.add port
  if ports.len > 1:
    note $ports.len & " boards attached: name one with -d:port=... or LUTRA_PORT"

template board*(default: static string) =
  const name = (if otherBoard != "": otherBoard else: default)
  importBoard(name)
  # What a board brings with it
  mixin memory, consolePorts, configure, audit, compiler, flasher, flash, size, resetCommand
  portNames = @consolePorts

  switch("define", "lutraBoard=" & name)
  switch("path", source)
  switch("out", elf(projectName()))
  switch("nimcache", buildDir() / "nimcache" / projectName())

  # No operating system and no heap
  switch("os", "any")
  switch("mm", "none")
  switch("define", "useMalloc")
  switch("define", "noSignalHandler")
  switch("threads", "off")
  switch("panics", "on")
  switch("exceptions", "goto")
  # Nim's checks stay on, and a failed one is reported by the board, through
  # Lutra's `system/fatal`. `-d:danger` turns them off.
  patchFile("stdlib", "fatal", source / "lutra/patches/fatal")
  if not defined(danger): switch("define", "release")
  # For an address to be named as a line of the program. None of it is on the board.
  switch("debugger", "native")
  switch("lineDir", "on")
  switch("passC", "-gdwarf-4") # The ESP32-C3's binutils can't read GCC 11's DWARF 5
  switch("passC", "-fno-tree-tail-merge") # Each failed check keeps its own call, and so its line
  switch("opt", "size")

  configure(memory, buildDir())

  proc build(program: string, switches = "") {.inject, used.} =
    ## Compiles, links and checks the result
    need compiler()
    compile(program, switches)
    audit(elf(program))

  task build, "Compile, link and check a program":
    build(program())

  proc flash(program: string, port: string) {.inject, used.} =
    ## Writes a built program to the board, and notes which it was
    try: flash(elf(program), memory, port)
    except OSError: fail noBoard, "Error: nothing was written to the board on " & port & "."
    mkDir buildDir() / "flashed"
    writeFile(flashedRecord(port), elf(program))

  task flash, "Build a program and write it to the board":
    need flasher()
    build(program())
    flash(program(), serialPort())

  task monitor, "Read the board's console. -d:until=..., -d:timeout=... and -d:send=... end it":
    let
      port = serialPort()
      status = buildDir() / "monitor.status"
      gcc = compiler().path
      addr2line = if gcc.endsWith("gcc"): gcc[0 ..< ^3] & "addr2line" else: "" # Beside it
    mkDir buildDir()
    rmFile status
    exec "sh -c " & quoteShell(console(port, if resetFirst: resetCommand(port) else: "true",
      monitorCommand(port, addr2line)) & "; echo $? > " & quoteShell(status))
    case (if fileExists(status): readFile(status).strip else: "")
    of "0": discard
    of "2": fail checkFailed, "\nThe board stopped."
    of "124":
      if until != "": fail checkFailed, "\nThe board did not print " & until & " within " & timeout & "."
    else: fail noBoard, "\nThe board on " & port & " could not be read."

  task capture, "Reset the board and write its records as CSV: nim capture > data.csv":
    # The board's records go to stdout and the rest to stderr, so nothing
    # else may go to stdout
    let decoder = buildDir() / "capture"
    exec getCurrentCompilerExe() & " c --skipProjCfg --hints:off -d:release --path:" & source &
      " --nimcache:" & buildDir() / "nimcache/capture" & " --out:" & decoder & " " &
      source / "lutra/capture.nim" & " >&2"
    exec "sh -c " & quoteShell(console(serialPort(), resetCommand(serialPort()), quoteShell(decoder)))

  task size, "Build a program and show what each memory region holds":
    build(program())
    size(elf(program()), memory)

  task selfcheck, "Run the board's hardware self-check":
    let
      check = source.parentDir / "checks" / name # Only in Lutra's repository
      expected = readFile(check & ".expected").strip
    need flasher()
    build(check & ".nim")
    flash(check, serialPort())
    let got = capture(serialPort(), resetCommand(serialPort()),
      expected.splitLines[0], expected.splitLines[^1]).strip
    echo got
    if not got.startsWith(expected): # The last line may go on, with the address of a fault
      fail checkFailed, "\nThe self-check FAILED. It should have printed:\n" & expected
    echo "\nThe self-check passed."

  task doctor, "Check that this machine has what the board needs":
    echo "For ", name, ":"
    let missing = problems(compiler(), flasher())
    if missing.len > 0: fail notSetUp, "\nMissing: " & missing.join(", ") & "."
    echo "\nNothing is missing."
