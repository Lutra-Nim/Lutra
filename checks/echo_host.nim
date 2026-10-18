## The host's side of `nim echo`: resets the board, sends it 64 KB of random
## bytes at 921600 baud, and checks that they all come back.
##
##   echo_host PORT RESET-COMMAND

import std/[os, osproc, random, times]
import lutra/host/serialport, lutra/tooling

let (port, reset) = (paramStr(1), paramStr(2))

proc check(passed: bool, message: string) =
  if not passed:
    echo message
    quit ord(checkFailed)

var link = try: openPort(port, 921600) except OSError as e: fail(noBoard, e.msg)
when defined(windows): link.close() # The reset may need the port, which only one program can hold
check execCmdEx(reset).exitCode == 0, "The board on " & port & " could not be reset."
when defined(windows): link = openPort(port, 921600) else: link.setBaud(921600)

# The reset's own chatter, at the boot ROM's baud rate, is read and dropped
var buffer: array[4096, byte]
let start = epochTime()
while epochTime() - start < 1: discard link.read(buffer, 50)

randomize()
var sent, got: seq[byte]
for i in 0 ..< 65536: sent.add byte(rand(255))
# A little at a time, reading between, so that what comes back never waits long
var at = 0
let sending = epochTime()
while got.len < sent.len and epochTime() - sending < 4:
  if at < sent.len:
    link.write(sent.toOpenArray(at, at + 63))
    at += 64
  let n = link.read(buffer, if at < sent.len: 0 else: 50)
  got.add buffer.toOpenArray(0, n - 1)
check got.len == sent.len, "Only " & $got.len & " of " & $sent.len & " bytes came back."
check got == sent, "The bytes came back changed."
