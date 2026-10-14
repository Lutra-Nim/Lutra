## Two things at once. A task steps the board's LED through red, green and
## blue while the program reports the time, and each hands over to the other
## whenever it waits, here in `delay`.

import lutra

task colours:
  while true:
    rgbLed.color(red = 20)
    delay 500.ms
    rgbLed.color(green = 20)
    delay 500.ms
    rgbLed.color(blue = 20)
    delay 500.ms

while true:
  print "up ", millis(), " ms\n"
  delay 1.sec
