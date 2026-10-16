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

type List*[N: static int; T] = object
  ## Up to `N` items, in the order added until one is deleted: what is wanted
  ## where `seq` is not allowed
  items: array[N, T]
  count: int

func len*(list: List): int = list.count
func full*(list: List): bool = list.count == list.N

proc add*[N, T](list: var List[N, T], item: T) =
  ## Panics when the list is full; `full` says so first
  list.items[list.count] = item
  inc list.count

template `[]`*(list: List, i: int): untyped =
  list.items.toOpenArray(0, list.count - 1)[i] # Checked against what is there, not N

template `[]=`*(list: var List, i: int, item: untyped) =
  list.items.toOpenArray(0, list.count - 1)[i] = item

proc del*[N, T](list: var List[N, T], i: int) =
  ## Removes item `i` by moving the last into its place, as `seq.del` does
  list.items.toOpenArray(0, list.count - 1)[i] = list.items[list.count - 1]
  dec list.count

proc clear*(list: var List) = list.count = 0

iterator items*[N, T](list: List[N, T]): T =
  for i in 0 ..< list.count: yield list.items[i]

iterator mitems*[N, T](list: var List[N, T]): var T =
  for i in 0 ..< list.count: yield list.items[i]

iterator pairs*[N, T](list: List[N, T]): (int, T) =
  for i in 0 ..< list.count: yield (i, list.items[i])
