## Somewhere bytes go, and a link they also come back over: a UART, and later
## USB serial.

type
  ByteSink* = concept
    proc send(sink: Self, c: char)

  ByteLink* = concept
    proc send(link: Self, c: char)
    proc poll(link: Self): bool ## Whether a byte is waiting
    proc receive(link: Self): char ## Waits for one
