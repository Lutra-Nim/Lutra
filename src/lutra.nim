## Lutra, a Nim-only bare-metal stack for TinyML microcontrollers.
##
## `import lutra` gives the board selected in the project's `config.nims`: its
## pins and peripherals, and printing, time and tasks on top of them.

import std/macros
import lutra/[fmt, time, tasks, claims]
import lutra/hal/[pin, bytelink, i2c, spi]
export fmt, time, pin, bytelink, i2c, spi
export tasks.wait, tasks.idle

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
  ## Lets the other tasks run for `duration`
  let start = micros()
  wait micros() - start >= duration.uint64

template wait*(condition: untyped, within: Duration): bool =
  ## Lets the other tasks run until `condition` holds, or until `within` has
  ## passed. True if it held.
  let start = micros()
  var held = condition
  while not held and micros() - start < within.uint64:
    idle()
    held = condition
  held

template task*(name: untyped, stack: static int, body: untyped) =
  ## Starts `body` here, as a task with a stack of `stack` bytes. It takes
  ## turns with the program and the other tasks, and ends when `body` does.
  when first("lutra.tasks"):
    proc handOver() {.gensym, exportc: "lutraIdle", cdecl.} = pass(console)
    discard cast[pointer](handOver) # Inside a procedure, Nim leaves out one nothing refers to
  # Above the program's variables, where the linker script puts `.stacks`
  var space {.global, gensym, codegenDecl: "$# $# __attribute__((section(\".stacks\"), aligned(16)))".}:
    Stack[stack]
  proc run() {.gensym, nimcall.} =
    body
    finish()
  space.start(astToStr(name), run)

template task*(name, body: untyped) =
  ## A task with a stack of 2 KB
  task(name, 2048, body)
