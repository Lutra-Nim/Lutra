## What a D1 has, by name.

import std/[macros, strutils]

type
  Gpio* = object
    port*: char
    num*: int
  Uart* = object
    num*: int
    base*: uint32
  RgbLed* = object
    ## Addressable LEDs, of the WS2812 or SK6812 kind, on the pin the LED
    ## controller drives
    pin*: Gpio
  Codec* = object
    ## The audio codec's DAC, mono, out of its headphone output

func name*(pin: Gpio): string = "P" & pin.port & $pin.num

macro pins(port: static char, count: static int) =
  ## PB0 to PB12, and the same for each port, as far as it goes
  result = newNimNode(nnkConstSection)
  for num in 0 ..< count:
    let (pin, portLit, numLit) = (postfix(ident("P" & port & $num), "*"), newLit(port), newLit(num))
    result.add newTree(nnkConstDef, pin, newEmptyNode(), quote do: Gpio(port: `portLit`, num: `numLit`))

pins 'B', 13
pins 'C', 8
pins 'D', 23
pins 'E', 18
pins 'F', 7
pins 'G', 19

const
  uart0* = Uart(num: 0, base: 0x0250_0000'u32)
  codec* = Codec()

# A peripheral's signal can come out on a few pins only. Each is listed with
# the number that selects it there, from Linux's `pinctrl-sun20i-d1.c`.
const functions = [
  ("UART0 TX", PB8, 6), ("UART0 RX", PB9, 6),
  ("the LED controller", PC0, 4)]

macro function*(pin: static Gpio, role: static string): int =
  ## The number that gives the pin to a role, or an error naming the pins
  ## that can take it
  var others: seq[string]
  for (candidate, where, number) in functions:
    if candidate == role:
      if where == pin: return newLit(number)
      others.add where.name
  error pin.name & " cannot be " & role & ". It can be " & others.join(" or ") & "."
