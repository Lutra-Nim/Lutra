## A button on any `Pin`, with its contacts' bounce taken out:
##
##   const button = bootButton.debounced(held = 1.sec)
##
##   proc watch() {.task.} =
##     for change in button.changes:
##       case change
##       of pressed: led.on()
##       of released: led.off()
##       of held: print "held\n"
##
## A change counts once the pin has read the same for `settle`.

import time, tasks, hal/pin

type
  Change* = enum
    pressed
    released
    held ## Once each press, when it has lasted `held`

  Debounced*[P] = object
    pin*: P
    held*, settle*: Duration
    activeLow*: bool ## Pressed reads low, as with a pull-up and a switch to ground

func debounced*[P: Pin](pin: P, held = 1.sec, settle = 20.ms, activeLow = true): Debounced[P] =
  Debounced[P](pin: pin, held: held, settle: settle, activeLow: activeLow)

iterator changes*(button: static Debounced): Change =
  ## Each change as it settles. Between them it waits, letting the other tasks
  ## run, and it never ends. The pin is made an input, pulled away from its
  ## pressed level.
  mixin micros, input, pullUp, pullDown, read
  const period = 5_000'u64 # Microseconds between readings
  button.pin.input()
  when button.activeLow: button.pin.pullUp() else: button.pin.pullDown()
  template down(): bool = button.pin.read() != button.activeLow
  var
    isDown = down()
    since = micros() # When the button last settled
    differs = false # The pin has read otherwise since `differsSince`
    differsSince = 0'u64
    told = false # That it is held
    due = micros()
  while true:
    due += period
    wait micros() >= due
    if down() != isDown:
      if not differs: (differs, differsSince) = (true, micros())
      elif micros() - differsSince >= button.settle.uint64:
        isDown = not isDown
        (since, differs, told) = (micros(), false, false)
        yield (if isDown: pressed else: released)
    else:
      differs = false
      if isDown and not told and micros() - since >= button.held.uint64:
        told = true
        yield held
