import registers, peripherals, gpio, clock

template control(bus: Spi): Reg = Reg(bus.base + spiControl)
template status(bus: Spi): Reg = Reg(bus.base + spiStatus)

type Byte {.importc: "volatile unsigned char", nodecl.} = uint8

template data(bus: Spi): var Byte =
  # A byte at a time: a wider write would send two
  cast[ptr Byte](bus.base + spiData)[]

const
  # Of `status`
  waiting = 1'u32 shl 0
  roomToSend = 1'u32 shl 1
  busy = 1'u32 shl 7

proc init*(bus: static Spi, clock, copi, cipo: static Gpio, hz: static int) =
  ## Brings the bus up as its controller, in mode 0 with the high bit first.
  ## `copi` carries data out of the controller and `cipo` data into it. The
  ## clock is the core's divided by 2, 4, 8 and so on to 256: the fastest of
  ## those no faster than `hz`.
  const prefix = "SPI" & $bus.num
  clock.asFunction(prefix & " clock")
  copi.asFunction(prefix & " data out of the controller")
  cipo.asFunction(prefix & " data into the controller")
  const halvings = block:
    var n = 0
    while n < 7 and cpuHz div (2 shl n) > hz: inc n
    n
  when cpuHz div (2 shl halvings) > hz:
    {.error: "The STM32L475's SPI clock can be 312.5 kHz to 40 MHz.".}
  switchOn(apb2Clocks, bus.clockBit)
  # 8 bits, and a byte received is a byte to read, rather than waiting for two
  Reg(bus.base + spiControl2)[] = (7 shl 8) or (1 shl 12)
  # The controller, choosing devices by plain pins, and on
  bus.control[] = (1 shl 2) or (halvings.uint32 shl 3) or (1 shl 8) or (1 shl 9) or (1 shl 6)

proc init*(device: static SpiDeviceOn) =
  device.select.claim("a chip-select of SPI" & $device.bus.num)
  device.select.high() # Before it is driven, so that it never dips low
  device.select.drive()

proc transfer*(device: static SpiDeviceOn, output: openArray[byte], input: var openArray[byte]) =
  ## Sends `output` while receiving as many bytes into `input`, which may be
  ## shorter, or empty, when what comes back is not wanted
  let bus = device.bus
  device.select.low()
  for i in 0 ..< output.len:
    while (bus.status[] and roomToSend) == 0: discard
    bus.data = output[i]
    while (bus.status[] and waiting) == 0: discard
    let b = uint8(bus.data)
    if i < input.len: input[i] = b
  while (bus.status[] and busy) != 0: discard
  device.select.high()
