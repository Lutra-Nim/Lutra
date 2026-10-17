## What an STM32L475 has, by name.

import std/[macros, strutils]

type
  Gpio* = object
    port*: char
    num*: int
  Uart* = object
    num*: int
    base*: uint32
    bus*: int ## Of the two peripheral buses, the one with its clock
    clockBit*: int
    interrupt*: int
  I2c* = object
    num*: int
    base*: uint32
    clockBit*: int ## In the clock enable register of the first peripheral bus
  Spi* = object
    num*: int
    base*: uint32
    clockBit*: int ## In the clock enable register of the second peripheral bus
  SpiDeviceOn* = object
    ## A device on an SPI bus, chosen by its own pin
    bus*: Spi
    select*: Gpio

func name*(pin: Gpio): string = "P" & pin.port & $pin.num

func name*(uart: Uart): string =
  ## As ST names it: the ports that can also run in step with a clock are USARTs
  (if uart.num <= 3: "USART" else: "UART") & $uart.num

func device*(bus: Spi, select: Gpio): SpiDeviceOn = SpiDeviceOn(bus: bus, select: select)

macro pins(ports: static string) =
  ## PA0 to PA15, and the same for each port
  result = newNimNode(nnkConstSection)
  for port in ports:
    for num in 0..15:
      let (pin, portLit, numLit) = (postfix(ident("P" & port & $num), "*"), newLit(port), newLit(num))
      result.add newTree(nnkConstDef, pin, newEmptyNode(), quote do: Gpio(port: `portLit`, num: `numLit`))

pins "ABCDE"

const
  usart1* = Uart(num: 1, base: 0x4001_3800'u32, bus: 2, clockBit: 14, interrupt: 37)
  uart4* = Uart(num: 4, base: 0x4000_4C00'u32, bus: 1, clockBit: 19, interrupt: 52)
  i2c2* = I2c(num: 2, base: 0x4000_5800'u32, clockBit: 22)
  spi1* = Spi(num: 1, base: 0x4001_3000'u32, clockBit: 12)

# Unlike an ESP32-C3's, a peripheral's signal can come out on a few pins only.
# Each is listed with the function number that selects it there.
const functions = [
  ("USART1 TX", PA9, 7), ("USART1 TX", PB6, 7),
  ("USART1 RX", PA10, 7), ("USART1 RX", PB7, 7),
  ("UART4 TX", PA0, 8), ("UART4 RX", PA1, 8),
  ("SPI1 clock", PA5, 5), ("SPI1 clock", PB3, 5),
  ("SPI1 data into the controller", PA6, 5), ("SPI1 data into the controller", PB4, 5),
  ("SPI1 data out of the controller", PA7, 5), ("SPI1 data out of the controller", PB5, 5),
  ("I2C2 SCL", PB10, 4), ("I2C2 SCL", PB13, 4),
  ("I2C2 SDA", PB11, 4), ("I2C2 SDA", PB14, 4)]

macro function*(pin: static Gpio, role: static string): int =
  ## The number that gives the pin to a role, or an error naming the pins
  ## that can take it
  var others: seq[string]
  for (candidate, where, number) in functions:
    if candidate == role:
      if where == pin: return newLit(number)
      others.add where.name
  error pin.name & " cannot be " & role & ". It can be " & others.join(" or ") & "."
