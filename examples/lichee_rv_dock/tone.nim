## A tone of 2 kHz for a second, from a speaker on the Dock's J7. Each 10 ms
## of it is worked out while the last plays.

import lutra, lutra/fixed

const step = uint32((2000'u64 shl 32) div 44_100) # Of a turn, in 2^32nds, each sample

speaker.buffer(4096)
speaker.start(volume = -12)
var
  samples: array[441, int16]
  phase = 0'u32
for _ in 1..100:
  for s in samples.mitems:
    s = int16(sin(Angle(phase shr 16)) div 8) # A quarter of full scale
    phase += step
  speaker.write(samples)
speaker.drain()
print "played\n"
