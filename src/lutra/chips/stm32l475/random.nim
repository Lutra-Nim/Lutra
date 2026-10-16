import registers, clock

proc random*(): uint32 =
  ## From the hardware's generator, whose noise is analog. The first call
  ## starts it, with the 48 MHz clock it needs.
  var started {.global.} = false
  if not started:
    # The second PLL, from the same 4 MHz as the first: times 24, halved
    pllSai1Config[] = (24 shl 8) or (1 shl 20)
    clockControl[] = clockControl[] or (1 shl 26)
    while (clockControl[] and (1 shl 27)) == 0: discard
    clockSources[] = clockSources[] and not (3'u32 shl 26) or (1 shl 26)
    switchOn(ahb2Clocks, 18)
    randomControl[] = 1 shl 2
    started = true
  while (randomStatus[] and 1) == 0: discard
  randomData[]
