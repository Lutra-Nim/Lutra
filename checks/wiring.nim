## Checks the wires between two boards before the link checks rely on them.
## Run it with `nim wiring`. One board, built with `-d:drive`, pulses each pin
## for a different length of time, and the other reports which of its own pins
## heard which.
##
##   IO0 - IO1    UART1, each board's transmit to the other's receive
##   IO1 - IO0
##   IO3 - IO3    SPI ready
##   IO5 - IO5    SPI data into the controller
##   IO6 - IO6    SPI clock
##   IO7 - IO7    SPI data out of the controller
##   IO10 - IO10  SPI chip-select
##   GND - GND

import lutra

# Each pin, how long the driver holds it high, and the pulse its wire should
# bring to the other board
template eachPin(action: untyped) =
  action(IO0, "IO0", 10, 20)
  action(IO1, "IO1", 20, 10)
  action(IO3, "IO3", 30, 30)
  action(IO5, "IO5", 40, 40)
  action(IO6, "IO6", 50, 50)
  action(IO7, "IO7", 60, 60)
  action(IO10, "IO10", 70, 70)

when defined(drive):
  template prepare(pin, name, pulse, expected) =
    pin.output()
    pin.low()
  template send(pin, name, pulse, expected) =
    pin.high()
    delay pulse.ms
    pin.low()
    delay 20.ms
  eachPin(prepare)
  while true:
    eachPin(send)
    delay 300.ms

else:
  template prepare(pin, name, pulse, expected) =
    pin.input()
    pin.pullDown()
  eachPin(prepare)

  proc name(pulse: int): cstring =
    template match(pin, pinName, pinPulse, expected) =
      if pulse == pinPulse: return pinName
    eachPin(match)
    "an unknown pin"

  print "BEGIN wiring\n"
  var wrong = 0
  template hear(pin, pinName, pinPulse, expected) =
    # The longest this pin stays high over two rounds of the driver's pulses
    var longest, current = 0
    for _ in 0..<1500:
      if pin.read(): inc current else: current = 0
      longest = max(longest, current)
      delay 1.ms
    let heard = (longest + 5) div 10 * 10
    if heard == expected:
      print pinName, " hears ", name(heard), ", ok\n"
    else:
      inc wrong
      print pinName, " should hear ", name(expected), " and hears "
      if longest < 5: print "nothing\n"
      elif longest > 100: print "a pin held high\n"
      else: print name(heard), "\n"
  eachPin(hear)
  print "END ", (if wrong == 0: cstring("wiring ok") else: cstring("wiring WRONG")), "\n"
  while true: discard
