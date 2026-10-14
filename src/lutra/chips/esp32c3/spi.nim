import ../../[claims, tasks]
import registers, peripherals, gpio

template command(bus: Spi): Reg = Reg(bus.base + spiCommand)
template clock(bus: Spi): Reg = Reg(bus.base + spiClock)
template user(bus: Spi): Reg = Reg(bus.base + spiUser)
template length(bus: Spi): Reg = Reg(bus.base + spiLength)
template misc(bus: Spi): Reg = Reg(bus.base + spiMisc)
template data(bus: Spi, word: int): Reg = Reg(bus.base + spiData + 4 * word.uint32)
template dma(bus: Spi): Reg = Reg(bus.base + spiDma)
template eventsClear(bus: Spi): Reg = Reg(bus.base + spiEventsClear)
template events(bus: Spi): Reg = Reg(bus.base + spiEvents)
template targetMode(bus: Spi): Reg = Reg(bus.base + spiTarget)
template targetLength(bus: Spi): Reg = Reg(bus.base + spiTargetLength)
template clockGate(bus: Spi): Reg = Reg(bus.base + spiClockGate)

const
  # The bus's signals in the GPIO matrix
  clockSignal = 63
  cipoSignal = 64
  copiSignal = 65
  selectSignal = 68

  update = 1'u32 shl 23 # Of `command`: take the registers written since the last transfer
  start = 1'u32 shl 24
  fullDuplex = (1'u32 shl 0) or (1 shl 27) or (1 shl 28) # Of `user`: data out and in, at once

proc claim(bus: static Spi, clock, copi, cipo: static Gpio) =
  claim("IO" & $clock.num, "SPI" & $bus.num & " clock")
  claim("IO" & $copi.num, "SPI" & $bus.num & " data out of the controller")
  claim("IO" & $cipo.num, "SPI" & $bus.num & " data into the controller")

proc init*(bus: static Spi, clock, copi, cipo: static Gpio, hz: static int) =
  ## Brings the bus up as its controller, in mode 0 with the high bit first.
  ## `copi` carries data out of the controller and `cipo` data into it.
  bus.claim(clock, copi, cipo)
  peripheralClocks[] = peripheralClocks[] or (1 shl 6)
  bus.clockGate[] = 0b111 # On, and from the 80 MHz clock
  bus.user[] = fullDuplex
  bus.misc[] = 0x3f # Chip-selects are plain pins, so the bus's own are off
  const divider = 80_000_000 div hz
  when divider notin 2..64: {.error: "The SPI clock can be 1.25 MHz to 40 MHz.".}
  bus.clock[] = uint32(((divider - 1) shl 12) or ((divider div 2 - 1) shl 6) or (divider - 1))
  clock.routeOut(clockSignal)
  copi.routeOut(copiSignal)
  cipo.routeIn(cipoSignal)
  # At the pins' usual strength the clock's edges ring on a jumper wire, and a
  # target counts some of them twice
  clock.driveGently()
  copi.driveGently()

proc init*(device: static SpiDeviceOn) =
  claim("IO" & $device.select.num, "a chip-select of SPI" & $device.bus.num)
  device.select.high() # Before it is driven, so that it never dips low
  device.select.drive()
  device.select.driveGently()
  when device.ready != noPin:
    claim("IO" & $device.ready.num, "the ready line of an SPI" & $device.bus.num & " device")
    device.ready.listen()
    device.ready.pullDown() # A device that is not there is not ready

proc transfer*(device: static SpiDeviceOn, output: openArray[byte], input: var openArray[byte]) =
  ## Sends `output` while receiving as many bytes into `input`, which may be
  ## shorter, or empty, when what comes back is not wanted. Waits first for a
  ## device with a ready line to raise it, and afterwards for it to drop.
  when device.ready != noPin:
    wait device.ready.read()
  let bus = device.bus
  device.select.low()
  var done = 0
  # The bus holds 64 bytes at a time. Chip-select stays low between them, so
  # the device sees one transfer.
  while done < output.len:
    let count = min(output.len - done, 64)
    for word in 0..<(count + 3) div 4:
      var packed = 0'u32
      for i in 0..<4:
        if done + 4 * word + i < output.len:
          packed = packed or (output[done + 4 * word + i].uint32 shl (8 * i))
      bus.data(word)[] = packed
    bus.length[] = uint32(8 * count - 1)
    bus.command[] = update
    while (bus.command[] and update) != 0: discard
    bus.command[] = start
    while (bus.command[] and start) != 0: discard
    for i in 0..<count:
      if done + i < input.len:
        input[done + i] = byte(bus.data(i div 4)[] shr (8 * (i mod 4)))
    done += count
  device.select.high()
  when device.ready != noPin:
    wait not device.ready.read()

# As a target the bus has to take a whole transfer however long the controller
# makes it, so DMA moves the data: one descriptor for each direction.
type Descriptor = object
  control: uint32 # Size in bits 11:0, length in 23:12, last in 30, the DMA's to use in 31
  buffer: pointer
  next: pointer

var descriptorOut, descriptorIn: Descriptor

const
  asTarget = 1'u32 shl 26 # Of `targetMode`
  reset = 1'u32 shl 27
  receiveByDma = 1'u32 shl 27 # Of `dma`
  sendByDma = 1'u32 shl 28
  receiveFifoReset = 1'u32 shl 29
  sendFifoReset = 1'u32 shl 31
  transferDone = 1'u32 shl 12 # Of `events`

proc pulse(register: Reg, bits: uint32) {.inline.} =
  register[] = register[] or bits
  register[] = register[] and not bits

proc init*(target: static SpiTarget, clock, copi, cipo, select: static Gpio) =
  ## Brings the bus up as a target, in mode 0 with the high bit first
  const (bus, ready) = (target.bus, target.ready)
  bus.claim(clock, copi, cipo)
  claim("IO" & $select.num, "the chip-select of SPI" & $bus.num)
  peripheralClocks[] = peripheralClocks[] or (1 shl 6)
  peripheralClocks1[] = peripheralClocks1[] or (1 shl 6) # The DMA's clock
  peripheralResets1[] = peripheralResets1[] and not (1'u32 shl 6)
  bus.clockGate[] = 1
  bus.clock[] = 0
  bus.misc[] = 0
  bus.user[] = fullDuplex
  bus.targetMode[] = asTarget
  dmaInSource[] = bus.dmaSource
  dmaOutSource[] = bus.dmaSource
  clock.routeIn(clockSignal)
  copi.routeIn(copiSignal)
  select.routeIn(selectSignal)
  # Without the filter, one clock edge in some tens of thousands is counted
  # twice, even from a gently driven pin
  clock.filter()
  select.filter()
  select.pullUp() # Not selected, until a controller says otherwise
  cipo.routeOut(cipoSignal)
  cipo.driveGently()
  when ready != noPin:
    claim("IO" & $ready.num, "the ready line of SPI" & $bus.num)
    ready.drive()
    ready.low()

proc exchange*(target: static SpiTarget, output: openArray[byte], input: var openArray[byte]): int =
  ## Waits for the controller to run one transfer, which sends it `output` and
  ## fills `input`. Returns how many bytes the controller clocked,
  ## which should be the length both sides expected: a longer transfer is cut
  ## short, and may spoil the next. Both buffers have to be in RAM, and up to
  ## 4092 bytes.
  const (bus, ready) = (target.bus, target.ready)
  while true:
    descriptorOut = Descriptor(buffer: unsafeAddr output[0],
      control: output.len.uint32 or (output.len.uint32 shl 12) or (1 shl 30) or (1'u32 shl 31))
    descriptorIn = Descriptor(buffer: addr input[0], control: input.len.uint32 or (1'u32 shl 31))

    dmaIn.pulse(1) # Reset
    bus.dma.pulse(receiveFifoReset)
    bus.targetMode.pulse(reset)
    bus.dma[] = bus.dma[] or receiveByDma
    dmaInLink[] = cast[uint32](addr descriptorIn) and 0xFFFFF
    dmaInLink[] = dmaInLink[] or (1 shl 22) # Start

    dmaOut.pulse(1)
    bus.dma.pulse(sendFifoReset)
    bus.targetMode.pulse(reset)
    bus.dma[] = bus.dma[] or sendByDma
    dmaOutLink[] = cast[uint32](addr descriptorOut) and 0xFFFFF
    dmaOutLink[] = dmaOutLink[] or (1 shl 21)

    bus.eventsClear[] = transferDone
    bus.command[] = update
    while (bus.command[] and update) != 0: discard
    bus.command[] = start

    when ready != noPin: ready.high()
    wait (bus.events[] and transferDone) != 0
    when ready != noPin: ready.low()
    result = int(bus.targetLength[] and 0x3ffff) div 8
    # Chip-select dipping with no data is what the line does as a controller
    # resets or starts, not a transfer
    if result > 0: break
