## Hardware self-check for the B-L475E-IOT01A. Run it with
## `nim -d:board=b_l475e_iot01a selfcheck`, with nothing wired to PC5.

import lutra
import lutra/chips/stm32l475/[registers, clock, gpio]

const
  table = block:
    # Large enough to be more than either of the caches in front of flash holds
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
  asm "udf #0" # Not an instruction

print "BEGIN selfcheck\n"

# The core's clock against the board's 32.768 kHz crystal, which nothing else
# here uses: it is started, and counted by a timer of its own
block:
  proc ticks(): uint32 =
    # The count changes under a different clock, so it is read until it agrees
    while true:
      result = lowTimerCount[]
      if lowTimerCount[] == result: return

  switchOn(apb1Clocks, 28) # Power control, which guards the crystal's switch
  powerControl[] = powerControl[] or (1 shl 8)
  backupControl[] = backupControl[] or 1
  let began = micros()
  while (backupControl[] and 2) == 0 and micros() - began < 5_000_000: discard
  clockSources[] = clockSources[] or (3 shl 18) # The timer counts the crystal
  switchOn(apb1Clocks, 31)
  lowTimerControl[] = 1
  lowTimerReload[] = 0xFFFF
  lowTimerControl[] = 5
  var first = ticks()
  while ticks() == first: discard # From the edge of a tick
  first = ticks()
  let start = cycles()
  while ((ticks() - first) and 0xFFFF) < 3277: discard
  check "clock", cycles() - start, uint32(3277'u64 * cpuHz div 32768)

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

checkPin(PC5)

# The pin interrupts itself. Inside a critical section the handler has to wait,
# and it has to run on the way out.
var edges {.volatile.}: uint32
PC5.output()
PC5.low()
PC5.onRising:
  inc edges

block:
  var kept = true
  for i in 1'u32..1000:
    critical:
      PC5.high()
      PC5.low()
      if edges != i - 1: kept = false
    if edges != i: kept = false
  check "interrupts", kept

const expected = checksum(table)
check "constants", checksum(table) == expected

# The board's sensors share this bus, and none of them may have the address
# asked here. It has to be refused at once, and a clock line held low has to
# be given up on.
block:
  proc refusal(): uint64 =
    ## How long the bus took to find nobody there, or 0 if somebody was
    let start = micros()
    if not i2c2.write(0x7F, []): result = micros() - start

  i2c2.init(sda = PB11, scl = PB10)
  check "i2c refusal", refusal() in 1'u64..1000'u64
  PB10.low()
  PB10.drive() # Held low from here, as a wedged device would
  check "i2c held line", refusal() in 10_000'u64..100_000'u64
  PB10.asFunction("I2C2 SCL") # The bus's clock again
  check "i2c recovery", refusal() in 1'u64..1000'u64

# Long enough for a watchdog to bite, if one were running, which would start
# again from the top
delay 30.sec
print "idle ok\n"

# Lutra's own handler reports this, and then halts
fault()
