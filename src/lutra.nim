## Lutra, a Nim-only bare-metal stack for TinyML microcontrollers.
##
## `import lutra` gives the board selected in the project's `config.nims`: its
## pins and peripherals, and printing, logging, reading numbers, time, tasks
## and records on top of them.

import std/[macros, strutils]
import lutra/[fmt, parse, time, tasks, claims, records]
import lutra/hal/[pin, bytelink, i2c, spi]
export fmt, parse, time, records, pin, bytelink, i2c, spi
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

type Log* = object

const
  log* = Log()
    ## Lines on the console, each with the time and its level:
    ##
    ##   log.info "joined ", network     # 1532 ms info  joined home
    ##
    ## `log.debug`, `log.info`, `log.warn` and `log.error` take what `print`
    ## takes. Below the level of `-d:log=...`, `info` unless it says, a line
    ## is left out of the program. `-d:log=off` leaves out every one.
  logLevel {.strdefine: "log".} = "info"
  levels = ["debug", "info", "warn", "error", "off"]

when logLevel notin levels:
  {.error: "-d:log=" & logLevel & " is not one of debug, info, warn, error and off".}

macro logLine(level: static string, args: varargs[untyped]): untyped =
  if levels.find(level) < levels.find(logLevel): return newEmptyNode()
  result = newCall(bindSym"print", newCall(bindSym"millis"), newLit(" ms " & level.alignLeft(6)))
  for arg in args: result.add arg
  result.add newLit('\n')

template debug*(_: Log, args: varargs[untyped]) = logLine("debug", args)
template info*(_: Log, args: varargs[untyped]) = logLine("info", args)
template warn*(_: Log, args: varargs[untyped]) = logLine("warn", args)
template error*(_: Log, args: varargs[untyped]) = logLine("error", args)

proc delay*(duration: Duration) =
  ## Lets the other tasks run for `duration`
  let start = micros()
  wait micros() - start >= duration.uint64

iterator every*(period: Duration): uint64 =
  ## Turns of a loop, one each `period`, numbered from 0. Each waits for its
  ## time, letting the other tasks run. A turn that would start late is
  ## skipped, and its number with it.
  let start = micros()
  var turn = 0'u64
  while true:
    yield turn
    turn = max(turn + 1, (micros() - start) div period.uint64 + 1)
    let due = start + turn * period.uint64
    wait micros() >= due

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
    if arg.kind == nnkExprEqExpr and not arg[0].eqIdent("stack"):
      error "A task has one setting, its stack: {.task(stack = 4.KB).}", arg
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
  ##   proc tick() {.interrupt: every(10.ms).} = ...
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
    arms.add newCall(bindSym"arm", event, where)
  result.add quote do:
    type `kind` = object
    const `exported` = `kind`()
    proc `start`(_: `kind`) = `arms`
