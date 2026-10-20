## How a D1's memory is laid out. A board says how much DRAM it has, and the
## linker script follows from that.
##
## The program is written into DRAM, through the boot ROM's USB loader, as
## one image: code, constants and what variables start out as, which need no
## copying. The stack grows down from the top of DRAM.

import std/strutils

type Memory* = object
  dramSize*: int

template KB*(n: int): int = n * 1024
template MB*(n: int): int = n * 1024 * 1024

const dramStart* = 0x4000_0000

func linkerScript*(m: Memory): string =
  """
ENTRY(_start)

MEMORY
{
  dram (rwx) : ORIGIN = $1, LENGTH = $2
}

SECTIONS
{
  /* First, where the loader starts the program */
  .start : { KEEP(*(.start)) } > dram
  .text : { *(.text .text.*) } > dram
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > dram

  .data :
  {
    *(.data .data.*)
    PROVIDE(__global_pointer$$ = . + 0x800);
    *(.sdata .sdata.*)
  } > dram

  /* Tasks' stacks go above every other variable, so that one which overflows
     runs into those or into another task's stack, never into the scheduler's
     own, above, which it needs to report it */
  .bss (NOLOAD) :
  {
    _bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    *(.stacks)
    *(.tasks)
    _bss_end = .;
  } > dram

  _stack_top = ORIGIN(dram) + LENGTH(dram);

  /DISCARD/ : { *(.eh_frame) *(.comment) *(.riscv.attributes) }
}
""" % ["0x" & dramStart.toHex(8), $m.dramSize]
