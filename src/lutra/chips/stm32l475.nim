## The STM32L475: a Cortex-M4 at 80 MHz with its flash on the chip and 128 KB
## of RAM, 96 KB of it in one piece.

import stm32l475/[peripherals, memory]
export peripherals except function
export memory

when defined(nimscript):
  import stm32l475/host
  export host
else:
  import ../arch/armv7m/[interrupts, fault, context]
  import stm32l475/[startup, gpio, uart, i2c, spi, clock, timer, random]
  export gpio except asFunction, drive, openDrain, pinInterrupt
  export uart, i2c, spi, timer, random, clock.cpuHz, clock.cycles, clock.micros, interrupts.critical, fault.reportFaults
