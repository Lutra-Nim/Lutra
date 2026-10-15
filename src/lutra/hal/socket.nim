## A connection to a server over TCP. The network stack may be on another
## chip, as it is with a Wi-Fi module driven by AT commands.

type Socket* = concept
  proc connect(socket: Self, host: openArray[char], port: int): bool
    ## False if the server could not be reached
  proc send(socket: Self, data: openArray[byte]): bool
    ## False if the connection is gone
  proc receive(socket: Self, data: var openArray[byte]): int
    ## Waits for bytes, and returns how many came, or 0 once the connection is
    ## gone
  proc close(socket: Self)
