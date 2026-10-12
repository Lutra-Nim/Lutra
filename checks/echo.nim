## Sends back whatever arrives on the console, at 921600 baud. Run it with
## `nim echo`, which counts what comes back.

import lutra

when defined(buffered):
  console.buffer(4096)

console.setBaud(921_600)

var echoed = 0
while true:
  console.send(console.receive())
  when defined(buffered):
    # Look away, now and then, for longer than the hardware's FIFO lasts
    inc echoed
    if echoed mod 8192 == 0: delay 3.ms
