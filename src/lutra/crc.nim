## Checksums, to tell data that arrived or was kept from data that was damaged.

func crc16*(data: openArray[byte]): uint16 =
  ## CRC-16/CCITT-FALSE, which `framing` sends with each packet
  result = 0xffff
  for b in data:
    result = result xor (b.uint16 shl 8)
    for _ in 0..<8:
      result = if (result and 0x8000) != 0: (result shl 1) xor 0x1021 else: result shl 1

func crc32*(data: openArray[byte]): uint32 =
  ## CRC-32 as zlib, Ethernet and PNG compute it. Bit by bit, which is slower
  ## than with a table and 1 KB smaller.
  result = 0xffff_ffff'u32
  for b in data:
    result = result xor b.uint32
    for _ in 0..<8:
      result = if (result and 1) != 0: (result shr 1) xor 0xedb8_8320'u32 else: result shr 1
  result = not result
