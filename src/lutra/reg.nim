## Memory-mapped registers. A `Reg` is an address, and reading or writing it
## compiles to a single volatile load or store.

type
  Volatile {.importc: "volatile unsigned int", nodecl.} = uint32
  Reg* = distinct uint32

proc load(address: uint32): uint32 {.importc: "*(volatile unsigned int *)", nodecl.}
  # A C expression called as a function. Nim takes it for a call, and so
  # evaluates it once where it checks the result, as the range check of
  # `char(reg[] and 0xff)` does; and reading some registers takes a byte
  # from a FIFO.

template `[]`*(reg: Reg): uint32 = load(uint32(reg))
template `[]=`*(reg: Reg, value: uint32) = cast[ptr Volatile](reg)[] = value
