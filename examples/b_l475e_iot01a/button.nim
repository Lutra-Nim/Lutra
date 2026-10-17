## Toggles LD2 from an interrupt, each time the board's blue button is pressed.
##
## Nothing here is debounced, so one press can count more than once if the
## contacts bounce. `debounced.nim` takes the bounce out.

import lutra

var presses {.volatile.}: uint32 # Changed by the handler, so read it afresh each time

proc pressed() {.interrupt: userButton.falling.} =
  led2.toggle()
  inc presses

led2.output()
userButton.input()
start pressed

while true:
  print presses, " presses\n"
  delay 1.sec
