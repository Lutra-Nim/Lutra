## Records the time and the blue button, every 10 ms, for `nim capture`:
##
##   nim flash record.nim
##   nim capture > button.csv
##
## Each line of `button.csv` is a turn, the milliseconds since reset, and 1
## while the button is held. A turn's number jumps if one was missed.

import lutra

userButton.input() # The board holds it high until it is pressed

print "Recording\n" # Shown on the terminal, not written to the file
for turn in every(10.ms):
  console.record(turn, ms = millis(), pressed = not userButton.read())
