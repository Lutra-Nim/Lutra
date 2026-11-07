## What a 64-bit RISC-V chip does about a fault. Nothing of the vendor's is
## left to say what went wrong, so a board asks for this, which names the
## fault and where it happened on the board's console, and stops:
##
##   Fault: illegal instruction at 0x40000a3c
##          last call from 0x40000311
##
## The second address is the return address register's, which is where the
## last call made before the fault will return to. The trap vector
## (`trap.nim`) hands a fault to `lutraFault`.

import ../../[fmt, tasks]
import ../../hal/bytelink

func cause(code: uint64): cstring =
  case code
  of 0: "jump to a misaligned address"
  of 1: "jump to a bad address"
  of 2: "illegal instruction"
  of 3: "breakpoint"
  of 4, 6: "misaligned address"
  of 5, 7: "bad address" # Reading or writing where there is no memory
  else: "unknown"

proc report*(sink: static ByteSink, code, at, value, returnAddress: uint64) =
  template say(what: untyped) = sink.put(what)
  say cstring("Fault: ")
  if (code shr 63) != 0:
    say cstring("interrupt ")
    say code and 0xfff
  else:
    say cause(code)
  if code in [4'u64, 5, 6, 7]:
    say cstring(" 0x")
    say hex(value.uint32)
  say cstring(" at 0x")
  say hex(at.uint32) # Every address the program has is below 4 GB
  say cstring("\n       last call from 0x")
  say hex(returnAddress.uint32)
  say '\n'
  halt()

template reportFaults*(sink: static ByteSink) =
  ## From here on, a fault is reported to `sink`
  proc handler(code, at, value, returnAddress: uint64) {.exportc: "lutraFaultReport", cdecl.} =
    report(sink, code, at, value, returnAddress)

  # The report is given a stack of its own, the top of the program's, in case
  # the fault was running out of stack
  proc entry() {.exportc: "lutraFault", codegenDecl: "__attribute__((naked, aligned(4))) $# $#$#".} =
    asm """
      mv a3, ra
      csrr a0, mcause
      csrr a1, mepc
      csrr a2, mtval
      la sp, _stack_top
      j lutraFaultReport
    """
