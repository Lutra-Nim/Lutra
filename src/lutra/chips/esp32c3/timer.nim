## Timer events. The system timer, which also keeps `micros`, has three
## alarms that can repeat, each with an interrupt of its own, and each
## `{.interrupt: every(...).}` takes the next.

import ../../[claims, time]
import registers, interrupts

template alarm(event: TimerEvent, where: string): int =
  slot("timers", 3, where & " every " & $event.period.uint64,
    "every(" & $event.period.uint64 & " us)" & where & " needs a timer, and the ESP32-C3's three are taken")

template attach*(event: static TimerEvent, where: static string, handler: untyped) =
  ## Binds `handler` to `event`, for `arm` to start. `where` is the handler's line.
  const n = alarm(event, where)
  proc entry() {.gensym, exportc: "lutra_interrupt_" & $alarmSources[n].line, cdecl.} =
    systemTimerInterruptClear[] = 1'u32 shl n
    handler()
  discard cast[pointer](entry) # Inside a procedure, Nim leaves out one nothing refers to

template arm*(event: static TimerEvent, where: static string) =
  const
    n = alarm(event, where)
    ticks = event.period.uint64 * 16 # The timer counts at 16 MHz
  when ticks notin 1'u64 ..< (1'u64 shl 26):
    {.error: "every(" & $event.period.uint64 & " us)" & where & ": a timer on the ESP32-C3 can be every 1 us to 4.19 s".}
  const running = 1'u32 shl (24 - n) # Of `systemTimerConfig`
  systemTimerConfig[] = systemTimerConfig[] and not running
  Reg(systemTimerAlarm + 4 * n.uint32)[] = ticks.uint32 # Compared with the count that `micros` reads
  Reg(systemTimerAlarmLoad + 4 * n.uint32)[] = 1
  Reg(systemTimerAlarm + 4 * n.uint32)[] = ticks.uint32 or (1'u32 shl 30) # Repeating
  systemTimerConfig[] = systemTimerConfig[] or running
  systemTimerInterruptEnable[] = systemTimerInterruptEnable[] or (1'u32 shl n)
  enable(alarmSources[n])
