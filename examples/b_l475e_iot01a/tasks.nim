## Two things at once. A task blinks LD2 while the program reports the time,
## and each hands over to the other whenever it waits, here in `delay`.

import lutra

task blink:
  led2.output()
  while true:
    led2.toggle()
    delay 250.ms

while true:
  print "up ", millis(), " ms\n"
  delay 1.sec
