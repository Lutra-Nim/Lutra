## Arithmetic in whole numbers, for cores with no floating-point unit. A
## fraction is held as a whole number of 65536ths, written Q16 below. Every
## result is the same, bit for bit, on the host as on a board.
##
##   let heading = atan2(field.y, field.x)  # An Angle
##   print heading.degrees                  # 0 to 359
##   let s = sin(30.degrees)                # Q16: 32768 is a half
##   let g = mulQ16(s, gain)                # Rounded, and held at the ends of int32
##   const half = q16(0.5)                  # Worked out when the program is compiled

# Hot loops, on the board without Nim's checks. The host tests run them with
# the checks on, and the board gives the same bits as the host.
when defined(lutraBoard): {.push checks: off.}

import std/math

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

type Angle* = distinct uint16
  ## A 65536th of a turn, so that angles wrap around as they should

func `+`*(a, b: Angle): Angle {.borrow.}
func `-`*(a, b: Angle): Angle {.borrow.}
func `==`*(a, b: Angle): bool {.borrow.}

func degrees*(d: int): Angle =
  ## An angle of `d` degrees, as `30.degrees`
  Angle(uint16(((d mod 360 + 360) mod 360 * 65536 + 180) div 360 and 0xffff))

func degrees*(a: Angle): int =
  ## Rounded, from 0 to 359
  (int(a.uint16) * 360 + 32768) shr 16 mod 360

func q16*(x: float): int32 {.compileTime.} =
  ## `x` as Q16, for constants: `const half = q16(0.5)`
  int32(round(x * 65536))

func mulQ16*(a, b: int32): int32 =
  ## Two Q16 numbers multiplied, rounded to the nearest and held at the ends
  ## of int32 rather than wrapping
  let product = (int64(a) * b + (1 shl 15)) shr 16
  int32(clamp(product, int64(int32.low), int64(int32.high)))

const quarter = block:
  ## The sine over a quarter turn, in 256 steps and one more, as Q20: finer
  ## than the answer, so that only the answer is rounded
  var table: array[257, int32]
  for i in 0..256: table[i] = int32(round(sin(PI / 2 * i.float / 256) * 1048576))
  table

func sin*(a: Angle): int32 =
  ## As Q16, within one 65536th of the true value
  let
    x = a.uint16
    within = int32(x and 0x3fff) # Into its quarter
    along = if (x and 0x4000) != 0: 0x4000 - within else: within # Second and fourth quarters run back
    step = along shr 6
    fraction = along and 63
    fine = if step == 256: quarter[256]
           else: quarter[step] + ((quarter[step + 1] - quarter[step]) * fraction + 32) shr 6
    value = (fine + 8) shr 4
  if (x and 0x8000) != 0: -value else: value

func cos*(a: Angle): int32 = sin(a + Angle(0x4000))

const arctangents = block:
  ## atan(2^-i) in 256ths of an Angle, for turning a point towards the x axis
  var table: array[24, int64]
  for i in 0..<24: table[i] = int64(round(arctan(pow(2.0, -i.float)) / (2 * PI) * 65536 * 256))
  table

func atan2*(y, x: int32): Angle =
  ## The direction of the point (x, y) from the origin, as `math.arctan2`
  ## gives it, within a 65536th of a turn. 0 for the origin.
  if x == 0 and y == 0: return Angle(0)
  var
    (x, y) = (int64(x) shl 24, int64(y) shl 24) # So that the shifts below lose nothing that matters
    turned = 0'i64
  if x < 0: # Into the right half, where the turns below converge
    (x, y) = (-x, -y)
    turned = 0x8000 shl 8
  for i in 0..<24:
    # Each step turns by atan(2^-i), towards the axis
    let (dx, dy) = (y shr i, x shr i)
    if y > 0:
      (x, y) = (x + dx, y - dy)
      turned += arctangents[i]
    else:
      (x, y) = (x - dx, y + dy)
      turned -= arctangents[i]
  Angle(uint16(((turned + 128) shr 8) and 0xffff))

when defined(lutraBoard): {.pop.}
