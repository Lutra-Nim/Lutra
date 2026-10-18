## The ESP32-C3: a single RV32IMC core at 160 MHz with 384 KB of RAM, reading
## its flash through a page table and a 16 KB cache.

import esp32c3/[peripherals, memory]
export peripherals, memory

when defined(nimscript):
  import esp32c3/host
  export host
else:
  import ../arch/riscv32/context
  import esp32c3/[startup, gpio, uart, i2c, spi, led, clock, interrupts, random, timer, power]
  import ../hal/resets
  export gpio except routeOut, routeIn, openDrain, drive, driveGently, filter, listen
  export uart, i2c, spi, led, clock, random, timer, power, resets, interrupts.critical
