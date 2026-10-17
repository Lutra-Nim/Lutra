## Steps the board's own LED through red, green and blue from an interrupt,
## each time the board's button is pressed.
##
## Nothing here is debounced, so one press can count more than once as the
## contacts bounce. `debounced.nim` takes the bounce out. On this board, opening the serial port counts as a press
## too: the USB bridge's reset circuit shares the button's pin.

import lutra

var presses {.volatile.}: uint32 # Changed by the handler, so read it afresh each time

proc pressed() {.interrupt: bootButton.falling.} =
  inc presses
  case presses mod 3
  of 1: rgbLed.color(red = 20)
  of 2: rgbLed.color(green = 20)
  else: rgbLed.color(blue = 20)

bootButton.input()
bootButton.pullUp()
start pressed

while true:
  print presses, " presses\n"
  delay 1.sec
