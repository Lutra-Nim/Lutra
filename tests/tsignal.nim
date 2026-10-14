## The whole-number front-end against the same sums in floating point, written
## the way `tf.signal` writes them.

import std/[math, complex]
import lutra/signal

const
  mfcc = Mfcc(sampleRate: 16000, window: 480, melBins: 40, lowHz: 20, highHz: 4000, coefficients: 10)
  size = 512

func hertzToMel(hz: float): float = 1127 * ln(1 + hz / 700)

proc reference(samples: openArray[int16], fullScale: float): array[10, float] =
  var spectrum: array[size div 2 + 1, float]
  for k in 0..size div 2:
    var sum = complex(0.0, 0.0)
    for n in 0..<480:
      let windowed = samples[n].float / fullScale * (0.5 - 0.5 * cos(2 * PI * n.float / 480))
      sum += windowed * exp(complex(0.0, -2 * PI * k.float * n.float / size.float))
    spectrum[k] = abs(sum)

  var logMel: array[40, float]
  for band in 0..<40:
    # The edges of the bands are spaced evenly in mel, each band running from
    # the centre of the one before to the centre of the one after
    template edge(i: int): float =
      hertzToMel(20) + (hertzToMel(4000) - hertzToMel(20)) * i.float / 41
    var sum = 0.0
    for k in 1..size div 2:
      let
        at = hertzToMel(k.float * 8000 / float(size div 2))
        lower = (at - edge(band)) / (edge(band + 1) - edge(band))
        upper = (edge(band + 2) - at) / (edge(band + 2) - edge(band + 1))
      sum += max(0, min(lower, upper)) * spectrum[k]
    logMel[band] = ln(sum + 1e-6)

  for k in 0..<10:
    for band in 0..<40:
      result[k] += 2 * logMel[band] * cos(PI * k.float * (band.float + 0.5) / 40) / sqrt(80.0)

var
  frame: array[480, int16]
  state = 7'u32

proc noise(): float =
  state = state * 1664525 + 1013904223
  float(state shr 16) / 32768 - 1

# A band is good to about a hundred-thousandth of the loudest thing in the
# frame. Sound from a microphone has noise well above that in every band; a
# pure tone has bands with nothing in them, where the limit shows.
for (tone, toneLevel, noiseLevel, fullScale, within) in [
    (440.0, 0.0, 0.0, 32768'i32, 0.0005),  # Silence
    (1234.5, 0.3, 0.01, 32768, 0.0005),
    (3000.0, 0.02, 0.3, 32768, 0.0005),
    (95.0, 0.001, 0.0005, 32768, 0.0005),  # A few counts
    (700.0, 0.25, 0.05, 9000, 0.0005),     # Against a quieter full scale
    (440.0, 1.0, 0.0, 32768, 0.01),        # As loud as a tone gets
    (5000.0, 0.5, 0.0, 32768, 0.5)]:       # A tone above every band
  for n in 0..<480:
    frame[n] = int16(clamp(32767 * (toneLevel * sin(2 * PI * tone * n.float / 16000) + noiseLevel * noise()),
      -32768, 32767))
  var got: array[10, int32]
  mfcc.compute(frame, got, fullScale)
  let want = reference(frame, fullScale.float)
  for k in 0..<10:
    doAssert abs(got[k].float / 65536 - want[k]) < within, $tone & " Hz, coefficient " & $k & ": " &
      $(got[k].float / 65536) & " rather than " & $want[k]
