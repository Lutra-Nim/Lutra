## Toggles an LED on IO4 from an interrupt, each time the board's button is
## pressed.

import lutra

const led = IO4
var presses {.volatile.}: uint32 # Changed by the handler, so read it afresh each time

led.output()
bootButton.input()
bootButton.pullUp()

bootButton.onFalling:
  led.toggle()
  inc presses

while true:
  print presses, " presses\n"
  delay 1.sec
