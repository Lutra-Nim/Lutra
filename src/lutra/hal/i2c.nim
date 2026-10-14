## An I2C bus, seen from its controller. Any number of devices share its two
## wires, each answering to its own address.

type I2cBus* = concept
  # Each is false if the device did not acknowledge, as when it is not there
  proc write(bus: Self, address: byte, data: openArray[byte]): bool
  proc read(bus: Self, address: byte, data: var openArray[byte]): bool
  proc writeRead(bus: Self, address: byte, output: openArray[byte], input: var openArray[byte]): bool
    ## Writes, then reads without letting go of the bus between, which is how
    ## a device's register is read
