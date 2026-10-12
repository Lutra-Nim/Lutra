## How an ESP32-C3's memory is laid out. A board says how much flash it has,
## and the linker script and the offsets an image is flashed at both follow
## from that.
##
## Flash is cut into 64K pages. The boot ROM loads the first into RAM, and
## the rest is mapped so that the low 23 bits of an address are its offset in
## flash: code, then constants, then anything held back.

import std/strutils

type Memory* = object
  flashSize*: int
  flashMode* = "dio"
  flashFreq* = "80m" ## These two set how fast constants stream out of flash
  codeSize*: int = 960 * 1024
  reservedSize*: int ## Left alone at the end of flash

template KB*(n: int): int = n * 1024
template MB*(n: int): int = n * 1024 * 1024

const
  page* = 64.KB
  ramCodeSize* = 64.KB
  ramSize* = 256.KB ## Data, then the stack growing down from the top

func inFlash*(address: int): bool =
  ## Whether an address is in one of the two windows flash is mapped into
  address in 0x4200_0000..0x427F_FFFF or address in 0x3C00_0000..0x3C7F_FFFF

func codeOffset*(m: Memory): int = page
func constantsOffset*(m: Memory): int = page + m.codeSize
func constantsSize*(m: Memory): int = m.flashSize - m.reservedSize - m.constantsOffset

func linkerScript*(m: Memory): string =
  doAssert m.codeSize mod page == 0 and m.reservedSize mod page == 0 and
    m.flashSize mod page == 0 and m.constantsSize > 0, "flash regions are whole 64K pages"
  """
ENTRY(_start)

MEMORY
{
  /* One block of RAM seen through two windows, instruction 0x40380000 is data
     0x3FC80000. The 64K above these two belong to the boot ROM. */
  ram_code        (rwx) : ORIGIN = 0x40380000, LENGTH = $1
  ram             (rw)  : ORIGIN = 0x3FC90000, LENGTH = $2
  flash_code      (rx)  : ORIGIN = 0x42000000 + $3, LENGTH = $4
  flash_constants (r)   : ORIGIN = 0x3C000000 + $5, LENGTH = $6
}

_flash_pages = $7;

SECTIONS
{
  /* Loaded by the boot ROM */
  .ram.text : { *(.start) *(.ram.text) } > ram_code

  .data :
  {
    *(.data .data.*)
    PROVIDE(__global_pointer$$ = . + 0x800);
    *(.sdata .sdata.*)
  } > ram

  .bss (NOLOAD) :
  {
    _bss_start = .;
    *(.sbss .sbss.* .bss .bss.* COMMON)
    _bss_end = .;
  } > ram

  _stack_top = ORIGIN(ram) + LENGTH(ram);

  /* Read from flash, once it is mapped */
  .flash.text : { *(.text .text.*) } > flash_code
  .flash.rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > flash_constants

  /DISCARD/ : { *(.eh_frame) *(.comment) *(.riscv.attributes) }
}
""" % [$ramCodeSize, $ramSize, $m.codeOffset, $m.codeSize,
       $m.constantsOffset, $m.constantsSize, $(m.flashSize div page)]
