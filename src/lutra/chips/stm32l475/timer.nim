## Timer events. Timers 6 and 7 only count, each with an interrupt of its
## own, and each `{.interrupt: every(...).}` takes the next.

import ../../[claims, time]
import ../../arch/armv7m/interrupts
import registers, clock

const timers = [(base: timer6, clockBit: 4, interrupt: 54), (base: timer7, clockBit: 5, interrupt: 55)]

template timer(event: TimerEvent, where: string): untyped =
  timers[slot("timers", 2, where & " every " & $event.period.uint64,
    "every(" & $event.period.uint64 & " us)" & where & " needs a timer, and the STM32L475's two are taken")]

func division(ticks: uint64): tuple[prescale, reload: uint64] =
  ## Two counts of at most 16 bits whose product is `ticks`, or as near as
  ## can be
  let least = (ticks + 0xFFFF) div 0x10000
  for prescale in least .. 0x10000'u64:
    if ticks mod prescale == 0: return (prescale, ticks div prescale)
  (least, (ticks + least div 2) div least)

template attach*(event: static TimerEvent, where: static string, handler: untyped) =
  ## Binds `handler` to `event`, for `arm` to start. `where` is the handler's line.
  const t = timer(event, where)
  proc entry() {.gensym, exportc: "lutra_interrupt_" & $t.interrupt, cdecl.} =
    Reg(t.base + timerStatus)[] = 0 # Cleared first, so that it has landed by the time the handler returns
    handler()
  discard cast[pointer](entry) # Inside a procedure, Nim leaves out one nothing refers to

template arm*(event: static TimerEvent, where: static string) =
  const
    t = timer(event, where)
    ticks = event.period.uint64 * (cpuHz div 1_000_000)
  when ticks notin 1'u64 .. (1'u64 shl 32):
    {.error: "every(" & $event.period.uint64 & " us)" & where & ": a timer on the STM32L475 can be every 1 us to 53 s".}
  const (prescale, reload) = division(ticks)
  switchOn(apb1Clocks, t.clockBit)
  Reg(t.base + timerPrescale)[] = uint32(prescale - 1)
  Reg(t.base + timerReload)[] = uint32(reload - 1)
  # The prescale is taken now, rather than at the first tick, without that
  # counting as one: only coming round does
  const onlyComingRound = 1'u32 shl 2
  Reg(t.base + timerControl)[] = onlyComingRound
  Reg(t.base + timerUpdate)[] = 1
  Reg(t.base + timerInterrupts)[] = 1
  Reg(t.base + timerControl)[] = onlyComingRound or 1
  enable(t.interrupt)
