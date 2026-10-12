## What an ESP32-C3 has, by name. Boards name the pins they bring out.

type
  Gpio* = object
    num*: int
  Uart* = object
    num*: int
    base*: uint32
    tx*: Gpio ## Where the boot ROM leaves it

const uart0* = Uart(num: 0, base: 0x6000_0000'u32, tx: Gpio(num: 21))
