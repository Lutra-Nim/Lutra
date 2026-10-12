import ../../arch/riscv32/start
import registers

{.used.}

# Programming the cache is left to the routines in the boot ROM
{.push cdecl, nodecl.}
proc cacheDisable() {.importc: "((void (*)(void))0x4000051c)".}
proc cacheInvalidate() {.importc: "((void (*)(void))0x400004d8)".}
proc cacheEnable(autoload: uint32) {.importc: "((void (*)(unsigned int))0x40000520)".}
{.pop.}

proc nimMain() {.importc: "NimMain", cdecl.}

# Set by the linker script; `flashPages` is a count held in a symbol's address
var bss {.importc: "_bss_start".}, bssEnd {.importc: "_bss_end".}, flashPages {.importc: "_flash_pages".}: uint32

proc main() {.exportc: "lutraMain", noinline.} =
  zeroMem(addr bss, cast[uint](addr bssEnd) - cast[uint](addr bss))
  nimMain()
  while true: discard

# The boot ROM loads this into RAM and runs it with flash still unreadable, so
# it can call or read nothing in flash but `main`, last. The build checks that.
proc reset() {.exportc: "lutraReset", codegenDecl: "__attribute__((section(\".ram.text\"))) $# $#$#".} =
  # Cycle counter on
  asm """
    csrwi 0x7e0, 1
    csrwi 0x7e1, 1
  """

  # The boot ROM leaves watchdogs running for a bootloader to feed
  rtcWatchdogProtect[] = 0x50D8_3AA1
  rtcWatchdog[] = 0
  timerWatchdogProtect[] = 0x50D8_3AA1
  timerWatchdog[] = 0
  superWatchdogProtect[] = 0x8F1D_312A'u32
  superWatchdog[] = superWatchdog[] or (1'u32 shl 31) # Feeds itself, it can't be stopped

  # 160 MHz, a third of the 480 MHz PLL which the boot ROM has already started
  cpuClock[] = cpuClock[] and not 3'u32 or 0b101
  systemClock[] = systemClock[] and not (3'u32 shl 10) or (1 shl 10)

  # Map flash in order, one 64K page at a time
  cacheDisable()
  for page in 0'u32..<128:
    Reg(flashPageTable + 4 * page)[] =
      if page < cast[uint32](addr flashPages): page else: 0x100 # Invalid
  cacheInvalidate()
  cacheEnable(0)
  cacheControl1[] = cacheControl1[] and not 3'u32 # Let both buses through

  main()
