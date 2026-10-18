import std/[macros, macrocache, strutils]
import ../../[tasks, containers]
import ../../arch/armv7m/interrupts
import registers, peripherals, gpio, clock

template control(uart: Uart): Reg = Reg(uart.base + uartControl)
template status(uart: Uart): Reg = Reg(uart.base + uartStatus)
template received(uart: Uart): char = char(Reg(uart.base + uartReceived)[] and 0xff)

const
  # Of `control`
  portOn = 1'u32 shl 0
  receiver = 1'u32 shl 2
  transmitter = 1'u32 shl 3
  receivedInterrupt = 1'u32 shl 5
  # Of `status`
  waiting = 1'u32 shl 5
  sent = 1'u32 shl 6 # The last byte is out on the line
  roomToSend = 1'u32 shl 7

proc init*(uart: static Uart, tx, rx: static Gpio, baud: uint32) =
  ## Brings the port up on two pins, with 8 data bits and no parity. The
  ## console is already up when a program starts.
  tx.asFunction(uart.name & " TX")
  rx.asFunction(uart.name & " RX")
  rx.pullUp() # So that a line nobody is driving yet reads as idle, not as noise
  switchOn(if uart.bus == 1: apb1Clocks else: apb2Clocks, uart.clockBit)
  Reg(uart.base + uartBaud)[] = cpuHz div baud # Both buses run at the core's clock
  # There is room for one byte. Left to itself the port goes deaf once a byte
  # arrives with the last unread, so it is told to keep the newer instead.
  Reg(uart.base + uartControl3)[] = 1 shl 12
  # `buffer` may have come first, and asked for the interrupt
  uart.control[] = uart.control[] and receivedInterrupt or portOn or receiver or transmitter

proc flush*(uart: static Uart) =
  ## Waits until what was sent is out on the line, the last byte included
  while (uart.status[] and sent) == 0: discard

proc setBaud*(uart: static Uart, baud: uint32) =
  # What was sent at the old rate goes first. The rate can only be changed
  # with the port off.
  uart.flush()
  let was = uart.control[]
  uart.control[] = was and not portOn
  Reg(uart.base + uartBaud)[] = cpuHz div baud
  uart.control[] = was

proc send*(uart: static Uart, c: char) =
  while (uart.status[] and roomToSend) == 0: discard
  Reg(uart.base + uartToSend)[] = c.uint32

# Receiving is polled, from the one byte the hardware holds, unless the program
# asks for a buffer. Which of the two a port uses is settled at compile time,
# here: its buffer's size, or 0 once it has been read polled.
const buffers = CacheTable"lutra.uartBuffers"

macro bufferSize(uart: static Uart): int =
  if uart.name notin buffers: buffers[uart.name] = newLit(0)
  buffers[uart.name]

macro setBufferSize(uart: static Uart, size: static int) =
  if uart.name in buffers:
    error uart.name.toLowerAscii & ".buffer has to come before the port is first read, and only once"
  buffers[uart.name] = newLit(size)

proc ring(uart: static Uart, size: static int): ptr Ring[size, char] =
  var buffer {.global.}: Ring[size, char]
  addr buffer

proc poll*(uart: static Uart): bool =
  const size = bufferSize(uart)
  when size > 0: uart.ring(size)[].len > 0
  else: (uart.status[] and waiting) != 0

proc receive*(uart: static Uart): char =
  const size = bufferSize(uart)
  wait uart.poll
  when size > 0: uart.ring(size)[].pop
  else: uart.received

template buffer*(uart: static Uart, size: static int) =
  ## From here on, receives through an interrupt into a buffer of `size`
  ## bytes, so the program may look away for longer than a byte takes to
  ## arrive. Bytes that arrive with the buffer full are dropped.
  setBufferSize(uart, size)

  proc handler() {.gensym, exportc: "lutra_interrupt_" & $uart.interrupt, cdecl.} =
    # Reading the byte is what clears the interrupt
    while (uart.status[] and waiting) != 0:
      discard uart.ring(size)[].push(uart.received)
  discard cast[pointer](handler) # Inside a procedure, Nim leaves out one nothing refers to

  # Before `init`, as it may be, the port takes nothing in until it has its clock
  switchOn(if uart.bus == 1: apb1Clocks else: apb2Clocks, uart.clockBit)
  uart.control[] = uart.control[] or receivedInterrupt
  enable(uart.interrupt)
