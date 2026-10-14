## A small MQTT client, of version 3.1.1, over any `Socket`:
##
##   const broker = mqtt(wifi.socket, "test.mosquitto.org")
##
##   if broker.connect(clientId = "lutra"):
##     broker.publish("lutra/up", millis(), " ms")
##
##   proc listen() {.task.} =
##     broker.subscribe("lutra/led/#")
##     for message in broker.messages:
##       print message.topic, " says ", message.payload, "\n"
##
## A payload is written as `print` writes. Messages go and come at most once,
## which MQTT calls QoS 0, and one longer than the broker's `size`, its topic
## included, is passed over. There is no keep-alive of MQTT's own: the socket
## is left to notice a dead connection, and then `messages` ends and
## `publish` is false.

import std/macros
import fmt, tasks, hal/socket

type
  Mqtt*[S] = object
    socket*: S
    host*: string
    port*: int
    size*: int

  Buffers[N: static int] = object
    outgoing: array[N, byte] # A packet being written, after room for its fixed header
    written: int
    full, busy: bool
    incoming: array[N, byte] # What has come, from the start of a packet
    held: int
    done: int # The length of the packet at the start of `incoming`, once it has been seen to
    lastId: uint16

  Payload*[S] = object
    ## Where `publish` prints to
    broker: Mqtt[S]

  Message* = object
    ## A message that has come, until the next turn of `messages`
    data: ptr UncheckedArray[char]
    topicAt, topicLength, payloadAt, payloadLength: int

const room = 5 # The most a fixed header takes: a byte, and a length in four

template topic*(message: Message): openArray[char] =
  message.data.toOpenArray(message.topicAt, message.topicAt + message.topicLength - 1)

template payload*(message: Message): openArray[char] =
  message.data.toOpenArray(message.payloadAt, message.payloadAt + message.payloadLength - 1)

func mqtt*[S](socket: S, host: string, port = 1883, size = 256): Mqtt[S] =
  ## A broker reached through `socket`. A packet either way, a message with
  ## its topic, takes up to `size` bytes.
  Mqtt[S](socket: socket, host: host, port: port, size: size)

proc buffers[S](broker: static Mqtt[S]): ptr Buffers[broker.size] =
  var buffers {.global.}: Buffers[broker.size]
  addr buffers

proc add(b: var Buffers, value: byte) =
  if b.written < b.N: b.outgoing[b.written] = value
  else: b.full = true
  inc b.written

proc add(b: var Buffers, text: openArray[char]) =
  for c in text: b.add c.byte

proc addNumber(b: var Buffers, n: int) =
  b.add byte(n shr 8)
  b.add byte(n and 0xff)

proc addText(b: var Buffers, text: openArray[char]) =
  b.addNumber text.len
  b.add text

proc begin[S](broker: static Mqtt[S]) =
  ## Waits for any packet another task is sending, and starts one
  let b = broker.buffers
  wait not b.busy
  b.busy = true
  b.written = room
  b.full = false

