## The D1's interrupt controller, a PLIC. Each of its 176 sources has a
## priority and a bit that lets it through to the core, in machine mode, and a
## handler is whatever defines `lutra_interrupt_<source>`. Numbers are from
## Linux's device tree, which counts the chip's peripherals from 16.

import std/strutils
import ../../arch/riscv64/trap
import registers

export trap.critical, trap.enableInterrupts, trap.disableInterrupts

const
  uartSources* = [18, 19, 20, 21, 22, 23]
  timerSources* = [75, 76]
  codecSource* = 41
  sources = 176

# Sources nobody handles are left out of the link, as null entries
{.emit: block:
  var (declarations, entries) = ("", "")
  for n in 0 ..< sources:
    declarations.add "void lutra_interrupt_$1(void) __attribute__((weak));\n" % $n
    entries.add "lutra_interrupt_$1, " % $n
  declarations & "static void (*const lutraHandlers[" & $sources & "])(void) = {" & entries & "};\n".}

var handlers {.importc: "lutraHandlers", nodecl.}: array[sources, proc() {.cdecl.}]

proc interrupt(frame: pointer, cause: uint64): pointer {.exportc: "lutraInterrupt".} =
  if (cause and 0xfff) == 11: # From the PLIC
    while true:
      let source = plicClaim[] # The highest waiting, and no longer waiting
      if source == 0: break
      if handlers[source] != nil: handlers[source]()
      plicClaim[] = source # Handled
  frame

proc enable*(source: static int) =
  ## Lets a source through to the core, and interrupts on
  Reg(plic + 4 * source.uint32)[] = 1 # Its priority, above the threshold's 0
  let bits = Reg(plicEnable + 4 * uint32(source div 32))
  bits[] = bits[] or (1'u32 shl (source mod 32))
  plicThreshold[] = 0
  {.emit: "__asm__ volatile(\"csrs mie, %0\" : : \"r\"(1 << 11));".} # From the PLIC
  enableInterrupts()
