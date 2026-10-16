## Checks the B-L475E-IOT01A's SPI bus through a jumper from its output back
## to its input, D11 to D12: PA7 to PA6. Run it with
## `nim -d:board=b_l475e_iot01a loopback`. Its second UART is checked by
## `nim wifi`.

import lutra

proc check(name: cstring, passed: bool) =
  print name, (if passed: cstring(" ok\n") else: cstring(" FAILED\n"))

const device = spi1.device(select = PA4)

spi1.init(clock = PA5, copi = PA7, cipo = PA6, hz = 10_000_000)
device.init()

print "BEGIN loopback\n"

block:
  var sent, got: array[300, byte]
  for i in 0..<sent.len: sent[i] = byte(i * 7)
  device.transfer(sent, got)
  check "spi1 comes back", got == sent
  var first: array[4, byte]
  device.transfer(sent, first) # What comes back may be shorter than what goes
  check "spi1 shorter input", first == [sent[0], sent[1], sent[2], sent[3]]

let start = cycles()
var fill: array[1000, byte]
device.transfer(fill, fill.toOpenArray(0, -1))
let took = cycles() - start
print "spi1 1000 bytes in ", took div (cpuHz div 1_000_000), " us\n"

print "END\n"
