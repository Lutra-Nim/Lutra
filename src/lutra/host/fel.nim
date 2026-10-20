## Loads a program into a D1's DRAM through its boot ROM's USB loader, FEL,
## and starts it: what the D1's `nim flash` does, and its reset, for
## `nim monitor -d:reset` and the checks. `lutra/chips/d1/host` builds it.
##
##   fel --port=P --xfel=X (--image=BIN | --flashed=DIR)
##
## With `--flashed`, the image is the one `nim flash` last wrote to the board
## on P. A chip not waiting in FEL is first sent a break on its console,
## which a Lutra program takes as asking to start again into FEL, and then,
## if that brought nothing, `efex` once a second, which U-Boot on its SD card
## takes the same way. It ends with a code of `Exit`.

import std/[os, osproc, parseopt, strutils, times, streams]
import serialport, ../tooling

var port, xfel, image, flashed: string

proc finish(code: Exit, message = "") {.noreturn.} =
  if message != "": stderr.writeLine message
  quit ord(code)

proc run(arguments: varargs[string], quiet = true): tuple[said: string, code: int] =
  ## Runs xfel, without a shell
  let p = try: startProcess(xfel, args = @arguments,
      options = if quiet: {poStdErrToStdOut} else: {poParentStreams})
    except OSError as e: finish notSetUp, "Error: can't run " & xfel & ": " & e.msg
  result.said = if quiet: p.outputStream.readAll else: ""
  result.code = p.waitForExit
  p.close

proc waiting(): bool =
  ## Whether the boot ROM is waiting for a program over USB
  let (said, code) = run("version")
  code == 0 and "D1" in said

proc waitFor(seconds: float, every: proc()): bool =
  ## Until the chip is waiting in FEL, calling `every` once a second
  let start = epochTime()
  var next = start
  while epochTime() - start < seconds:
    if waiting(): return true
    if epochTime() >= next:
      every()
      next += 1
    sleep 100

for kind, key, value in getopt():
  case key
  of "port": port = value
  of "xfel": xfel = value
  of "image": image = value
  of "flashed": flashed = value
  else: finish buildFailed, "Error: fel does not know --" & key & "."

if xfel == "" or port == "": finish buildFailed, "Error: give --port and --xfel."
if flashed != "":
  let note = flashed / canonical(port).lastPathPart
  if not fileExists(note): finish noBoard, "Error: nothing has been flashed to the board on " & port & " from here."
  image = readFile(note).strip.changeFileExt("bin")
if not fileExists(image): finish buildFailed, "Error: there is no image " & image & "."

if not waiting():
  var link = try: openPort(port, 115200)
    except OSError as e: finish noBoard, "Error: " & e.msg & "."
  link.sendBreak()
  if not waitFor(4, proc() = discard) and
      not waitFor(8, proc() = link.write("efex\r")):
    finish noBoard, "Error: the D1 did not come back to wait for a program over USB. Is its USB-C port " &
      "plugged into this computer? If a program has hung, press the board's reset button, and try again."
  link.close()

# The program has nowhere to live until the DRAM is set up
for step in [@["ddr", "d1"], @["write", "0x40000000", image], @["exec", "0x40000000"]]:
  if run(step, quiet = false).code != 0:
    finish noBoard, "Error: xfel " & step[0] & " failed."
