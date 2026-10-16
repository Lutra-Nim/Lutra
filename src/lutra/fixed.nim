## Arithmetic in whole numbers, for cores with no floating-point unit. A
## fraction is held as a whole number of 65536ths, written Q16 below. Every
## result is the same, bit for bit, on the host as on a board.

# Hot loops, on the board without Nim's checks. The host tests run them with
# the checks on, and the board gives the same bits as the host.
when defined(lutraBoard): {.push checks: off.}

func isqrt*(x: uint64): uint32 =
  ## The square root, rounded down
  var
    rest = x
    root = 0'u64
    bit = 1'u64 shl 62
  while bit != 0:
    if rest >= root + bit:
      rest -= root + bit
      root = (root shr 1) + bit
    else:
      root = root shr 1
    bit = bit shr 2
  uint32(root)

func log2*(x: uint64): int32 =
  ## The base-2 logarithm of a whole number that is not zero, as Q16
  var whole = 63
  while (x shr whole) == 0: dec whole
  # What is left is between 1 and 2, held in 31 fractional bits. Squaring it
  # doubles its logarithm, so each squaring gives the next bit.
  var rest = if whole >= 31: uint32(x shr (whole - 31)) else: uint32(x shl (31 - whole))
  result = int32(whole) shl 16
  for bit in countdown(15, 0):
    let square = uint64(rest) * rest
    if square >= 1'u64 shl 63:
      result += 1'i32 shl bit
      rest = uint32(square shr 32)
    else:
      rest = uint32(square shr 31)

func ln*(x: uint64): int32 =
  ## The natural logarithm of a whole number that is not zero, as Q16
  int32((int64(log2(x)) * 744261118 + (1 shl 29)) shr 30) # By ln 2, as Q30

when defined(lutraBoard): {.pop.}
