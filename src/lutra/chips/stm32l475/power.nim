## The watchdog, the reason the chip last started, and starting it again.
## The watchdog is the independent one, counting the chip's own 32 kHz
## oscillator, which is only roughly that.

import ../../[time, claims]
import ../../hal/resets
import registers

type Watchdog* = object
const watchdog* = Watchdog()

var flags: uint32 # Why the chip last started, kept from before they were cleared

proc noteReset*() =
  ## For the startup: the flags stay set across resets until cleared, so
  ## they are read and cleared each time
  flags = resetFlags[]
  resetFlags[] = resetFlags[] or (1'u32 shl 23)

proc arm(prescale, reload: static uint32) =
  watchdogKey[] = 0xCCCC # Starts it, and its oscillator
  watchdogKey[] = 0x5555 # Unlocks the two below
  watchdogPrescale[] = prescale
  watchdogReload[] = reload
  while watchdogStatus[] != 0: discard # Until it has taken them
  watchdogKey[] = 0xAAAA

func setting(within: Duration): tuple[prescale, reload: uint32] =
  ## The finest division of 32 kHz that counts to `within` in 12 bits
  for prescale in 0'u32..6:
    let ticks = uint64(within) * 32 div (4'u64 shl prescale) div 1000
    if ticks <= 4096: return (prescale, uint32(max(ticks, 1) - 1))
  (7'u32, 0'u32)

template start*(w: static Watchdog, within: static Duration) =
  ## From here on the chip starts again unless `feed` is called at least
  ## once every `within`. It can't be stopped.
  once("Starting the watchdog", at(instantiationInfo()))
  const s = setting(within)
  when s.prescale > 6 or uint64(within) < 125:
    {.error: "The watchdog waits from 125 us to 32 s" & at(instantiationInfo()).}
  arm(s.prescale, s.reload)

proc feed*(w: static Watchdog) =
  ## Gives the program another `within` before the chip starts again
  watchdogKey[] = 0xAAAA

proc resetReason*(): ResetReason =
  ## Why the chip last started. A reset by its pin goes with every other, so
  ## it counts last; power coming on is told by the supply's flag.
  if (flags and (3'u32 shl 29)) != 0: watchdogTimeout # Either watchdog
  elif (flags and (1'u32 shl 28)) != 0: software
  elif (flags and (1'u32 shl 27)) != 0: powerOn
  elif (flags and (1'u32 shl 26)) != 0: resetPin
  else: other

proc restartNow*() {.noreturn.} =
  ## Starts the chip again at once, as its reset pin would but for the
  ## reason. `restart` lets the console finish first.
  systemReset[] = 0x05FA_0004 # The key, and the request
  while true: discard
