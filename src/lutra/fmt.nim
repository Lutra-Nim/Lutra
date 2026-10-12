## Printing without a heap, to any `ByteSink`:
##
##   uart0.write "took ", elapsed, " us, status ", hex(status), "\n"
##
## A type becomes printable by giving it a `put`.

import std/macros
import hal/bytelink

type Hex* = object
  value: uint64
  digits: int

func hex*[T: SomeInteger](value: T): Hex =
  ## Prints as fixed-width hexadecimal, two digits per byte of `T`
  when T is SomeSignedInt: Hex(value: cast[uint64](value.int64), digits: 2 * sizeof(T))
  else: Hex(value: value.uint64, digits: 2 * sizeof(T))

proc put*(link: static ByteSink, c: char) =
  mixin send
  link.send(c)

proc put*(link: static ByteSink, text: cstring) =
  for c in text: link.put(c)

proc put*(link: static ByteSink, flag: bool) =
  link.put(if flag: cstring("true") else: cstring("false"))

proc putDecimal[T: uint32 or uint64](link: static ByteSink, value: T) =
  var
    digits: array[20, char]
    count = 0
    rest = value
  while true:
    digits[count] = char(ord('0') + int(rest mod 10))
    inc count
    rest = rest div 10
    if rest == 0: break
  while count > 0:
    dec count
    link.put(digits[count])

proc put*(link: static ByteSink, value: SomeInteger) =
  # 64-bit division is a library call on a 32-bit core, so only pay for it
  # when the type needs it
  type Unsigned = (when sizeof(value) <= 4: uint32 else: uint64)
  when value is SomeSignedInt:
    if value < 0:
      link.put('-')
      link.putDecimal(Unsigned(0'u64 - cast[uint64](value.int64)))
      return
  link.putDecimal(Unsigned(value))

proc put*(link: static ByteSink, value: Hex) =
  for digit in countdown(value.digits - 1, 0):
    link.put("0123456789abcdef"[int((value.value shr (4 * digit)) and 0xf)])

macro write*(link: untyped, args: varargs[untyped]): untyped =
  ## Writes each argument to `link` in turn
  result = newStmtList()
  for arg in args:
    result.add newCall(ident"put", link, arg)
