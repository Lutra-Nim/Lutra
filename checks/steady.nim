## Steady's on-target benchmark on Lutra: the ten entry points it asks of a
## board. Run it with `nim steady`, which generates the model it imports.

import lutra
import bench

# What a chip has in front of its flash, what counts its cycles, and the LED
when declared(rgbLed):
  import lutra/chips/esp32c3/registers
  const (timebase, cache) = ("pccr", "icache=16K") # One cache, which can't be turned off
  proc cacheState(): uint32 = cacheControl[]
  proc led(on: bool) = (if on: rgbLed.color(green = 20) else: rgbLed.off())
else:
  import lutra/chips/stm32l475/registers
  const (timebase, cache) = ("tim2", "prefetch=1 icache=1 dcache=1") # As Lutra leaves them
  proc cacheState(): uint32 = flashAccess[]
  proc led(on: bool) = (if on: led2.high() else: led2.low())
  led2.output()

{.used.}
{.push exportc, cdecl.}
proc board_putc(c: char) = console.send(c)
proc board_cycles(): uint32 = cycles()
proc board_sysclk(): uint32 = cpuHz
proc board_timebase(): cstring = timebase
proc board_led(on: cint) = led(on != 0)
proc board_poll() = discard
proc board_cache_configs(): cint = 1
proc board_cache_label(i: cint): cstring = cache
proc board_cache_select(i: cint) = discard
proc board_cache_state(): uint32 = cacheState()
{.pop.}

proc run() {.importc: "steady_mcu_main", cdecl.}
run()
