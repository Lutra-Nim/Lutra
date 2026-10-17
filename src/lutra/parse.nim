## Reading numbers from text, without allocating or raising:
##
##   var n: int32
##   if line.parseInt(n, start = 5) == 0: ...  # No number there
##
## Each returns how many characters it used, and 0 when there is no number at
## `start` or it does not fit `number`, which is then left as it was. The
## names and shapes are `std/parseutils`', which raises instead, and allocates
## to do it.

func digit(c: char, base: uint64): uint64 =
  ## The value of `c` as a digit in `base`, or `base` if it is not one
  result = case c
    of '0'..'9': uint64(ord(c) - ord('0'))
    of 'a'..'f': uint64(ord(c) - ord('a') + 10)
    of 'A'..'F': uint64(ord(c) - ord('A') + 10)
    else: base
  if result > base: result = base

func magnitude(s: openArray[char], at: var int, last: int, base, limit: uint64): tuple[value: uint64, ok: bool] =
  ## The digits from `at` up to `last`, if there are some and they come to no
  ## more than `limit`. `at` is left after them.
  let first = at
  result.ok = true
  while at < last and digit(s[at], base) < base:
    let d = digit(s[at], base)
    if result.value > (limit - d) div base: result.ok = false
    else: result.value = result.value * base + d
    inc at
  if at == first: result.ok = false

func parseUInt*[T: SomeUnsignedInt](s: openArray[char], number: var T, start = 0): int =
  ## Decimal digits
  var at = start
  let (value, ok) = magnitude(s, at, s.len, 10, uint64(high(T)))
  if not ok: return 0
  number = T(value)
  at - start

func parseInt*[T: SomeSignedInt](s: openArray[char], number: var T, start = 0): int =
  ## Decimal digits, after a `+` or a `-`
  var at = start
  let negative = at < s.len and s[at] == '-'
  if at < s.len and s[at] in {'+', '-'}: inc at
  let (value, ok) = magnitude(s, at, s.len, 10, uint64(high(T)) + uint64(negative))
  if not ok: return 0
  number = if negative and value > 0: T(-int64(value - 1) - 1) else: T(value) # Down to low(T)
  at - start

func parseHex*[T: SomeInteger](s: openArray[char], number: var T, start = 0, maxLen = 0): int =
  ## Hexadecimal digits, after `0x`, `0X` or `#`, all within `maxLen`
  ## characters if it is not 0. A signed `number` takes the bits, as -1 for ff.
  let last = if maxLen == 0: s.len else: min(s.len, start + maxLen)
  var at = start
  if at + 1 < last and s[at] == '0' and s[at + 1] in {'x', 'X'}: at += 2
  elif at < last and s[at] == '#': inc at
  let (value, ok) = magnitude(s, at, last, 16, (1'u64 shl (8 * sizeof(T) - 1) shl 1) - 1)
  if not ok: return 0
  number = cast[T](value)
  at - start
