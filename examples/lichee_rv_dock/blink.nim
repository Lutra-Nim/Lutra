## Blinks the module's green LED. The LED on the Dock itself is an addressable
## one: `rgb.nim` lights that.

import lutra

led.output()

while true:
  led.toggle()
  print "up ", millis(), " ms\n"
  delay 500.ms
