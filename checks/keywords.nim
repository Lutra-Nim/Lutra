## Keyword spotting on recorded speech. Twelve one-second clips, held in flash,
## each go through the front-end and Steady's `kws` model, and the word it
## hears is printed and shown on the LED: blue while it listens, then green if
## it heard the word spoken and red if not.
## Run it with `nim keywords`, which fetches the clips, builds the model, runs this
## file on the host as well and expects the board to print the same, down to a
## checksum of the features. `nim -d:testset keywords` instead scores every clip of
## the test set, on the host alone.
##
## The clips are from the Speech Commands test set, by Pete Warden and Google,
## under CC BY 4.0. Each is the first of its word that the model gets right.
## The model is MLPerf Tiny's, trained on features `tf.signal` computed; they
## are computed the same way here, and scaled the way its training code did.

import lutra/signal
import kws as model

when defined(lutraBoard): import lutra
else:
  template print(args: varargs[untyped]) = stdout.write(args)
when defined(testset): import std/os

const
  mfcc = Mfcc(sampleRate: 16000, window: 480, melBins: 40, lowHz: 20, highHz: 4000, coefficients: 10)
  hop = 320
  frames = 49
  # The model's input: a coefficient is this many steps of 0.5847, from 83.
  # Steady does not pass these on from the model file.
  stepsPerUnit = int64(65536 / 0.5847029089927673)
  zero = 83

  words: array[12, cstring] = ["down", "go", "left", "no", "off", "on", "right", "stop", "up", "yes",
    "silence", "unknown"]
  folder = "build/keywords/"
  files = ["down/022cd682_nohash_0.wav", "go/022cd682_nohash_0.wav", "left/022cd682_nohash_0.wav",
    "no/03401e93_nohash_0.wav", "off/03401e93_nohash_0.wav", "on/022cd682_nohash_0.wav",
    "right/03401e93_nohash_0.wav", "stop/022cd682_nohash_0.wav", "up/03401e93_nohash_0.wav",
    "yes/022cd682_nohash_0.wav", "_silence_/1024.wav", "_unknown_/backward_0c540988_nohash_0.wav.wav"]

type Clip = array[16000, int16]

func samples(wav: string): Clip =
  ## From a WAV file of 16-bit samples, which follow its 44-byte header
  for i in 0..<result.len: result[i] = cast[int16](wav[44 + 2 * i].uint16 or (wav[45 + 2 * i].uint16 shl 8))

const clips = block:
  var all: array[files.len, Clip]
  for i, file in files: all[i] = samples(staticRead(folder & file))
  all

proc listen(clip: Clip) =
  ## Fills the model's input with the features of a clip
  # Training scaled each clip to make its highest sample 1
  var
    peak = 1'i32
    coefficients: array[mfcc.coefficients, int32]
  for sample in clip: peak = max(peak, sample)
  for f in 0..<frames:
    mfcc.compute(clip.toOpenArray(hop * f, hop * f + mfcc.window - 1), coefficients, fullScale = peak)
    for k, c in coefficients:
      # Rounded towards zero, as training did, with the fraction in Q16 until then
      model.input0()[mfcc.coefficients * f + k] =
        int8(clamp((int64(c) * stepsPerUnit div 65536 + zero * 65536) div 65536, -128, 127))

proc heard(): int =
  ## The word the model gives the highest score, having run
  model.invoke()
  for word in 1..<words.len:
    if model.output0()[word] > model.output0()[result]: result = word

when defined(testset):
  var right, total = 0
  for word, name in ["down", "go", "left", "no", "off", "on", "right", "stop", "up", "yes",
      "_silence_", "_unknown_"]:
    for file in walkFiles(currentSourcePath().parentDir / folder / name / "*.wav"):
      listen(samples(readFile(file)))
      inc total
      if heard() == word: inc right
  print right, " of ", total, " clips of the test set recognised\n"
else:
  print "BEGIN keywords\n"
  var right = 0
  for word in 0..<clips.len:
    when defined(lutraBoard):
      rgbLed.color(blue = 20)
      let start = cycles()
    listen(clips[word])
    var checksum = 0x811c9dc5'u32
    for i in 0..<model.Input0Elems: checksum = (checksum xor cast[uint8](model.input0()[i])) * 0x01000193
    when defined(lutraBoard):
      let listened = cycles()
    let answer = heard()
    when defined(lutraBoard):
      print "time: features ", (listened - start) div (cpuHz div 1000), " ms, model ",
        (cycles() - listened) div (cpuHz div 1000), " ms\n"
      if answer == word: rgbLed.color(green = 20) else: rgbLed.color(red = 20)
      delay 300.ms
    if answer == word: inc right
    print words[word], ": heard ", words[answer], ", ", (model.output0()[answer].int + 128) * 100 div 256,
      "% sure, features ", checksum, "\n"
  print right, " of ", clips.len, "\n"
  print "END keywords\n"
  when defined(lutraBoard):
    while true: discard
