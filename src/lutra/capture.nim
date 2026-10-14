## The host's side of `records`, run by `nim capture`: reads a board's
## console on stdin, and writes its records to stdout as CSV and everything
## else it says to stderr.

import std/posix
import framing, records

# What came since the last zero. A packet ends with a zero, and so text
# between packets is known for text once the next zero arrives, or once the
# line has been quiet a while.
var
  segment: seq[byte]
  replayed: int
  names = "" # Records before the first are from before the board was reset

type Segment = object # A link that is never sent to, only replayed
proc send(s: static Segment, c: char) = discard
proc poll(s: static Segment): bool = true
proc receive(s: static Segment): char =
  ## The segment again, then the zero that ended it
  result = if replayed < segment.len: char(segment[replayed]) else: '\0'
  inc replayed

proc text() =
  if segment.len > 0:
    discard stderr.writeBuffer(addr segment[0], segment.len)
    stderr.flushFile()

proc ended() =
  ## A zero has arrived
  if segment.len == 0: return
  replayed = 0
  var packet: array[4096, byte]
  let length = Segment().receiveFrame(packet)
  if length < 1: text()
  elif packet[0] == namesKind:
    let line = cast[string](packet[1 ..< length])
    if line != names: stdout.writeLine line # They come again every hundredth record
    names = line
  elif packet[0] == valuesKind and names != "":
    var (at, line) = (1, "")
    while at < length:
      if line.len > 0: line.add ','
      line.add $packet.toOpenArray(0, length - 1).getVarint(at)
    stdout.writeLine line
  stdout.flushFile()
  segment.setLen 0

var waiting = TPollfd(fd: 0, events: POLLIN)
while true:
  if poll(addr waiting, 1, 50) == 0: # Quiet for 50 ms
    text()
    segment.setLen 0
    continue
  var b: byte
  if read(0, addr b, 1) != 1: break
  if b == 0: ended() else: segment.add b
text()
