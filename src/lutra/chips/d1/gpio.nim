import ../../claims
import registers, peripherals

template base(pin: Gpio): uint32 = gpioPorts + 0x30 * uint32(ord(pin.port) - ord('A'))
template mask(pin: Gpio): uint32 = 1'u32 shl pin.num
template data(pin: Gpio): Reg = Reg(pin.base + gpioData)

template claim*(pin: static Gpio, role: static string) =
  ## For a template that configures a pin, which makes the site the line that
  ## used that template
  claim(pin.name, role, at(instantiationInfo(-2)))

template field(pin: static Gpio, register: uint32, width: int, value: uint32) =
  ## Sets the pin's own bits in one of its port's registers
  const shift = width * pin.num
  let reg = Reg(pin.base + register + 4 * uint32(shift div 32))
  reg[] = reg[] and not (((1'u32 shl width) - 1) shl (shift mod 32)) or (uint32(value) shl (shift mod 32))

template asFunction*(pin: static Gpio, role: static string) =
  ## Gives the pin to a peripheral, for a role only certain pins can take.
  ## For the chip's own peripherals, which claim pins for themselves.
  claim(pin.name, role)
  pin.field(gpioConfig, 4, function(pin, role).uint32)

template output*(pin: static Gpio) =
  ## Drives the pin. It can still be `read`.
  pin.claim("a GPIO")
  pin.field(gpioConfig, 4, 1)

template input*(pin: static Gpio) =
  pin.claim("a GPIO")
  pin.field(gpioConfig, 4, 0)

# A port has no registers that set or clear one pin, so these read its levels
# and write them back. An interrupt handler that drives a pin of the same
# port in between would be undone, and nothing takes interrupts yet.
template high*(pin: static Gpio) = pin.data[] = pin.data[] or pin.mask
template low*(pin: static Gpio) = pin.data[] = pin.data[] and not pin.mask

template toggle*(pin: static Gpio) = pin.data[] = pin.data[] xor pin.mask

template read*(pin: static Gpio): bool =
  ## The level at the pin itself, once it is an input or an output
  (pin.data[] and pin.mask) != 0

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

# A pin's interrupt takes the pin from its output, so the self-check can't
# raise one itself as on the other chips; these wait for something that can
template attach*(event: static PinEvent, where: static string, handler: untyped) =
  {.error: "Pin interrupts are not written for the D1 yet" & where.}

template arm*(event: static PinEvent, where: static string) = discard
