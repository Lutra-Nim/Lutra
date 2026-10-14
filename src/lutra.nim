## Lutra, a Nim-only bare-metal stack for TinyML microcontrollers.
##
## `import lutra` gives the board selected in the project's `config.nims`: its
## pins and peripherals, and printing, time and tasks on top of them.

import std/[macros, strutils]
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

proc start*[T](thing: T) {.error: "Only a proc declared {.task.} or {.interrupt: ...} can be started".}

proc plain(p: NimNode, what: string): tuple[name, exported, start: NimNode] =
  ## The name of a proc that takes nothing and returns nothing, and that name
  ## and `start`, each with the export marker if the proc has one
  if p.kind != nnkProcDef or p.params.len > 1 or p.params[0].kind != nnkEmpty:
    error what & " is a proc that takes nothing and returns nothing", p
  let name = ident(p.name.strVal)
  if p[0].kind == nnkPostfix: (name, postfix(name, "*"), postfix(ident"start", "*"))
  else: (name, name, ident"start")

macro task*(args: varargs[untyped]): untyped =
  ## Makes a proc a task, with a stack of 2 KB or of what it says:
  ##
  ##   proc blink() {.task.} = ...
  ##   proc logger() {.task(stack = 4.KB).} = ...
  ##
  ## `start blink` starts it. It takes turns with the program and the other
  ## tasks, and ends when the proc returns.
  let p = args[^1]
  var stack = newLit(2048)
  for arg in args[0 ..< ^1]:
    stack = if arg.kind == nnkExprEqExpr: arg[1] else: arg
  let
    (name, exported, start) = plain(p, "A task")
    body = p.body
    title = newLit(name.strVal)
    kind = genSym(nskType, "Task")
    space = genSym(nskVar, "space")
    run = genSym(nskProc, "run")
    (first, pass, console, Stack) = (bindSym"first", bindSym"pass", bindSym"console", bindSym"Stack")
    (finish, begin) = (bindSym"finish", bindSym"begin")
  quote do:
    when `first`("lutra.tasks"):
      proc handOver() {.gensym, exportc: "lutraIdle", cdecl.} = `pass`(`console`)
      discard cast[pointer](handOver) # Inside a procedure, Nim leaves out one nothing refers to
    # Above the program's variables, where the linker script puts `.stacks`
    var `space` {.global, codegenDecl: "$# $# __attribute__((section(\".stacks\"), aligned(16)))".}:
      `Stack`[`stack`]
    proc `run`() {.nimcall.} =
      `body`
      `finish`()
    type `kind` = object
    const `exported` = `kind`()
    proc `start`(_: `kind`) = `begin`(`space`, `title`, `run`)

proc events(n: NimNode): seq[NimNode] =
  ## The events of `a | b | c`
  if n.kind == nnkInfix and n[0].eqIdent("|"): events(n[1]) & events(n[2])
  else: @[n]

macro interrupt*(on, p: untyped): untyped =
  ## Makes a proc the handler of an event, or of several joined by `|`:
  ##
  ##   proc pressed() {.interrupt: bootButton.falling.} = ...
  ##
  ## `start pressed` switches it on. Its waits never hand over to a task.
  let
    (_, exported, start) = plain(p, "An interrupt")
    body = p.body
    info = p.lineInfoObj
    where = newLit(" at " & info.filename.split('/')[^1] & "(" & $info.line & ")")
    kind = genSym(nskType, "Interrupt")
    handler = genSym(nskProc, "handler")
    arms = newStmtList()
  result = newStmtList quote do:
    proc `handler`() {.inline.} = `body`
  for event in events(on):
    result.add newCall(bindSym"attach", event, where, handler)
    arms.add newCall(bindSym"arm", event)
  result.add quote do:
    type `kind` = object
    const `exported` = `kind`()
    proc `start`(_: `kind`) = `arms`
