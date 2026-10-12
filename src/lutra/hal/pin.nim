## A digital pin.

type Pin* = concept
  proc output(pin: Self)
  proc input(pin: Self)
  proc high(pin: Self)
  proc low(pin: Self)
  proc toggle(pin: Self)
  proc read(pin: Self): bool
  proc pullUp(pin: Self)
  proc pullDown(pin: Self)
  proc noPull(pin: Self)
