## One device on an SPI bus, with its own chip-select.

type SpiDevice* = concept
  proc transfer(device: Self, output: openArray[byte], input: var openArray[byte])
    ## Sends `output` while receiving into `input`, which may be shorter
