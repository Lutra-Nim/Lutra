## Lutra, a Nim-only bare-metal stack for TinyML microcontrollers.
##
## `import lutra` gives the board selected in the project's `config.nims`: its
## pins and peripherals, and printing and time on top of them.

import std/macros
import lutra/[fmt, time]
import lutra/hal/[pin, bytelink, i2c, spi]
export fmt, time, pin, bytelink, i2c, spi

const lutraBoard {.strdefine.} = ""

macro importBoard() =
  if lutraBoard == "":
    error "No board is selected. Put this in the project's config.nims:\n" &
      "  import lutra/project\n  board \"esp32c3_devkitm1\""
  let board = ident lutraBoard
  quote do:
    import lutra/boards/`board`
    export `board`

importBoard()

template print*(args: varargs[untyped]) =
  ## Writes each argument to the board's console
  console.write(args)

proc millis*(): uint64 = micros() div 1000
  ## Milliseconds since reset

proc delay*(duration: Duration) =
  let start = micros()
  while micros() - start < duration.uint64: discard
