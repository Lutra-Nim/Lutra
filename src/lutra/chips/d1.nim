## The Allwinner D1: a single T-Head C906 core, RV64GC with T-Head's vector
## unit, at 1008 MHz, with its program in DRAM beside it.

import d1/[peripherals, memory]
export peripherals except function
export memory

when defined(nimscript):
  import d1/host
  export host
else:
  import ../arch/riscv64/[trap, fault, context]
  import d1/[startup, gpio, uart, led, clock, random, power, interrupts, timer]
  export gpio except asFunction
  export uart, led.color, led.off, random, power, timer, clock.cpuHz, clock.cycles, clock.micros,
    interrupts.critical, fault.reportFaults
