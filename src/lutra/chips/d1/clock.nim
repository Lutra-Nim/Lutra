import registers

const cpuHz* = 1_008_000_000

proc setClocks*() =
  ## The core at 1008 MHz, from its PLL: 24 MHz times 42. The core runs from
  ## the crystal while the PLL changes, and the bus behind it at half.
  riscvClock[] = (1'u32 shl 8) # From the crystal, the bus at half
  pllCpu[] = (pllCpu[] and not ((1'u32 shl 27) or (0xff'u32 shl 8) or 3'u32)) or # Output gated off, and N and M cleared
    (41'u32 shl 8) or (1'u32 shl 30) or (1'u32 shl 29) or (1'u32 shl 31) # N + 1 = 42; its regulator, lock detection, and on
  while (pllCpu[] and (1'u32 shl 28)) == 0: discard # Until it has locked
  pllCpu[] = (pllCpu[] or (1'u32 shl 27)) and not (1'u32 shl 29)
  riscvClock[] = (5'u32 shl 24) or (1'u32 shl 8) # From the PLL, the bus at half

  # The second peripheral bus, which the UARTs are on, straight from the
  # crystal, whatever came before set it to
  apb1Clock[] = 0

proc cycles*(): uint32 =
  ## Core clock cycles, wrapping every 4.3 seconds
  {.emit: ["__asm__ volatile(\"csrr %0, mcycle\" : \"=r\"(", result, "));"].}

proc micros*(): uint64 =
  ## Microseconds since the chip was reset
  # The core's time counts at 24 MHz, from the crystal
  {.emit: ["__asm__ volatile(\"csrr %0, time\" : \"=r\"(", result, "));"].}
  result = result div 24
