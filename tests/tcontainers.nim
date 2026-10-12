import lutra/containers

var ring: Ring[4, int]
doAssert ring.len == 0
for item in 1..4: doAssert ring.push(item)
doAssert not ring.push(5)
doAssert ring.len == 4
doAssert ring.pop == 1
doAssert ring.push(5)
# The indices run on past the size, and past where they wrap
for item in 6..1000:
  doAssert ring.pop == item - 4
  doAssert ring.push(item)
doAssert ring.len == 4
for item in 997..1000: doAssert ring.pop == item
doAssert ring.len == 0
doAssert not compiles(block:
  var odd: Ring[3, int]
  discard odd.push(1))
