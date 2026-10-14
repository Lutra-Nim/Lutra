import ../../claims
import registers, peripherals, gpio, clock

template sclLow(bus: I2c): Reg = Reg(bus.base + i2cSclLow)
template control(bus: I2c): Reg = Reg(bus.base + i2cControl)
template status(bus: I2c): Reg = Reg(bus.base + i2cStatus)
template fifoConfig(bus: I2c): Reg = Reg(bus.base + i2cFifoConfig)
template data(bus: I2c): Reg = Reg(bus.base + i2cData)
template events(bus: I2c): Reg = Reg(bus.base + i2cEvents)
template eventsClear(bus: I2c): Reg = Reg(bus.base + i2cEventsClear)
template sdaHold(bus: I2c): Reg = Reg(bus.base + i2cSdaHold)
template sdaSample(bus: I2c): Reg = Reg(bus.base + i2cSdaSample)
template sclHigh(bus: I2c): Reg = Reg(bus.base + i2cSclHigh)
template startHold(bus: I2c): Reg = Reg(bus.base + i2cStartHold)
template restartSetup(bus: I2c): Reg = Reg(bus.base + i2cRestartSetup)
template stopHold(bus: I2c): Reg = Reg(bus.base + i2cStopHold)
template stopSetup(bus: I2c): Reg = Reg(bus.base + i2cStopSetup)
template command(bus: I2c, slot: int): Reg = Reg(bus.base + i2cCommand + 4 * slot.uint32)

const
  # The bus's signals in the GPIO matrix, each the same in both directions
  sclSignal = 53
  sdaSignal = 54

  asController = 1'u32 shl 4 # Of `control`
  start = 1'u32 shl 5
  clockEnable = 1'u32 shl 8
  update = 1'u32 shl 11 # Take the registers written since the last transaction
  fifoResets = 3'u32 shl 12 # Of `fifoConfig`
  complete = 1'u32 shl 7 # Of `events`
  refused = 1'u32 shl 10

  # What the bus is told to do, queued in up to eight slots. The low byte of a
  # write or a read is how many bytes.
  restart = 6'u32 shl 11
  writeBytes = (1'u32 shl 11) or (1 shl 8) # And expect each to be acknowledged
  readBytes = 3'u32 shl 11
  readLast = readBytes or (1 shl 10) or 1 # Left unacknowledged, which tells the device to stop
  stop = 2'u32 shl 11

proc init*(bus: static I2c, sda, scl: static Gpio, hz: static int = 100_000) =
  ## Brings the bus up as its controller. The pins' own pull-ups are switched
  ## on. They are weak, enough for a short wire at 100 kHz; faster or further
  ## wants the resistors most sensor boards carry.
  claim("IO" & $sda.num, "I2C" & $bus.num & " SDA")
  claim("IO" & $scl.num, "I2C" & $bus.num & " SCL")
  when hz notin 40_000..400_000: {.error: "The I2C clock can be 40 kHz to 400 kHz.".}
  peripheralClocks[] = peripheralClocks[] or (1 shl 7)
  # Everything is timed in ticks of the 40 MHz crystal
  const
    half = uint32(40_000_000 div hz div 2)
    rise = half div 8
  bus.sclLow[] = half - 1
  bus.sclHigh[] = (half - rise) or (rise shl 9) # `rise` is allowed for the line to come up
  bus.sdaHold[] = half div 4
  bus.sdaSample[] = half div 2
  bus.startHold[] = half - 1
  bus.restartSetup[] = half
  bus.stopHold[] = half
  bus.stopSetup[] = half
  bus.control[] = bus.control[] or asController or clockEnable
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
  sda.routeOut(sdaSignal)
  sda.routeIn(sdaSignal)
  scl.routeOut(sclSignal)
  scl.routeIn(sclSignal)

proc recover(bus: static I2c) =
  ## Resets the bus's controller and puts its settings back. Nothing less
  ## clears it once a device has refused a transaction of more than its
  ## address: what was left unsent goes out as the address of the next.
  const settings = [i2cSclLow, i2cSdaHold, i2cSdaSample, i2cSclHigh, i2cStartHold, i2cRestartSetup,
    i2cStopHold, i2cStopSetup]
  var kept: array[settings.len, uint32]
  for i, setting in settings: kept[i] = Reg(bus.base + setting)[]
  peripheralResets[] = peripheralResets[] or (1 shl 7)
  peripheralResets[] = peripheralResets[] and not (1'u32 shl 7)
  for i, setting in settings: Reg(bus.base + setting)[] = kept[i]
  bus.control[] = bus.control[] or asController or clockEnable

proc transact(bus: static I2c, address: byte, output: openArray[byte], input: var openArray[byte]): bool =
  ## Writes `output` and then reads into `input`. Either may be empty.
  if output.len > 254 or input.len > 256: return false # More than one command can count
  var slot = 0
  template queue(what: uint32) =
    bus.command(slot)[] = what
    inc slot
  let
    writing = output.len > 0 or input.len == 0 # An empty write still asks whether anyone is there
    toSend = (if writing: 1 + output.len else: 0) + (if input.len > 0: 1 else: 0)
  if writing:
    queue restart
    queue writeBytes or uint32(1 + output.len)
  if input.len > 0:
    queue restart
    queue writeBytes or 1
    if input.len > 1: queue readBytes or uint32(input.len - 1)
    queue readLast
  queue stop

  template outgoing(i: int): byte =
    # The address to write to, the data, and the address again to read from
    if writing and i == 0: address shl 1
    elif writing and i <= output.len: output[i - 1]
    else: (address shl 1) or 1

  var (sent, received) = (0, 0)
  template shuttle() =
    # The bus holds 32 bytes each way, so both are kept moving as it works
    while sent < toSend and (bus.status[] shr 18 and 0x3f) < 32:
      bus.data[] = outgoing(sent)
      inc sent
    while received < input.len and (bus.status[] shr 8 and 0x3f) > 0:
      input[received] = byte(bus.data[])
      inc received

  bus.fifoConfig[] = bus.fifoConfig[] or fifoResets
  bus.fifoConfig[] = bus.fifoConfig[] and not fifoResets
  bus.eventsClear[] = 0xffff_ffff'u32
  shuttle()
  bus.control[] = bus.control[] or update
  bus.control[] = bus.control[] or start
  # A device that does not acknowledge is sent a stop, which completes the
  # transaction. One that never completes has a line held low, and the bus's
  # own timeouts do not catch every way that happens, so a deadline does.
  let deadline = micros() + 50_000 + 1000 * uint64(toSend + input.len)
  while (bus.events[] and complete) == 0 and micros() < deadline: shuttle()
  shuttle()
  result = (bus.events[] and (complete or refused)) == complete
  if not result: bus.recover()

proc write*(bus: static I2c, address: byte, data: openArray[byte]): bool {.discardable.} =
  ## Up to 254 bytes. False if the device did not acknowledge, as when it is
  ## not there; with no data, this only asks whether it is.
  var nothing: array[0, byte]
  bus.transact(address, data, nothing)

proc read*(bus: static I2c, address: byte, data: var openArray[byte]): bool {.discardable.} =
  ## Up to 256 bytes
  bus.transact(address, [], data)

proc writeRead*(bus: static I2c, address: byte, output: openArray[byte], input: var openArray[byte]): bool {.discardable.} =
  ## Writes, then reads without letting go of the bus between
  bus.transact(address, output, input)
