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

import std/[macros, os, strutils, algorithm, hashes]
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

proc hostProgram*(program: string, sources: openArray[string]): string =
  ## A program for the host, built the first time it is needed. It is named
  ## after its sources, so that a changed one is built again.
  var text = ""
  for file in sources: text.add readFile(file)
  result = buildDir() / program.splitFile.name & "-" & toHex(hash(text).uint32) & ExeExt
  if not fileExists(result):
    mkDir buildDir()
    try:
      exec quoteShell(getCurrentCompilerExe()) & " c --skipProjCfg --hints:off -d:release --path:" &
        quoteShell(source) & " --nimcache:" & quoteShell(buildDir() / "nimcache" / program.splitFile.name) &
        " --out:" & quoteShell(result) & " " & quoteShell(program)
    except OSError: fail buildFailed, "Error: " & program.lastPathPart & " did not build for the host."

proc helper(): string =
  ## The host's side of the console, `lutra/host/monitor`
  var sources: seq[string]
  for file in ["host/monitor", "host/serialport", "framing", "records", "crc", "tooling"]:
    sources.add source / "lutra" / file & ".nim"
  hostProgram(source / "lutra/host/monitor.nim", sources)

proc helperCommand(arguments: openArray[string]): string =
  result = quoteShell(helper())
  for argument in arguments: result.add " " & quoteShell(argument)

proc run(arguments: varargs[string]): Exit =
  ## Runs the helper, printing what it prints, and gives how it ended
  let status = buildDir() / "monitor.status"
  rmFile status
  try: exec helperCommand(@arguments & ("--status=" & status))
  except OSError: discard # Its status says how
  if not fileExists(status): return noBoard
  Exit(readFile(status).strip.parseInt)

proc serialPorts*(): seq[string] =
  ## Every port the board could be on, in order
  for listed in gorge(helperCommand(["--list"])).splitLines:
    let fields = listed.split('\t')
    if fields.len != 2: continue
    # On Windows the kind of port is in its device's name, \Device\Silabser0
    let (name, device) = (fields[0], fields[1].replace('\\', '/').lastPathPart)
    for prefix in portNames:
      if name.lastPathPart.startsWith(prefix) or device.startsWith(prefix): result.add name
  result.sort()

var chosenPort: string

proc serialPort*(): string =
  if chosenPort != "": return chosenPort
  result = if namedPort != "": namedPort else: getEnv("LUTRA_PORT")
  if result == "":
    let found = serialPorts()
    if found.len != 1:
      fail noBoard, "Expected one serial port and found " & $found.len & " " & $found &
        ". Name the board's with -d:port=... or LUTRA_PORT."
    result = found[0]
  else:
    let (why, code) = gorgeEx(helperCommand(["--check=" & result]))
    if code != 0: fail noBoard, "Error: " & why
  chosenPort = result

proc milliseconds(duration: string): int =
  ## `-d:timeout` as the helper takes it
  try:
    if duration.endsWith("ms"): return duration[0..^3].parseInt
    if duration.endsWith("s"): return duration[0..^2].parseInt * 1000
    if duration.endsWith("m"): return duration[0..^2].parseInt * 60_000
  except ValueError: discard
  fail buildFailed, "Error: -d:timeout=" & duration & " should be as 30s, 500ms or 2m."

proc captureArguments(port, resetCommand, first, last, file: string, seconds: int): seq[string] =
  @["--port=" & port, "--reset=" & resetCommand, "--from=" & first, "--until=" & last,
    "--timeout=" & $(seconds * 1000), "--out=" & file]

proc captureCommand*(port, resetCommand, first, last, file: string, seconds = 120): string =
  ## A command that does what `capture` does, writing to `file`
  helperCommand(captureArguments(port, resetCommand, first, last, file, seconds))

proc capture*(port, resetCommand, first, last: string, seconds = 120): string =
  ## Resets a board and prints what it prints, from the line containing
  ## `first` to the one containing `last`, and gives that too. A panic, or
  ## `last` not seen in time, is a failed check.
  let file = buildDir() / "capture.txt"
  rmFile file
  if run(captureArguments(port, resetCommand, first, last, file, seconds)) == noBoard:
    quit ord(noBoard) # The helper has said why
  result = if fileExists(file): readFile(file).strip(leading = false) else: ""

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
  let ports = serialPorts()
  if ports.len == 0: note "No board attached"
  for port in ports:
    let (why, code) = gorgeEx(helperCommand(["--check=" & port]))
    line code == 0, port, why.strip
    if code != 0: result.add port
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
    exec helperCommand(["--port=" & port, "--note=" & buildDir() / "flashed", "--elf=" & elf(program)])

  task flash, "Build a program and write it to the board":
    need flasher()
    build(program())
    flash(program(), serialPort())

  task monitor, "Read the board's console. -d:until=..., -d:timeout=... and -d:send=... end it":
    let
      port = serialPort()
      (dir, file, ext) = compiler().path.splitFile
      addr2line = if file.endsWith("gcc"): dir / file[0 ..< ^3] & "addr2line" & ext else: "" # Beside it
    var arguments = @["--port=" & port, "--baud=" & $baud, "--flashed=" & buildDir() / "flashed",
      "--addr2line=" & addr2line]
    if resetFirst: arguments.add "--reset=" & resetCommand(port)
    if send != "": arguments.add "--send=" & send
    if until != "": arguments.add "--until=" & until
    if timeout != "": arguments.add "--timeout=" & $milliseconds(timeout)
    quit ord(run(arguments)) # The helper has said what went wrong

  task capture, "Reset the board and write its records as CSV: nim capture > data.csv":
    # The board's records go to stdout and the rest to stderr
    quit ord(run("--port=" & serialPort(), "--reset=" & resetCommand(serialPort()), "--records"))

  task size, "Build a program and show what each memory region holds":
    build(program())
    size(elf(program()), memory)

  task selfcheck, "Run the board's hardware self-check":
    let
      check = source / "lutra/selfcheck" / name # Installed with the package
      expected = readFile(check & ".expected").strip
      program = buildDir() / "selfcheck.nim"
    # Built from the project's folder, so that its config.nims applies. Nim
    # takes that from the program's folder and those above it.
    mkDir buildDir()
    writeFile(program, readFile(check & ".nim"))
    need flasher()
    build(program)
    flash(program, serialPort())
    let got = capture(serialPort(), resetCommand(serialPort()),
      expected.splitLines[0], expected.splitLines[^1]).strip
    if not got.startsWith(expected): # The last line may go on, with the address of a fault
      fail checkFailed, "\nThe self-check FAILED. It should have printed:\n" & expected
    echo "\nThe self-check passed."

  task doctor, "Check that this machine has what the board needs":
    echo "For ", name, ":"
    let missing = problems(compiler(), flasher())
    if missing.len > 0: fail notSetUp, "\nMissing: " & missing.join(", ") & "."
    echo "\nNothing is missing."
