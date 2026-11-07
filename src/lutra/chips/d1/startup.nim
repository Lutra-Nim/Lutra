import ../../arch/riscv64/start
import ../../tasks
import clock

{.used.}

proc nimMain() {.importc: "NimMain", cdecl.}
proc boardStart() {.importc: "lutraBoardStart".} # What the board does before a program

# Set by the linker script
var bss {.importc: "_bss_start".}, bssEnd {.importc: "_bss_end".}: uint32

proc reset() {.exportc: "lutraReset".} =
  # Every trap comes to the architecture's vector, in `trap.nim`, which
  # hands a fault to the board's `reportFaults`
  asm """
    la t0, lutraTrapVector
    csrw mtvec, t0
  """

  # The boot ROM leaves the FPU and the vector unit off, and the data cache
  # with them. The vector unit's switch is where the T-Head C906 has it, in
  # bits 24:23, as the vector extension's draft 0.7.1 had it.
  asm """
    li t0, (1 << 13) | (1 << 23)
    csrs mstatus, t0
    csrw fcsr, zero
    .word 0x0030000b
    li t0, 0x2 | 0x4 | 0x10 | 0x20 | 0x1000
    csrs 0x7c1, t0
    li t0, 0x650c
    csrw 0x7c5, t0
  """
  # `.word 0x0030000b` is T-Head's `dcache.ciall`, emptying the data cache
  # before it is used, and 0x7c1 is its cache control: the data cache, its
  # writes allocating, its refills, and branch prediction, on. 0x7c5 is its
  # prefetching, off as the boot ROM leaves it: on, reading from DRAM
  # streams twice as fast, and with bit 3, stores do too (Appendix E).

  setClocks()
  zeroMem(addr bss, cast[uint](addr bssEnd) - cast[uint](addr bss))
  boardStart()
  nimMain()
  while true: idle() # The program has ended, and any tasks go on
