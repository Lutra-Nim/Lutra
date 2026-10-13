## Where every Cortex-M begins: a table of addresses at the start of flash,
## which the core reads for itself. The first is the stack to start on and the
## second the chip's `lutraReset`. Then come the faults, and then an entry for
## each interrupt the chip has: its handler is whatever defines
## `lutra_interrupt_<n>`, and the ones nobody handles are left null.
##
## The chip's linker script puts `.vectors` first and provides `_stack_top`.

import std/strutils

func vectors*(interrupts: int): string =
  ## The table, as C for the chip to emit
  var (declarations, entries) = ("", "")
  for n in 0..<interrupts:
    declarations.add "void lutra_interrupt_$1(void) __attribute__((weak));\n" % $n
    entries.add ", lutra_interrupt_$1" % $n
  "extern char _stack_top;\nvoid lutraReset(void);\nvoid lutraFault(void) __attribute__((weak));\n" &
    declarations &
    "__attribute__((section(\".vectors\"), used)) void (*const lutraVectors[])(void) = {\n" &
    "(void (*)(void))&_stack_top, lutraReset,\n" &
    "lutraFault, lutraFault, lutraFault, lutraFault, lutraFault,\n" & # The one that can't be masked, and the four kinds of fault
    "0, 0, 0, 0, 0, 0, 0, 0, 0" & entries & "};\n" # System calls and the tick are not used
