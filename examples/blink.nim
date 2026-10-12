## An LED on IO4, and the board's own button.

import lutra

const led = IO4

led.output()
bootButton.input()
bootButton.pullUp()

while true:
  led.toggle()
  print "up ", millis(), " ms, button ", (if bootButton.read(): cstring("up") else: cstring("down")), "\n"
  delay 500.ms
