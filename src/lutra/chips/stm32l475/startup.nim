import ../../arch/armv7m/start
import ../../tasks
import registers, clock, power

{.used.}
{.emit: vectors(82).}

proc nimMain() {.importc: "NimMain", cdecl.}
proc boardStart() {.importc: "lutraBoardStart".} # What the board does before a program

# Set by the linker script
var
  data {.importc: "_data_start".}, dataEnd {.importc: "_data_end".}, dataLoad {.importc: "_data_load".}: uint32
  bss {.importc: "_bss_start".}, bssEnd {.importc: "_bss_end".}: uint32

proc reset() {.exportc: "lutraReset".} =
  # What variables start out as is kept in flash
  copyMem(addr data, addr dataLoad, cast[uint](addr dataEnd) - cast[uint](addr data))
  zeroMem(addr bss, cast[uint](addr bssEnd) - cast[uint](addr bss))

  # Flash can't be read at 80 MHz without four cycles to wait, so it is told
  # first, with its prefetch and both its caches on
  flashAccess[] = 0x704
  while (flashAccess[] and 7) != 4: discard

  # 80 MHz, from the 4 MHz oscillator the chip starts on: multiplied by 40 and halved
  pllConfig[] = 1 or (40 shl 8) or (1 shl 24)
  clockControl[] = clockControl[] or (1 shl 24)
  while (clockControl[] and (1 shl 25)) == 0: discard
  clockConfig[] = clockConfig[] or 3
  while (clockConfig[] shr 2 and 3) != 3: discard

  startCounting()
  noteReset()
  boardStart()
  nimMain()
  while true: idle() # The program has ended, and any tasks go on
