## Steady's on-target benchmark on Lutra: the ten entry points it asks of a
## board. Run it with `nim steady`, which generates the model it imports.

import lutra
import lutra/chips/esp32c3/registers
import bench

{.used.}
{.push exportc, cdecl.}
proc board_putc(c: char) = console.send(c)
proc board_cycles(): uint32 = cycles()
proc board_sysclk(): uint32 = cpuHz
proc board_timebase(): cstring = "pccr"
proc board_led(on: cint) = discard # The only LED needs a driver
proc board_poll() = discard
# There is one cache in front of flash and it can't be turned off
proc board_cache_configs(): cint = 1
proc board_cache_label(i: cint): cstring = "icache=16K"
proc board_cache_select(i: cint) = discard
proc board_cache_state(): uint32 = cacheControl[]
{.pop.}

proc run() {.importc: "steady_mcu_main", cdecl.}
run()
