## Checks the watchdog, the reason a board last started, and restarting it.
## The host resets the board, which then starts twice more by itself: once
## when it stops feeding its watchdog, and once when it restarts.

import lutra

proc check(name: cstring, passed: bool) =
  print name, (if passed: cstring(" ok\n") else: cstring(" FAILED\n"))

# How the host resets each board: the DevKitM-1 by its EN line, the other by its reset pin
const byHost = when declared(i2c2): resetPin else: powerOn

case resetReason()
of watchdogTimeout:
  check "the watchdog resets", true
  restart()
of software:
  check "restart", true
  print "END\n"
else:
  print "BEGIN resets\n"
  check "started by the host", resetReason() == byHost
  watchdog.start(within = 300.ms)
  for turn in every(100.ms): # Fed, it waits
    watchdog.feed()
    if turn == 10: break
  check "fed for a second", true
  delay 250.ms # Starved, it waits as long as it was told
  check "starved for 250 ms", true
  delay 1.sec
  check "the watchdog resets", false
