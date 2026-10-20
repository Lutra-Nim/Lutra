## What the host does for a D1: finding the compiler, the flags and linker
## script to build with, and loading a program into the board's DRAM through
## the boot ROM's USB loader, FEL.

import std/[os, strutils, sequtils, hashes, algorithm]
import memory, ../../tooling

# T-Head's own instructions, as for addresses and multiplying and adding, are
# switched on when the chip starts, so the compiler may use them
const arch = "-mcpu=thead-c906 -mabi=lp64d -mcmodel=medany"

proc tool(name: string): string =
  ## A tool from the xPack RISC-V toolchain, on the PATH or where it was
  ## unpacked under ~/.local/xPacks, by hand or by `xpm`
  let exe = "riscv-none-elf-" & name
  if findExe(exe) != "": return exe
  var found: seq[string]
  for root in [getHomeDir() / ".local/xPacks/riscv-none-elf-gcc",
      getHomeDir() / ".local/xPacks/@xpack-dev-tools/riscv-none-elf-gcc"]:
    if dirExists(root):
      for version in listDirs(root):
        for bin in [version / "bin", version / ".content/bin"]:
          if fileExists(bin / exe & ExeExt): found.add bin / exe & ExeExt
  if found.len > 0: found.sorted[^1] else: exe # The newest

proc compiler*(): Tool =
  result = found(tool"gcc", "Unpack the xPack RISC-V toolchain, riscv-none-elf-gcc 14 or later, " &
    "from github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack under ~/.local/xPacks/riscv-none-elf-gcc, " &
    "or put it on the PATH.")
  result.name = "riscv-none-elf-gcc"

proc flasher*(): Tool =
  found("xfel", "Build it from github.com/xboot/xfel, which needs libusb 1.0, and put it on the PATH " &
    "or point XFEL at it.", "XFEL")

proc xfel(): string =
  need flasher()
  flasher().path

proc configure*(m: Memory, buildDir: string) =
  switch("cpu", "riscv64")
  switch("cc", "gcc")
  switch("riscv64.any.gcc.exe", tool"gcc")
  switch("riscv64.any.gcc.linkerexe", tool"gcc")
  switch("gcc.options.linker", "") # Nim has already added the host's libraries
  switch("passC", arch & " -ffunction-sections -fdata-sections")

  # Named after its contents, so that a changed layout is a changed link
  # command and Nim links again
  let
    text = linkerScript(m)
    script = buildDir / "d1-" & toHex(hash(text).uint32) & ".ld"
  if not fileExists(script):
    mkDir buildDir
    writeFile(script, text)
  # The C library wants an operating system under it, and is given stubs that
  # nothing reaches. The whole image is in RAM, so it is writable and runs.
  switch("passL", arch & " -nostartfiles --specs=nosys.specs -Wl,--gc-sections -Wl,--no-warn-rwx-segments -T" & script)

proc sections(elf: string): seq[tuple[name: string, size, address: int]] =
  for line in gorge(tool"size" & " -A " & quoteShell(elf)).splitLines:
    let fields = line.splitWhitespace
    if fields.len == 3 and fields[0].startsWith("."):
      result.add (fields[0], fields[1].parseInt, fields[2].parseInt)

proc audit*(elf: string) =
  ## Stops on what links without complaint and would not run
  let orphans = sections(elf).filterIt(it.address != 0 and
    it.name notin [".start", ".text", ".rodata", ".data", ".bss"])
  if orphans.len > 0:
    fail buildFailed, "Error: " & elf.lastPathPart & " would not run as built.\n  " &
      orphans.mapIt("The section " & it.name & " has no place in the memory layout.").join("\n  ")

proc size*(elf: string, m: Memory) =
  ## Prints what each region holds against what it can
  for (label, names) in [("Image", @[".start", ".text", ".rodata", ".data"]),
      ("DRAM", @[".start", ".text", ".rodata", ".data", ".bss"])]:
    var used = 0
    for section in sections(elf):
      if section.name in names: used += section.size
    echo label.alignLeft(16), align($used, 9), " of ", align($m.dramSize, 9), " bytes"

proc loader(arguments: openArray[string]): string =
  ## A command for `lutra/host/fel`, which loads a program and starts it
  let host = currentSourcePath().parentDir.parentDir.parentDir / "host"
  result = quoteShell(hostProgram(host / "fel.nim",
    [host / "fel.nim", host / "serialport.nim", host.parentDir / "tooling.nim"]))
  for argument in arguments: result.add " " & quoteShell(argument)

proc flash*(elf: string, m: Memory, port: string) =
  let image = elf.changeFileExt("bin")
  exec tool"objcopy" & " -O binary " & quoteShell(elf) & " " & quoteShell(image)
  exec loader(["--port=" & port, "--xfel=" & xfel(), "--image=" & image]) # It says why, if it fails

proc resetCommand*(port: string): string =
  # Loads again the program `nim flash` last wrote from here, as a reset loses it
  loader(["--port=" & port, "--xfel=" & xfel(), "--flashed=" & buildDir() / "flashed"])
