## How an STM32L475's memory is laid out. A board says how much flash its
## chip has, and the linker script follows from that.
##
## Flash is on the chip and read where it is, so one image holds the table of
## vectors, the code, the constants and what variables start out as.

import std/strutils

type Memory* = object
  flashSize*: int

template KB*(n: int): int = n * 1024
template MB*(n: int): int = n * 1024 * 1024

const ramSize* = 96.KB ## Data, then the stack growing down from the top

func linkerScript*(m: Memory): string =
  """
ENTRY(lutraReset)

MEMORY
{
  flash (rx) : ORIGIN = 0x08000000, LENGTH = $1
  /* The larger of two blocks. The other, 32K at 0x10000000, is left alone. */
  ram   (rw) : ORIGIN = 0x20000000, LENGTH = $2
}

SECTIONS
{
  .vectors : { KEEP(*(.vectors)) } > flash
  .text : { *(.text .text.*) } > flash
  .rodata : { *(.rodata .rodata.*) } > flash

  /* Kept in flash, and copied out by the startup code */
  .data :
  {
    _data_start = .;
    *(.data .data.*)
    _data_end = .;
  } > ram AT> flash
  _data_load = LOADADDR(.data);

  /* Tasks' stacks go above every other variable, so that one which overflows
     runs into those or into another task's stack, never off the end of RAM
     or into the scheduler's own, above, which it needs to report it */
  .bss (NOLOAD) :
  {
    _bss_start = .;
    *(.bss .bss.* COMMON)
    *(.stacks)
    *(.tasks)
    _bss_end = .;
  } > ram

  _stack_top = ORIGIN(ram) + LENGTH(ram);

  /DISCARD/ : { *(.ARM.exidx*) *(.ARM.extab*) *(.comment) }
}
""" % [$m.flashSize, $ramSize]
