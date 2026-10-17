## MQTT over Wi-Fi, through a second DevKitM-1 running Espressif's AT
## firmware, to test.mosquitto.org. Run it with `nim wifi`, with
## `lutra-espat` checked out beside this repository, the network named in
## LUTRA_WIFI_NETWORK and LUTRA_WIFI_PASSWORD, and the boards wired as
## `wiring.nim` describes, of which IO6, IO7 and ground are used. From the
## B-L475E-IOT01A, D1 goes to the module's IO6, D0 to its IO7, and ground to
## ground.
##
## The board subscribes to a topic of its own, publishes to it, and counts
## what the broker sends back.

import lutra, lutra/mqtt, lutra_espat

const
  network {.strdefine.} = ""
  password {.strdefine.} = ""
  port = when declared(uart4): uart4 else: uart1
  wifi = espAt(port)
  broker = mqtt(wifi.socket, "test.mosquitto.org")
  rounds = 20

port.buffer(1024)
when declared(uart4): port.init(tx = PA0, rx = PA1, baud = 115_200)
else: port.init(tx = IO6, rx = IO7, baud = 115_200)

var
  topic: Text[20] # lutra/check/, then eight hex digits, so that runs do not meet
  heard, longest = 0
  inOrder, ended = false

proc check(name: cstring, passed: bool) =
  print name, (if passed: cstring(" ok\n") else: cstring(" FAILED\n"))

proc listen() {.task.} =
  inOrder = true
  for message in broker.messages:
    var n = 0
    discard message.payload.parseInt(n)
    if message.payload.len > 100: longest = message.payload.len
    else:
      if n != heard: inOrder = false
      inc heard
  ended = true

topic.write "lutra/check/", hex(random())

print "BEGIN wifi\n"
check "module answers", wifi.init()
check "joins the network", wifi.join(network, password)
check "broker answers", broker.connect()
check "subscribes", broker.subscribe(topic.chars)
start listen

for n in 0..<rounds:
  broker.publish(topic.chars, n)
  delay 100.ms
discard wait(heard == rounds, within = 10.sec)
print "round trip ", heard, " of ", rounds, "\n"
check "in order", inOrder

var long: array[230, char]
for c in long.mitems: c = 'x'
check "a long message goes", broker.publish(topic.chars, long.toOpenArray(0, 199))
check "and comes back whole", wait(longest == 200, within = 5.sec)
check "one too long is refused", not broker.publish(topic.chars, long)

broker.socket.close()
check "messages end with the connection", wait(ended, within = 5.sec)
check "connects again", broker.connect()
print "END wifi\n"
