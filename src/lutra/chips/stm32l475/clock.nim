import registers

const cpuHz* = 80_000_000

template count(timer: uint32): Reg = Reg(timer + timerCount)

template switchOn*(clocks: Reg, bit: int) =
  ## Gives a peripheral its clock. The write takes a moment to land, and
  ## anything written to the peripheral before it has is dropped; reading the
  ## register back waits for it.
  clocks[] = clocks[] or (1'u32 shl bit)
  discard clocks[]

proc startCounting*() =
  ## Timer 2 counts cycles of the core's clock, and timer 5 counts each time
  ## timer 2 comes round: 64 bits between them, with no interrupt
  switchOn(apb1Clocks, 0)
  switchOn(apb1Clocks, 3)
  Reg(timer2 + timerControl2)[] = 2 shl 4 # Tell the others on coming round
  Reg(timer5 + timerFollow)[] = 7 # Count what timer 2 tells
  Reg(timer5 + timerControl)[] = 1
  Reg(timer2 + timerControl)[] = 1

proc cycles*(): uint32 = timer2.count[]
  ## Core clock cycles, wrapping every 54 seconds

proc micros*(): uint64 =
  ## Microseconds since reset
  var high = timer5.count[]
  while true:
    # Timer 2 may come round between the two reads, so the high half is read
    # until it holds still
    let (low, again) = (timer2.count[], timer5.count[])
    if again == high: return ((high.uint64 shl 32) or low) div (cpuHz div 1_000_000)
    high = again
