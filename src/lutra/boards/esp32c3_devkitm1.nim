## ESP32-C3-DevKitM-1: an ESP32-C3-MINI-1 module with 4 MB of flash, a CP2102N
## USB bridge on UART0, an addressable LED on IO8 and the boot button on IO9.

import ../chips/esp32c3
export esp32c3

const
  memory* = Memory(flashSize: 4.MB)
  console* = uart0

  IO0* = Gpio(num: 0)
  IO1* = Gpio(num: 1)
  IO2* = Gpio(num: 2)
  IO3* = Gpio(num: 3)
  IO4* = Gpio(num: 4)
  IO5* = Gpio(num: 5)
  IO6* = Gpio(num: 6)
  IO7* = Gpio(num: 7)
  IO8* = Gpio(num: 8)
  IO9* = Gpio(num: 9)
  IO10* = Gpio(num: 10)
  IO18* = Gpio(num: 18)
  IO19* = Gpio(num: 19)
  IO20* = Gpio(num: 20)
  IO21* = Gpio(num: 21)

  rgbLed* = RgbLed(pin: IO8)
  bootButton* = IO9
