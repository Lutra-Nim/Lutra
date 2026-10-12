## Must not compile; `tclaims` checks why.

import lutra/claims

claim("IO6", "UART1 TX")
claim("IO6", "UART1 TX")
claim("IO7", "a GPIO", " at main.nim(3)")
claim("IO6", "a GPIO", " at main.nim(4)")

once("Handling the interrupt of IO9", " at main.nim(6)")
once("Handling the interrupt of IO9", " at main.nim(8)")
