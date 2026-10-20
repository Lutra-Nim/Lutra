## Tasks that take turns. Each runs until it waits, and then the next in line
## runs, so code between two waits is never interrupted by another task:
##
##   proc blink() {.task.} =
##     while true:
##       led.toggle()
##       delay 500.ms
##
##   start blink
##
## The `task` pragma is in `lutra`. Every wait goes through `idle`, which
## does nothing until a program has a task: the linker then binds it to `pass`
## instead. A driver waits through it only on the world outside, as for a byte
## to arrive, and never part-way through something another task could break
## into, so a `print` comes out whole. An interrupt handler's waits never
## hand over.

import hal/bytelink, fmt

{.emit: "__attribute__((weak)) void lutraIdle(void) {}".}
{.emit: "__attribute__((weak)) void lutraHalted(void) {}".}

proc idle*() {.importc: "lutraIdle", cdecl.}
  ## Lets the other tasks run, if there are any

proc halted() {.importc: "lutraHalted", cdecl.}

template halt*() =
  ## Stops for good, once a panic or a fault has been reported. A board whose
  ## host has no other way to start it again defines `lutraHalted` to watch
  ## for the host asking.
  while true: halted()

template wait*(condition: untyped) =
  ## Lets the other tasks run until `condition` holds
  while not condition: idle()

# The architecture's, found by the linker
proc switch(save: ptr pointer, to: pointer) {.importc: "lutraSwitch", cdecl.}
proc prepare(top, entry: pointer): pointer {.importc: "lutraPrepare", cdecl.}
proc inHandler(): bool {.importc: "lutraInHandler", cdecl.}

type
  Task = object
    saved: pointer # Where its registers are, while another task runs
    next: ptr Task # The task after it in line, or nil when it is not running
    stack: ptr UncheckedArray[uint32]
    size: int # Of the stack, in bytes
    name: cstring

  Stack*[bytes: static int] = object
    ## A task's stack, and above it what says whose it is. An overflow runs
    ## away from that, so it can still be reported.
    words: array[bytes div 4, uint32]
    task: Task

const guard = 0x6c75_7472'u32 # In the lowest word of a stack, until something overwrites it

# Above every task's stack, as the linker script places them, out of reach of
# one that overflows
{.push codegenDecl: "$# $# __attribute__((section(\".tasks\")))".}
var
  program: Task # The program itself, on the stack it started on
  running: ptr Task # Nil until the first task starts
{.pop.}

proc before(task: ptr Task): ptr Task =
  ## The task whose turn comes just before
  result = task
  while result.next != task: result = result.next

proc begin(task: var Task, name: cstring, stack: var openArray[uint32], entry: proc() {.nimcall.}) =
  if running == nil:
    program.next = addr program
    running = addr program
  if task.next != nil: return
  task.stack = cast[ptr UncheckedArray[uint32]](addr stack[0])
  task.size = 4 * stack.len
  task.name = name
  stack[0] = guard
  task.saved = prepare(addr task.stack[stack.len], cast[pointer](entry))
  task.next = running
  running.before.next = addr task

proc begin*(stack: var Stack, name: cstring, entry: proc() {.nimcall.}) =
  ## Puts a task at the end of the line, so that its first turn comes after
  ## everyone else's. A task already in line stays where it is.
  begin(stack.task, name, stack.words, entry)

proc pass*(console: static ByteSink) =
  ## Hands over to the next task in line. A stack found overflowed is
  ## reported on `console`, and everything stops.
  if running == nil or inHandler(): return
  let task = running
  if task.stack != nil and task.stack[0] != guard:
    console.put cstring("Task ")
    console.put task.name
    console.put cstring(" overflowed its stack of ")
    console.put task.size
    console.put cstring(" bytes\n")
    halt()
  running = task.next
  if running != task: switch(addr task.saved, running.saved)

proc finish*() =
  ## Takes the running task out of line, and hands over
  let (task, previous) = (running, running.before)
  previous.next = task.next
  task.next = nil
  running = previous.next
  switch(addr task.saved, running.saved)
