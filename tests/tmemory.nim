import std/strutils
import lutra/chips/esp32c3/memory

# The DevKitM-1's layout, as it was verified on hardware
let m = Memory(flashSize: 4.MB)
doAssert m.codeOffset == 0x10000
doAssert m.constantsOffset == 0x100000
doAssert m.constantsSize == 3.MB

let script = m.linkerScript
doAssert "ORIGIN = 0x42000000 + 65536, LENGTH = 983040" in script
doAssert "ORIGIN = 0x3C000000 + 1048576, LENGTH = 3145728" in script
doAssert "_flash_pages = 64;" in script
doAssert "__global_pointer$ = " in script

# Holding back the end of flash comes out of the constants
doAssert Memory(flashSize: 4.MB, reservedSize: 1.MB).constantsSize == 2.MB
doAssertRaises(AssertionDefect): discard Memory(flashSize: 4.MB, codeSize: 1000).linkerScript
