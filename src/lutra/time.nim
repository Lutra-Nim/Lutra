## Durations, in whole microseconds.

type Duration* = distinct uint64

template us*(n: SomeInteger): Duration = Duration(n)
template ms*(n: SomeInteger): Duration = Duration(n * 1_000)
template sec*(n: SomeInteger): Duration = Duration(n * 1_000_000)
