import ../../claims
import registers, peripherals, gpio, clock

# The LED takes its colour as 24 pulses on one wire, a long one for a 1 and a
# short one for a 0. The chip's pulse generator (its "remote control"
# peripheral) plays them from a list, so their timing owes nothing to what
# the core is doing.
const
  signal = 51 # The generator's first channel, in the GPIO matrix
  # A pulse is a time high then a time low, in ticks of 12.5 ns. These suit
  # both kinds of LED.
  zeroBit = (1'u32 shl 15) or 28 or (72 shl 16) # 0.35 us, then 0.9 us
  oneBit = (1'u32 shl 15) or 56 or (44 shl 16) # 0.7 us, then 0.55 us
  start = 1'u32 shl 0 # Of `pulseChannel`
  rewind = 3'u32 shl 1
  update = 1'u32 shl 24
  done = 1'u32 shl 0 # Of `pulseEvents`

proc color*(led: static RgbLed, red: byte = 0, green: byte = 0, blue: byte = 0) =
  ## Each from 0 to 255, which is bright enough to hurt: 20 is plenty indoors
  claim("IO" & $led.pin.num, "an addressable LED")
  claim("The pulse generator", "IO" & $led.pin.num & "'s LED") # There is one LED's worth of it so far
  peripheralClocks[] = peripheralClocks[] or (1 shl 9)
  # On, from the 80 MHz clock undivided, with its memory written directly
  pulseConfig[] = (1'u32 shl 31) or (1 shl 26) or (1 shl 24) or 1
  pulseChannel[] = (1 shl 16) or (1 shl 8) or (1 shl 6) # One block of memory, no divider, low when idle
  led.pin.routeOut(signal)

  let bits = (green.uint32 shl 16) or (red.uint32 shl 8) or blue # The order they go in
  for i in 0..<24:
    Reg(pulseMemory + 4 * i.uint32)[] = if (bits shr (23 - i) and 1) != 0: oneBit else: zeroBit
  Reg(pulseMemory + 4 * 24)[] = 0 # Ends the list
  pulseChannel[] = pulseChannel[] or rewind
  pulseChannel[] = pulseChannel[] and not rewind
  pulseEventsClear[] = done
  pulseChannel[] = pulseChannel[] or update
  pulseChannel[] = pulseChannel[] or start
  while (pulseEvents[] and done) == 0: discard
  # The LED takes the colour once the wire has been quiet for a while
  let sent = micros()
  while micros() - sent < 300: discard

proc off*(led: static RgbLed) = led.color()
