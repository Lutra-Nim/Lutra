## What a program does when one of Nim's checks fails: an index out of range,
## an overflow, a failed `assert`. A board asks for this, which says what
## failed and where on the board's console, and stops:
##
##   Panic: index out of bounds at 0x42000a3c
##
## `nim monitor` adds the line of the program the address is in.

import fmt, tasks
import hal/bytelink

template reportPanics*(sink: static ByteSink) =
  ## From here on, a failed check is reported to `sink`
  mixin critical
  proc lutraPanic(what: cstring, at: pointer) {.exportc, cdecl, noreturn.} =
    critical:
      sink.put cstring("Panic: ")
      sink.put what
      if at != nil:
        sink.put cstring(" at 0x")
        sink.put hex(cast[uint32](at))
      sink.put '\n'
      halt()

  # Nim calls `exit` when a program quits or an exception goes uncaught. This
  # one keeps the C library's out of the image, and its 1 KB of RAM on ARM.
  proc exit(code: cint) {.exportc, cdecl, noreturn.} = lutraPanic(cstring("the program quit"), nil)
