import registers

const cpuHz* = 160_000_000

proc cycles*(): uint32 =
  ## Core clock cycles, wrapping every 27 seconds
  {.emit: ["__asm__ volatile(\"csrr %0, 0x7e2\" : \"=r\"(", result, "));"].}

proc micros*(): uint64 =
  ## Microseconds since reset
  # The system timer counts at 16 MHz whatever the clock of the core
  systemTimerOp[] = 1 shl 30
  while (systemTimerOp[] and (1 shl 29)) == 0: discard
  ((systemTimerHigh[].uint64 shl 32) or systemTimerLow[]) div 16
