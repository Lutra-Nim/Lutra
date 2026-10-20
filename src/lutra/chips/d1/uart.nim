import std/[macros, macrocache, strutils]
import ../../[tasks, containers, claims]
import registers, peripherals, gpio, interrupts

template reg(uart: Uart, offset: uint32): Reg = Reg(uart.base + offset)
template lineStatus(uart: Uart): uint32 = uart.reg(uartLineStatus)[]

const
  # Of `uartLineStatus`
  waiting = 1'u32 shl 0
  lineBroken = 1'u32 shl 4 # The line held low for longer than a byte
  roomToSend = 1'u32 shl 5 # The transmit FIFO is empty
  sent = 1'u32 shl 6 # And so is the line
  # Of `uartLineControl`
  eightBits = 3'u32
  dividerAccess = 1'u32 shl 7
  # Of `uartInterruptEnable`
  receivedInterrupt = 1'u32 shl 0
  lineInterrupt = 1'u32 shl 2

proc flush*(uart: static Uart) =
  ## Waits until what was sent is out on the line, the last byte included
  while (uart.lineStatus and sent) == 0: discard

proc setBaud*(uart: static Uart, baud: uint32) =
  ## Ports are clocked from the 24 MHz crystal, so rates up to 115200 come
  ## within 0.2%, and 1500000 exactly. 921600 is 19% off, too far to work.
  uart.flush() # What was sent at the old rate goes first
  let divider = (24_000_000'u32 + 8 * baud) div (16 * baud)
  critical: # While the divider is reached, a handler reading a byte would read it
    uart.reg(uartLineControl)[] = eightBits or dividerAccess
    uart.reg(uartData)[] = divider and 0xff
    uart.reg(uartDividerHigh)[] = divider shr 8
    uart.reg(uartLineControl)[] = eightBits

proc init*(uart: static Uart, tx, rx: static Gpio, baud: uint32) =
  ## Brings the port up on two pins, with 8 data bits and no parity
  tx.asFunction("UART" & $uart.num & " TX")
  rx.asFunction("UART" & $uart.num & " RX")
  rx.pullUp() # So that a line nobody is driving yet reads as idle, not as noise
  uartGates[] = uartGates[] or (1'u32 shl uart.num) or (1'u32 shl (16 + uart.num))
  uart.setBaud(baud)
  uart.reg(uartFifoControl)[] = 7 # FIFOs on, and emptied

proc send*(uart: static Uart, c: char) =
  while (uart.lineStatus and roomToSend) == 0: discard
  uart.reg(uartData)[] = c.uint32

# A port's one interrupt serves a break and a buffer. Each is whatever defines
# `lutra_uart<n>_break` or `lutra_uart<n>_received`, and one nobody defines is
# left out of the link, as null.
{.emit: block:
  var (declarations, breaks, received) = ("", "", "")
  for n in 0..5:
    declarations.add "void lutra_uart$1_break(void) __attribute__((weak));\n" % $n
    declarations.add "void lutra_uart$1_received(void) __attribute__((weak));\n" % $n
    breaks.add "lutra_uart$1_break, " % $n
    received.add "lutra_uart$1_received, " % $n
  declarations & "static void (*const lutraUartBreaks[6])(void) = {" & breaks & "};\n" &
    "static void (*const lutraUartReceived[6])(void) = {" & received & "};\n".}

var
  breakHandlers {.importc: "lutraUartBreaks", nodecl.}: array[6, proc() {.cdecl.}]
  receivedHandlers {.importc: "lutraUartReceived", nodecl.}: array[6, proc() {.cdecl.}]

proc portInterrupt(uart: static Uart) =
  while true:
    case uart.reg(uartFifoControl)[] and 0xf # Why it interrupted
    of 6: # The line: reading its status clears it
      if (uart.lineStatus and lineBroken) != 0 and breakHandlers[uart.num] != nil:
        breakHandlers[uart.num]()
    of 4, 0xC: # Bytes waiting, or some, with the line gone quiet
      receivedHandlers[uart.num]()
    of 7: discard uart.reg(uartStatus)[] # Written to while busy
    else: break # Nothing more

proc breakSeen*(uart: static Uart): bool =
  ## Whether the line has been held low for longer than a byte since this was
  ## last asked, for a program that can't take the interrupt
  (uart.lineStatus and lineBroken) != 0

template listen(uart: static Uart, enabling: uint32) =
  when first("UART" & $uart.num & "'s interrupt"):
    proc handler() {.gensym, exportc: "lutra_interrupt_" & $uartSources[uart.num], cdecl.} =
      portInterrupt(uart)
    discard cast[pointer](handler) # Inside a procedure, Nim leaves out one nothing refers to
  uart.reg(uartInterruptEnable)[] = uart.reg(uartInterruptEnable)[] or enabling
  enable(uartSources[uart.num])

template onBreak*(uart: static Uart, action: untyped) =
  ## Does `action` in an interrupt when the line is held low for longer than
  ## a byte, as a host can, and as no text sent can
  once("Handling a break on UART" & $uart.num, at(instantiationInfo()))
  proc onBreak() {.gensym, exportc: "lutra_uart" & $uart.num & "_break", cdecl.} = action
  discard cast[pointer](onBreak)
  uart.listen(lineInterrupt)

# Receiving is polled, straight from the 64-byte FIFO in the hardware, unless
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
  else: (uart.lineStatus and waiting) != 0

proc receive*(uart: static Uart): char =
  const size = bufferSize(uart)
  wait uart.poll
  when size > 0: uart.ring(size)[].pop
  else: char(uart.reg(uartData)[] and 0xff)

template buffer*(uart: static Uart, size: static int) =
  ## From here on, receives through an interrupt into a buffer of `size`
  ## bytes, so the program may look away for longer than the hardware's FIFO
  ## lasts. Bytes that arrive with the buffer full are dropped.
  setBufferSize(uart, size)
  proc received() {.gensym, exportc: "lutra_uart" & $uart.num & "_received", cdecl.} =
    while (uart.lineStatus and waiting) != 0:
      discard uart.ring(size)[].push(char(uart.reg(uartData)[] and 0xff))
  discard cast[pointer](received)
  uart.listen(receivedInterrupt)