proc finish[S: Socket](broker: static Mqtt[S], kind: byte): bool {.discardable.} =
  ## Puts the fixed header before what was written, and sends it all
  mixin send
  let b = broker.buffers
  if not b.full:
    # The length that follows, seven bits a byte, low first
    var
      length = b.written - room
      header: array[room, byte]
      count = 1
    header[0] = kind
    while true:
      header[count] = byte(length and 0x7f) or (if length > 0x7f: 0x80'u8 else: 0)
      inc count
      length = length shr 7
      if length == 0: break
    let first = room - count
    for i in 0..<count: b.outgoing[first + i] = header[i]
    result = broker.socket.send(b.outgoing.toOpenArray(first, b.written - 1))
  b.busy = false

proc next[S: Socket](broker: static Mqtt[S]): int =
  ## Waits for the next whole packet, which it leaves at the start of
  ## `incoming`, and returns its length; or 0 once the connection is gone. One
  ## too long for `incoming` is passed over.
  mixin receive
  let b = broker.buffers
  # The packet before goes, and whatever came after it moves up
  for i in b.done..<b.held: b.incoming[i - b.done] = b.incoming[i]
  b.held -= b.done
  b.done = 0
  while true:
    # A type byte, then the remaining length, seven bits a byte, low first
    var (length, count, known) = (0, 1, false)
    while count < min(b.held, room) and not known:
      length = length or (int(b.incoming[count] and 0x7f) shl (7 * (count - 1)))
      known = (b.incoming[count] and 0x80) == 0
      inc count
    let total = count + length
    if known and total <= b.N and b.held >= total:
      b.done = total
      return total
    if known and total > b.N:
      var left = total - b.held
      while left > 0:
        let got = broker.socket.receive(b.incoming.toOpenArray(0, min(left, b.N) - 1))
        if got == 0: return 0
        left -= got
      b.held = 0
      continue
    let got = broker.socket.receive(b.incoming.toOpenArray(b.held, b.N - 1))
    if got == 0: return 0
    b.held += got

proc connect*[S: Socket](broker: static Mqtt[S], clientId: openArray[char] = ""): bool =
  ## Connects to the broker. With no `clientId`, the broker makes one up.
  ## False if the broker could not be reached or turned the connection down.
  mixin connect, close
  let b = broker.buffers
  (b.held, b.done) = (0, 0)
  if not broker.socket.connect(broker.host, broker.port): return false
  broker.begin()
  b[].addText "MQTT"
  b[].add 4 # Version 3.1.1
  b[].add 0x02 # A clean session: nothing is kept from an earlier connection
  b[].addNumber 0 # No keep-alive
  b[].addText clientId
  if broker.finish(0x10) and broker.next() == 4 and b.incoming[0] == 0x20 and b.incoming[3] == 0:
    return true
  broker.socket.close()

proc subscribe*[S: Socket](broker: static Mqtt[S], topic: openArray[char]): bool {.discardable.} =
  ## Asks for the messages on `topic`, which may have MQTT's wildcards, `+`
  ## and `#`. They come through `messages`. False if the request could not
  ## be sent; a broker that turns it down sends nothing.
  let b = broker.buffers
  broker.begin()
  b.lastId = max(b.lastId + 1, 1) # An id of 0 is not allowed
  b[].addNumber b.lastId.int
  b[].addText topic
  b[].add 0 # At most once
  broker.finish(0x82)

proc send*[S](payload: static Payload[S], c: char) =
  payload.broker.buffers[].add c.byte

proc beginPublish[S](broker: static Mqtt[S], topic: openArray[char]) =
  broker.begin()
  broker.buffers[].addText topic

template payloadOf(server: Mqtt): untyped = Payload[typeof(server.socket)](broker: server)

macro publish*(broker: Mqtt, topic: openArray[char], args: varargs[untyped]): bool =
  ## Sends a message, with each of `args` written in turn as `print` writes
  ## them. False if it was too long, or the connection is gone.
  ##
  ##   broker.publish("lutra/up", millis(), " ms")
  result = newTree(nnkStmtListExpr, newCall(bindSym"beginPublish", broker, topic))
  for arg in args:
    result.add newCall(bindSym("put", brOpen), newCall(bindSym"payloadOf", broker), arg)
  result.add newCall(bindSym"finish", broker, newLit(0x30'u8))

iterator messages*[S: Socket](broker: static Mqtt[S]): Message =
  ## Waits for each message on the topics subscribed to, and ends once the
  ## connection is gone
  let b = broker.buffers
  while true:
    let total = broker.next()
    if total == 0: break
    if b.incoming[0] shr 4 == 3: # Anything else is the broker's answer to a request
      var at = 1 # Past the fixed header
      while (b.incoming[at] and 0x80) != 0: inc at
      inc at
      let topicLength = b.incoming[at].int shl 8 or b.incoming[at + 1].int
      yield Message(data: cast[ptr UncheckedArray[char]](addr b.incoming[0]),
        topicAt: at + 2, topicLength: topicLength,
        payloadAt: at + 2 + topicLength, payloadLength: total - (at + 2 + topicLength))
