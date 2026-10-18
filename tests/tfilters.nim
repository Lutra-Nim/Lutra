## Each filter against the same sums in floating point.

import std/[math, random]
import lutra/filters

block: # The mean of the last few, rounded
  var f: MovingAverage[4]
  doAssert f.value == 0
  for x in [10'i32, 20, 30, 40, 50]: f.add x
  doAssert f.value == 35 # 20, 30, 40 and 50
  var g: MovingAverage[2]
  g.add -1
  g.add -2
  doAssert g.value == -1 # -1.5 rounds up, as 1.5 does

block: # One pole, against the same recurrence in floating point
  var f = lowPass(hz = 2, sampleHz = 100)
  let alpha = 1 - exp(-2 * PI * 2 / 100)
  var y = 1000.0
  for i in 0..<500:
    let x = int32(if i < 250: 1000 else: -3000)
    f.add x
    if i > 0: y += alpha * (x.float - y)
    doAssert abs(f.value.float - y) <= 1, $i
  doAssert f.value == -3000 # Settled

proc gain(f: var Biquad, hz, sampleHz: float): float =
  ## How much of a sine at `hz` gets through, once settled, by its power over
  ## the last 1000 samples: whole cycles of each frequency tried
  var power = 0.0
  for i in 0..<4000:
    f.add int32(round(10000 * sin(2 * PI * hz * i.float / sampleHz)))
    if i >= 3000: power += f.value.float ^ 2
  sqrt(power / 1000 * 2) / 10000

block: # Second order, by what passes
  var f = lowPass2(hz = 10, sampleHz = 1000)
  doAssert abs(f.gain(1, 1000) - 1) < 0.01
  f = lowPass2(hz = 10, sampleHz = 1000)
  doAssert abs(f.gain(10, 1000) - sqrt(0.5)) < 0.01 # Half the power at the corner
  f = lowPass2(hz = 10, sampleHz = 1000)
  doAssert f.gain(100, 1000) < 0.011
  var h = highPass(hz = 10, sampleHz = 1000)
  doAssert h.gain(1, 1000) < 0.011 and h.gain(100, 1000) > 0.99
  var n = notch(hz = 50, sampleHz = 1000, q = 2)
  doAssert n.gain(50, 1000) < 0.01 and n.gain(5, 1000) > 0.99
  var b = bandPass(hz = 50, sampleHz = 1000, q = 2)
  doAssert abs(b.gain(50, 1000) - 1) < 0.01 and b.gain(5, 1000) < 0.06
  var settled = highPass(hz = 1, sampleHz = 100) # A steady offset goes
  for i in 0..<2000: settled.add 5000
  doAssert settled.value == 0

block: # A spike is passed over
  var f: MedianOf[5]
  doAssert f.value == 0
  f.add 7
  doAssert f.value == 7
  for x in [10'i32, 11, 9000, 12]: f.add x
  doAssert f.value == 11
  var r = initRand(1)
  for _ in 0..<1000:
    let x = int32(r.rand(2000) - 1000)
    f.add x
  doAssert f.value in -1000'i32..1000'i32

doAssert not compiles(lowPass(hz = 0.0001, sampleHz = 100000)) # Too slow to hold
