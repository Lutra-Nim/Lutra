## Statistics against the same sums in floating point.

import std/[algorithm, math, random, sequtils]
import lutra/stats

block:
  var s: Stats
  doAssert s.count == 0 and s.mean == 0 and s.variance == 0 and s.deviation == 0
  for x in [2'i32, 4, 4, 4, 5, 5, 7, 9]: s.add x
  doAssert s.count == 8 and s.mean == 5 and s.variance == 4 and s.deviation == 2
  doAssert s.least == 2 and s.greatest == 9
  s.clear()
  doAssert s.count == 0

block: # Many values, of every scale
  var r = initRand(7)
  for (centre, spread) in [(0, 3), (-20_000, 1000), (1_000_000, 50_000), (5, 0)]:
    var
      s: Stats
      xs: seq[float]
    for _ in 0..<100_000:
      let x = int32(centre + r.rand(2 * spread) - spread)
      s.add x
      xs.add x.float
    let
      mean = xs.sum / xs.len.float
      variance = xs.mapIt((it - mean) ^ 2).sum / xs.len.float
    doAssert abs(s.mean.float - mean) <= 0.5 + 1e-9, $centre
    doAssert abs(s.variance.float - variance) <= max(1, variance * 1e-6), $centre
    doAssert abs(s.deviation.float - sqrt(variance)) <= 0.5 + 1e-6, $centre

block:
  var a = [5'i32, -3, 9, 0, 9, 2]
  stats.sort(a)
  doAssert a == [-3'i32, 0, 2, 5, 9, 9]
  var empty: array[0, int]
  stats.sort(empty)

block: # The median and percentiles of random windows, against a full sort
  var r = initRand(3)
  for n in 1..60:
    var a = newSeq[int32](n)
    for x in a.mitems: x = int32(r.rand(100) - 50)
    let sorted = a.sorted
    var b = a
    let m = median(b)
    doAssert m == (if n mod 2 == 1: sorted[n div 2]
                   else: sorted[n div 2 - 1] + (sorted[n div 2] - sorted[n div 2 - 1]) div 2)
    for p in [0, 10, 50, 90, 100]:
      var c = a
      doAssert percentile(c, p) == sorted[max((p * n + 99) div 100, 1) - 1]
  var f = [1.0, 2.0]
  doAssert median(f) == 1.5
