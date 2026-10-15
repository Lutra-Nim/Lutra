## The MQTT client against a socket that is not there: the bytes it sends, and
## what it makes of what comes back. `nim r -d:live tmqtt.nim` also runs it
## against test.mosquitto.org, through a socket of the host's.

import lutra/[mqtt, fmt]

type Fake = object

var
  sent: seq[seq[byte]]
  coming: seq[seq[byte]] # Each is what one receive gives, at most
  open = false

proc connect(socket: static Fake, host: openArray[char], port: int): bool =
  open = @host == @"broker" and port == 1883
  open

proc send(socket: static Fake, data: openArray[byte]): bool =
  sent.add @data
  open

proc receive(socket: static Fake, data: var openArray[byte]): int =
  if coming.len == 0: return 0
  result = min(data.len, coming[0].len)
  for i in 0..<result: data[i] = coming[0][i]
  coming[0] = coming[0][result..^1]
  if coming[0].len == 0: coming.delete(0)

proc close(socket: static Fake) = open = false

func bytes(text: string): seq[byte] =
  for c in text: result.add c.byte
func `$`(text: openArray[char]): string =
  for c in text: result.add c

const
  broker = mqtt(Fake(), "broker", size = 32)
  elsewhere = mqtt(Fake(), "elsewhere")

doAssert not elsewhere.connect()

# Connecting
coming = @[@[0x20'u8, 2, 0, 0]]
doAssert broker.connect(clientId = "lutra")
doAssert sent == @[@[0x10'u8, 17, 0, 4] & "MQTT".bytes & @[4'u8, 2, 0, 0, 0, 5] & "lutra".bytes]
sent.setLen 0
coming = @[@[0x20'u8, 2, 0, 5]] # Not authorised
doAssert not broker.connect()
doAssert sent == @[@[0x10'u8, 12, 0, 4] & "MQTT".bytes & @[4'u8, 2, 0, 0, 0, 0]]
doAssert not open
coming = @[@[0x20'u8], @[2'u8, 0], @[0'u8]] # In pieces
doAssert broker.connect()

# Publishing, with a payload written as `print` writes
sent.setLen 0
doAssert broker.publish("a/b", 42, " ms")
broker.publish("a/b", true) # Need not be looked at
doAssert sent == @[@[0x30'u8, 10, 0, 3] & "a/b42 ms".bytes, @[0x30'u8, 9, 0, 3] & "a/btrue".bytes]
doAssert not broker.publish("a/b", "too long for a packet of 32 bytes")
doAssert sent.len == 2

# Subscribing
sent.setLen 0
doAssert broker.subscribe("led/#")
doAssert broker.subscribe("x")
doAssert sent == @[@[0x82'u8, 10, 0, 1, 0, 5] & "led/#".bytes & @[0'u8], @[0x82'u8, 6, 0, 2, 0, 1, 'x'.byte, 0]]

# Messages: the broker's answers are passed over, a message split across
# receives is put together, and one too long is passed over
coming = @[
  @[0x90'u8, 3, 0, 1, 0, 0x30, 9, 0, 5] & "led/1".bytes, # An answer, and the start of a message
  "on".bytes & @[0x30'u8, 40, 0, 1, 'y'.byte] & newSeq[byte](37), # And a message too long
  @[0x30'u8, 7, 0, 1, 'x'.byte] & "abcd".bytes & @[0x30'u8, 3, 0, 1, 'x'.byte]]
var got: seq[string]
for message in broker.messages:
  got.add $message.topic & "=" & $message.payload
doAssert got == @["led/1=on", "x=abcd", "x="], $got

# A loop left part-way does not see the same message again
coming = @[@[0x30'u8, 4, 0, 1, 'x'.byte, '1'.byte, 0x30, 4, 0, 1, 'x'.byte, '2'.byte]]
for message in broker.messages:
  doAssert message.payload == "1"
  break
for message in broker.messages:
  doAssert message.payload == "2"

when defined(live):
  import std/[net, times]

  type Host = object
  var connection: net.Socket

  proc connect(socket: static Host, host: openArray[char], port: int): bool =
    connection = newSocket()
    connection.connect($host, Port(port), timeout = 5000)
    true
  proc send(socket: static Host, data: openArray[byte]): bool =
    var text: string
    for b in data: text.add b.char
    connection.send(text)
    true
  proc receive(socket: static Host, data: var openArray[byte]): int =
    var text = newString(1)
    if connection.recv(text, 1, timeout = 5000) == 0: return 0
    data[0] = text[0].byte
    1
  proc close(socket: static Host) = connection.close()

  const live = mqtt(Host(), "test.mosquitto.org")
  let topic = "lutra/test/" & $epochTime()
  doAssert live.connect()
  doAssert live.subscribe(topic & "/#")
  doAssert live.publish(topic & "/one", "hello ", 7)
  for message in live.messages:
    doAssert $message.topic == topic & "/one" and $message.payload == "hello 7"
    break
  echo "test.mosquitto.org gave back what was published"
