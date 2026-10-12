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
