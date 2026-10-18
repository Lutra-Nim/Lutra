import std/math
import lutra/fixed

doAssert isqrt(0) == 0 and isqrt(1) == 1 and isqrt(3) == 1 and isqrt(4) == 2
doAssert isqrt(uint64.high) == uint32.high
doAssert isqrt(1'u64 shl 62) == 1'u32 shl 31
var state = 1'u64
for _ in 0..<10_000:
  state = state * 6364136223846793005'u64 + 1442695040888963407'u64
  let
    x = state shr (state shr 58) # Of every size
    root = isqrt(x).uint64
  doAssert root * root <= x and (root == uint32.high or (root + 1) * (root + 1) > x)

  if x > 0:
    # Rounded down, to within one part in 65536
    doAssert log2(x).float / 65536 <= log2(x.float) + 1e-9
    doAssert log2(x).float / 65536 > log2(x.float) - 1 / 65536 - 1e-9
    doAssert abs(ln(x).float / 65536 - ln(x.float)) < 1.25 / 65536

doAssert log2(1) == 0 and log2(2) == 65536 and log2(1'u64 shl 63) == 63 * 65536
doAssert ln(1) == 0

block: # Angles and the trigonometry on them
  doAssert 90.degrees == Angle(16384) and 0.degrees == 360.degrees and -90.degrees == 270.degrees
  doAssert 359.degrees.degrees == 359 and Angle(65535).degrees == 0
  doAssert (350.degrees + 20.degrees).degrees == 10 # Wraps
  for i in 0..65535:
    let a = Angle(uint16(i))
    let angle = 2 * PI * i.float / 65536
    doAssert abs(sin(a).float - sin(angle) * 65536) <= 1, $i
    doAssert abs(cos(a).float - cos(angle) * 65536) <= 1, $i
  doAssert sin(90.degrees) == 65536 and cos(180.degrees) == -65536
  doAssert abs(sin(30.degrees) - 32768) <= 3 # 30° is not a whole number of 65536ths
  doAssert atan2(0, 0) == Angle(0)
  var state = 12345'u64
  for _ in 0..<100_000:
    state = state * 6364136223846793005'u64 + 1442695040888963407'u64
    let
      shift = int(state shr 59) # Points near the origin and far from it
      x = cast[int32](uint32(state shr 32)) shr shift
      y = cast[int32](uint32(state and 0xffffffff'u64)) shr shift
    if x == 0 and y == 0: continue
    let
      expected = arctan2(y.float, x.float) / (2 * PI) * 65536
      got = atan2(y, x).uint16.float
      error = abs(((got - expected) mod 65536 + 98304) mod 65536 - 32768)
    doAssert error <= 1, $x & ", " & $y & ": " & $got & " for " & $expected

block:
  doAssert mulQ16(q16(0.5), q16(0.5)) == q16(0.25)
  doAssert mulQ16(q16(-1.5), q16(2)) == q16(-3)
  doAssert mulQ16(int32.high, q16(2)) == int32.high and mulQ16(int32.low, q16(2)) == int32.low
  doAssert mulQ16(1, 32768) == 1 # A half rounds up
