## Sipeed's Lichee RV Dock: the Lichee RV module, a D1 with 512 MB of DRAM
## and a green LED, on a carrier with an addressable LED, Wi-Fi and HDMI. Its
## console is UART0, on the pins marked TX and RX underneath, which take a
## 3.3 V USB serial adapter. Programs are loaded through the module's USB-C
## port (Appendix E of Lutra's design).

import ../chips/d1, ../panic
export d1

const
  memory* = Memory(dramSize: 512.MB)
  console* = uart0
  consolePorts* = ["ttyUSB", "cu.usbserial", "Silabser"] ## What a host calls a USB serial adapter's port, as the DevKitM-1's. On Windows, its driver's device, untried

  led* = PC1 ## Green, on the module
  rgbLed* = RgbLed(pin: PC0)
  speaker* = codec
    ## Into the Dock's NS4150 amplifier, for a speaker on J7, 2 pins of 1.25 mm,
    ## between its outputs, neither of which is ground. The amplifier is always
    ## on: R77, which would give its enable to PB12, is not fitted.

when not defined(nimscript):
  proc start() {.exportc: "lutraBoardStart".} =
    ## Runs before the program. Whatever loaded it set the console up, at a
    ## rate it chose, from a clock it chose.
    console.init(tx = PB8, rx = PB9, baud = 115200)
    # Nothing else joins the host to the board, so this is how it starts a
    # program again, or loads another, while one runs
    console.onBreak(restartIntoLoader())

  proc halted() {.exportc: "lutraHalted".} =
    ## After a panic or a fault, with interrupts off, the break is still heard
    if console.breakSeen: restartIntoLoader()

  reportFaults(console)
  reportPanics(console)
