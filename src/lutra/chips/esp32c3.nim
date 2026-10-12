## The ESP32-C3: a single RV32IMC core at 160 MHz with 384 KB of RAM, reading
## its flash through a page table and a 16 KB cache.

import esp32c3/[peripherals, memory]
export peripherals, memory

when defined(nimscript):
  import esp32c3/host
  export host
else:
  import esp32c3/[startup, gpio, uart, clock, interrupts]
  export gpio, uart, clock, interrupts.critical
