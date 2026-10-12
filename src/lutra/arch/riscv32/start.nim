## Where every RISC-V chip begins. The chip's linker script decides where the
## `.start` section goes and provides the two symbols, and the chip continues
## in `lutraReset`.

{.used.}

proc start() {.exportc: "_start", codegenDecl: "__attribute__((naked, section(\".start\"))) $# $#$#".} =
  # The global pointer has to be loaded without the relaxation that relies on it
  asm """
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, _stack_top
    csrci mstatus, 8
    j lutraReset
  """
