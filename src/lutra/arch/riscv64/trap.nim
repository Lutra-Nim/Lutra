## Trap entry for 64-bit RISC-V, and switching interrupts on and off.
##
## Every trap comes to one vector, which the chip's startup installs. A fault
## goes on to the board's fault report (`fault.nim`) with the registers exactly
## as they were. The chip decides what an interrupt means, in
## `lutraInterrupt`.

var handling {.exportc: "lutraHandling".}: uint64 # Set while an interrupt is handled

# An interrupt saves every register a call may change on the stack it arrived
# on, the FPU's among them, and resumes from whichever stack `lutraInterrupt`
# returns: that is what a scheduler needs to switch tasks.
proc vector() {.exportc: "lutraTrapVector", codegenDecl: "__attribute__((naked, aligned(4))) $# $#$#".} =
  asm """
    csrw mscratch, t0
    csrr t0, mcause
    bltz t0, 1f
    csrr t0, mscratch
    j lutraFault
  1:
    csrr t0, mscratch
    addi sp, sp, -416
    sd ra, 0(sp)
    sd t0, 8(sp)
    sd t1, 16(sp)
    sd t2, 24(sp)
    sd a0, 32(sp)
    sd a1, 40(sp)
    sd a2, 48(sp)
    sd a3, 56(sp)
    sd a4, 64(sp)
    sd a5, 72(sp)
    sd a6, 80(sp)
    sd a7, 88(sp)
    sd t3, 96(sp)
    sd t4, 104(sp)
    sd t5, 112(sp)
    sd t6, 120(sp)
    fsd ft0, 128(sp)
    fsd ft1, 136(sp)
    fsd ft2, 144(sp)
    fsd ft3, 152(sp)
    fsd ft4, 160(sp)
    fsd ft5, 168(sp)
    fsd ft6, 176(sp)
    fsd ft7, 184(sp)
    fsd fa0, 192(sp)
    fsd fa1, 200(sp)
    fsd fa2, 208(sp)
    fsd fa3, 216(sp)
    fsd fa4, 224(sp)
    fsd fa5, 232(sp)
    fsd fa6, 240(sp)
    fsd fa7, 248(sp)
    fsd ft8, 256(sp)
    fsd ft9, 264(sp)
    fsd ft10, 272(sp)
    fsd ft11, 280(sp)
    frcsr t0
    sd t0, 288(sp)
    csrr t0, mepc
    sd t0, 296(sp)
    csrr t0, mstatus
    sd t0, 304(sp)
    sd s0, 312(sp)
    sd s1, 320(sp)
    sd s2, 328(sp)
    sd s3, 336(sp)
    sd s4, 344(sp)
    sd s5, 352(sp)
    sd s6, 360(sp)
    sd s7, 368(sp)
    sd s8, 376(sp)
    sd s9, 384(sp)
    sd s10, 392(sp)
    sd s11, 400(sp)
    li t0, 1
    sd t0, lutraHandling, t1
    mv a0, sp
    csrr a1, mcause
    call lutraInterrupt
    sd zero, lutraHandling, t0
    mv sp, a0
    ld t0, 288(sp)
    fscsr t0
    ld t0, 296(sp)
    csrw mepc, t0
    ld t0, 304(sp)
    csrw mstatus, t0
    ld ra, 0(sp)
    ld t0, 8(sp)
    ld t1, 16(sp)
    ld t2, 24(sp)
    ld a0, 32(sp)
    ld a1, 40(sp)
    ld a2, 48(sp)
    ld a3, 56(sp)
    ld a4, 64(sp)
    ld a5, 72(sp)
    ld a6, 80(sp)
    ld a7, 88(sp)
    ld t3, 96(sp)
    ld t4, 104(sp)
    ld t5, 112(sp)
    ld t6, 120(sp)
    fld ft0, 128(sp)
    fld ft1, 136(sp)
    fld ft2, 144(sp)
    fld ft3, 152(sp)
    fld ft4, 160(sp)
    fld ft5, 168(sp)
    fld ft6, 176(sp)
    fld ft7, 184(sp)
    fld fa0, 192(sp)
    fld fa1, 200(sp)
    fld fa2, 208(sp)
    fld fa3, 216(sp)
    fld fa4, 224(sp)
    fld fa5, 232(sp)
    fld fa6, 240(sp)
    fld fa7, 248(sp)
    fld ft8, 256(sp)
    fld ft9, 264(sp)
    fld ft10, 272(sp)
    fld ft11, 280(sp)
    ld s0, 312(sp)
    ld s1, 320(sp)
    ld s2, 328(sp)
    ld s3, 336(sp)
    ld s4, 344(sp)
    ld s5, 352(sp)
    ld s6, 360(sp)
    ld s7, 368(sp)
    ld s8, 376(sp)
    ld s9, 384(sp)
    ld s10, 392(sp)
    ld s11, 400(sp)
    addi sp, sp, 416
    mret
  """

proc enableInterrupts*() =
  {.emit: "__asm__ volatile(\"csrsi mstatus, 8\");".}

proc disableInterrupts*(): bool =
  ## True if they were on
  var status: uint64
  {.emit: ["__asm__ volatile(\"csrrci %0, mstatus, 8\" : \"=r\"(", status, "));"].}
  (status and 8) != 0

proc inHandler(): bool {.exportc: "lutraInHandler".} = handling != 0

template critical*(body: untyped) =
  ## Runs `body` with interrupts off, and leaves them as they were
  let wereOn = disableInterrupts()
  body
  if wereOn: enableInterrupts()
