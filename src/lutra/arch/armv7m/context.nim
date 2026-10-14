## Switching from one stack to another, which is all that tasks need of the
## core. Only the registers a call has to leave as it found them are kept: r4
## to r11 and the return address, on the stack being left. Programs are built
## for software floating point, so there are no others.

{.used.}

proc switch(save: ptr pointer, to: pointer) {.exportc: "lutraSwitch", codegenDecl: "__attribute__((naked)) $# $#$#".} =
  asm """
    push {r4-r11, lr}
    str sp, [r0]
    mov sp, r1
    pop {r4-r11, pc}
  """

proc prepare(top, entry: pointer): pointer {.exportc: "lutraPrepare".} =
  ## A new stack, set out as `switch` leaves one, so that switching to it
  ## returns into `entry`
  let saved = cast[ptr array[9, pointer]](cast[uint](top) - 36)
  saved[8] = entry
  saved
