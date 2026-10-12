import std/[os, osproc, strutils]

let (output, exitCode) = execCmdEx("nim check --hints:off " &
  quoteShell(currentSourcePath().parentDir / "claims_conflict.nim"))
doAssert exitCode != 0
doAssert "IO6 is claimed as UART1 TX and as a GPIO at main.nim(4)" in output, output
doAssert "IO7" notin output, output
doAssert "Handling the interrupt of IO9 twice, at main.nim(6) and at main.nim(8)" in output, output
