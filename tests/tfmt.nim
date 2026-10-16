import lutra/fmt

type Sink = object

var written: string
proc send(sink: static Sink, c: char) = written.add c

template printed(args: varargs[untyped]): string =
  written = ""
  Sink().write(args)
  written

doAssert printed("a", 'b', "\n") == "ab\n"
doAssert printed(true, " ", false) == "true false"
doAssert printed(0, " ", 7'u8, " ", 1234567890) == "0 7 1234567890"
doAssert printed(uint32.high, " ", uint64.high) == "4294967295 18446744073709551615"
doAssert printed(-1, " ", int8.low, " ", int32.low, " ", int64.low) ==
  "-1 -128 -2147483648 -9223372036854775808"
doAssert printed(hex(0xAB'u8), " ", hex(0xC0FFEE'u32), " ", hex(-1'i16), " ", hex(1'u64)) ==
  "ab 00c0ffee ffff 0000000000000001"
doAssert printed(decimal(712, 3), " ", decimal(-5, 2), " ", decimal(1234, 0), " ", decimal(1500'u32, 3)) ==
  "0.712 -0.05 1234 1.500"
doAssert printed(decimal(int32.low, 9), " ", decimal(-1'i64, 1)) == "-2.147483648 -0.1"

# A text takes what print takes, keeps what fits, and goes where an openArray does
proc str(chars: openArray[char]): string =
  for c in chars: result.add c

var topic: Text[16]
topic.write "lutra/", hex(0xBEEF'u16), "/", 42, " ", decimal(7, 1)
doAssert topic.chars.str == "lutra/beef/42 0." and topic.full and topic.len == 16
topic.clear()
doAssert topic.len == 0 and not topic.full and topic.chars.len == 0
topic.write true, '!'
doAssert printed(topic) == "true!"
