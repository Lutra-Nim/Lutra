## Where every 64-bit RISC-V chip begins. The chip's linker script puts the
## `.start` section first and provides the two symbols, and the chip continues
## in `lutraReset`.
##
## A loader that writes the program into RAM does so behind the instruction
## cache, which may still hold the last program's code at the same addresses.
## So the first cache line is the same in every program: `fence.i`, which
## empties the cache, and a jump past the line. A stale copy of it is still
## right.

{.used.}

proc start() {.exportc: "_start", codegenDecl: "__attribute__((naked, section(\".start\"))) $# $#$#".} =
  # The global pointer has to be loaded without the relaxation that relies on it
  asm """
    .option push
    .option norvc
    .option arch, +zifencei
    fence.i
    j 1f
    .balign 64
  1:
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, _stack_top
    csrci mstatus, 8
    j lutraReset
  """
