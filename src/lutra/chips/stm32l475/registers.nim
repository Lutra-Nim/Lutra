## Register addresses, from ST's reference manual RM0351. Only the ones
## something uses.

import ../../reg
export reg

const
  # Clocks
  clockControl* = Reg 0x4002_1000
  clockConfig* = Reg 0x4002_1008
  pllConfig* = Reg 0x4002_100C
  pllSai1Config* = Reg 0x4002_1010
  ahb2Clocks* = Reg 0x4002_104C
  apb1Clocks* = Reg 0x4002_1058
  apb2Clocks* = Reg 0x4002_1060

  flashAccess* = Reg 0x4002_2000

  # The 32.768 kHz crystal and the timer that can count it, for the self-check
  powerControl* = Reg 0x4000_7000
  backupControl* = Reg 0x4002_1090
  resetFlags* = Reg 0x4002_1094 # In the clock controller's status
  watchdogKey* = Reg 0x4000_3000 # The independent watchdog
  watchdogPrescale* = Reg 0x4000_3004
  watchdogReload* = Reg 0x4000_3008
  watchdogStatus* = Reg 0x4000_300C
  systemReset* = Reg 0xE000_ED0C # The core's application interrupt and reset control
  clockSources* = Reg 0x4002_1088
  lowTimerControl* = Reg 0x4000_7C10
  lowTimerReload* = Reg 0x4000_7C18
  lowTimerCount* = Reg 0x4000_7C1C

  # GPIO, as offsets from a port's base. Port A is first, and the rest follow
  # 0x400 apart.
  gpioPorts* = 0x4800_0000'u32
  gpioMode* = 0x00'u32
  gpioOutputType* = 0x04'u32
  gpioPull* = 0x0C'u32
  gpioIn* = 0x10'u32
  gpioOut* = 0x14'u32
  gpioSetReset* = 0x18'u32
  gpioFunction* = 0x20'u32 # Two words, four bits a pin

  # Which port's pin each of the sixteen lines of pin interrupts listens to,
  # four bits a line, and then the lines themselves
  pinInterruptPorts* = 0x4001_0008'u32
  pinInterruptEnable* = Reg 0x4001_0400
  pinRisingEdges* = Reg 0x4001_0408
  pinFallingEdges* = Reg 0x4001_040C
  pinInterrupts* = Reg 0x4001_0414

  # The random number generator, which wants a 48 MHz clock, chosen in `clockSources`
  randomControl* = Reg 0x5006_0800
  randomStatus* = Reg 0x5006_0804
  randomData* = Reg 0x5006_0808

  # USART, as offsets from a port's base
  uartControl* = 0x00'u32
  uartControl3* = 0x08'u32
  uartBaud* = 0x0C'u32
  uartStatus* = 0x1C'u32
  uartReceived* = 0x24'u32
  uartToSend* = 0x28'u32

  # SPI, as offsets from a bus's base
  spiControl* = 0x00'u32
  spiControl2* = 0x04'u32
  spiStatus* = 0x08'u32
  spiData* = 0x0C'u32

  # I2C, as offsets from a bus's base
  i2cControl* = 0x00'u32
  i2cTransfer* = 0x04'u32
  i2cTiming* = 0x10'u32
  i2cStatus* = 0x18'u32
  i2cStatusClear* = 0x1C'u32
  i2cReceived* = 0x24'u32
  i2cToSend* = 0x28'u32

  # Timers 2 and 5, the two that count to 32 bits
  timer2* = 0x4000_0000'u32
  timer5* = 0x4000_0C00'u32
  timerControl* = 0x00'u32
  timerControl2* = 0x04'u32
  timerFollow* = 0x08'u32
  timerCount* = 0x24'u32

  # Timers 6 and 7, which only count, for timer events
  timer6* = 0x4000_1000'u32
  timer7* = 0x4000_1400'u32
  timerInterrupts* = 0x0C'u32
  timerStatus* = 0x10'u32
  timerUpdate* = 0x14'u32
  timerPrescale* = 0x28'u32
  timerReload* = 0x2C'u32
