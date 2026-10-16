import lutra/parse

var
  i: int
  i8: int8
  i32: int32
  i64: int64
  u8: uint8
  u32: uint32
  u64: uint64

doAssert "123".parseInt(i) == 3 and i == 123
doAssert "x=-42;".parseInt(i, start = 2) == 3 and i == -42
doAssert "+7".parseInt(i32) == 2 and i32 == 7
doAssert "-0".parseInt(i32) == 2 and i32 == 0
doAssert "-128 127".parseInt(i8) == 4 and i8 == -128
doAssert "127".parseInt(i8) == 3 and i8 == 127
i8 = 5
doAssert "128".parseInt(i8) == 0 and i8 == 5 # Too large: nothing used, nothing changed
doAssert "-129".parseInt(i8) == 0 and i8 == 5
doAssert "-9223372036854775808".parseInt(i64) == 20 and i64 == int64.low
doAssert "9223372036854775808".parseInt(i64) == 0
doAssert "".parseInt(i) == 0 and "-".parseInt(i) == 0 and "a1".parseInt(i) == 0

doAssert "255".parseUInt(u8) == 3 and u8 == 255
doAssert "256".parseUInt(u8) == 0 and u8 == 255
doAssert "-1".parseUInt(u32) == 0
doAssert "18446744073709551615 ".parseUInt(u64) == 20 and u64 == uint64.high
doAssert "18446744073709551616".parseUInt(u64) == 0
doAssert "4294967295".parseUInt(u32) == 10 and u32 == uint32.high

doAssert "0xC0FFEE".parseHex(u32) == 8 and u32 == 0xC0FFEE
doAssert "#ff".parseHex(u8) == 3 and u8 == 0xff
doAssert "ff".parseHex(i8) == 2 and i8 == -1
doAssert "100".parseHex(u8) == 0
doAssert "deadbeefcafe".parseHex(u32, maxLen = 8) == 8 and u32 == 0xdeadbeef'u32
doAssert "ffffffffffffffff".parseHex(u64) == 16 and u64 == uint64.high
doAssert "0x".parseHex(u32) == 0 and "g".parseHex(u32) == 0
