## Blinks LD2, one of the board's two green LEDs, and reports its blue button.

import lutra

led2.output()
userButton.input() # The board holds it high until it is pressed

while true:
  led2.toggle()
  print "up ", millis(), " ms, button ", (if userButton.read(): cstring("up") else: cstring("down")), "\n"
  delay 500.ms
