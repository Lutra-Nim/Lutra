import ../../tasks
import registers, peripherals, gpio, clock

template control(uart: Uart): Reg = Reg(uart.base + uartControl)
template status(uart: Uart): Reg = Reg(uart.base + uartStatus)

const
  # Of `control`
  enable = 1'u32 shl 0
  receiver = 1'u32 shl 2
  transmitter = 1'u32 shl 3
  # Of `status`
  received = 1'u32 shl 5
  roomToSend = 1'u32 shl 7

proc init*(uart: static Uart, tx, rx: static Gpio, baud: uint32) =
  ## Brings the port up on two pins, with 8 data bits and no parity
  tx.asFunction("USART" & $uart.num & " TX")
  rx.asFunction("USART" & $uart.num & " RX")
  rx.pullUp() # So that a line nobody is driving yet reads as idle, not as noise
  switchOn(apb2Clocks, uart.clockBit)
  Reg(uart.base + uartBaud)[] = cpuHz div baud
  # There is room for one byte. Left to itself the port goes deaf once a byte
  # arrives with the last unread, so it is told to keep the newer instead.
  Reg(uart.base + uartControl3)[] = 1 shl 12
  uart.control[] = enable or receiver or transmitter

proc send*(uart: static Uart, c: char) =
  while (uart.status[] and roomToSend) == 0: discard
  Reg(uart.base + uartToSend)[] = c.uint32

proc poll*(uart: static Uart): bool = (uart.status[] and received) != 0

proc receive*(uart: static Uart): char =
  wait uart.poll
  char(Reg(uart.base + uartReceived)[] and 0xff)
