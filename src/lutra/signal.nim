## The features a speech model listens to, computed in whole numbers so that a
## board gives the same bits as the host:
##
##   const mfcc = Mfcc(sampleRate: 16000, window: 480, melBins: 40,
##                     lowHz: 20, highHz: 4000, coefficients: 10)
##   var features: array[10, int32]
##   mfcc.compute(samples, features)
##
## One frame of sound goes through a Hann window and a Fourier transform. The
## strength of each frequency is gathered into bands evenly spaced on the mel
## scale, the natural logarithm of each band is taken, and a cosine transform
## of those gives the coefficients. This is what `tf.signal` computes, with
## its defaults.

import std/[math, bitops]
import fixed

type Mfcc* = object
  sampleRate*: int ## In Hz
  window*: int ## Samples in a frame
  melBins*: int
  lowHz*, highHz*: float ## The frequencies the mel bands span
  coefficients*: int
  floor*: float = 1e-6 ## Added to each band before its logarithm, where full scale is 1

# The tables are worked out as the program is compiled, and live in flash

func hann(n: static int): array[n, uint32] {.compileTime.} =
  ## As Q31. Any coarser and its rounding shows, under a loud sound, as noise
  ## in the quiet bands.
  for i in 0..<n: result[i] = uint32(round(pow(2.0, 31) * (0.5 - 0.5 * cos(2 * PI * i.float / n.float))))

func rotations(n: static int): array[n div 2, tuple[cos, sin: int32]] {.compileTime.} =
  ## The steps around a circle that a transform of `n` points turns by, as Q30
  for k in 0..<n div 2:
    let angle = 2 * PI * k.float / n.float
    result[k] = (int32(round(cos(angle) * float(1 shl 30))), int32(round(sin(angle) * float(1 shl 30))))

func mel(hz: float): float = 1127 * ln(1 + hz / 700)

func melWeight(m: Mfcc, band, bin, size: int): float =
  ## How much of a frequency bin a band takes: a triangle on the mel scale
  ## between the centres of the bands either side of it
  if bin == 0: return 0
  let
    spacing = (mel(m.highHz) - mel(m.lowHz)) / float(m.melBins + 1)
    centre = mel(m.lowHz) + spacing * float(band + 1)
    at = mel(bin.float * m.sampleRate.float / size.float)
  max(0, 1 - abs(at - centre) / spacing)

func melBands(m: Mfcc, bands, size, bins: static int): array[bands, array[bins, uint16]] {.compileTime.} =
  for band in 0..<bands:
    for bin in 0..<bins:
      result[band][bin] = uint16(round(32768 * melWeight(m, band, bin, size)))

func cosines(coefficients, bands: static int): array[coefficients, array[bands, int32]] {.compileTime.} =
  ## As Q30
  for k in 0..<coefficients:
    for band in 0..<bands:
      result[k][band] = int32(round(float(1 shl 30) * sqrt(2 / bands.float) *
        cos(PI * k.float * (2 * band + 1).float / (2 * bands).float)))

func turn(x, by: int32): int32 {.inline.} = int32((int64(x) * by + (1 shl 29)) shr 30)

proc transform[N: static int](re, im: var array[N, int32]) =
  ## A Fourier transform, in place. Each result can be as large as its inputs
  ## summed, which the caller leaves room for.
  const rotation = rotations(N)
  var j = 0
  for i in 1..<N:
    var bit = N shr 1
    while (j and bit) != 0:
      j = j xor bit
      bit = bit shr 1
    j = j xor bit
    if i < j:
      swap(re[i], re[j])
      swap(im[i], im[j])
  var half = 1
  while half < N:
    for first in countup(0, N - 1, 2 * half):
      for k in 0..<half:
        let
          (a, b) = (first + k, first + k + half)
          (c, s) = rotation[k * (N div (2 * half))]
          (r, i) = (turn(re[b], c) + turn(im[b], s), turn(im[b], c) - turn(re[b], s))
        re[b] = re[a] - r
        im[b] = im[a] - i
        re[a] += r
        im[a] += i
    half *= 2

proc compute*(m: static Mfcc, samples: openArray[int16], output: var openArray[int32],
    fullScale = 32768'i32) =
  ## The coefficients of one frame, `m.window` samples long, as Q16.
  ## `fullScale` is the sample value that counts as 1.
  const
    size = nextPowerOfTwo(m.window)
    # A windowed frame sums to at most half its length times the largest
    # sample, so this many fractional bits still fit after the transform
    fraction = 16 - fastLog2(size)
    bins = block:
      # No band reaches above its top frequency
      var last = size div 2
      while last > 0 and melWeight(m, m.melBins - 1, last, size) == 0: dec last
      last + 1
    window = hann(m.window)
    bands = melBands(m, m.melBins, size, bins)
    cosine = cosines(m.coefficients, m.melBins)
    floor = uint64(round(m.floor * pow(2.0, float(fraction + 31)))) # 16 bits finer than a band's sum

  var re, im: array[size, int32]
  for i in 0..<m.window:
    re[i] = int32((int64(samples[i]) * int64(window[i]) + (1'i64 shl (30 - fraction))) shr (31 - fraction))
  transform(re, im)
  var strength: array[bins, uint32]
  for bin in 0..<bins:
    # Rounded to the nearest, by way of twice the root: always rounding down
    # would pull the quiet bands lower
    let power = uint64(int64(re[bin]) * re[bin] + int64(im[bin]) * im[bin])
    strength[bin] = (isqrt(power shl 2) + 1) shr 1

  # A band's sum has 15 more fractional bits, from its weights
  let one = uint64(fullScale) shl (fraction + 15)
  var logs: array[m.melBins, int32]
  for band in 0..<m.melBins:
    var sum = (floor * uint64(fullScale)) shr 16
    for bin in 0..<bins: sum += uint64(bands[band][bin]) * strength[bin]
    logs[band] = ln(max(sum, 1)) - ln(one)
  for k in 0..<m.coefficients:
    var sum = 0'i64
    for band in 0..<m.melBins: sum += int64(cosine[k][band]) * logs[band]
    output[k] = int32((sum + (1 shl 29)) shr 30)
