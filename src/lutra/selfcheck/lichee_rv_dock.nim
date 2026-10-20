## Hardware self-check for the Lichee RV Dock. Run it with `nim selfcheck`,
## from any project for this board. The module's green LED blinks and the
## Dock's addressable LED steps through red, green and blue, for an eye to
## check: nothing reads them back.

import lutra

const
  table = block:
    # Large enough to span many cache lines, and pages of DRAM
    var
      bytes: array[200_000, uint8]
      state = 12345'u32
    for b in bytes.mitems:
      state = state * 1664525 + 1013904223
      b = uint8(state shr 24)
    bytes

func checksum(data: openArray[uint8]): uint32 =
  result = 0x811c9dc5'u32
  for b in data: result = (result xor b) * 0x01000193

proc check(name: cstring, passed: bool) =
  print name, (if passed: cstring(" ok\n") else: cstring(" FAILED\n"))

proc check(name: cstring, value, target: uint32) =
  ## Passes within 1% of the target
  if value >= target - target div 100 and value <= target + target div 100:
    print name, " ok\n"
  else:
    print name, " FAILED, ", value, " rather than ", target, "\n"

proc fault() =
  asm ".word 0" # Not an instruction

print "BEGIN selfcheck\n"

# The core's clock, from its PLL, against the time, which counts the crystal
block:
  let (startMicros, startCycles) = (micros(), cycles())
  while micros() - startMicros < 100_000: discard
  check "clock", cycles() - startCycles, uint32(cpuHz div 10)

block:
  let start = cycles()
  delay 50.ms
  check "delay", cycles() - start, uint32(cpuHz div 20)

block:
  let start = millis()
  delay 250.ms
  check "millis", uint32(millis() - start), 250

# The data cache is on: a loop that reads and writes the stack takes a few
# cycles a turn, not the two hundred it takes from DRAM
block:
  var counter {.volatile.}: int32
  let start = cycles()
  for _ in 1..100_000: counter = counter + 1
  check "cache", cycles() - start < 2_000_000

# The FPU is on, or the first instruction for it would fault
block:
  var x {.volatile.} = 2.0
  let root = x * 0.5 + 1.0 / x
  check "fpu", root > 1.4999 and root < 1.5001

# The vector unit is on, or its first instruction would fault: four 32-bit
# sums in one instruction, as T-Head's 128-bit vectors hold four. In a proc,
# as an `emit` at the top level lands outside any function.
proc vectorSums(): bool =
  var
    a = [1'u32, 2, 3, 4]
    b = [10'u32, 20, 30, 40]
    c: array[4, uint32]
    lanes: uint64
  let (pa, pb, pc) = (addr a[0], addr b[0], addr c[0])
  {.emit: ["""__asm__ volatile(
    ".option push\n.option arch, +xtheadvector\n"
    "th.vsetvli %0, %4, e32, m1\n"
    "th.vle.v v1, (%1)\n"
    "th.vle.v v2, (%2)\n"
    "th.vadd.vv v3, v1, v2\n"
    "th.vse.v v3, (%3)\n"
    ".option pop\n"
    : "=&r"(""", lanes, """) : "r"(""", pa, """), "r"(""", pb, """), "r"(""", pc, """), "r"(4) : "memory");"""].}
  lanes == 4 and c == [11'u32, 22, 33, 44]

check "vector", vectorSums()

# The module's LED drives its pin, which reads back what is driven
block:
  led.output()
  led.high()
  delay 1.us
  let readHigh = led.read()
  led.low()
  delay 1.us
  let readLow = led.read()
  check "gpio output", readHigh and not readLow

block:
  let (a, b, c) = (random(), random(), random())
  check "random", a != b and b != c and a != c

const expected = checksum(table)
check "constants", checksum(table) == expected

# The LED controller says it has sent each colour
block:
  for (r, g, b) in [(20'u8, 0'u8, 0'u8), (0'u8, 20'u8, 0'u8), (0'u8, 0'u8, 20'u8)]:
    rgbLed.color(red = r, green = g, blue = b)
    delay 300.ms
  rgbLed.off()
  check "led sent", true

# Tasks take turns in the order they were started, each until it waits, and
# one that ends leaves the line
var
  order: array[9, char]
  noted: int

proc note(c: char) =
  order[noted] = c
  inc noted

proc first() {.task.} =
  for _ in 1..3:
    note 'a'
    idle()

proc second() {.task.} =
  for _ in 1..2:
    note 'b'
    idle()

start first
start second

for _ in 1..4:
  note 'p'
  idle()
check "tasks", order == ['p', 'a', 'b', 'p', 'a', 'b', 'p', 'a', 'p']

var
  ticks: uint32
  raised: bool
  sum: float # Kept across the task's waits, in a register the switch has to keep

proc ticker() {.task.} =
  var local = 0.0
  while true:
    delay 10.ms
    inc ticks
    local += 0.5
    sum = local

proc raiser() {.task.} =
  delay 20.ms
  raised = true

proc blinker() {.task.} =
  while true:
    led.toggle()
    delay 250.ms

start ticker
start raiser
start blinker

block:
  let start = ticks
  delay 100.ms
  check "tasks delay", ticks - start in 9'u32..10'u32

block:
  let met = wait(raised, within = 100.ms)
  let start = millis()
  let missed = not wait(false, within = 10.ms)
  check "tasks wait", met and missed and millis() - start in 10'u64..11'u64

block:
  check "tasks fpu", sum == 0.5 * float(ticks)

# A timer event comes as often as asked; inside a critical section it has to
# wait, and it comes on the way out. Its waits never hand over to a task.
var
  ticked {.volatile.}: uint32
  turns {.volatile.}: uint32

proc spinner() {.task.} =
  while true:
    inc turns
    idle()

proc tick() {.interrupt: every(1.ms).} =
  inc ticked
  idle() # Which has to do nothing here

start spinner

block:
  start tick
  let before = ticked
  delay 100.ms
  check "timer", ticked - before, 100

block:
  var (kept, before) = (true, 0'u32)
  critical:
    before = ticked
    let start = micros()
    while micros() - start < 3000: discard
    kept = ticked == before
  # The three ticks missed are one interrupt, taken as soon as they are on again
  check "interrupts", kept and ticked == before + 1

block:
  let (before, ticksBefore) = (turns, ticked)
  while ticked - ticksBefore < 5: discard # Spinning, so only a handler could hand over
  check "tasks in handler", turns == before

# A turn of `every` comes as often as asked, and skips the turns it would
# start late
block:
  var
    turns: array[4, uint64]
    taken = 0
  let began = millis()
  for turn in every(10.ms):
    if taken == 1: delay 25.ms # Too late for turns 2 and 3
    turns[taken] = turn
    inc taken
    if taken == turns.len: break
  check "every", turns == [0'u64, 1, 4, 5] and millis() - began in 50'u64..51'u64

# Long enough for any watchdog left running to bite, which would start the
# chip again into its SD card's bootloader
delay 30.sec
print "idle ok\n"

# Reported by Lutra's fault handler, which then halts
fault()
