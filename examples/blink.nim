## Blinks an LED wired from IO4, through a resistor, to ground, and reports the
## board's own button. The LED on the board itself is an addressable one:
## `rgb.nim` lights that.

import lutra

const led = IO4

led.output()
bootButton.input()
bootButton.pullUp()

while true:
  led.toggle()
  print "up ", millis(), " ms, button ", (if bootButton.read(): cstring("up") else: cstring("down")), "\n"
  delay 500.ms
