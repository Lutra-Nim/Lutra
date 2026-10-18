## The watchdog, the reason the chip last started, and starting it again.
## The watchdog is the first timer group's, counting the 40 MHz crystal.

import ../../[time, claims]
import ../../hal/resets
import registers

type Watchdog* = object
const watchdog* = Watchdog()

const
  key = 0x50D8_3AA1'u32 # Unlocks the watchdog's registers
  # Of `timerWatchdog`
  enabled = 1'u32 shl 31
  resetsSystem = 3'u32 shl 29 # What its first stage does when it runs out
  fromCrystal = 1'u32 shl 21
  update = 1'u32 shl 22 # Takes up what was written
  resetLength = (7'u32 shl 18) or (7'u32 shl 15) # The longest, 3.2 us

proc arm(ticks: static uint64) =
  when ticks < 1 or ticks > uint32.high: {.error: "The watchdog waits from 1 ms to 49 days.".}
  timerWatchdogProtect[] = key
  timerWatchdogPrescale[] = 40_000'u32 shl 16 # A millisecond of the crystal
  timerWatchdogStage0[] = uint32(ticks)
  timerWatchdog[] = enabled or resetsSystem or fromCrystal or resetLength
  timerWatchdog[] = timerWatchdog[] or update
  timerWatchdogFeed[] = 1
  timerWatchdogProtect[] = 0

template start*(w: static Watchdog, within: static Duration) =
  ## From here on the chip starts again unless `feed` is called at least
  ## once every `within`. It can't be stopped.
  once("Starting the watchdog", at(instantiationInfo()))
  arm(uint64(within) div 1000) # In milliseconds

proc feed*(w: static Watchdog) =
  ## Gives the program another `within` before the chip starts again
  timerWatchdogProtect[] = key
  timerWatchdogFeed[] = 1
  timerWatchdogProtect[] = 0

proc resetReason*(): ResetReason =
  ## Why the chip last started, from the cause the boot ROM prints as `rst:`
  case resetState[] and 0x3f
  of 0x01: powerOn
  of 0x03, 0x0D: software
  of 0x05: wake
  of 0x07, 0x08, 0x09, 0x0C, 0x0E, 0x10, 0x11, 0x12: watchdogTimeout
  of 0x0F: brownout
  else: other

proc restartNow*() {.noreturn.} =
  ## Starts the chip again at once, as power coming on would but for the
  ## reason. `restart` lets the console finish first.
  rtcOptions[] = rtcOptions[] or (1'u32 shl 31)
  while true: discard
