## Hardware self-check for the ESP32-C3-DevKitM-1. Run it with `nim selfcheck`,
## with nothing wired to IO4. IO18 and IO19 may have an I2C device on them or
## nothing.

import lutra
import lutra/chips/esp32c3/[registers, gpio]

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

# An I2C bus needs nobody on it to show that an address no device may have is
# refused, at once, and that a clock line held low is given up on
block:
  proc refusal(): uint64 =
    ## How long the bus took to find nobody there, or 0 if somebody was
    let start = micros()
    if not i2c0.write(0x7F, []): result = micros() - start

  i2c0.init(sda = IO18, scl = IO19)
  check "i2c refusal", refusal() in 1'u64..1000'u64
  IO19.low()
  IO19.routeOut(0x80) # Held low from here, as a wedged device would
  check "i2c held line", refusal() in 10_000'u64..100_000'u64
  IO19.routeOut(53) # The bus's clock again
  check "i2c recovery", refusal() in 1'u64..1000'u64

# The LED's 24 pulses are played a second time and read back from its pin,
# after once more to bring this loop into the cache
block:
  rgbLed.color(red = 0xA5, green = 0x0F, blue = 0x81)
  var
    edges: array[48, uint32]
    count: int
  for attempt in 1..2:
    pulseChannel[] = pulseChannel[] or (3 shl 1)
    pulseChannel[] = pulseChannel[] and not (3'u32 shl 1)
    pulseChannel[] = pulseChannel[] or (1 shl 24)
    var level = false
    count = 0
    let start = cycles()
    pulseChannel[] = pulseChannel[] or 1
    while count < edges.len and cycles() - start < cpuHz div 10_000:
      if rgbLed.pin.read() != level:
        edges[count] = cycles()
        level = not level
        inc count
    delay 1.ms
  var bits = 0'u32
  for bit in 0..<count div 2: # High for longer than half a microsecond is a 1
    bits = (bits shl 1) or (if edges[2 * bit + 1] - edges[2 * bit] > cpuHz div 2_000_000: 1 else: 0)
  check "led pulses", count == edges.len and bits == 0x0FA581 # Green goes first
  rgbLed.off()

# Long enough for any watchdog left running to bite, which would start again
# from the top
delay 30.sec
print "idle ok\n"

# The boot ROM's trap handler reports this, and then halts. With interrupts in
# use the fault arrives at Lutra's vector first, which has to hand it on.
fault()
