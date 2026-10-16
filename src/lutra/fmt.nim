## Printing without a heap, to any `ByteSink`:
##
##   uart0.write "took ", elapsed, " us, status ", hex(status), "\n"
##
## or into a `Text`, which goes wherever an `openArray[char]` goes:
##
##   var topic: Text[32]
##   topic.write "lutra/", hex(id), "/temp"
##   broker.subscribe(topic.chars)
##
## A type becomes printable by giving it a `put`.

import std/macros
import hal/bytelink

type
  Hex* = object
    value: uint64
    digits: int

  Decimal*[T] = object
    value: T
    places: int

  Text*[N: static int] = object
    ## Up to `N` characters. What does not fit is dropped, and `full` says so.
    data: array[N, char]
    length: int

func hex*[T: SomeInteger](value: T): Hex =
  ## Prints as fixed-width hexadecimal, two digits per byte of `T`
  when T is SomeSignedInt: Hex(value: cast[uint64](value.int64), digits: 2 * sizeof(T))
  else: Hex(value: value.uint64, digits: 2 * sizeof(T))

func decimal*[T: SomeInteger](value: T, places: int): Decimal[T] =
  ## Prints `value` as a number of `places` decimal places: 712 with 3 is
  ## 0.712, and -5 with 2 is -0.05
  Decimal[T](value: value, places: places)

func len*(text: Text): int = text.length
func full*(text: Text): bool = text.length == text.N
proc clear*(text: var Text) = text.length = 0

template chars*(text: Text): openArray[char] =
  ## What has been written, as an `openArray[char]`
  text.data.toOpenArray(0, text.length - 1)

proc put*(link: static ByteSink, c: char) =
  mixin send
  link.send(c)

proc put*(text: var Text, c: char) =
  if text.length < text.N:
    text.data[text.length] = c
    inc text.length

# Each kind of value is written the same way to a sink as to a text, by
# these, which need only the `put` of a `char` above. Declared after it, so
# that they find it wherever they are used.

template putUnsigned(link: untyped, value: uint32 | uint64) =
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

template magnitude(value: SomeInteger): untyped =
  # 64-bit division is a library call on a 32-bit core, so only pay for it
  # when the type needs it
  type Unsigned = (when sizeof(value) <= 4: uint32 else: uint64)
  when value is SomeSignedInt:
    if value < 0: Unsigned(0'u64 - cast[uint64](value.int64)) else: Unsigned(value)
  else: Unsigned(value)

template putInteger(link: untyped, value: SomeInteger) =
  when value is SomeSignedInt:
    if value < 0: link.put('-')
  link.putUnsigned(magnitude(value))

template putHex(link: untyped, value: Hex) =
  for digit in countdown(value.digits - 1, 0):
    link.put("0123456789abcdef"[int((value.value shr (4 * digit)) and 0xf)])

template putDecimal(link: untyped, number: Decimal) =
  let whole = magnitude(number.value)
  var scale = typeof(whole)(1)
  for _ in 1 .. number.places: scale *= 10
  when number.value is SomeSignedInt:
    if number.value < 0: link.put('-')
  link.putUnsigned(whole div scale)
  if number.places > 0:
    link.put('.')
    var rest = whole mod scale
    for _ in 1 .. number.places:
      scale = scale div 10
      link.put(char(ord('0') + int(rest div scale)))
      rest = rest mod scale

proc put*(link: static ByteSink, text: cstring) =
  for c in text: link.put(c)

proc put*(link: static ByteSink, text: openArray[char]) =
  for c in text: link.put(c)

proc put*(link: static ByteSink, flag: bool) =
  link.put(if flag: cstring("true") else: cstring("false"))

proc put*(link: static ByteSink, value: SomeInteger) = link.putInteger(value)
proc put*(link: static ByteSink, value: Hex) = link.putHex(value)
proc put*(link: static ByteSink, value: Decimal) = link.putDecimal(value)
proc put*(link: static ByteSink, text: Text) = link.put(text.chars)

proc put*(text: var Text, s: cstring) =
  for c in s: text.put(c)

proc put*(text: var Text, s: openArray[char]) =
  for c in s: text.put(c)

proc put*(text: var Text, flag: bool) =
  text.put(if flag: cstring("true") else: cstring("false"))

proc put*(text: var Text, value: SomeInteger) = text.putInteger(value)
proc put*(text: var Text, value: Hex) = text.putHex(value)
proc put*(text: var Text, value: Decimal) = text.putDecimal(value)

macro write*(link: untyped, args: varargs[untyped]): untyped =
  ## Writes each argument to `link` in turn
  result = newStmtList()
  for arg in args:
    result.add newCall(bindSym("put", brOpen), link, arg)
