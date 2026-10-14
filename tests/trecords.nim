import lutra/[records, framing]

for value in [0'i64, 1, -1, 63, -64, 64, 300, -300, int64.high, int64.low]:
  var (buffer, at) = (newSeq[byte](10), 0)
  buffer.putVarint(at, value)
  var back = 0
  doAssert buffer.getVarint(back) == value and back == at, $value

# Records through framing, as a board sends them
type Loop = object
var wire: seq[byte]
proc send(link: static Loop, c: char) = wire.add c.byte
proc poll(link: static Loop): bool = wire.len > 0
proc receive(link: static Loop): char =
  result = wire[0].char
  wire.delete(0)

proc values(packet: openArray[byte]): seq[int64] =
  var at = 1
  while at < packet.len: result.add packet.getVarint(at)

let (a, b) = (-7, 1023)
for i in 0..1:
  Loop().record(a, b, ms = 5'u64 + i.uint64, flag = i == 0) # Names go only with the first
var packet: array[64, byte]
var length = Loop().receiveFrame(packet)
doAssert packet[0] == namesKind and cast[string](packet[1 ..< length]) == "a,b,ms,flag"
length = Loop().receiveFrame(packet)
doAssert packet[0] == valuesKind and packet.toOpenArray(0, length - 1).values == @[-7'i64, 1023, 5, 1]
length = Loop().receiveFrame(packet)
doAssert packet.toOpenArray(0, length - 1).values == @[-7'i64, 1023, 6, 0]
doAssert wire.len == 0

Loop().record(max(a, b))
length = Loop().receiveFrame(packet)
doAssert cast[string](packet[1 ..< length]) == "\"max(a, b)\""
