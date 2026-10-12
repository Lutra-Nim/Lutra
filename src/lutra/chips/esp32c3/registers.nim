## Register addresses, from the ESP32-C3 Technical Reference Manual. Only the
## ones something uses.

import ../../reg
export reg

const
  # UART, as offsets from a port's base
  uartFifo* = 0x00'u32
  uartInterruptEnable* = 0x0C'u32
  uartInterruptClear* = 0x10'u32
  uartClockDivider* = 0x14'u32
  uartStatus* = 0x1C'u32
  uartConfig1* = 0x24'u32

  gpioOut* = Reg 0x6000_4004
  gpioOutSet* = Reg 0x6000_4008
  gpioOutClear* = Reg 0x6000_400C
  gpioEnableSet* = Reg 0x6000_4024
  gpioEnableClear* = Reg 0x6000_4028
  gpioIn* = Reg 0x6000_403C
  gpioInterrupts* = Reg 0x6000_4044
  gpioInterruptsClear* = Reg 0x6000_404C
  gpioPin* = 0x6000_4074'u32 # One per pin
  gpioOutSelect* = 0x6000_4554'u32 # One per pin
  ioMux* = 0x6000_9004'u32 # One per pin

  rtcWatchdog* = Reg 0x6000_8090
  rtcWatchdogProtect* = Reg 0x6000_80A8
  superWatchdog* = Reg 0x6000_80AC
  superWatchdogProtect* = Reg 0x6000_80B0
  timerWatchdog* = Reg 0x6001_F048
  timerWatchdogProtect* = Reg 0x6001_F064

  systemTimerOp* = Reg 0x6002_3004
  systemTimerHigh* = Reg 0x6002_3040
  systemTimerLow* = Reg 0x6002_3044

  interruptMap* = 0x600C_2000'u32 # One per source
  interruptEnable* = Reg 0x600C_2104
  interruptPriority* = 0x600C_2114'u32 # One per line
  interruptThreshold* = Reg 0x600C_2194

  cpuClock* = Reg 0x600C_0008
  systemClock* = Reg 0x600C_0058
  cacheControl* = Reg 0x600C_4000
  cacheControl1* = Reg 0x600C_4004
  flashPageTable* = 0x600C_5000'u32 # One entry per 64K page
