## B-L475E-IOT01A, ST's Discovery kit for an "IoT node": an STM32L475VG with
## 1 MB of flash, an ST-LINK probe that also carries USART1 to the host, two
## green LEDs and a button.

import ../chips/stm32l475, ../panic
export stm32l475

const
  memory* = Memory(flashSize: 1.MB)
  console* = usart1
  consolePorts* = ["ttyACM", "cu.usbmodem"] ## What a host calls the ST-LINK's serial port

  led1* = PA5
  led2* = PB14
  userButton* = PC13

when not defined(nimscript):
  proc start() {.exportc: "lutraBoardStart".} =
    ## Runs before the program. Nothing else has brought the console up.
    console.init(tx = PB6, rx = PB7, baud = 115200)

  reportFaults(console)
  reportPanics(console)
