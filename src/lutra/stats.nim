## Statistics in whole numbers: a running summary of a stream, and the order
## of a window of values.
##
##   var normal: Stats
##   normal.add x                   # count, mean, variance, deviation, least, greatest
##
##   sort(window)                   # In place
##   let middle = median(window)    # These two reorder `window`, which is why it is `var`
##   let high = percentile(window, 90)
##
## Not exported by `lutra`, as `sort` and `median` are names programs use.

import fixed

when defined(lutraBoard): {.push checks: off.}

type Stats* = object
  ## A running count, mean and variance, by Welford's method, and the least
  ## and greatest. Nothing is kept of the values themselves.
  count: int64
  mean: int64   # Q16
  spread: int64 # The sum of squared differences from the mean, Q8
  least, greatest: int32

func rounded(x: int64, bits: int): int64 {.inline.} = (x + (1'i64 shl (bits - 1))) shr bits

proc add*(s: var Stats, x: int32) =
  ## For values within about 8 million of the mean. The variance stays exact
  ## to a 256th for some 30 million values that differ by thousands.
  if s.count == 0 or x < s.least: s.least = x
  if s.count == 0 or x > s.greatest: s.greatest = x
  inc s.count
  let
    value = int64(x) shl 16
    before = value - s.mean
  s.mean += before div s.count
  let after = value - s.mean
  s.spread += rounded((before shr 8) * (after shr 8), 8) # Q16 by Q16, less the bits each lost

func count*(s: Stats): int64 = s.count
func least*(s: Stats): int32 = s.least       ## 0 before anything is added
func greatest*(s: Stats): int32 = s.greatest ## 0 before anything is added
func mean*(s: Stats): int32 = int32(rounded(s.mean, 16)) ## Rounded

func variance*(s: Stats): int64 =
  ## Of the values themselves, divided by their count rather than one less,
  ## as numpy's `var` does
  if s.count == 0: 0'i64 else: rounded(s.spread div s.count, 8)

func deviation*(s: Stats): int32 =
  ## The standard deviation: the root of the variance, rounded
  if s.count == 0: 0'i32
  else: int32((isqrt(uint64(max(s.spread div s.count, 0)) shl 2) + 16) shr 5) # Q8 to Q4, doubled

proc clear*(s: var Stats) = s = Stats()

proc sort*[T](a: var openArray[T]) =
  ## Into rising order, in place. An insertion sort: quick for the few dozen
  ## values of a window, and slow for thousands.
  for i in 1 ..< a.len:
    let x = a[i]
    var j = i
    while j > 0 and x < a[j - 1]:
      a[j] = a[j - 1]
      dec j
    a[j] = x

proc select[T](a: var openArray[T], k: int): T =
  ## The value that would be at `k` were `a` sorted, by reordering it only as
  ## far as that needs: Hoare's quickselect
  var (low, high) = (0, a.high)
  while low < high:
    let pivot = a[(low + high) div 2]
    var (i, j) = (low, high)
    while i <= j:
      while a[i] < pivot: inc i
      while pivot < a[j]: dec j
      if i <= j:
        swap a[i], a[j]
        inc i
        dec j
    if k <= j: high = j
    elif k >= i: low = i
    else: break
  a[k]

proc median*[T: SomeNumber](a: var openArray[T]): T =
  ## The middle value, or the mean of the two middles, rounded down. Reorders
  ## `a`; copy it first to keep its order.
  assert a.len > 0, "There is no median of nothing"
  let upper = a.select(a.len div 2)
  if a.len mod 2 == 1: return upper
  let lower = a.select(a.len div 2 - 1)
  when T is SomeFloat: (lower + upper) / 2
  else: lower + (upper - lower) div 2

proc percentile*[T](a: var openArray[T], p: range[0..100]): T =
  ## The smallest value that at least `p` percent of `a` are no greater than,
  ## which is always one of the values. Reorders `a`.
  assert a.len > 0, "There is no percentile of nothing"
  a.select(max((p * a.len + 99) div 100, 1) - 1)

when defined(lutraBoard): {.pop.}
