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
##   nim size hello.nim       Build, and show what each memory region holds
##   nim selfcheck            Run the board's hardware self-check
##
## The serial port is found when only one is attached. Otherwise name it with
## `-d:port=/dev/ttyUSB1` before the task, or in `LUTRA_PORT`. `monitor` takes
## `-d:reset` to reset the board before it starts reading, and `-d:baud=...`.

import std/[macros, os, strutils]

const
  namedPort {.strdefine: "port".} = ""
  baud {.intdefine.} = 115200
  resetFirst {.booldefine: "reset".} = false
  source = currentSourcePath().parentDir.parentDir ## Holds lutra.nim

macro importBoard(name: static string) =
  let file = source / "lutra/boards" / name
  if not fileExists(file & ".nim"):
    error "There is no board named '" & name & "' in " & file.parentDir
  newTree(nnkImportStmt, newLit(file))

proc arguments(): tuple[switches, program: string] =
  ## Splits `nim -d:x flash hello.nim` into "-d:x" and "hello.nim"
  var positional: seq[string]
  for i in 1..paramCount():
    if paramStr(i).startsWith("-"): result.switches.add paramStr(i) & " "
    else: positional.add paramStr(i)
  if positional.len > 1: result.program = positional[1]

proc program*(): string =
  result = arguments().program
  if result == "": quit "Which program? For example: nim " & getCommand() & " hello.nim"

proc buildDir*(): string = thisDir() / "build"
  ## Next to the project's config.nims

proc elf*(program: string): string =
  buildDir() / program.lastPathPart.changeFileExt("elf")

proc compile*(program: string, switches = "") =
  selfExec arguments().switches & switches & " c " & quoteShell(program)

proc serialPort*(): string =
  result = if namedPort != "": namedPort else: getEnv("LUTRA_PORT")
  if result == "":
    var found: seq[string]
    for file in listFiles("/dev"):
      for prefix in ["ttyUSB", "ttyACM", "cu.usbserial", "cu.usbmodem"]:
        if file.extractFilename.startsWith(prefix): found.add file
    if found.len != 1:
      quit "Expected one serial port and found " & $found.len & " " & $found &
        ". Name the board's with -d:port=... or LUTRA_PORT."
    result = found[0]

proc console(resetCommand, reader: string): string =
  ## A shell command that reads the board's console. The port is opened once
  ## and held, so that nothing sent after a reset is lost before reading starts.
  "exec 3<>" & serialPort() & "; " & resetCommand & "; stty " & $baud &
    " raw -echo -hupcl <&3; " & reader & " <&3"

proc capture*(resetCommand, first, last: string): string =
  ## Resets the board and returns what it prints from the line containing
  ## `first` to the one containing `last`
  putEnv("LUTRA_FIRST", first)
  putEnv("LUTRA_LAST", last)
  let reader = "timeout 120 awk 'index($0, ENVIRON[\"LUTRA_FIRST\"]) { on = 1 } on { print } " &
    "on && index($0, ENVIRON[\"LUTRA_LAST\"]) { exit }'"
  gorge("sh -c " & quoteShell(console(resetCommand, reader))).replace("\r", "")

template board*(name: static string) =
  importBoard(name)
  # What a board brings with it
  mixin memory, configure, audit, checkFlasher, flash, size, resetCommand

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
  switch("define", "danger")
  switch("opt", "size")

  configure(memory, buildDir())

  proc build(program: string, switches = "") {.inject, used.} =
    ## Compiles, links and checks the result
    compile(program, switches)
    audit(elf(program))

  task build, "Compile, link and check a program":
    build(program())

  task flash, "Build a program and write it to the board":
    checkFlasher()
    build(program())
    flash(elf(program()), memory, serialPort())

  task monitor, "Read the board's console":
    exec "sh -c " & quoteShell(console(
      if resetFirst: resetCommand(serialPort()) else: "true", "cat"))

  task size, "Build a program and show what each memory region holds":
    build(program())
    size(elf(program()), memory)

  task selfcheck, "Run the board's hardware self-check":
    let
      check = source.parentDir / "checks" / name # Only in Lutra's repository
      expected = readFile(check & ".expected").strip
    checkFlasher()
    build(check & ".nim")
    flash(elf(check), memory, serialPort())
    let got = capture(resetCommand(serialPort()),
      expected.splitLines[0], expected.splitLines[^1]).strip
    echo got
    if got != expected:
      quit "\nThe self-check FAILED. It should have printed:\n" & expected
    echo "\nThe self-check passed."
