import ../../claims
import ../../arch/armv7m/interrupts
import registers, peripherals, clock

template base(pin: Gpio): uint32 = gpioPorts + 0x400 * uint32(ord(pin.port) - ord('A'))
template mask(pin: Gpio): uint32 = 1'u32 shl pin.num

template claim*(pin: static Gpio, role: static string) =
  ## For a template that configures a pin, which makes the site the line that
  ## used that template
  claim(pin.name, role, at(instantiationInfo(-2)))

template field(pin: static Gpio, register: uint32, width: int, value: uint32) =
  ## Sets the pin's own bits in one of its port's registers
  const shift = width * pin.num
  let reg = Reg(pin.base + register + 4 * uint32(shift div 32))
  switchOn(ahb2Clocks, ord(pin.port) - ord('A')) # A port takes nothing in until it has its clock
  reg[] = reg[] and not (((1'u32 shl width) - 1) shl (shift mod 32)) or (uint32(value) shl (shift mod 32))

# The next three are for the chip's own peripherals, which claim pins for
# themselves
template asFunction*(pin: static Gpio, role: static string) =
  ## Gives the pin to a peripheral, for a role only certain pins can take
  claim(pin.name, role)
  pin.field(gpioFunction, 4, function(pin, role).uint32)
  pin.field(gpioMode, 2, 2)

template drive*(pin: static Gpio) = pin.field(gpioMode, 2, 1)

template openDrain*(pin: static Gpio) =
  ## Only ever pulls the pin low, leaving a resistor to take it high: what a
  ## line that several devices drive needs
  pin.field(gpioOutputType, 1, 1)

template output*(pin: static Gpio) =
  ## Drives the pin. It can still be `read`.
  pin.claim("a GPIO")
  pin.drive()

template input*(pin: static Gpio) =
  pin.claim("a GPIO")
  pin.field(gpioMode, 2, 0)

template high*(pin: static Gpio) = Reg(pin.base + gpioSetReset)[] = pin.mask
template low*(pin: static Gpio) = Reg(pin.base + gpioSetReset)[] = pin.mask shl 16

template toggle*(pin: static Gpio) =
  if (Reg(pin.base + gpioOut)[] and pin.mask) != 0: pin.low() else: pin.high()

template read*(pin: static Gpio): bool =
  ## The level at the pin itself, once it is an input or an output
  (Reg(pin.base + gpioIn)[] and pin.mask) != 0

template pullUp*(pin: static Gpio) = pin.field(gpioPull, 2, 1)
template pullDown*(pin: static Gpio) = pin.field(gpioPull, 2, 2)
template noPull*(pin: static Gpio) = pin.field(gpioPull, 2, 0)

type
  Edge* = enum risingEdge, fallingEdge, eitherEdge
  PinEvent* = object
    ## An edge on a pin, which an `{.interrupt.}` proc can be bound to
    pin*: Gpio
    edge*: Edge

func rising*(pin: Gpio): PinEvent = PinEvent(pin: pin, edge: risingEdge)
func falling*(pin: Gpio): PinEvent = PinEvent(pin: pin, edge: fallingEdge)
func changing*(pin: Gpio): PinEvent = PinEvent(pin: pin, edge: eitherEdge)

# Pin n of every port shares one line to the interrupt controller, so only one
# of them can have a handler. Lines 0 to 4 have an interrupt each, 5 to 9 share
# one, and 10 to 15 another. Pins nobody handles are left out of the link, as
# null entries.
{.emit: block:
  var (declarations, entries) = ("", "")
  for pin in 0..15:
    declarations.add "void lutra_pin_" & $pin & "(void) __attribute__((weak));\n"
    entries.add "lutra_pin_" & $pin & ", "
  declarations & "static void (*const lutraPinHandlers[16])(void) = {" & entries & "};\n".}

var pinHandlers {.importc: "lutraPinHandlers", nodecl.}: array[16, proc() {.cdecl.}]

proc pinInterrupt*(lines: Slice[int]) =
  for line in lines:
    if (pinInterrupts[] shr line and 1) != 0:
      pinInterrupts[] = 1'u32 shl line # Writing a 1 clears it
      pinHandlers[line]()

func lines(pin: Gpio): Slice[int] =
  ## The pins whose interrupt `pin` shares
  if pin.num < 5: pin.num..pin.num elif pin.num < 10: 5..9 else: 10..15

func sharedInterrupt(pin: Gpio): int = (if pin.num < 5: 6 + pin.num elif pin.num < 10: 23 else: 40)

template attach*(event: static PinEvent, where: static string, handler: untyped) =
  ## Binds `handler` to `event`, for `arm` to switch on. `where` is the
  ## handler's line, for the message when a line has two.
  once("Handling the interrupt that pin " & $event.pin.num & " of every port shares", where)
  proc entry() {.gensym, exportc: "lutra_pin_" & $event.pin.num, cdecl.} = handler()
  discard cast[pointer](entry) # Inside a procedure, Nim leaves out one nothing refers to
  const lines = event.pin.lines
  when first("The interrupt of pins " & $lines):
    proc shared() {.gensym, exportc: "lutra_interrupt_" & $event.pin.sharedInterrupt, cdecl.} =
      pinInterrupt(lines)
    discard cast[pointer](shared)

template arm*(event: static PinEvent, where: static string) =
  const pin = event.pin
  switchOn(apb2Clocks, 0) # Of the register that picks the port
  let source = Reg(pinInterruptPorts + 4 * uint32(pin.num div 4))
  source[] = source[] and not (0xf'u32 shl (4 * (pin.num mod 4))) or
    (uint32(ord(pin.port) - ord('A')) shl (4 * (pin.num mod 4)))
  if event.edge != fallingEdge: pinRisingEdges[] = pinRisingEdges[] or pin.mask
  if event.edge != risingEdge: pinFallingEdges[] = pinFallingEdges[] or pin.mask
  pinInterruptEnable[] = pinInterruptEnable[] or pin.mask
  enable(pin.sharedInterrupt)
