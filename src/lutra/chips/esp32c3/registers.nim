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
  uartClockConfig* = 0x78'u32

  # SPI, as offsets from a bus's base
  spiCommand* = 0x00'u32
  spiClock* = 0x0C'u32
  spiUser* = 0x10'u32
  spiLength* = 0x1C'u32
  spiMisc* = 0x20'u32
  spiDma* = 0x30'u32
  spiEventsClear* = 0x38'u32
  spiEvents* = 0x3C'u32
  spiData* = 0x98'u32 # Sixteen words
  spiTarget* = 0xE0'u32
  spiTargetLength* = 0xE4'u32
  spiClockGate* = 0xE8'u32

  # DMA channel 0, the only one in use
  dmaIn* = Reg 0x6003_F070
  dmaInLink* = Reg 0x6003_F080
  dmaInSource* = Reg 0x6003_F0A0
  dmaOut* = Reg 0x6003_F0D0
  dmaOutLink* = Reg 0x6003_F0E0
  dmaOutSource* = Reg 0x6003_F100

  gpioOut* = Reg 0x6000_4004
  gpioOutSet* = Reg 0x6000_4008
  gpioOutClear* = Reg 0x6000_400C
  gpioEnableSet* = Reg 0x6000_4024
  gpioEnableClear* = Reg 0x6000_4028
  gpioIn* = Reg 0x6000_403C
  gpioInterrupts* = Reg 0x6000_4044
  gpioInterruptsClear* = Reg 0x6000_404C
  gpioPin* = 0x6000_4074'u32 # One per pin
  gpioInSelect* = 0x6000_4154'u32 # One per signal
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

  randomNumber* = Reg 0x6002_60B0

  cpuClock* = Reg 0x600C_0008
  peripheralClocks* = Reg 0x600C_0010
  peripheralClocks1* = Reg 0x600C_0014
  peripheralResets1* = Reg 0x600C_001C
  systemClock* = Reg 0x600C_0058
  cacheControl* = Reg 0x600C_4000
  cacheControl1* = Reg 0x600C_4004
  flashPageTable* = 0x600C_5000'u32 # One entry per 64K page
