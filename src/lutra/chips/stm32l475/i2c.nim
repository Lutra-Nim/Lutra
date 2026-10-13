import registers, peripherals, gpio, clock

template control(bus: I2c): Reg = Reg(bus.base + i2cControl)
template transfer(bus: I2c): Reg = Reg(bus.base + i2cTransfer)
template status(bus: I2c): Reg = Reg(bus.base + i2cStatus)

const
  # Of `transfer`, which also holds the address and a count of bytes
  reading = 1'u32 shl 10
  start = 1'u32 shl 13
  thenStop = 1'u32 shl 25 # Once the bytes counted have gone
  # Of `status`
  wantsByte = 1'u32 shl 1
  hasByte = 1'u32 shl 2
  refused = 1'u32 shl 4
  stopped = 1'u32 shl 5
  written = 1'u32 shl 6 # Every byte counted, with no stop asked for

proc init*(bus: static I2c, sda, scl: static Gpio, hz: static int = 100_000) =
  ## Brings the bus up as its controller. The pins' own pull-ups are switched
  ## on. They are weak, enough for a short wire at 100 kHz; faster or further
  ## wants the resistors most sensor boards carry.
  when hz notin 40_000..400_000: {.error: "The I2C clock can be 40 kHz to 400 kHz.".}
  const (data, clock) = ("I2C" & $bus.num & " SDA", "I2C" & $bus.num & " SCL")
  sda.asFunction(data)
  scl.asFunction(clock)
  sda.openDrain()
  sda.pullUp()
  scl.openDrain()
  scl.pullUp()
  # A device this chip was reading when it was last reset is still part-way
  # through a byte, and holds the data line low wherever that byte has a 0.
  # So before the bus takes the pins it is clocked by hand until the device
  # lets go, and then told to stop.
  template pause() =
    let began = micros()
    while micros() - began < 5: discard
  sda.high()
  scl.high()
  sda.drive()
  scl.drive()
  pause()
  for _ in 1..9:
    if sda.read(): break
    scl.low()
    pause()
    scl.high()
    pause()
  sda.low()
  pause()
  sda.high()
  pause()
  sda.asFunction(data)
  scl.asFunction(clock)

  switchOn(apb1Clocks, bus.clockBit)
  # Everything is timed in ticks of an eighth of a microsecond, the bus's
  # 80 MHz clock divided by ten
  const
    ticks = 8_000_000 div hz
    low = ticks * 11 div 20
    setup = min(ticks div 5, 16) # For the data line to settle before the clock rises
  Reg(bus.base + i2cTiming)[] = (9'u32 shl 28) or uint32((setup - 1) shl 20) or (2 shl 16) or
    uint32((ticks - low - 1) shl 8) or uint32(low - 1)
  bus.control[] = 1

proc transact(bus: static I2c, address: byte, output: openArray[byte], input: var openArray[byte]): bool =
  ## Writes `output` and then reads into `input`. Either may be empty.
  if output.len > 255 or input.len > 255: return false # More than the bus can count
  template begin(direction: uint32, count: int, last: bool) =
    bus.transfer[] = (address.uint32 shl 1) or direction or (count.uint32 shl 16) or start or
      (if last: thenStop else: 0)

  if output.len > 0 or input.len == 0: # An empty write still asks whether anyone is there
    begin(0, output.len, input.len == 0)
  else:
    begin(reading, input.len, true)
  # A device that does not acknowledge is sent a stop, as the end of every
  # transaction is. One that never stops has a line held low, and nothing in
  # the bus says so, so a deadline does.
  var (sent, received, flags) = (0, 0, 0'u32)
  let deadline = micros() + 50_000 + 1000 * uint64(output.len + input.len)
  while (flags and stopped) == 0 and micros() < deadline:
    flags = bus.status[]
    if (flags and wantsByte) != 0:
      Reg(bus.base + i2cToSend)[] = output[sent]
      inc sent
    elif (flags and hasByte) != 0:
      input[received] = byte(Reg(bus.base + i2cReceived)[])
      inc received
    elif (flags and written) != 0:
      begin(reading, input.len, true)
  Reg(bus.base + i2cStatusClear)[] = stopped or refused
  result = (flags and (stopped or refused)) == stopped
  if not result:
    # Off and on again, which empties it of a byte a device refused and of
    # whatever it was in the middle of
    bus.control[] = 0
    discard bus.control[]
    bus.control[] = 1

proc write*(bus: static I2c, address: byte, data: openArray[byte]): bool {.discardable.} =
  ## Up to 255 bytes. False if the device did not acknowledge, as when it is
  ## not there; with no data, this only asks whether it is.
  var nothing: array[0, byte]
  bus.transact(address, data, nothing)

proc read*(bus: static I2c, address: byte, data: var openArray[byte]): bool {.discardable.} =
  ## Up to 255 bytes
  bus.transact(address, [], data)

proc writeRead*(bus: static I2c, address: byte, output: openArray[byte], input: var openArray[byte]): bool {.discardable.} =
  ## Writes, then reads without letting go of the bus between
  bus.transact(address, output, input)
