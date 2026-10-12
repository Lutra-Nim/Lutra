## Trap entry for RISC-V, and switching interrupts on and off.
##
## The vector is only installed by `takeTraps`, so a program that uses no
## interrupts keeps whatever handler the chip's vendor left. The chip decides
## what an interrupt means, in `lutraInterrupt`.

var vendorVector {.exportc: "lutraVendorVector".}: uint32

# An interrupt saves every register on the stack it arrived on, and resumes
# from whichever stack `lutraInterrupt` returns: that is what a scheduler needs
# to switch tasks. A fault is handed to the vendor's handler with the registers
# exactly as they were, by putting its vector back and faulting again.
proc vector() {.exportc: "lutraTrapVector", codegenDecl: "__attribute__((naked, aligned(256))) $# $#$#".} =
  asm """
    .option push
    .option norvc
    j 1f
    .rept 31
    j 2f
    .endr
    .option pop
  1:
    csrw mscratch, t0
    lui t0, %hi(lutraVendorVector)
    lw t0, %lo(lutraVendorVector)(t0)
    csrw mtvec, t0
    li t0, 0x80
    csrc mstatus, t0
    csrr t0, mscratch
    mret
  2:
    addi sp, sp, -128
    sw ra, 0(sp)
    sw t0, 4(sp)
    sw t1, 8(sp)
    sw t2, 12(sp)
    sw s0, 16(sp)
    sw s1, 20(sp)
    sw a0, 24(sp)
    sw a1, 28(sp)
    sw a2, 32(sp)
    sw a3, 36(sp)
    sw a4, 40(sp)
    sw a5, 44(sp)
    sw a6, 48(sp)
    sw a7, 52(sp)
    sw s2, 56(sp)
    sw s3, 60(sp)
    sw s4, 64(sp)
    sw s5, 68(sp)
    sw s6, 72(sp)
    sw s7, 76(sp)
    sw s8, 80(sp)
    sw s9, 84(sp)
    sw s10, 88(sp)
    sw s11, 92(sp)
    sw t3, 96(sp)
    sw t4, 100(sp)
    sw t5, 104(sp)
    sw t6, 108(sp)
    csrr t0, mepc
    sw t0, 112(sp)
    csrr t0, mstatus
    sw t0, 116(sp)
    mv a0, sp
    csrr a1, mcause
    call lutraInterrupt
    mv sp, a0
    lw t0, 112(sp)
    csrw mepc, t0
    lw t0, 116(sp)
    csrw mstatus, t0
    lw ra, 0(sp)
    lw t0, 4(sp)
    lw t1, 8(sp)
    lw t2, 12(sp)
    lw s0, 16(sp)
    lw s1, 20(sp)
    lw a0, 24(sp)
    lw a1, 28(sp)
    lw a2, 32(sp)
    lw a3, 36(sp)
    lw a4, 40(sp)
    lw a5, 44(sp)
    lw a6, 48(sp)
    lw a7, 52(sp)
    lw s2, 56(sp)
    lw s3, 60(sp)
    lw s4, 64(sp)
    lw s5, 68(sp)
    lw s6, 72(sp)
    lw s7, 76(sp)
    lw s8, 80(sp)
    lw s9, 84(sp)
    lw s10, 88(sp)
    lw s11, 92(sp)
    lw t3, 96(sp)
    lw t4, 100(sp)
    lw t5, 104(sp)
    lw t6, 108(sp)
    addi sp, sp, 128
    mret
  """

proc takeTraps*(): bool =
  ## Points the core at the vector above. True the first time.
  if vendorVector != 0: return false
  {.emit: ["__asm__ volatile(\"csrr %0, mtvec\" : \"=r\"(", vendorVector, "));"].}
  {.emit: ["__asm__ volatile(\"csrw mtvec, %0\" : : \"r\"(", vector, "));"].}
  true

proc enableInterrupts*() =
  {.emit: "__asm__ volatile(\"csrsi mstatus, 8\");".}

proc disableInterrupts*(): bool =
  ## True if they were on
  var status: uint32
  {.emit: ["__asm__ volatile(\"csrrci %0, mstatus, 8\" : \"=r\"(", status, "));"].}
  (status and 8) != 0

template critical*(body: untyped) =
  ## Runs `body` with interrupts off, and leaves them as they were
  let wereOn = disableInterrupts()
  body
  if wereOn: enableInterrupts()
