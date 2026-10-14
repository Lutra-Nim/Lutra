## Switching from one stack to another, which is all that tasks need of the
## core. Only the registers a call has to leave as it found them are kept: the
## return address and s0 to s11, on the stack being left.

{.used.}

proc switch(save: ptr pointer, to: pointer) {.exportc: "lutraSwitch", codegenDecl: "__attribute__((naked)) $# $#$#".} =
  asm """
    addi sp, sp, -64
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    sw s5, 24(sp)
    sw s6, 28(sp)
    sw s7, 32(sp)
    sw s8, 36(sp)
    sw s9, 40(sp)
    sw s10, 44(sp)
    sw s11, 48(sp)
    sw sp, 0(a0)
    mv sp, a1
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    lw s5, 24(sp)
    lw s6, 28(sp)
    lw s7, 32(sp)
    lw s8, 36(sp)
    lw s9, 40(sp)
    lw s10, 44(sp)
    lw s11, 48(sp)
    addi sp, sp, 64
    ret
  """

proc prepare(top, entry: pointer): pointer {.exportc: "lutraPrepare".} =
  ## A new stack, set out as `switch` leaves one, so that switching to it
  ## returns into `entry`
  let saved = cast[ptr array[16, pointer]](cast[uint](top) - 64)
  saved[0] = entry
  saved
