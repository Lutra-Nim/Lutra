## What an ESP32-C3 has, by name. Boards name the pins they bring out.

type
  Gpio* = object
    num*: int
  Uart* = object
    num*: int
    base*: uint32
    signal*: int ## Its number in the GPIO matrix, the same for both directions
    clockBit*: int ## In the system's clock enable register
    tx*: Gpio ## Where the boot ROM leaves it, if it does

  Spi* = object
    num*: int
    base*: uint32
    dmaSource*: uint32 ## What a DMA channel is told to serve it
  SpiDeviceOn* = object
    ## One device on a bus, picked out by its own chip-select
    bus*: Spi
    select*: Gpio
    ready*: Gpio ## Where the device says it is ready for a transfer, if it does
  SpiTarget* = object
    ## A bus used from the other end: a controller elsewhere clocks it
    bus*: Spi
    ready*: Gpio ## Raised while it waits for the controller, if wired

const
  noPin* = Gpio(num: -1)
  spi2* = Spi(num: 2, base: 0x6002_4000'u32, dmaSource: 0)
  uart0* = Uart(num: 0, base: 0x6000_0000'u32, signal: 6, clockBit: 2, tx: Gpio(num: 21))
  uart1* = Uart(num: 1, base: 0x6001_0000'u32, signal: 9, clockBit: 5, tx: noPin)

func device*(bus: Spi, select: Gpio, ready = noPin): SpiDeviceOn =
  SpiDeviceOn(bus: bus, select: select, ready: ready)

func target*(bus: Spi, ready = noPin): SpiTarget = SpiTarget(bus: bus, ready: ready)
