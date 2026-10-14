## Switching interrupts on and off on a Cortex-M, whose core has the interrupt
## controller in it. The handler of interrupt n is whatever defines
## `lutra_interrupt_<n>`, as `start` says.

import ../../reg

proc enable*(interrupt: static int) =
  ## Lets one of the chip's interrupts through
  Reg(0xE000_E100'u32 + 4 * uint32(interrupt div 32))[] = 1'u32 shl (interrupt mod 32)

proc enableInterrupts*() =
  {.emit: "__asm__ volatile(\"cpsie i\");".}

proc disableInterrupts*(): bool =
  ## True if they were on, as they are from reset
  var masked: uint32
  {.emit: ["__asm__ volatile(\"mrs %0, primask\\n cpsid i\" : \"=r\"(", masked, "));"].}
  masked == 0

proc inHandler(): bool {.exportc: "lutraInHandler".} =
  var exception: uint32 # The one being handled, or 0
  {.emit: ["__asm__ volatile(\"mrs %0, ipsr\" : \"=r\"(", exception, "));"].}
  exception != 0

template critical*(body: untyped) =
  ## Runs `body` with interrupts off, and leaves them as they were
  let wereOn = disableInterrupts()
  body
  if wereOn: enableInterrupts()
