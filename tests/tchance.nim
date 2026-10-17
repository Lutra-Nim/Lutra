import lutra/[chance, time]

# The same seed gives the same numbers, and 0 is taken as 1
var a = seeded(42)
var b = seeded(42)
for _ in 1..100: doAssert a.next() == b.next()
var zero = seeded(0)
var one = seeded(1)
doAssert zero.next() == one.next() and zero.next() != 0

# below stays below, and reaches every value
var dice = seeded(7)
var seen: array[6, int]
for _ in 1..6000:
  let roll = dice.below(6)
  doAssert roll < 6
  inc seen[roll]
for count in seen: doAssert count in 800..1200

# Waits double up to the most, each within a tenth, and reset starts again
var retry = backoff(first = 100.ms, most = 1.sec, seed = 3)
for expected in [100_000'u64, 200_000, 400_000, 800_000, 1_000_000, 1_000_000]:
  let wait = retry.next().uint64
  doAssert wait in expected - expected div 10 .. expected + expected div 10, $wait
retry.reset()
doAssert retry.next().uint64 in 90_000'u64..110_000'u64
