## The audio codec's DAC: 16-bit samples, mono, at 44.1 kHz, out of the
## headphone output. Its FIFO holds 128 samples, under 3 ms, so a program
## that computes while it plays asks for a buffer, which the codec's
## interrupt plays from.

import std/[macros, macrocache]
import ../../[tasks, containers]
import registers, peripherals, interrupts

const
  # Of `dacFifoControl`. The rate's field, bits 31:29, stays 0: 48 kHz from
  # 24.576 MHz, and so 44.1 kHz from the 22.5792 MHz given it here.
  flush = 1'u32 shl 0
  roomInterrupt = 1'u32 shl 3 # Whenever it has room for `trigger` samples
  mono = 1'u32 shl 6 # One sample to both channels, and 128 places
  trigger = 64'u32 shl 8
  lowHalf = 1'u32 shl 24 # A sample is bits 15:0 of what is written
  # Of `dacFifoStatus`
  roomFlag = 1'u32 shl 3
  places = 128
  # Of `dacAnalog`
  leftDac = 1'u32 shl 15
  rightDac = 1'u32 shl 14
  leftUnmuted = 1'u32 shl 12
  rightUnmuted = 1'u32 shl 10
  # Of `headphone`: its driver and the driver's output, and the ramp's
  # output, as Allwinner's driver turns them on
  headphoneOn = (1'u32 shl 21) or (1'u32 shl 20) or (1'u32 shl 15)
  headphoneRegulator = 1'u32 shl 30 # Of `codecPower`
  manualRamp = 1'u32 shl 1 # Of `codecRamp`

template room(): int = int((dacFifoStatus[] shr 8) and 0x7fff)

proc start*(codec: static Codec, volume: static int = 0) =
  ## Starts the DAC. `volume` is in dB, from -119 to 0, in steps of 0.75.
  when volume > 0 or volume < -119:
    {.error: "volume is from -119 to 0 dB, not " & $volume.}
  codecGates[] = 1'u32 or (1'u32 shl 16)
  # 90.3168 MHz, four times 22.5792: 24 MHz times 22 and a fraction, which
  # the pattern gives, over 6, as Linux sets it
  pllAudio0Pattern[] = 0xc001288d'u32
  pllAudio0[] = (1'u32 shl 31) or (1'u32 shl 30) or (1'u32 shl 29) or # On, its regulator, lock detection
    (1'u32 shl 24) or (5'u32 shl 16) or (21'u32 shl 8) # The pattern on, M - 1 and N - 1
  while (pllAudio0[] and (1'u32 shl 28)) == 0: discard # Until it has locked
  pllAudio0[] = pllAudio0[] or (1'u32 shl 27) # Its output on
  dacClock[] = 1'u32 shl 31 # From it, undivided

  const level = uint32(0xA0 + volume * 4 div 3) # 0xA0 is 0 dB
  dacFifoControl[] = lowHalf or trigger or mono or flush
  dacVolume[] = (1'u32 shl 16) or (level shl 8) or level
  dacControl[] = 1'u32 shl 31 # The digital part on
  dacAnalog[] = dacAnalog[] or leftDac or rightDac or leftUnmuted or rightUnmuted
  codecPower[] = codecPower[] or headphoneRegulator
  codecRamp[] = codecRamp[] or manualRamp
  headphone[] = headphone[] or headphoneOn

# Written straight into the FIFO, unless the program asks for a buffer. Which
# is settled at compile time, here: the buffer's size, or 0 once the codec
# has been written to unbuffered.
const buffers = CacheTable"lutra.codecBuffers"

macro bufferSize(codec: static Codec): int =
  if "codec" notin buffers: buffers["codec"] = newLit(0)
  buffers["codec"]

macro setBufferSize(codec: static Codec, size: static int) =
  if "codec" in buffers:
    error "codec.buffer has to come before the codec is first written to, and only once"
  buffers["codec"] = newLit(size)

proc ring(size: static int): ptr Ring[size, int16] =
  var buffer {.global.}: Ring[size, int16]
  addr buffer

template buffer*(codec: static Codec, size: static int) =
  ## From here on, `write` puts samples in a buffer of `size`, from which the
  ## codec's interrupt plays them, so that the program may compute meanwhile.
  ## It comes before any code that writes, a proc's included.
  setBufferSize(codec, size)
  proc refill() {.gensym, exportc: "lutra_interrupt_" & $codecSource, cdecl.} =
    var free = room()
    while free > 0 and ring(size)[].len > 0:
      dacData[] = uint32(cast[uint16](ring(size)[].pop))
      dec free
    if ring(size)[].len == 0: # Quiet until `write` brings more
      dacFifoControl[] = dacFifoControl[] and not roomInterrupt
    dacFifoStatus[] = roomFlag
  discard cast[pointer](refill) # Inside a procedure, Nim leaves out one nothing refers to
  enable(codecSource)

proc write*(codec: static Codec, samples: openArray[int16]) =
  ## Plays `samples` after those written before. With a buffer, waits only
  ## while it is full, letting tasks run; without, until the last is in the
  ## FIFO. When nothing is left to play, the DAC plays silence.
  const size = bufferSize(codec)
  when size > 0:
    for s in samples:
      if ring(size)[].len == size:
        dacFifoControl[] = dacFifoControl[] or roomInterrupt
        wait ring(size)[].len < size
      discard ring(size)[].push(s)
    dacFifoControl[] = dacFifoControl[] or roomInterrupt
  else:
    for s in samples:
      wait room() > 0
      dacData[] = uint32(cast[uint16](s))

proc drain*(codec: static Codec) =
  ## Waits until every sample written has gone to the DAC
  const size = bufferSize(codec)
  when size > 0:
    wait ring(size)[].len == 0
  wait room() == places
