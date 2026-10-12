## Fixed-size containers, for programs with no heap.

type
  Index {.importc: "volatile unsigned int", nodecl.} = uint32
  Ring*[N: static int; T] = object
    ## A first-in first-out buffer of up to `N` items. One side may `push` and
    ## the other `pop` without a critical section between them, which is what
    ## makes it safe between an interrupt handler and the main program.
    items: array[N, T]
    head, tail: Index # Never wrapped: each is only ever written by one side

func len*[N, T](ring: var Ring[N, T]): int = int(ring.tail - ring.head)

proc push*[N, T](ring: var Ring[N, T], item: T): bool =
  ## False, and nothing is stored, when the ring is full
  when (N and (N - 1)) != 0: {.error: "The size of a Ring must be a power of two.".}
  if ring.len == N: return false
  ring.items[ring.tail and (N - 1)] = item
  ring.tail = ring.tail + 1
  true

proc pop*[N, T](ring: var Ring[N, T]): T =
  ## The oldest item. The ring must not be empty.
  result = ring.items[ring.head and (N - 1)]
  ring.head = ring.head + 1
