## What a Cortex-M does about a fault. No vendor's handler is there to say
## what went wrong, so a board asks for this one, which names the fault and
## where it happened on the board's console, and stops:
##
##   Fault: undefined instruction at 0x08000a3c
##          last call from 0x08000311
##
## The second address is the link register's, which is where the last call
## made before the fault will return to.

import ../../[reg, fmt, tasks]
import ../../hal/bytelink

const
  faultStatus = Reg 0xE000_ED28'u32
  faultAddress = Reg 0xE000_ED38'u32
  addressKnown = 1'u32 shl 15 # Of `faultStatus`

func cause(status: uint32): cstring =
  if (status and (1 shl 16)) != 0: "undefined instruction"
  elif (status and 0x1E00) != 0: "bad address" # Reading or writing where there is no memory
  elif (status and 0x0002_0101) != 0: "jump to a bad address"
  else: "unknown"

proc report*(sink: static ByteSink, frame: ptr array[8, uint32]) =
  # The core has pushed eight registers: the instruction is the seventh and
  # the link register the sixth
  let status = faultStatus[]
  template say(what: untyped) = sink.put(what)
  say cstring("Fault: ")
  say cause(status)
  if (status and addressKnown) != 0:
    say cstring(" 0x")
    say hex(faultAddress[])
  say cstring(" at 0x")
  say hex(frame[6])
  say cstring("\n       last call from 0x")
  say hex(frame[5] and not 1'u32)
  say '\n'
  halt()

template reportFaults*(sink: static ByteSink) =
  ## From here on, a fault is reported to `sink`
  proc handler(frame: ptr array[8, uint32]) {.exportc: "lutraFaultReport", cdecl.} = report(sink, frame)

  # The report is given a stack of its own, the top of the program's, in case
  # the fault was running out of stack
  proc entry() {.exportc: "lutraFault", codegenDecl: "__attribute__((naked)) $# $#$#".} =
    asm """
      mrs r0, msp
      ldr r1, =_stack_top
      mov sp, r1
      b lutraFaultReport
    """
