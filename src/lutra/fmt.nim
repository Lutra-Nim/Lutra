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
## `json(...)` writes an object, for the dashboards and brokers that expect one:
##
##   broker.publish("lutra/imu", json(ax = ax, temp = decimal(t, 2), ok = true))
##   # {"ax":12,"temp":21.50,"ok":true}
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

template putHex(link: untyped, number: Hex) =
  for digit in countdown(number.digits - 1, 0):
    link.put("0123456789abcdef"[int((number.value shr (4 * digit)) and 0xf)])

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

func name[E: enum](value: E): cstring =
  ## An enum's value by name, from a table in flash rather than a string made
  const names = block:
    var table: array[E, cstring]
    for e in E: table[e] = cstring($e)
    table
  names[value]

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
proc put*[E: enum](link: static ByteSink, value: E) = link.put(value.name) ## By name

proc put*(text: var Text, s: cstring) =
  for c in s: text.put(c)

proc put*(text: var Text, s: openArray[char]) =
  for c in s: text.put(c)

proc put*(text: var Text, flag: bool) =
  text.put(if flag: cstring("true") else: cstring("false"))

proc put*(text: var Text, value: SomeInteger) = text.putInteger(value)
proc put*(text: var Text, value: Hex) = text.putHex(value)
proc put*(text: var Text, value: Decimal) = text.putDecimal(value)
proc put*[E: enum](text: var Text, value: E) = text.put(value.name) ## By name

# JSON. An object holds its fields, each as `json` was given it, but for
# text, which it holds by reference until it is printed.

type
  Chars = object
    data: ptr UncheckedArray[char]
    len: int

  Json*[T] = object
    fields: T

func field[T](value: T): T = value
func field(text: static string): cstring = cstring(text) # A literal, which a field may hold
func field(text: openArray[char]): Chars =
  Chars(data: if text.len == 0: nil else: cast[ptr UncheckedArray[char]](unsafeAddr text[0]), len: text.len)
template field(text: Text): Chars = field(text.chars)

func jsonObject[T](fields: T): Json[T] = Json[T](fields: fields)

macro json*(fields: varargs[untyped]): untyped =
  ## An object of `name = value` fields, each a whole number, a `decimal`, a
  ## `bool`, text, or another `json(...)`
  let values = newNimNode(nnkTupleConstr)
  for f in fields:
    if f.kind != nnkExprEqExpr: error "json(...) takes name = value fields, as json(x = 1)", f
    values.add newColonExpr(f[0], newCall(bindSym"field", f[1]))
  newCall(bindSym"jsonObject", values)

proc put*[T](link: static ByteSink, value: Json[T])
proc put*[T](text: var Text, value: Json[T])

template putEscaped(link: untyped, c: char) =
  case c
  of '"', '\\':
    link.put('\\')
    link.put(c)
  of '\n': link.put(cstring("\\n"))
  of '\0'..'\x09', '\x0b'..'\x1f':
    link.put(cstring("\\u00"))
    link.putHex(hex(uint8(c)))
  else: link.put(c)

template putQuoted(link: untyped, text: Chars | cstring) =
  link.put('"')
  when text is Chars:
    for i in 0 ..< text.len: link.putEscaped(text.data[i])
  else:
    for c in text: link.putEscaped(c)
  link.put('"')

template putJson(link: untyped, value: Json) =
  link.put('{')
  var first = true
  for name, item in value.fields.fieldPairs:
    if not first: link.put(',')
    first = false
    link.put('"')
    link.put(name)
    link.put(cstring("\":"))
    when item is Chars or item is cstring: link.putQuoted(item)
    elif item is Json or item is bool or item is SomeInteger or item is Decimal: link.put(item)
    else: {.error: "A json(...) field is a whole number, a decimal, a bool, text or a json(...)".}
  link.put('}')

proc put*[T](link: static ByteSink, value: Json[T]) = link.putJson(value)
proc put*[T](text: var Text, value: Json[T]) = text.putJson(value)

macro write*(link: untyped, args: varargs[untyped]): untyped =
  ## Writes each argument to `link` in turn
  result = newStmtList()
  for arg in args:
    result.add newCall(bindSym("put", brOpen), link, arg)
