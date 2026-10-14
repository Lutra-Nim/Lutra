## What the host does for an STM32L475: the flags and linker script to build
## with, and flashing through the board's debug probe.

import std/[os, strutils, sequtils, hashes]
import memory

const
  arch = "-mcpu=cortex-m4 -mthumb -mfloat-abi=soft"
  target = "stm32l475xg" # As pyocd knows the chip

proc tool(name: string): string = "arm-none-eabi-" & name

proc pyocd(): string =
  result = getEnv("PYOCD", "pyocd")
  if findExe(result) == "":
    quit "Error: pyocd not found, so nothing was flashed. Install it with " &
      "`pipx install pyocd`, or point PYOCD at it."

proc checkFlasher*() =
  ## Stops now, rather than after a build, if the board can't be flashed
  discard pyocd()

proc configure*(m: Memory, buildDir: string) =
  switch("cpu", "arm")
  switch("cc", "gcc")
  switch("arm.any.gcc.exe", tool"gcc")
  switch("arm.any.gcc.linkerexe", tool"gcc")
  switch("gcc.options.linker", "") # Nim has already added the host's libraries
  switch("passC", arch & " -ffunction-sections -fdata-sections")

  # Named after its contents, so that a changed layout is a changed link
  # command and Nim links again
  let
    text = linkerScript(m)
    script = buildDir / "stm32l475-" & toHex(hash(text).uint32) & ".ld"
  if not fileExists(script):
    mkDir buildDir
    writeFile(script, text)
  # The C library wants an operating system under it, and is given stubs that
  # nothing reaches
  switch("passL", arch & " -nostartfiles --specs=nosys.specs -Wl,--gc-sections -T" & script)

proc sections(elf: string): seq[tuple[name: string, size, address: int]] =
  for line in gorge(tool"size" & " -A " & quoteShell(elf)).splitLines:
    let fields = line.splitWhitespace
    if fields.len == 3 and fields[0].startsWith("."):
      result.add (fields[0], fields[1].parseInt, fields[2].parseInt)

proc audit*(elf: string) =
  ## Stops on what links without complaint and would not run
  let orphans = sections(elf).filterIt(it.address != 0 and
    it.name notin [".vectors", ".text", ".rodata", ".data", ".bss"])
  if orphans.len > 0:
    quit "Error: " & elf.lastPathPart & " would not run as built.\n  " &
      orphans.mapIt("The section " & it.name & " has no place in the memory layout.").join("\n  ")

proc size*(elf: string, m: Memory) =
  ## Prints what each region holds against what it can
  for (label, names, budget) in [
      ("RAM", @[".data", ".bss"], ramSize),
      ("Flash", @[".vectors", ".text", ".rodata", ".data"], m.flashSize)]:
    var used = 0
    for section in sections(elf):
      if section.name in names: used += section.size
    echo label.alignLeft(16), align($used, 9), " of ", align($budget, 8), " bytes"

proc flash*(elf: string, m: Memory, port: string) =
  # Through the probe, which wants no serial port
  exec pyocd() & " flash -t " & target & " " & quoteShell(elf)

proc resetCommand*(port: string): string =
  pyocd() & " reset -t " & target & " >/dev/null 2>&1"
