## Filters for a stream of readings, in whole numbers. Each takes values with
## `add` and gives its output as `value`, in the units it was given:
##
##   var
##     smooth: MovingAverage[8]                # The mean of the last 8
##     slow = lowPass(hz = 2, sampleHz = 100)  # One pole
##     hum = notch(hz = 50, sampleHz = 1000)   # Second order: also lowPass2, highPass, bandPass
##     spikes: MedianOf[5]                     # The median of the last 5
##
##   spikes.add x
##   slow.add spikes.value
##
## A filter's settings are worked out when the program is compiled. Not
## exported by `lutra`, as `average` and `median` are names programs use.

import std/math

# Hot loops, on the board without Nim's checks. The host tests run them with
# the checks on, and the board gives the same bits as the host.
when defined(lutraBoard): {.push checks: off.}

type
  MovingAverage*[N: static int] = object
    window: array[N, int32]
    at, count: int
    sum: int64

  LowPass* = object
    ## One pole: each value moves the output part of the way to it
    alpha: int32 # Q16
    state: int64 # Q16
    started: bool

  Biquad* = object
    ## Two poles and two zeros: what the coefficients make it
    b0, b1, b2, a1, a2: int32 # Q28
    x1, x2: int32
    y1, y2: int64 # Q8, so that a slow filter's small steps are not lost

  MedianOf*[N: static int] = object
    window: array[N, int32]
    at, count: int

func rounded(x: int64, bits: int): int64 {.inline.} = (x + (1'i64 shl (bits - 1))) shr bits

proc add*[N](f: var MovingAverage[N], x: int32) =
  if f.count == N: f.sum -= f.window[f.at]
  else: inc f.count
  f.window[f.at] = x
  f.sum += x
  f.at = (f.at + 1) mod N

func value*[N](f: MovingAverage[N]): int32 =
  ## The mean of what it holds, rounded; 0 before anything is added
  if f.count == 0: 0'i32
  else: int32(floorDiv(2 * f.sum + f.count, 2 * f.count.int64))

func lowPass*(hz, sampleHz: static float): LowPass =
  ## Halves a sine at about `hz` in power, for values added `sampleHz` times
  ## a second. The output starts at the first value, not at 0.
  const alpha = int32(round(65536 * (1 - exp(-2 * PI * hz / sampleHz))))
  when alpha < 1: {.error: "lowPass: " & $hz & " Hz is too slow for whole numbers at " & $sampleHz & " Hz.".}
  LowPass(alpha: alpha)

proc add*(f: var LowPass, x: int32) =
  let target = int64(x) shl 16
  if not f.started:
    f.state = target
    f.started = true
  else:
    f.state += rounded((target - f.state) * f.alpha, 16)

func value*(f: LowPass): int32 = int32(rounded(f.state, 16))

type Shape = enum lowShape, highShape, bandShape, notchShape

func biquad(shape: Shape, hz, sampleHz, q: float): array[5, int32] {.compileTime.} =
  ## b0, b1, b2, a1 and a2 as Q28, from Robert Bristow-Johnson's cookbook
  if hz <= 0 or hz >= sampleHz / 2:
    raise newException(ValueError, $hz & " Hz is not between 0 and half of " & $sampleHz & " Hz.")
  let
    w = 2 * PI * hz / sampleHz
    alpha = sin(w) / (2 * q)
    a0 = 1 + alpha
    b = case shape
      of lowShape: [(1 - cos(w)) / 2, 1 - cos(w), (1 - cos(w)) / 2]
      of highShape: [(1 + cos(w)) / 2, -(1 + cos(w)), (1 + cos(w)) / 2]
      of bandShape: [alpha, 0.0, -alpha]
      of notchShape: [1.0, -2 * cos(w), 1.0]
  for i, c in [b[0] / a0, b[1] / a0, b[2] / a0, -2 * cos(w) / a0, (1 - alpha) / a0]:
    result[i] = int32(round(c * float(1 shl 28)))

func toBiquad(c: array[5, int32]): Biquad =
  Biquad(b0: c[0], b1: c[1], b2: c[2], a1: c[3], a2: c[4])

func lowPass2*(hz, sampleHz: static float, q: static float = 0.7071): Biquad =
  ## Passes what is slower than `hz`, falling twice as steeply as `lowPass`
  const c = biquad(lowShape, hz, sampleHz, q)
  toBiquad(c)

func highPass*(hz, sampleHz: static float, q: static float = 0.7071): Biquad =
  ## Passes what is faster than `hz`, which takes away a steady offset
  const c = biquad(highShape, hz, sampleHz, q)
  toBiquad(c)

func bandPass*(hz, sampleHz: static float, q: static float = 0.7071): Biquad =
  ## Passes what is near `hz`; a larger `q` is a narrower band
  const c = biquad(bandShape, hz, sampleHz, q)
  toBiquad(c)

func notch*(hz, sampleHz: static float, q: static float = 0.7071): Biquad =
  ## Takes out what is near `hz`, such as the hum of the mains
  const c = biquad(notchShape, hz, sampleHz, q)
  toBiquad(c)

proc add*(f: var Biquad, x: int32) =
  ## For values within about 8 million either way: more, and its sums overflow
  let y = rounded(int64(f.b0) * x + int64(f.b1) * f.x1 + int64(f.b2) * f.x2, 20) -
    rounded(f.a1 * f.y1 + f.a2 * f.y2, 28)
  f.x2 = f.x1
  f.x1 = x
  f.y2 = f.y1
  f.y1 = y

func value*(f: Biquad): int32 = int32(rounded(f.y1, 8))

proc add*[N](f: var MedianOf[N], x: int32) =
  f.window[f.at] = x
  f.at = (f.at + 1) mod N
  if f.count < N: inc f.count

func value*[N](f: MedianOf[N]): int32 =
  ## The middle of what it holds, or the lower of the two middles; 0 before
  ## anything is added
  if f.count == 0: return 0
  var sorted = f.window
  for i in 1 ..< f.count: # Insertion sort: it is a handful
    let x = sorted[i]
    var j = i
    while j > 0 and sorted[j - 1] > x:
      sorted[j] = sorted[j - 1]
      dec j
    sorted[j] = x
  sorted[(f.count - 1) div 2]

when defined(lutraBoard): {.pop.}
