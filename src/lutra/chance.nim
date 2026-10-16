## Random numbers from a seed, the same each run, and waits that grow for
## trying something again:
##
##   var dice = seeded(42)
##   let roll = dice.below(6) + 1
##
##   var retry = backoff(first = 100.ms, most = 30.sec)
##   while not broker.connect():
##     delay retry.next()
##
## Neither is fit for keys or anything secret.

import time

type
  Seeded* = object
    ## Marsaglia's xorshift: 4 bytes of state, a few instructions a number
    state: uint32

  Backoff* = object
    first, most, now: uint64 # Microseconds
    jitter: Seeded

func seeded*(seed: uint32): Seeded =
  ## The state can't be 0, which it would never leave, so 0 is taken as 1
  Seeded(state: max(seed, 1))

proc next*(dice: var Seeded): uint32 =
  var x = dice.state
  x = x xor (x shl 13)
  x = x xor (x shr 17)
  x = x xor (x shl 5)
  dice.state = x
  x

proc below*(dice: var Seeded, n: uint32): uint32 =
  ## From 0 to `n` - 1, with each about as likely: off by at most one in
  ## 2^32 / n
  uint32((dice.next().uint64 * n.uint64) shr 32)

func backoff*(first, most: Duration, seed: uint32): Backoff =
  ## Waits of `first`, then twice as long each time, up to `most`. Each is
  ## moved by up to a tenth either way, so that devices that lost a server
  ## together don't all come back at once. `seed` should differ between
  ## devices: `import lutra` gives a `backoff` seeded by the hardware.
  Backoff(first: first.uint64, most: most.uint64, now: first.uint64, jitter: seeded(seed))

proc next*(retry: var Backoff): Duration =
  ## The next wait
  let
    tenth = retry.now div 10
    shift = if tenth == 0: 0'u64 else: retry.jitter.below(uint32(min(2 * tenth, high(uint32)))).uint64
  result = Duration(retry.now - tenth + shift)
  retry.now = min(2 * retry.now, retry.most)

proc reset*(retry: var Backoff) =
  ## Starts again from `first`, once whatever was being tried has worked
  retry.now = retry.first
