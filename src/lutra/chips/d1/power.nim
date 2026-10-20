## Starting the chip again. The watchdog for programs, and the reason the
## chip last started, are not written yet.
##
## A program is in DRAM, which a restart does not keep, so the chip starts
## whatever is on its SD card, or waits for one over USB.

import registers

const key = 0x16AA_0000'u32 # Unlocks the watchdog's registers

proc restartNow*() {.noreturn.} =
  ## Starts the chip again at once, from its watchdog given its shortest time,
  ## half a second
  watchdogConfig[] = (watchdogConfig[] and not 3'u32) or 1 or key # Resets the whole chip
  watchdogMode[] = (watchdogMode[] and not (0xf'u32 shl 4)) or 1 or key
  watchdogControl[] = 1 or (0xA57'u32 shl 1) # Starts it counting
  while true: discard

proc restartIntoLoader*() {.noreturn.} =
  ## Starts the chip again into the boot ROM's USB loader, FEL, to wait for a
  ## program from the host. boot0, on the SD card, takes this note left in
  ## the RTC as asking for that, and clears it; with no card the boot ROM
  ## goes there anyway.
  rtcSpare2[] = 0x5AA5_A55A
  restartNow()
