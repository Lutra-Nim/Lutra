import ../../claims
import registers, peripherals, interrupts

const
  # Fields of a pin's IO MUX register
  pullDownEnable = 1'u32 shl 7
  pullUpEnable = 1'u32 shl 8
  inputEnable = 1'u32 shl 9
  driveStrength = 3'u32 shl 10
  function = 7'u32 shl 12
  filterEnable = 1'u32 shl 15
  gpioFunction = 1'u32 shl 12

template mask(pin: Gpio): uint32 = 1'u32 shl pin.num
template mux(pin: Gpio): Reg = Reg(ioMux + 4 * pin.num.uint32)
template outSelect(pin: Gpio): Reg = Reg(gpioOutSelect + 4 * pin.num.uint32)

template claim*(pin: static Gpio, role: static string) =
  ## For a template that configures a pin, which makes the site the line that
  ## used that template
  claim("IO" & $pin.num, role, at(instantiationInfo(-2)))

template asGpio(pin: static Gpio) =
  # IO18 and IO19 start out as the pads of the chip's USB port, which holds
  # them whatever else is asked of them
  when pin.num in 18..19: usbPads[] = usbPads[] and not ((1'u32 shl 14) or (1 shl 9))
  pin.mux[] = pin.mux[] and not function or gpioFunction or inputEnable

# From here to `listen` is for the chip's own peripherals, which claim pins for
# themselves. Any peripheral signal can be routed to any pin.
template routeOut*(pin: static Gpio, signal: int) =
  pin.asGpio()
  pin.outSelect[] = signal.uint32
  gpioEnableSet[] = pin.mask

template routeIn*(pin: static Gpio, signal: int) =
  pin.asGpio()
  Reg(gpioInSelect + 4 * signal.uint32)[] = pin.num.uint32 or (1 shl 6) # Bit 6: from a pin, not fixed

template openDrain*(pin: static Gpio) =
  ## Only ever pulls the pin low, leaving a resistor to take it high: what a
  ## line that several devices drive needs
  Reg(gpioPin + 4 * pin.num.uint32)[] = Reg(gpioPin + 4 * pin.num.uint32)[] or (1 shl 2)

template drive*(pin: static Gpio) =
  pin.routeOut(0x80) # From `gpioOut` rather than a peripheral

template driveGently*(pin: static Gpio) =
  ## The weakest of the pin's four drive strengths, about 5 mA, for edges slow
  ## enough not to ring on a wire
  pin.mux[] = pin.mux[] and not driveStrength

template filter*(pin: static Gpio) =
  ## Ignores pulses on an input shorter than about 25 ns
  pin.mux[] = pin.mux[] or filterEnable

template listen*(pin: static Gpio) =
  pin.asGpio()
  gpioEnableClear[] = pin.mask

template output*(pin: static Gpio) =
  ## Drives the pin. It can still be `read`.
  pin.claim("a GPIO")
  pin.drive()

template input*(pin: static Gpio) =
  pin.claim("a GPIO")
  pin.listen()

template high*(pin: static Gpio) = gpioOutSet[] = pin.mask
template low*(pin: static Gpio) = gpioOutClear[] = pin.mask

template toggle*(pin: static Gpio) =
  if (gpioOut[] and pin.mask) != 0: pin.low() else: pin.high()

template read*(pin: static Gpio): bool =
  ## The level at the pin itself, whichever way it is configured
  (gpioIn[] and pin.mask) != 0

template pullUp*(pin: static Gpio) =
  pin.mux[] = pin.mux[] and not pullDownEnable or pullUpEnable

template pullDown*(pin: static Gpio) =
  pin.mux[] = pin.mux[] and not pullUpEnable or pullDownEnable

template noPull*(pin: static Gpio) =
  pin.mux[] = pin.mux[] and not (pullUpEnable or pullDownEnable)

type
  Edge* = enum risingEdge = 1, fallingEdge, eitherEdge
  PinEvent* = object
    ## An edge on a pin, which an `{.interrupt.}` proc can be bound to
    pin*: Gpio
    edge*: Edge

func rising*(pin: Gpio): PinEvent = PinEvent(pin: pin, edge: risingEdge)
func falling*(pin: Gpio): PinEvent = PinEvent(pin: pin, edge: fallingEdge)
func changing*(pin: Gpio): PinEvent = PinEvent(pin: pin, edge: eitherEdge)

# Pins nobody handles are left out of the link, as null entries
{.emit: block:
  var (declarations, entries) = ("", "")
  for pin in 0..21:
    declarations.add "void lutra_gpio_" & $pin & "(void) __attribute__((weak));\n"
    entries.add "lutra_gpio_" & $pin & ", "
  declarations & "static void (*const lutraPinHandlers[22])(void) = {" & entries & "};\n".}

var pinHandlers {.importc: "lutraPinHandlers", nodecl.}: array[22, proc() {.cdecl.}]

proc pinInterrupt() {.exportc: "lutra_interrupt_" & $gpioSource.line, cdecl.} =
  let pending = gpioInterrupts[]
  gpioInterruptsClear[] = pending
  for pin in 0..21:
    if (pending shr pin and 1) != 0: pinHandlers[pin]()

template attach*(event: static PinEvent, where: static string, handler: untyped) =
  ## Binds `handler` to `event`, for `arm` to switch on. `where` is the
  ## handler's line, for the message when a pin has two.
  once("Handling the interrupt of IO" & $event.pin.num, where)
  proc entry() {.gensym, exportc: "lutra_gpio_" & $event.pin.num, cdecl.} = handler()
  discard cast[pointer](entry) # Inside a procedure, Nim leaves out one nothing refers to

template arm*(event: static PinEvent) =
  Reg(gpioPin + 4 * event.pin.num.uint32)[] = (event.edge.uint32 shl 7) or (1 shl 13)
  enable(gpioSource)
