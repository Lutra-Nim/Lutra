# The debounced button, against a stand-in pin and clock: the pin reads what
# `script` says for the time, and each wait moves the time on

import lutra/[button, time]

var
  now = 0'u64
  level: proc (t: uint64): bool

proc micros(): uint64 =
  inc now, 100 # Each look at the clock takes a while, so waits end
  now

type FakePin = object
proc input(pin: static FakePin) = discard
proc output(pin: static FakePin) = discard
proc high(pin: static FakePin) = discard
proc low(pin: static FakePin) = discard
proc toggle(pin: static FakePin) = discard
proc pullUp(pin: static FakePin) = discard
proc pullDown(pin: static FakePin) = discard
proc noPull(pin: static FakePin) = discard
proc read(pin: static FakePin): bool = level(now)

const key = FakePin().debounced(held = 1.sec)

proc run(until: uint64): seq[(Change, uint64)] =
  now = 0
  for change in key.changes:
    result.add (change, now div 1000)
    if now >= until: break
    if result.len >= 10: break

# Pressed (low) from 100 ms to 1500 ms, bouncing for the first 10 ms of each
# edge, and again from 1800 ms, which ends the run
level = proc (t: uint64): bool =
  let ms = t div 1000
  if ms in 100'u64..110'u64 or ms in 1500'u64..1510'u64: (t div 1500) mod 2 == 0
  else: ms notin 100'u64..1500'u64 and ms < 1800
let changes = run(1800_000)
doAssert changes.len == 4 and changes[3][0] == pressed, $changes
doAssert changes[0][0] == pressed and changes[0][1] in 110'u64..135'u64, $changes
doAssert changes[1][0] == held and changes[1][1] in 1110'u64..1140'u64, $changes
doAssert changes[2][0] == released and changes[2][1] in 1510'u64..1535'u64, $changes

# A bounce shorter than `settle` is no change at all: the first is the press at 800 ms
level = proc (t: uint64): bool =
  let ms = t div 1000
  ms notin 300'u64..305'u64 and ms < 800
let first = run(0)
doAssert first.len == 1 and first[0][0] == pressed and first[0][1] in 820'u64..845'u64, $first
