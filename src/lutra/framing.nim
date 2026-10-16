## Packets over a `ByteLink`, each with a checksum:
##
##   link.sendFrame(vector)
##   let length = link.receiveFrame(buffer)
##
## On the wire a packet is a zero, then its payload and a CRC-16 encoded so
## that no byte is zero (COBS), then another zero. A receiver that starts
## listening part-way through, or hears noise, is back in step at the next
## zero, and noise between packets cannot damage the packet after it. Zeros
## with nothing between them are passed over.

import hal/bytelink, crc
export crc16

proc sendFrame*(link: static ByteLink, payload: openArray[byte]) =
  mixin send
  let
    crc = crc16(payload)
    length = payload.len + 2
  template at(i: int): byte =
    if i < payload.len: payload[i] elif i == payload.len: byte(crc and 0xff) else: byte(crc shr 8)

  # Each run of non-zero bytes goes out behind a count of how far away the
  # zero that ends it is. A run of 254 ends without one. The packet is treated
  # as ending in one zero more than it has, which is how the last run ends.
  link.send(char(0)) # Ends whatever noise the line picked up since the last packet
  var position = 0
  while true:
    var run = 0
    while position + run < length and run < 254 and at(position + run) != 0: inc run
    link.send(char(run + 1))
    for i in position..<position + run: link.send(char(at(i)))
    position += run
    if run == 254: continue
    if position == length: break
    inc position
  link.send(char(0))

proc receiveFrame*(link: static ByteLink, buffer: var openArray[byte]): int =
  ## Waits for a packet and returns its length, or -1 for one that was damaged
  ## or too long for `buffer`
  mixin receive
  var
    length = 0 # Of what has been decoded, the CRC included
    last: array[2, byte] # The newest two bytes, which turn out to be the CRC
    fits = true
    run = 0 # Bytes left before the next count
    zeroDue = false
  template decoded(b: byte) =
    if length >= 2:
      if length - 2 < buffer.len: buffer[length - 2] = last[0]
      else: fits = false
    last[0] = last[1]
    last[1] = b
    inc length

  var heard = false
  while true:
    let b = link.receive().byte
    if b == 0:
      # A zero on its own is what a line does as the far end resets, not a packet
      if heard: break else: continue
    heard = true
    if run == 0:
      if zeroDue: decoded(0)
      run = b.int - 1
      zeroDue = b != 255
    else:
      decoded(b)
      dec run

  if length < 2 or not fits or run != 0: return -1
  let payload = length - 2
  if crc16(buffer.toOpenArray(0, payload - 1)) != (last[0].uint16 or (last[1].uint16 shl 8)): return -1
  payload
