import registers, peripherals, gpio, clock

# The LED takes its colour as 24 pulses on one wire, a long one for a 1 and a
# short one for a 0. The chip's LED controller makes them from a word for each
# LED, so their timing owes nothing to what the core is doing. Its times are
# counted in its clock's ticks: here the 24 MHz crystal, 41.7 ns.
const
  enable = 1'u32 shl 0 # Of `ledcControl`, cleared once the colours are sent
  grb = 2'u32 shl 6 # The order the LED takes them in
  # 0.33 us high then 0.83 low for a 0, 0.88 then 0.29 for a 1: Linux's, which suit both kinds
  bitTimes = (21'u32 shl 21) or (7'u32 shl 16) or (8'u32 shl 6) or 20'u32
  resetTime = 7200'u32 shl 16 # 300 us of quiet, after which the LED takes the colour
  done = 1'u32 shl 0 # Of `ledcStatus`

proc color*(led: static RgbLed, red: byte = 0, green: byte = 0, blue: byte = 0) =
  ## Each from 0 to 255, which is bright enough to hurt: 20 is plenty indoors
  led.pin.asFunction("the LED controller")
  ledcGates[] = ledcGates[] or 1 or (1'u32 shl 16) # Its bus clock on, and out of reset
  ledcClock[] = 1'u32 shl 31 # From the crystal, undivided
  ledcBitTimes[] = bitTimes
  ledcResetTime[] = resetTime # And one LED
  ledcStatus[] = ledcStatus[] # Writing a 1 clears each
  ledcControl[] = (1'u32 shl 16) or grb or enable # One LED's word
  ledcData[] = (red.uint32 shl 16) or (green.uint32 shl 8) or blue
  while (ledcStatus[] and done) == 0: discard
  let sent = micros()
  while micros() - sent < 300: discard # Until the LED has taken it

proc off*(led: static RgbLed) = led.color()
