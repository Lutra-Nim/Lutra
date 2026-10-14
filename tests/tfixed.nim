import std/math
import lutra/fixed

doAssert isqrt(0) == 0 and isqrt(1) == 1 and isqrt(3) == 1 and isqrt(4) == 2
doAssert isqrt(uint64.high) == uint32.high
doAssert isqrt(1'u64 shl 62) == 1'u32 shl 31
var state = 1'u64
for _ in 0..<10_000:
  state = state * 6364136223846793005'u64 + 1442695040888963407'u64
  let
    x = state shr (state shr 58) # Of every size
    root = isqrt(x).uint64
  doAssert root * root <= x and (root == uint32.high or (root + 1) * (root + 1) > x)

  if x > 0:
    # Rounded down, to within one part in 65536
    doAssert log2(x).float / 65536 <= log2(x.float) + 1e-9
    doAssert log2(x).float / 65536 > log2(x.float) - 1 / 65536 - 1e-9
    doAssert abs(ln(x).float / 65536 - ln(x.float)) < 1.25 / 65536

doAssert log2(1) == 0 and log2(2) == 65536 and log2(1'u64 shl 63) == 63 * 65536
doAssert ln(1) == 0
