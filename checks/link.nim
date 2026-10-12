## Two boards exchange checksummed buffers, first over UART1 and then over SPI.
## Run it with `nim link`, on boards wired as `wiring.nim` describes. The board
## built with `-d:first` starts each exchange and is the SPI controller.
##
## Every buffer is a known pattern, so each side checks what it was sent as
## well as the checksum on it.

import lutra
import lutra/framing

const
  rounds = 200
  largest = 2000

var sent, received: array[largest + 2, byte]

proc fill(buffer: var openArray[byte], length, seed: int) =
  ## The pattern for one direction of one round
  var state = seed.uint32
  for i in 0..<length:
    state = state * 1664525 + 1013904223
    buffer[i] = byte(state shr 24)

proc matches(buffer: openArray[byte], length, seed: int): bool =
  var expected {.global.}: array[largest, byte]
  expected.fill(length, seed)
  for i in 0..<length:
    if buffer[i] != expected[i]: return false
  true

func size(round: int): int = 1 + (round * 37) mod largest

# Seeds for what this board sends and what it expects, by round
const (mine, theirs) = when defined(first): (1000, 2000) else: (2000, 1000)

uart1.buffer(4096)
uart1.init(tx = IO0, rx = IO1, baud = 921_600)

print "BEGIN link\n"
block:
  var good = 0
  for round in 0..<rounds:
    let length = size(round)
    sent.fill(length, mine + round)
    when defined(first): uart1.sendFrame(sent.toOpenArray(0, length - 1))
    # Whatever the line picked up while the other board was starting is passed over
    var got = -1
    while got < 0: got = uart1.receiveFrame(received)
    if got == length and received.matches(length, theirs + round): inc good
    when not defined(first): uart1.sendFrame(sent.toOpenArray(0, length - 1))
  print "uart ", good, " of ", rounds, "\n"

when defined(first):
  const peer = spi2.device(select = IO10, ready = IO3)
  spi2.init(clock = IO6, copi = IO7, cipo = IO5, hz = 10_000_000)
  peer.init()
else:
  const peer = spi2.target(ready = IO3)
  peer.init(clock = IO6, copi = IO7, cipo = IO5, select = IO10)

proc swap(device: static SpiDevice, output: openArray[byte], input: var openArray[byte]) =
  ## Written against the interface, as a driver for some device would be
  device.transfer(output, input)

block:
  var good = 0
  for round in 0..<rounds:
    # The pattern, and then its CRC-16
    let length = size(round)
    sent.fill(length, mine + round)
    let crc = crc16(sent.toOpenArray(0, length - 1))
    sent[length] = byte(crc)
    sent[length + 1] = byte(crc shr 8)
    when defined(first):
      peer.swap(sent.toOpenArray(0, length + 1), received.toOpenArray(0, length + 1))
      let count = length + 2
    else:
      let count = peer.exchange(sent.toOpenArray(0, length + 1), received.toOpenArray(0, length + 1))
    let theirCrc = received[length].uint16 or (received[length + 1].uint16 shl 8)
    if count == length + 2 and crc16(received.toOpenArray(0, length - 1)) == theirCrc and
        received.matches(length, theirs + round): inc good
  print "spi ", good, " of ", rounds, "\n"

print "END link\n"
while true: discard
