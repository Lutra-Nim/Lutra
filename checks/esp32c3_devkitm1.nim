## Hardware self-check for the ESP32-C3-DevKitM-1. Run it with `nim selfcheck`,
## with nothing wired to IO4.

import lutra

const
  table = block:
    # Large enough to span several pages of flash
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

# The core's clock against the system timer, which runs straight off the crystal
block:
  let (startMicros, startCycles) = (micros(), cycles())
  while micros() - startMicros < 100_000: discard
  check "clock", cycles() - startCycles, cpuHz div 10

block:
  let start = cycles()
  delay 50.ms
  check "delay", cycles() - start, cpuHz div 20

block:
  let start = millis()
  delay 250.ms
  check "millis", uint32(millis() - start), 250

proc checkPin(pin: static Pin) =
  pin.output()
  pin.high()
  let readHigh = pin.read()
  pin.low()
  let readLow = pin.read()
  pin.toggle()
  check "gpio output", readHigh and not readLow and pin.read()

  pin.input()
  pin.pullUp()
  delay 1.ms
  check "gpio pull-up", pin.read()
  pin.pullDown()
  delay 1.ms
  check "gpio pull-down", not pin.read()
  pin.noPull()

checkPin(IO4)

# The pin interrupts itself. Inside a critical section the handler has to wait,
# and it has to run on the way out.
var edges {.volatile.}: uint32
IO4.output()
IO4.low()
IO4.onRising:
  inc edges

block:
  var kept = true
  for i in 1'u32..1000:
    critical:
      IO4.high()
      IO4.low()
      if edges != i - 1: kept = false
    if edges != i: kept = false
  check "interrupts", kept

block:
  let (a, b, c) = (random(), random(), random())
  check "random", a != b and b != c and a != c

const expected = checksum(table)
check "constants", checksum(table) == expected

# Long enough for any watchdog left running to bite, which would start again
# from the top
delay 30.sec
print "idle ok\n"

# The boot ROM's trap handler reports this, and then halts. With interrupts in
# use the fault arrives at Lutra's vector first, which has to hand it on.
fault()
