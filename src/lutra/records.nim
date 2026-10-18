## Records of whole numbers, sent for `nim capture` to write as CSV:
##
##   for tick in every(10.ms):
##     console.record(tick, ms = millis(), x, y, z)
##
## Each record is a packet of `framing`, so it arrives whole or not at all,
## and the board's own `print`s can go between them. The first record from
## each line of the program, and every hundredth after, sends the names of its
## columns first: a value's name if it is given one, or else the expression
## itself. Sending them again lets a capture recover from losing the first.
## Before the program's first record goes a packet saying it has started, by
## which a capture tells its records from those sent before a reset.

import std/[macros, strutils]
import framing, hal/bytelink

const
  namesKind* = 0'u8 ## A packet of column names, separated by commas
  valuesKind* = 1'u8 ## A packet of values, each a varint
  startKind* = 2'u8 ## The program has started, and its records follow

var started: bool

proc start(link: static ByteLink) =
  ## Says so before the program's first record
  if not started:
    started = true
    sendFrame(link, [startKind])

func zigzag*(value: int64): uint64 =
  ## Small numbers of either sign as small unsigned ones
  (cast[uint64](value) shl 1) xor cast[uint64](value shr 63)

func unzigzag*(value: uint64): int64 = cast[int64](value shr 1) xor -cast[int64](value and 1)

proc putVarint*(buffer: var openArray[byte], at: var int, value: int64) =
  ## Seven bits a byte, low first, with the top bit set on all but the last
  var rest = zigzag(value)
  while rest >= 0x80:
    buffer[at] = byte(rest and 0x7F) or 0x80
    rest = rest shr 7
    inc at
  buffer[at] = byte(rest)
  inc at

proc getVarint*(buffer: openArray[byte], at: var int): int64 =
  var (value, shift) = (0'u64, 0)
  while at < buffer.len:
    let b = buffer[at]
    inc at
    value = value or ((b.uint64 and 0x7F) shl shift)
    if b < 0x80: break
    shift += 7
  unzigzag(value)

macro record*(link: untyped, values: varargs[untyped]): untyped =
  ## Sends `values`, each a whole number or a `bool`, as one record
  var names: seq[string]
  let
    buffer = genSym(nskVar, "buffer")
    at = genSym(nskVar, "at")
    count = genSym(nskVar, "count")
    (putVarint, sendFrame, valuesKind) = (bindSym"putVarint", bindSym"sendFrame", bindSym"valuesKind")
    start = bindSym"start"
  var puts = newStmtList()
  for value in values:
    let (name, expression) =
      if value.kind == nnkExprEqExpr: (value[0].strVal, value[1]) else: (value.repr, value)
    # As CSV wants a name with a comma in it, such as `max(a, b)`
    names.add(if ',' in name or '"' in name: '"' & name.replace("\"", "\"\"") & '"' else: name)
    puts.add quote do: `putVarint`(`buffer`, `at`, int64(`expression`))
  var header = @[newLit(namesKind)]
  for c in names.join(","): header.add newLit(byte(c))
  let
    headerBytes = nnkBracket.newTree(header)
    size = newLit(1 + 10 * values.len) # A varint of 64 bits takes at most ten bytes
  quote do:
    block:
      var `count` {.global.}: uint8
      if `count` == 0:
        `start`(`link`)
        const names: array[`headerBytes`.len, byte] = `headerBytes`
        `sendFrame`(`link`, names)
      `count` = (`count` + 1) mod 100
      var
        `buffer`: array[`size`, byte]
        `at` = 1
      `buffer`[0] = `valuesKind`
      `puts`
      `sendFrame`(`link`, `buffer`.toOpenArray(0, `at` - 1))
