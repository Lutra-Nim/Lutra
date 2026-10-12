## What the host does for an ESP32-C3: finding the compiler, the flags and
## linker script to build with, and packaging and flashing an image.

import std/[os, strutils, sequtils, hashes]
import memory

const arch = "-march=rv32imc_zicsr -mabi=ilp32"

proc tool(name: string): string =
  ## A tool from Espressif's RISC-V toolchain, which its installer leaves off
  ## the PATH
  let exe = "riscv32-esp-elf-" & name
  if findExe(exe) != "": return exe
  for version in listDirs(getHomeDir() / ".espressif/tools/riscv32-esp-elf"):
    if fileExists(version / "riscv32-esp-elf/bin" / exe):
      return version / "riscv32-esp-elf/bin" / exe
  exe

proc esptool(): string =
  result = getEnv("ESPTOOL", "esptool")
  if findExe(result) == "":
    quit "Error: esptool not found, so nothing was flashed. Install it with " &
      "`pipx install esptool`, or point ESPTOOL at it."

proc checkFlasher*() =
  ## Stops now, rather than after a build, if the board can't be flashed
  discard esptool()

proc configure*(m: Memory, buildDir: string) =
  switch("cpu", "riscv32")
  switch("cc", "gcc")
  switch("riscv32.any.gcc.exe", tool"gcc")
  switch("riscv32.any.gcc.linkerexe", tool"gcc")
  switch("gcc.options.linker", "") # Nim has already added the host's libraries
  switch("passC", arch & " -ffunction-sections -fdata-sections")

  # Named after its contents, so that a changed layout is a changed link
  # command and Nim links again
  let
    text = linkerScript(m)
    script = buildDir / "esp32c3-" & toHex(hash(text).uint32) & ".ld"
  if not fileExists(script):
    mkDir buildDir
    writeFile(script, text)
  # The relocations are kept for `audit` to read
  switch("passL", arch & " -nostartfiles -Wl,--gc-sections -Wl,--emit-relocs -T" & script)

proc sections(elf: string): seq[tuple[name: string, size, address: int]] =
  for line in gorge(tool"size" & " -A " & quoteShell(elf)).splitLines:
    let fields = line.splitWhitespace
    if fields.len == 3 and fields[0].startsWith("."):
      result.add (fields[0], fields[1].parseInt, fields[2].parseInt)

proc audit*(elf: string) =
  ## Stops on the mistakes that link without complaint and then fail on the
  ## board, or quietly cost what the program was not meant to spend
  var problems: seq[string]

  for section in sections(elf):
    if section.address != 0 and section.name notin
        [".ram.text", ".data", ".bss", ".flash.text", ".flash.rodata"]:
      problems.add "The section " & section.name & " has no place in the memory layout."

  # Startup runs from RAM before flash can be read
  var inRamCode = false
  for line in gorge(tool"readelf" & " -rW " & quoteShell(elf)).splitLines:
    let fields = line.splitWhitespace
    if line.startsWith("Relocation section"):
      inRamCode = "'.rela.ram.text'" in line
    elif inRamCode and fields.len >= 5 and fields[2].startsWith("R_RISCV") and
        fields[4] != "lutraMain" and inFlash(fromHex[int](fields[3])):
      problems.add "Code that runs from RAM refers to " & fields[4] &
        ", which is in flash and can't be read until flash is mapped."

  if problems.len > 0:
    quit "Error: " & elf.lastPathPart & " would not run as built.\n  " &
      problems.deduplicate.join("\n  ")

proc size*(elf: string, m: Memory) =
  ## Prints what each region holds against what it can
  for (label, names, budget) in [
      ("RAM code", @[".ram.text"], ramCodeSize),
      ("RAM data", @[".data", ".bss"], ramSize),
      ("Flash code", @[".flash.text"], m.codeSize),
      ("Flash constants", @[".flash.rodata"], m.constantsSize)]:
    var used = 0
    for section in sections(elf):
      if section.name in names: used += section.size
    echo label.alignLeft(16), align($used, 9), " of ", align($budget, 8), " bytes"

proc flash*(elf: string, m: Memory, port: string) =
  # The boot ROM only loads the part of the program that runs from RAM. The
  # rest is written to where the linker script expects to find it once flash
  # has been mapped.
  let
    base = elf.changeFileExt("")
    (boot, code, constants) = (base & ".boot.bin", base & ".code.bin", base & ".constants.bin")
  exec tool"objcopy" & " -O binary -j .flash.text " & quoteShell(elf) & " " & quoteShell(code)
  exec tool"objcopy" & " -O binary -j .flash.rodata " & quoteShell(elf) & " " & quoteShell(constants)
  exec tool"objcopy" & " -R .flash.text -R .flash.rodata -R '.rela.*' " & quoteShell(elf) & " " & quoteShell(base & ".ram.elf")
  exec esptool() & " --chip esp32c3 elf2image --flash-mode " & m.flashMode &
    " --flash-freq " & m.flashFreq & " --flash-size " & $(m.flashSize div 1.MB) & "MB" &
    " -o " & quoteShell(boot) & " " & quoteShell(base & ".ram.elf")
  if readFile(boot).len > m.codeOffset:
    quit "The part of the program loaded into RAM is larger than the 64K of flash set aside for it."
  exec esptool() & " --chip esp32c3 --port " & port & " --baud 460800 write-flash" &
    " 0x0 " & quoteShell(boot) &
    " " & $m.codeOffset & " " & quoteShell(code) &
    " " & $m.constantsOffset & " " & quoteShell(constants)

proc resetCommand*(port: string): string =
  esptool() & " --chip esp32c3 --port " & port & " --after hard-reset chip-id >/dev/null"
