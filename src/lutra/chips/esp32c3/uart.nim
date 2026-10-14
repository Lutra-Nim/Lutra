import std/[macros, macrocache]
import ../../[claims, containers, tasks]
import registers, peripherals, interrupts, gpio, clock

template fifo(uart: Uart): Reg = Reg(uart.base + uartFifo)
template interruptEnable(uart: Uart): Reg = Reg(uart.base + uartInterruptEnable)
template interruptClear(uart: Uart): Reg = Reg(uart.base + uartInterruptClear)
template clockDivider(uart: Uart): Reg = Reg(uart.base + uartClockDivider)
template status(uart: Uart): Reg = Reg(uart.base + uartStatus)
template config1(uart: Uart): Reg = Reg(uart.base + uartConfig1)
template clockConfig(uart: Uart): Reg = Reg(uart.base + uartClockConfig)

template waiting(uart: Uart): uint32 = uart.status[] and 0x3ff # In the receive FIFO

proc setBaud*(uart: static Uart, baud: uint32) =
  # What was sent at the old rate goes first, the last byte included, which
  # leaves the FIFO a byte's time before it is out on the line
  while (uart.status[] shr 16 and 0x3ff) > 0: discard
  let byteTime = 10 * (uart.clockDivider[] and 0xfff) div 40 + 1 # In microseconds
  let began = micros()
  while micros() - began < byteTime: discard
  # Ports are clocked from the 40 MHz crystal, so the core's clock does not
  # come into it. The divider has four fractional bits.
  let divider = 40_000_000'u32 * 16 div baud
  uart.clockDivider[] = (divider shr 4) or ((divider and 0xf) shl 20)

proc init*(uart: static Uart, tx, rx: static Gpio, baud: uint32) =
  ## Brings the port up on two pins, with 8 data bits and no parity. The
  ## console is already up when a program starts.
  claim("IO" & $tx.num, "UART" & $uart.num & " TX")
  claim("IO" & $rx.num, "UART" & $uart.num & " RX")
  peripheralClocks[] = peripheralClocks[] or (1'u32 shl uart.clockBit)
  uart.clockConfig[] = 0x0370_0000 # From the crystal, undivided, as the boot ROM sets the console's
  uart.setBaud(baud)
  tx.routeOut(uart.signal)
  rx.pullUp() # So that a line nobody is driving yet reads as idle, not as noise
  rx.routeIn(uart.signal)

proc send*(uart: static Uart, c: char) =
  when uart.tx != noPin: claim("IO" & $uart.tx.num, "UART" & $uart.num & " TX")
  while (uart.status[] shr 16 and 0x3ff) >= 126: discard # Transmit FIFO is full
  uart.fifo[] = c.uint32

# Receiving is polled, straight from the 128-byte FIFO in the hardware, unless
# the program asks for a buffer. Which of the two a port uses is settled at
# compile time, here: its buffer's size, or 0 once it has been read polled.
const buffers = CacheTable"lutra.uartBuffers"

macro bufferSize(uart: static Uart): int =
  let port = "UART" & $uart.num
  if port notin buffers: buffers[port] = newLit(0)
  buffers[port]

macro setBufferSize(uart: static Uart, size: static int) =
  let port = "UART" & $uart.num
  if port in buffers:
    error "uart" & $uart.num & ".buffer has to come before the port is first read, and only once"
  buffers[port] = newLit(size)

proc ring(uart: static Uart, size: static int): ptr Ring[size, char] =
  var buffer {.global.}: Ring[size, char]
  addr buffer

proc poll*(uart: static Uart): bool =
  const size = bufferSize(uart)
  when size > 0: uart.ring(size)[].len > 0
  else: uart.waiting > 0

proc receive*(uart: static Uart): char =
  const size = bufferSize(uart)
  wait uart.poll
  when size > 0: uart.ring(size)[].pop
  else: char(uart.fifo[] and 0xff)

const
  fifoFull = 1'u32 shl 0
  fifoTimeout = 1'u32 shl 8 # The line went quiet with bytes still in the FIFO
  timeoutEnable = 1'u32 shl 21

template buffer*(uart: static Uart, size: static int) =
  ## From here on, receives through an interrupt into a buffer of `size`
  ## bytes, so the program may look away for longer than the hardware's FIFO
  ## lasts. Bytes that arrive with the buffer full are dropped.
  setBufferSize(uart, size)

  proc handler() {.gensym, exportc: "lutra_interrupt_" & $uartSources[uart.num].line, cdecl.} =
    uart.interruptClear[] = fifoFull or fifoTimeout
    while uart.waiting > 0:
      discard uart.ring(size)[].push(char(uart.fifo[] and 0xff))

  uart.config1[] = uart.config1[] and not 0x1ff'u32 or 64 or timeoutEnable # Interrupt at 64 bytes
  uart.interruptEnable[] = fifoFull or fifoTimeout
  enable(uartSources[uart.num])
