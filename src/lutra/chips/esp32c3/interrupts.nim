## The ESP32-C3's interrupt controller. Each source a peripheral raises is
## routed to one of the core's 31 lines, and Lutra gives each source it knows a
## line of its own. A handler is whatever defines `lutra_interrupt_<line>`.

import std/strutils
import ../../arch/riscv32/trap
import registers

export trap.critical, trap.enableInterrupts, trap.disableInterrupts

type Source* = tuple[number, line: int]

const
  gpioSource*: Source = (16, 1)
  uartSources*: array[2, Source] = [(21, 2), (22, 3)]

# Lines nobody handles are left out of the link, as null entries
{.emit: block:
  var (declarations, entries) = ("", "0")
  for line in 1..31:
    declarations.add "void lutra_interrupt_$1(void) __attribute__((weak));\n" % $line
    entries.add ", lutra_interrupt_$1" % $line
  declarations & "static void (*const lutraHandlers[32])(void) = {" & entries & "};\n".}

var handlers {.importc: "lutraHandlers", nodecl.}: array[32, proc() {.cdecl.}]

proc interrupt(frame: pointer, cause: uint32): pointer {.exportc: "lutraInterrupt".} =
  handlers[cause and 31]()
  frame

proc enable*(source: static Source) =
  if takeTraps():
    interruptEnable[] = 0 # Whatever the boot ROM was listening to
    interruptThreshold[] = 1
  Reg(interruptMap + 4 * source.number.uint32)[] = source.line.uint32
  Reg(interruptPriority + 4 * source.line.uint32)[] = 1
  interruptEnable[] = interruptEnable[] or (1'u32 shl source.line)
  enableInterrupts()
