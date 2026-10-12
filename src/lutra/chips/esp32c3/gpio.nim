import ../../claims
import registers, peripherals, interrupts

const
  # Fields of a pin's IO MUX register
  pullDownEnable = 1'u32 shl 7
  pullUpEnable = 1'u32 shl 8
  inputEnable = 1'u32 shl 9
  function = 7'u32 shl 12
  gpioFunction = 1'u32 shl 12

template mask(pin: Gpio): uint32 = 1'u32 shl pin.num
template mux(pin: Gpio): Reg = Reg(ioMux + 4 * pin.num.uint32)
template outSelect(pin: Gpio): Reg = Reg(gpioOutSelect + 4 * pin.num.uint32)

template claim*(pin: static Gpio, role: static string) =
  ## For a template that configures a pin, which makes the site the line that
  ## used that template
  claim("IO" & $pin.num, role, at(instantiationInfo(-2)))

template output*(pin: static Gpio) =
  ## Drives the pin. It can still be `read`.
  pin.claim("a GPIO")
  pin.mux[] = pin.mux[] and not function or gpioFunction or inputEnable
  pin.outSelect[] = 0x80 # Driven by `gpioOut` rather than a peripheral
  gpioEnableSet[] = pin.mask

template input*(pin: static Gpio) =
  pin.claim("a GPIO")
  pin.mux[] = pin.mux[] and not function or gpioFunction or inputEnable
  gpioEnableClear[] = pin.mask

template high*(pin: static Gpio) = gpioOutSet[] = pin.mask
template low*(pin: static Gpio) = gpioOutClear[] = pin.mask

template toggle*(pin: static Gpio) =
  if (gpioOut[] and pin.mask) != 0: pin.low() else: pin.high()

template read*(pin: static Gpio): bool =
  ## The level at the pin itself, whichever way it is configured
  (gpioIn[] and pin.mask) != 0

type Edge = enum rising = 1, falling, either

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

template onEdge(pin: static Gpio, edge: Edge, body: untyped) =
  once("Handling the interrupt of IO" & $pin.num, at(instantiationInfo(-2)))
  proc handler() {.exportc: "lutra_gpio_" & $pin.num, cdecl.} = body
  Reg(gpioPin + 4 * pin.num.uint32)[] = (edge.uint32 shl 7) or (1 shl 13)
  enable(gpioSource)

template onRising*(pin: static Gpio, body: untyped) =
  ## Runs `body` as an interrupt, from here on, whenever the pin goes high
  onEdge(pin, rising, body)

template onFalling*(pin: static Gpio, body: untyped) = onEdge(pin, falling, body)
template onChange*(pin: static Gpio, body: untyped) = onEdge(pin, either, body)

template pullUp*(pin: static Gpio) =
  pin.mux[] = pin.mux[] and not pullDownEnable or pullUpEnable

template pullDown*(pin: static Gpio) =
  pin.mux[] = pin.mux[] and not pullUpEnable or pullDownEnable

template noPull*(pin: static Gpio) =
  pin.mux[] = pin.mux[] and not (pullUpEnable or pullDownEnable)
