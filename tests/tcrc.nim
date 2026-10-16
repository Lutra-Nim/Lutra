import lutra/crc

proc bytes(s: string): seq[byte] =
  for c in s: result.add byte(c)

# The check values of the catalogue of CRCs: each over "123456789"
doAssert crc16(bytes"123456789") == 0x29b1
doAssert crc32(bytes"123456789") == 0xcbf43926'u32
doAssert crc32(bytes"") == 0
doAssert crc32(bytes"The quick brown fox jumps over the lazy dog") == 0x414fa339'u32
