## Timer events. The timer block has two timers that count the 24 MHz crystal
## down and start again, each with an interrupt of its own, and each
## `{.interrupt: every(...).}` takes the next.

import ../../[claims, time]
import registers, interrupts

template timer(event: TimerEvent, where: string): int =
  slot("timers", 2, where & " every " & $event.period.uint64,
    "every(" & $event.period.uint64 & " us)" & where & " needs a timer, and the D1's two are taken")

template attach*(event: static TimerEvent, where: static string, handler: untyped) =
  ## Binds `handler` to `event`, for `arm` to start. `where` is the handler's line.
  const n = timer(event, where)
  proc entry() {.gensym, exportc: "lutra_interrupt_" & $timerSources[n], cdecl.} =
    timerInterruptStatus[] = 1'u32 shl n
    # Read back, so that the write has landed before the interrupt controller
    # is told this one is handled: otherwise it sees the line still raised,
    # and takes it again
    discard timerInterruptStatus[]
    handler()
  discard cast[pointer](entry) # Inside a procedure, Nim leaves out one nothing refers to

template arm*(event: static TimerEvent, where: static string) =
  const
    n = timer(event, where)
    ticks = event.period.uint64 * 24
  when ticks notin 1'u64 .. uint64(uint32.high):
    {.error: "every(" & $event.period.uint64 & " us)" & where & ": a timer on the D1 can be every 1 us to 178 s".}
  let control = Reg(timerControl + 0x10 * n.uint32)
  control[] = 0 # Stopped while it is set
  Reg(timerInterval + 0x10 * n.uint32)[] = uint32(ticks)
  control[] = (1'u32 shl 2) or 3 # From the crystal, undivided, the interval taken up and counting
  timerInterruptEnable[] = timerInterruptEnable[] or (1'u32 shl n)
  enable(timerSources[n])
