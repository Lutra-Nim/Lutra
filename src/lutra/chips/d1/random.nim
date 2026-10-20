import clock

var state: uint64

proc random*(): uint32 =
  ## Not from hardware: the D1's generator is in its crypto engine, which
  ## nothing drives yet. These mix the cycle counter and the time, which differ
  ## from one start to the next, and are not fit for keys.
  state += 0x9E37_79B9_7F4A_7C15'u64 xor (micros() shl 20) xor cycles()
  var z = state
  z = (z xor (z shr 30)) * 0xBF58_476D_1CE4_E5B9'u64
  z = (z xor (z shr 27)) * 0x94D0_49BB_1331_11EB'u64
  uint32((z xor (z shr 31)) shr 32)
