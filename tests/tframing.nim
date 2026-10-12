import lutra/framing

# A link that hands back whatever was sent over it
type Loop = object
var wire: seq[byte]
proc send(link: static Loop, c: char) = wire.add c.byte
proc poll(link: static Loop): bool = wire.len > 0
proc receive(link: static Loop): char =
  result = wire[0].char
  wire.delete(0)

doAssert crc16(cast[seq[byte]]("123456789")) == 0x29B1

var buffer: array[2048, byte]

proc roundTrip(payload: seq[byte]) =
  wire.setLen 0
  Loop().sendFrame(payload)
  doAssert wire[0] == 0 and wire[^1] == 0
  for b in wire[1..^2]: doAssert b != 0
  doAssert wire.len <= payload.len + 2 + (payload.len + 2) div 254 + 3
  let length = Loop().receiveFrame(buffer)
  doAssert length == payload.len, $payload.len & " came back as " & $length
  doAssert buffer[0..<length] == payload
  doAssert wire.len == 0

# Every length around the 254-byte runs, of zeros, of non-zeros and of a mix
for length in 0..600:
  var zeros, ones, mixed = newSeq[byte](length)
  var state = 12345'u32 + length.uint32
  for i in 0..<length:
    ones[i] = 1
    state = state * 1664525 + 1013904223
    mixed[i] = if (state shr 28) < 3: 0 else: byte(state shr 16)
  roundTrip zeros
  roundTrip ones
  roundTrip mixed

# Noise ahead of a packet is a damaged packet of its own, and costs no other
wire = @[7'u8, 200, 3]
Loop().sendFrame([1'u8, 2, 3])
Loop().sendFrame([4'u8, 5])
doAssert Loop().receiveFrame(buffer) == -1
doAssert Loop().receiveFrame(buffer) == 3 and buffer[0..2] == [1'u8, 2, 3]
doAssert Loop().receiveFrame(buffer) == 2 and buffer[0..1] == [4'u8, 5]

# Stray zeros, as a line gives when the far end resets, are not packets
wire = @[0'u8, 0, 0]
Loop().sendFrame([6'u8])
wire.add 0
Loop().sendFrame([7'u8, 0])
doAssert Loop().receiveFrame(buffer) == 1 and buffer[0] == 6
doAssert Loop().receiveFrame(buffer) == 2 and buffer[0..1] == [7'u8, 0]

# A flipped bit, and a packet too long for the buffer
wire.setLen 0
Loop().sendFrame([9'u8, 8, 7, 6])
wire[3] = wire[3] xor 0x10
doAssert Loop().receiveFrame(buffer) == -1
var small: array[3, byte]
Loop().sendFrame([9'u8, 8, 7, 6])
doAssert Loop().receiveFrame(small) == -1
doAssert wire.len == 0
