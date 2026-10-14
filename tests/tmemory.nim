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

# The B-L475E-IOT01A's, likewise
from lutra/chips/stm32l475/memory as stm32 import nil

let other = stm32.linkerScript(stm32.Memory(flashSize: 1.MB))
doAssert "ORIGIN = 0x08000000, LENGTH = 1048576" in other
doAssert "ORIGIN = 0x20000000, LENGTH = 98304" in other
doAssert other.find(".vectors") < other.find(".text") # The core looks for its table at the very start
