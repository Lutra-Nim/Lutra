## Why a board last started, as each chip tells it. `print` shows it by name.

type ResetReason* = enum
  powerOn         ## Power came on. On the DevKitM-1, also its EN button and a reset from the host
  resetPin        ## The reset pin: the B-L475E-IOT01A's black button, and a reset from the host
  watchdogTimeout ## The watchdog was not fed in time
  software        ## The program called `restart`. On the B-L475E-IOT01A, also after flashing
  brownout        ## The supply fell too low. The STM32L475 can't tell this from powerOn
  wake            ## Woken from deep sleep
  other
