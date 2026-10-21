## Register addresses, from mainline Linux's device tree and drivers for the
## D1 (`sunxi-d1s-t113.dtsi`, `ccu-sun20i-d1.c`, `pinctrl-sunxi.h`,
## `leds-sun50i-a100.c`), and for the audio codec, which mainline does not
## drive, Allwinner's `sun20iw1-codec.h` and the D1's manual as `hello-d1`
## quotes it. Only the ones something uses.

import ../../reg
export reg

const
  # Clocks
  pllCpu* = Reg 0x0200_1000
  apb1Clock* = Reg 0x0200_1524
  uartGates* = Reg 0x0200_190C ## A port's clock in bit n, and out of reset in bit 16 + n
  ledcClock* = Reg 0x0200_1BF0
  ledcGates* = Reg 0x0200_1BFC
  riscvClock* = Reg 0x0200_1D00

  # Pins. Each port has a block of 0x30 bytes, B's first at 0x30.
  gpioPorts* = 0x0200_0000'u32
  gpioConfig* = 0x00'u32 ## Four bits a pin: what it is for
  gpioData* = 0x10'u32
  gpioPull* = 0x24'u32 ## Two bits a pin

  # UARTs, which are 16550s, their registers a word apart
  uartData* = 0x00'u32 ## What comes in and goes out, or the divider's low byte
  uartDividerHigh* = 0x04'u32
  uartInterruptEnable* = 0x04'u32 ## Or, while the divider is reached, its high byte
  uartFifoControl* = 0x08'u32 ## Written; read, it says why the port interrupted
  uartLineControl* = 0x0C'u32
  uartLineStatus* = 0x14'u32
  uartStatus* = 0x7C'u32 ## Reading it clears the interrupt for writing while busy

  # The controller for addressable LEDs
  ledc* = 0x0200_8000'u32
  ledcControl* = Reg(ledc + 0x00)
  ledcBitTimes* = Reg(ledc + 0x04)
  ledcResetTime* = Reg(ledc + 0x0C)
  ledcData* = Reg(ledc + 0x14)
  ledcStatus* = Reg(ledc + 0x20)

  # The interrupt controller, a PLIC. Context 0 is the core in machine mode.
  plic* = 0x1000_0000'u32 ## A source's priority at 4 times its number
  plicEnable* = 0x1000_2000'u32 ## A bit a source
  plicThreshold* = Reg 0x1020_0000
  plicClaim* = Reg 0x1020_0004 ## Read to take the next waiting source, written to say it is handled

  # The timer block's two timers, counting down from what they are given
  timerInterruptEnable* = Reg 0x0205_0000
  timerInterruptStatus* = Reg 0x0205_0004 ## Writing a 1 clears each
  timerControl* = 0x0205_0010'u32 ## Timer n's at 0x10 times n further
  timerInterval* = 0x0205_0014'u32

  # The audio codec's clocks: PLL_AUDIO0, whose fraction comes from its
  # sigma-delta pattern, and the DAC's clock from it
  pllAudio0* = Reg 0x0200_1078
  pllAudio0Pattern* = Reg 0x0200_1178
  dacClock* = Reg 0x0200_1A50
  codecGates* = Reg 0x0200_1A5C ## Its bus clock in bit 0, and out of reset in bit 16

  # The audio codec: its digital part, and from 0x300 its analog part
  codec = 0x0203_0000'u32
  dacControl* = Reg(codec + 0x00)
  dacVolume* = Reg(codec + 0x04)
  dacFifoControl* = Reg(codec + 0x10)
  dacFifoStatus* = Reg(codec + 0x14) ## Its free places in bits 22:8; pending flags, cleared by a 1
  dacData* = Reg(codec + 0x20)
  dacAnalog* = Reg(codec + 0x310)
  codecRamp* = Reg(codec + 0x31C)
  headphone* = Reg(codec + 0x340)
  codecPower* = Reg(codec + 0x348)

  # The RTC's spare registers, which a reset keeps
  rtcSpare2* = Reg 0x0709_0108 ## boot0 hands over to FEL when this holds `0x5AA5A55A`

  # The watchdog of the timer block, from Linux's `sunxi_wdt.c`
  watchdogControl* = Reg 0x0205_00B0
  watchdogConfig* = Reg 0x0205_00B4
  watchdogMode* = Reg 0x0205_00B8
