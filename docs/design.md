# Lutra: a Nim-only bare-metal stack for TinyML microcontrollers

**A hardware abstraction layer and library ecosystem in pure Nim, RISC-V first, built so that running a model on a microcontroller is as approachable as blinking an LED on an Arduino.**

Status: design doc · v0.3 · October 2026 · milestones M0 to M4 are built

How to read the status of what follows:

- **Decided** means the author has settled it.
- **Proposed** means it is the current plan and has not been built or tested.
- **Verified** means it was observed on real hardware, during the ESP32-C3 port described in Appendix A, the STM32L475 port described in Appendix D, or by one of Lutra's own checks.

Someone picking the work up should read §1.2 first.

---

## 1. Summary

Lutra is a spiritual successor to [Ratel](https://github.com/PMunch/ratel). It keeps Ratel's central idea, that pins and peripherals are compile-time constants and the abstraction costs nothing at runtime, and rebuilds everything else for 32-bit microcontrollers.

Goals:

1. **Pure Nim from register definitions to application.** No vendor SDK, no C board glue. The exceptions are a linker script and, on some chips, routines in the chip's mask ROM.
2. **RISC-V first, not RISC-V only.** The ESP32-C3 is the first target. A Cortex-M board comes second, to prove the abstractions.
3. **TinyML as the reason to exist.** Lutra is the board layer underneath [Steady](https://github.com/garrettkinman/Steady), and the first-run experience is a model producing output, not a blinking LED.
4. **An ecosystem.** Sensor, actuator and utility libraries are written once against small interfaces and work on every supported board.
5. **Mistakes are compile errors.** Wiring conflicts, memory layout disagreements and missing peripherals are caught on the host, before flashing.

Non-goals:

- A real-time operating system.
- Arduino API compatibility.
- Floating-point APIs in the HAL. The first target has no floating-point unit.
- Driving a chip's built-in radio. This is deferred, not ruled out (§9).

### 1.1 Name

**Decided: Lutra**, the otter genus. It is aquatic, like the author's other project names (Krill, Rorqual). Otters are mustelids, like the ratel. It also sounds like "LUT", a look-up table.

Name collisions on the Nimble directory, GitHub and trademarks have not been checked.

### 1.2 Where things stand

Two boards are supported: the ESP32-C3-DevKitM-1, a RISC-V, and ST's B-L475E-IOT01A, a Cortex-M4. Milestones M0 to M4 of §11 are done, and §11 says what each verified. The second board has what M4's exit asked of it and no more; §7 sets the two side by side. Sampling and data capture were moved to M5, where the gesture demo will say what shape they should have.

Where to pick up: M5. Ask the author what comes first in it, and whether to merge M4 into `main` first. M4 is on the branch `feature/m4-cortex-m`. `main` has M3 on the author's machine, and on GitHub still ends at M2.

What exists, all exercised on hardware:

| Area | What |
|---|---|
| Bring-up | Startup from the boot ROM, 160 MHz, flash mapping, a linker script generated from the board's memory description |
| Pins | GPIO, pulls, edge interrupts as `pin.onFalling:` blocks, compile-time ownership |
| UART | Both ports, polled or received through an interrupt into a ring buffer, on any pins |
| SPI | Controller, and a target driven by DMA, with a ready line between them |
| I2C | Controller, on any pins. Reads and writes verified against a real sensor |
| LED | The board's addressable LED, as `rgbLed.color(green = 20)`. Its pulses are checked on the pin, and its colours were seen by eye |
| Other | Microsecond time and delays, the cycle counter, a random number source, `critical:` sections |
| Libraries | Printing without a heap, a ring buffer, durations, COBS framing with a CRC, a square root and logarithms in whole numbers, and the audio front-end a keyword-spotting model needs |
| Beside this repository | Two driver packages, both verified on the real chips: `lutra_lsm6ds33`, for an accelerometer and gyroscope, and `lutra_lis3mdl`, for a magnetometer. Each is a repository of its own (§8) |
| Host side | `build`, `flash`, `monitor`, `size` and `selfcheck` tasks, and checks that stop a build that would not run |

On the B-L475E-IOT01A, also exercised on hardware: bring-up at 80 MHz, pins and their edge interrupts, the console on USART1, I2C, time, the cycle counter, `critical:` sections and a fault report of Lutra's own (§5.5). `hello.nim` is the same program in both boards' folders of `examples/`.

How to confirm nothing is broken. Appendix C has the machine's set-up; with two boards of one kind attached, the single-board commands need `LUTRA_PORT` or `-d:port=...`. The checks run on the DevKitM-1 unless `-d:board=b_l475e_iot01a` comes before the command.

| Run | From | Proves |
|---|---|---|
| `nim r` on each `tests/t*.nim` | `tests/` | Formatting, framing, the ring buffer, claims, the memory layout, the arithmetic and the front-end, on the host |
| `nim selfcheck` | `checks/` | The board: clock, time, pins, interrupts, flash, I2C with nothing on it, the LED's pulses, no watchdog, the fault report. Takes 45 s |
| `nim steady` | `checks/` | Steady's `kws` gives checksum `ab2fdbf1` |
| `nim echo` | `checks/` | 64 KB at 921600 baud comes back intact, polled and buffered |
| `nim wiring`, then `nim link` | `checks/` | Two wired boards exchange 200 buffers over UART1 and 200 over SPI |
| `nim keywords` | `checks/` | Twelve recorded words are recognised on the board, from features that match the host's bit for bit. The first run downloads 112 MB of recordings |
| `nim sensors` | `checks/` | With the sensor board on IO18 and IO19, lying still: both chips answer through their drivers at the rates asked for, gravity is 1 g, and a refused transaction does not spoil the next |
| `nim -d:board=b_l475e_iot01a selfcheck` | `checks/` | The other board: its clock against its crystal, time, pins, interrupts, flash, I2C, no watchdog, the fault report. Takes 45 s |
| `nim -d:board=b_l475e_iot01a sensors` | `checks/` | That board's own LIS3MDL answers through the same driver, at the rate asked for, and a refused transaction does not spoil the next |
| `nim -d:board=b_l475e_iot01a steady` | `checks/` | Steady's `kws` gives `ab2fdbf1` there too |
| `nim r tlsm6ds33.nim` and `nim r tlis3mdl.nim` | `tests/` of `lutra-lsm6ds33` and `lutra-lis3mdl` | Each sensor's driver against a stand-in for the bus |

Conventions the code follows:

- **A chip is a folder of small modules.** `registers.nim` holds every address. `peripherals.nim` holds the types and instances and has to stay pure Nim, because `config.nims` imports it too. `host.nim` is the NimScript side: compiler flags, linker script, flashing, the link audit. `memory.nim` is shared by both sides.
- **A chip's `host.nim` provides `configure`, `audit`, `size`, `flash`, `checkFlasher` and `resetCommand`**, and a board provides `memory`, `console` and `consolePorts`. That is all `lutra/project` asks of them.
- **What a board must do before a program starts goes in a procedure the chip's startup calls**, `lutraBoardStart` on the STM32L475, and not at the top level of the board's module (Appendix B).
- **Interfaces own the good names.** `Pin`, `ByteLink` and `SpiDevice` are concepts in `hal/`, so the chip's own types are called something else (`Gpio`, `SpiDeviceOn`).
- **Whatever configures a pin claims it** (§5.4), and whatever a program may do only once says so with `once`.
- **A hardware fact is not relied on until a check has exercised it.** Then it goes in Appendix A or D. Register addresses so far were written from memory of the manual and confirmed that way.
- **Arithmetic that has to agree with the host names its sizes.** `int` is 32 bits on the board and 64 on the host, so `fixed` and `signal` use `int32`, `int64` and `uint64` throughout.
- **Examples stay short.** A wart is noted in the example's comment, not coded around.
- **Comments say why, briefly.** No ceremony, as in Ratel.

---

## 2. Background

| Project | Link | Relationship |
|---|---|---|
| Ratel | `github.com/PMunch/ratel` | The inspiration. Dormant for about four years. MIT licensed, so ideas and code can be borrowed with attribution. |
| Ratel fork with the C3 port | `github.com/garrettkinman/ratel`, `master` at `58a230d` | The seed code. A working ESP32-C3-DevKitM-1 board, 283 lines, verified on hardware. Files are under `src/private/boards/esp32c3devkitm1*`. |
| Steady | `github.com/garrettkinman/Steady` | Ahead-of-time TinyML compiler and runtime in Nim. Its on-target benchmark currently uses C board glue in `tests/mcu/boards/esp32c3/`. Lutra replaces that glue. |
| Krill | project doc "Krill & Reflex: Byte LLMs on ESP32-C3 Clusters" | The first demanding user. Its "Track R" called for a Ratel board package; Lutra takes that role. Krill must never block on Lutra, so Steady keeps its C path. |

### 2.1 Why not keep extending Ratel

**Decided.** The port showed how little carries over:

- Ratel's interfaces are shaped for 8-bit AVR: lettered 8-bit ports, `uint8` register helpers, `progmem`, cycle-counted delay loops, delays taking floating-point arguments.
- It has only two layers, "board" and shared "helpers". Chip startup for the C3 had to live in a board folder.
- It has no interface for UART receive, SPI, DMA, RNG or interrupts. Each would need to be designed inside a dormant upstream.
- A fixed list of built-in boards is hard-coded in `src/private/helpers.nim`.
- Every procedure in an interface module must exist or the module fails to compile, even if the program never calls it.
- The upstream README example for the Arduino Uno does not compile under Nim 2.2.
- The `ratel` command depends on the `nimscripter` package to interpret `config.nims`.

### 2.2 What to keep from Ratel

- Pins and peripherals are compile-time constants passed as `static` parameters, so calls compile to single register writes. **Verified:** on the C3, `IO4.high()` compiles to one store instruction.
- The board is chosen in the project's `config.nims`, and that choice brings compiler flags and build tasks with it.
- The terse style: small files, short comments, no ceremony.

---

## 3. Design principles

1. **The host decides everything.** Pin assignment, memory layout, clock configuration and interrupt routing are resolved at compile time. This is Steady's philosophy applied to hardware.
2. **One source of truth.** A fact such as "the weights region starts at flash offset 0x100000" is written once and everything else is generated from it.
3. **Zero cost.** An abstraction that cannot compile down to the register write it stands for does not belong in the HAL.
4. **No allocator by default.** A program that does not ask for a heap does not link one.
5. **Polled by default.** Interrupts are opt-in and declared statically. Steady's cycle counts depend on nothing firing inside a measured region.
6. **Small interfaces.** Libraries depend on a few narrow capability interfaces, never on a chip.
7. **Grow by need.** Each peripheral is added when a real program needs it, in the order Krill and the demos require. Breadth for its own sake is how HAL projects die.

---

## 4. Architecture

### 4.1 Layers

```
  applications, demos, Steady models
  ───────────────────────────────────────────────────────────
  libraries     drivers (sensors, radios), protocols, signal front-end
  ───────────────────────────────────────────────────────────
  interfaces    Pin, ByteLink, I2cBus, SpiDevice, Clock, PwmChannel, ...
  ───────────────────────────────────────────────────────────
  board         pin names, what is wired to what, flash size, console
  chip          registers, clocks, memory map, peripherals, startup
  architecture  CSRs, trap entry, context switch, critical sections
```

| Layer | Owns | Example |
|---|---|---|
| Architecture | Everything that depends only on the instruction set | `riscv32`: trap entry, interrupt enable and disable, context switch, `_start` |
| Chip | Everything that depends on the silicon | `esp32c3`: register definitions, watchdogs, clock tree, flash mapping, UART and SPI implementations |
| Board | Everything that depends on the circuit board | `esp32c3_devkitm1`: pin names as printed, 4 MB flash, console on UART0, addressable LED on GPIO8 |
| Interfaces | The contract libraries are written against | §6 |
| Libraries | Everything portable | §8 |

A new RISC-V chip reuses the architecture layer. A new board on a supported chip is one short file.

### 4.2 Repository layout

One repository and one Nimble package. Split chips into their own packages only once the interfaces have stopped moving.

```
lutra/
  src/lutra.nim              `import lutra` gives the selected board
  src/lutra/
    project.nim              the host side: `board "..."` and the tasks (§4.3)
    arch/riscv32/            start.nim, trap.nim
    arch/armv7m/             start.nim, interrupts.nim, fault.nim
    chips/esp32c3.nim        and chips/esp32c3/, one module per peripheral
    chips/stm32l475.nim      and chips/stm32l475/
    boards/esp32c3_devkitm1.nim
    boards/b_l475e_iot01a.nim
    hal/                     the interfaces: pin, bytelink, i2c, spi
    reg, claims              registers and compile-time ownership
    fmt, time, containers, framing, fixed, signal        libraries (§8)
  checks/                    hardware checks, with their tasks in config.nims
  examples/                  a folder for each board, with its own config.nims
  tests/                     host-side tests
  tools/                     empty; for the register generator
```

Which libraries live here and which are separate packages is in §8.

### 4.3 Build tooling

**Decided.** Plain `nim` tasks written in NimScript, pulled in by two lines in `config.nims`. No interpreter dependency, and no program to install.

```nim
import lutra/project
board "esp32c3_devkitm1"
```

Commands every board provides, run as `nim <command> [program.nim]`:

| Command | Does |
|---|---|
| `build` | Compile, link and check the image (§5.7). Plain `nim c` skips the checks |
| `flash` | Build, package the image and program the board |
| `monitor` | Read the console, with a reset option |
| `size` | Build, and show per-region sizes against the board's budgets |
| `selfcheck` | Build, flash and run the board's self-check, and compare the output |

The self-check command is not called `check` because `nim check` already exists.

Nim rejects flags it does not know, so options are defines placed before the command, for example `nim -d:port=/dev/ttyUSB1 flash hello.nim`. The serial port can also be named in `LUTRA_PORT`, and is found without help when only one board of the kind is attached: a board says what a host calls its console's port, `ttyUSB` for the DevKitM-1's bridge and `ttyACM` for an ST-LINK.

`-d:board=b_l475e_iot01a` builds a project for another board than its `config.nims` names. Lutra's own checks name the DevKitM-1 and serve the other board this way.

The DevKitM-1 is flashed with `esptool` and the B-L475E-IOT01A with `pyocd`, through its debug probe. Each is looked for on the `PATH`, or named in `ESPTOOL` or `PYOCD`.

Not built yet: selecting a board by MAC address, and an "all attached boards" mode. Krill flashes up to 16 boards at a time. Port names swap when boards are replugged, so the two-board checks simply take the two ports in name order.

`checks/config.nims` adds tasks that are not for every project: `steady`, `echo`, `wiring` and `link`. `selfcheck` and these only work from Lutra's repository, because `checks/` is not installed with the package.

The tasks use `sh`, `stty` and `awk`, so they run on Linux only for now.

---

## 5. Key mechanisms

### 5.1 Registers

**Proposed:** generate typed register and field definitions from the vendor's SVD file. Evaluate existing `svd2nim` work in the EmbeddedNim community before writing a generator. Generated output lives with the chip and is not hand-edited.

**Verified** access idiom, from the seed code. It compiles to a direct volatile load or store with no function call:

```nim
type
  Volatile {.importc: "volatile unsigned int", nodecl.} = uint32
  Reg* = distinct uint32

template `[]`*(reg: Reg): uint32 = cast[ptr Volatile](reg)[]
template `[]=`*(reg: Reg, value: uint32) = cast[ptr Volatile](reg)[] = value

const gpioOutSet* = Reg 0x6000_4008
gpioOutSet[] = 1'u32 shl 4
```

Do not use `std/volatile`. See Appendix B.

### 5.2 Memory layout from one description

**Proposed.** The chip and board describe memory regions once, in Nim. The linker script, the flash offsets used by `flash`, and the budgets reported by `size` are all generated from that description.

Reason: in the seed code the flash offsets appear in both `board.ld` and the upload task and must agree by hand. If they disagree the program reads plausible rubbish from the wrong part of flash instead of failing.

The description must be able to express:

- Regions for RAM code, data, flash code and flash constants.
- A constants region sized by the user. Krill wants about 3 MB of a 4 MB flash for weights.
- Reserved regions, so that space for a future second firmware image (§8.5) can be set aside now.

**Verified** for the ESP32-C3. A board declares `Memory(flashSize: 4.MB)`. The chip turns that value into the linker script when `config.nims` is evaluated, and into the offsets `flash` writes at, so `nim c` alone is a complete build. The script's file name contains a hash of its text, because Nim does not link again when only a linker script's contents change.

The description has fields for the code region's size and for a reserved region at the end of flash. There is no user-facing way to set them yet.

**Verified** for the STM32L475, where there is less to describe. Flash is read where it is, so there is one image, and `pyocd` takes its addresses from the linked file. A board declares `Memory(flashSize: 1.MB)` and that is the whole description.

### 5.3 Startup and code that runs before flash is readable

On the ESP32-C3 the core cannot read flash until a page table is written, so startup code is loaded into RAM by the boot ROM and must not touch anything in flash. Other chips have similar early-boot constraints.

- **Verified:** a build check that fails if RAM code references a flash address. The link keeps its relocations (`--emit-relocs`), and `build` reads the ones in the RAM code section. On the C3 the startup is in two parts for this: `lutraReset` in RAM, which ends by calling `lutraMain` in flash, the one reference the check allows.
- **Proposed:** a pragma, for example `{.ram.}`, that places a procedure in RAM.

The startup sequence itself is in Appendix A.

### 5.4 Compile-time ownership of pins and peripherals

**Decided:** claims are implicit and by role. Whatever configures a pin or peripheral claims it for a role, and a second claim for a different role is a compile error naming both:

```
IO21 is claimed as UART0 TX and as a GPIO at blink.nim(8)
```

- `output()` and `input()` claim a pin as a GPIO. A UART claims its TX pin when it is first sent to. A peripheral that takes pins claims each for its own role.
- Claiming again for the same role is allowed, so a pin can be reconfigured and a bus can be shared. Several devices may sit on one I2C bus. Several SPI devices may share clock and data pins, each claiming its own chip-select.
- There is no new syntax. The cost is that two pieces of code using one pin as a plain GPIO are not caught.

**Verified** mechanism: a macro, `claim(resource, role, where)` in `lutra/claims`, records claims in a `std/macrocache` table. It works across modules and inside procedures with `static` parameters.

**Decided** for I2C, the first shared bus: the bus is brought up once, with its pins, and a driver is given the bus and knows its own part's address.

```nim
const imu = lsm6ds33(i2c0)   # At 0x6A unless told otherwise

i2c0.init(sda = IO18, scl = IO19)
imu.init()
```

The bus claims its two pins. Nothing is claimed for a device, so two drivers given one address are not caught.

Not built: naming pins in an optional declaration block, and printing a wiring table from the claims.

### 5.5 Interrupts, trap entry and tasking

**Decided.** Interrupts are off unless a program asks for them. Handlers are bound at compile time, and a program writes one as a block:

```nim
bootButton.onFalling:
  led.toggle()
```

The block becomes an ordinary procedure, and the interrupt is switched on at that point in the program. A second handler for the same source is a compile error. A variable a handler shares with the rest of the program has to be declared `{.volatile.}`.

**Verified** on the C3:

- Binding is done by the linker. The chip's table of handlers refers to weak symbols, one per interrupt line and one per pin, and a handler is whatever defines the symbol. There is no table in RAM and nothing is registered at runtime.
- A program that uses no interrupts links none of this and keeps the vendor's trap vector.
- One level, no nesting: a handler runs to completion with interrupts off.
- `critical:` runs a block with interrupts off and leaves them as they were.
- A driver may own its interrupt. `uart0.buffer(4096)` receives through an interrupt into a ring buffer; without it, receiving is polled from the hardware FIFO and no interrupt exists. Which of the two a port uses is fixed at compile time.

The trap entry is the one part that is expensive to change later, so it is designed for tasking from the start:

1. **Trap entry saves the full register context on the current stack and can return onto a different stack.** This allows preemptive task switching to be added without rewriting the interrupt path. **Verified** as far as it goes: the entry passes the stack pointer to the chip's `lutraInterrupt` and resumes from the one it returns, which today is always the same.
2. **The architecture layer exposes a small context primitive:** prepare a stack, switch to it. This is per architecture, not per chip: one RV32 implementation serves every RISC-V chip. The tasking library (§8.1) is pure Nim on top of it.
3. **Every blocking wait in every driver goes through one hook.** By default the hook spins. A scheduler replaces it with a yield, and no driver changes.

Chip-specific facts that affect this on the ESP32-C3 are in Appendix A.3.

Default trap behaviour: leave the vendor's handler in place where it is useful. **Verified:** on the C3 the boot ROM's handler prints a full register dump on a fault. It then halts. It does not reset the chip.

**Decided:** once Lutra owns the vector, faults are still handed to the vendor's handler. **Verified:** Lutra's vector puts the vendor's `mtvec` back and returns to the faulting instruction with interrupts off, so it faults again into the boot ROM with every register as it was. No ROM address is hard-coded; the old `mtvec` is read when the vector is installed.

**Verified** on the STM32L475, where the core does more of this itself:

- The core reads its handlers from a table at the start of flash. The architecture layer writes the table, with a weak symbol for each of the chip's 82 interrupts, so binding is by the linker here too. A program that uses no interrupts links no handler; the table itself is 392 bytes and always there.
- The core saves the registers, so a handler is an ordinary procedure and there is no trap entry of Lutra's. Item 1 above is therefore still to do on this architecture, where a task switch belongs in the PendSV exception.
- Pin *n* of every port shares one line to the interrupt controller, so PA13 and PC13 cannot both have a handler. Asking for both stops the build: `Handling the interrupt that pin 13 of every port shares twice, at a.nim(9) and at a.nim(10)`.
- `critical:` and `pin.onFalling:` read the same as on the C3, and the self-check's test of them is the same source.

**Decided:** a Cortex-M has no vendor's handler to report a fault, so Lutra has a short one of its own in the architecture layer, which a board points at its console:

```
Fault: undefined instruction at 0x08000b66
       last call from 0x080004c6
```

It names an undefined instruction, a bad address (with the address, when the core knows it) and a jump to a bad address, and calls anything else unknown. The second line is the link register: where the last call made before the fault will return to. Then it halts. **Verified** with one of each, and with a fault inside an interrupt handler. The C3 keeps the boot ROM's report.

Not done: the trap vector and entry are in flash, so an interrupt can wait on a cache miss. Moving them to RAM needs the check in §5.3 to tell startup code from other RAM code.

### 5.6 Memory model

**Decided:** no allocator unless requested.

**Verified** complication: with `--mm:arc`, Nim's runtime keeps `malloc`, `free` and `exit` reachable even for a program that never allocates, about 1.4 KB. Steady builds with `--mm:none --panics:on` and links no allocator. Lutra's default configuration does the same, and also builds with `-d:danger`. **Verified:** no allocator symbols are linked into the hello-world or the Steady benchmark. The heap opt-in is not built yet. Neither is a panic handler, which is what building without `-d:danger` is waiting on.

Consequence: the core needs allocation-free formatting and fixed-size containers (§8.1), because `string` and `seq` are not available by default.

### 5.7 Build checks

Each of these was done by hand during the port. `build`, and so `flash`, `size` and `selfcheck`, now does them. Plain `nim c` does not.

| Check | How |
|---|---|
| RAM code does not reference flash | **Verified.** Read from the relocations (§5.3) |
| No orphan sections appear in the link | **Verified.** Any section with an address that the linker script does not name stops the build |
| Constant data is in flash, not RAM | Follows from the two above: the linker script sends every read-only section to flash, and nothing can be placed outside the script. A table declared `let` or `var` is not constant data and still goes to RAM |
| No allocator symbols are linked unless the heap was requested | **Verified**, by the linker. Without the heap opt-in, a program that allocates fails to link, with an undefined reference to `end`. The message is unfriendly |
| Image regions do not overlap | The linker enforces each region's length, and `flash` stops if the RAM-loaded image is larger than its 64K page |

On the STM32L475 nothing runs before flash can be read, so the first check has nothing to do. **Verified** there: a section the linker script does not name stops the build, and a program that allocates fails to link, for want of `end` as on the C3.

### 5.8 Hardware self-check

Every board ships a self-check program and the expected output. `check` runs it. The check used for the C3 port covers:

- core clock frequency measured against an independent timer
- delay and millisecond accuracy
- GPIO output, input, read-back and pull-up
- a large constant table spanning several flash pages, checksummed
- heap allocation, when enabled
- a long idle run to prove no watchdog fires
- a deliberate fault, to confirm the trap report

A port is accepted when its self-check passes and Steady's benchmark gives the reference checksum (§10).

**Verified** on the DevKitM-1: everything in the list except heap allocation, plus the GPIO pull-down. The idle run is 30 seconds. The check runs once and ends in the fault, so the `selfcheck` command resets the board and reads from the first byte.

**Verified** on the B-L475E-IOT01A: the same list, in a program of its own, `checks/b_l475e_iot01a.nim`. The clock is measured against the board's 32.768 kHz crystal, and the fault is reported by Lutra. A fault's report ends in an address, so the command accepts a last line that goes on past what was expected.

---

## 6. The driver contract

Libraries are written against these interfaces and nothing else. This contract is the most important thing to get right, because changing it later breaks every driver.

**Decided:** each interface is a Nim concept in `src/lutra/hal/`, and a library takes one as a `static` parameter:

```nim
type ByteSink* = concept
  proc send(sink: Self, c: char)

proc put*(sink: static ByteSink, c: char) =
  mixin send
  sink.send(c)
```

**Verified:** peripherals stay compile-time constants, the code is the same as without the concept, and a wrong argument is reported at the caller's line and names the interface. Concepts match the chip's templates and procedures that take `static` parameters. A library has to declare the operations it calls with `mixin`, or it compiles for the target and not on the host (Appendix B).

An interface is added when a chip implements it. So far:

| Interface | Operations | Used by |
|---|---|---|
| `Pin` | output, input, high, low, toggle, read, pullUp, pullDown, noPull | The self-check |
| `ByteSink` | send | Printing. Split from ByteLink so that printing can target things that cannot receive |
| `ByteLink` | send, poll, receive | Framing |
| `SpiDevice` | transfer | The link check |
| `I2cBus` | write, read, writeRead, each to an address, and each false if the device did not acknowledge | `lutra_lsm6ds33`, `lutra_lis3mdl` |

The chip's own types need different names from the interfaces, so the C3's pin type is `Gpio` and a device on its SPI bus is made with `spi2.device(select = IO10)`.

**Verified** on two architectures: `Pin`, `ByteSink`, `ByteLink` and `I2cBus` are implemented by both chips. Printing, the self-check's pin test and `lutra_lis3mdl` are the same source on both. `SpiDevice` still has one implementation.

On the STM32L475 a peripheral's signal can come out on a few pins only, where the C3 can route any signal to any pin. A bus is brought up the same way, and the wrong pin stops the build: `PB9 cannot be I2C2 SDA. It can be PB11 or PB14.`

**Verified** from outside this repository: `lutra_lsm6ds33` and `lutra_lis3mdl` each import `lutra/hal/i2c` and nothing else of Lutra. A driver there is an object that holds its bus, and its procedures take that object as a `static` parameter:

```nim
type Lis3mdl*[B] = object
  bus*: B
  address*: byte

proc ready*[B: I2cBus](sensor: static Lis3mdl[B]): bool =
  mixin writeRead
  ...
```

This builds for the board and passes on the host against a stand-in bus. Given something that is not a bus, the compiler says only that the procedure does not exist for that type.

Edge interrupts, UART set-up and the SPI target are not behind interfaces yet. They are called on the chip's types directly.

**Proposed** set. Operation names are indicative.

| Interface | Operations | Notes |
|---|---|---|
| Pin | output, input, high, low, read, pull-up, pull-down | Interrupt on edge is a separate capability |
| ByteLink | send, receive, poll | UART, and later USB serial. This is Steady's link contract (§10) |
| I2cBus | write, read, write-then-read, to an address | Shareable |
| SpiDevice | transfer | Owns a chip-select on a shared bus |
| Clock | now, delay, deadline | Monotonic, integer units |
| CycleCounter | cycles | For measurement |
| PwmChannel | set duty, set frequency | |
| AdcChannel | read | |
| Console | print | Where diagnostics go |
| PacketRadio | send frame, receive frame | LoRa, ESP-NOW |
| Socket | connect, send, receive, close | May be implemented by an external module (§9) |

Rules:

- **A missing capability is an error only where it is used.** A board without I2C still compiles programs that do not use I2C.
- **DMA is not an interface.** It is how a chip's SPI, UART or I2S implementation chooses to move a buffer.
- **Prove the contract on two architectures before inviting third-party libraries.**

---

## 7. HAL features

| Tier | Features | Reason |
|---|---|---|
| Core, every chip | Startup, clocks, memory layout; GPIO; UART transmit and receive; monotonic time, delays, cycle counter; interrupts and critical sections; console, panic and trap report; watchdog; reset reason; sleep | Nothing works without these |
| Buses | I2C controller; SPI controller and target; DMA behind them | Krill needs SPI target with DMA; most sensors use I2C or SPI |
| Timing and analog | PWM; ADC; pulse capture; addressable-LED output | Actuators, analog sensors, and the DevKitM-1's own LED |
| TinyML inputs | I2S; hardware RNG; raw flash storage | Microphones, sampling, weights and recorded data |
| Later | USB device; I2C target; low-power modes; SPI cameras | Useful, not blocking |

State of Lutra against this table, on the ESP32-C3:

| Tier | Verified | Not written |
|---|---|---|
| Core | Startup, clock, memory layout, GPIO, UART both ways, time, delays, cycle counter, interrupts, critical sections, console, watchdogs off | A panic handler, a trap report of Lutra's own, reset reason, sleep, feeding a watchdog on purpose |
| Buses | SPI controller, SPI target with DMA, I2C controller | DMA for the SPI controller; I2C target |
| Timing and analog | Addressable LED | PWM, ADC, pulse capture |
| TinyML inputs | Hardware RNG | I2S, raw flash storage |

And on the STM32L475, which has what M4's exit needed:

| Tier | Verified | Not written |
|---|---|---|
| Core | Startup, clock, memory layout, GPIO, USART1 both ways, time, delays, cycle counter, interrupts, critical sections, console, a fault report | Receive through an interrupt, a second UART, a panic handler, reset reason, sleep, a watchdog |
| Buses | I2C controller | SPI, DMA, I2C target |
| Timing and analog | | PWM, ADC, pulse capture |
| TinyML inputs | | Hardware RNG, which wants a 48 MHz clock started for it; I2S; raw flash storage |

---

## 8. Libraries

**Decided** rule for placement, October 2026:

| Lives in | What | Examples |
|---|---|---|
| `lutra` itself, as `lutra/<name>` | Anything written only against the `hal/` interfaces, with no specific part number in it | Everything in §8.1; framing, the signal front-end, the sampling pipeline, the AT command engine, the settings store |
| Its own package, `lutra_<part>` | Anything tied to one external chip or module, or maintained by someone else | `lutra_lsm6ds33`, an SX126x LoRa driver, a driver for one cellular modem |

- Nim compiles only what a program imports, so a bundled library costs nothing in the image. What it costs is sharing Lutra's version: a breaking change in one bundled library is a breaking release of all.
- First-party drivers are separate packages from the start, to prove the interfaces can be used from outside this repository. The first two are for the chips on the author's sensor board: `lutra_lsm6ds33`, at `github.com/garrettkinman/Lutra-LSM6DS33`, and `lutra_lis3mdl`, at `github.com/garrettkinman/Lutra-LIS3MDL`. Each covers starting its sensor and reading it. Until Lutra can be installed as a package, their examples find Lutra as a checkout beside them, in a folder named `lutra`, and `nim sensors` finds them the same way, in `lutra-lsm6ds33` and `lutra-lis3mdl`.
- How settled a module is belongs in its documentation, not in where it lives.

The earlier rule was narrower: only what every other library must agree on was core, and everything in §8.2 to §8.4 was a separate package.

Written so far: printing (`fmt`), durations (`time`), a ring buffer (`containers`), framing (`framing`), a square root and logarithms (`fixed`) and the audio front-end (`signal`).

### 8.1 Core

| Library | Contents | Reason |
|---|---|---|
| Printing and logging | Allocation-free formatting of integers, hex and fixed-point; log levels | Every program needs output and there is no heap by default. Steady's benchmark hand-rolls this today |
| Fixed-size containers | Ring buffer, queue, bounded string; safe between an interrupt and main code | UART receive, AT commands, sensor streams |
| Time | Durations, deadlines, timeouts, periodic timers | Every driver and protocol waits on something |
| Fixed-point math | Q-format arithmetic; table-based `sin`, `exp`, `sqrt` | No floating-point unit on the C3 |
| Tasking | Cooperative tasks with statically sized stacks; signals from interrupts | Lets "sample, infer, transmit" be written as straight-line code |

Tasking uses stackful tasks, not Nim's closure iterators. Closure iterators need no assembly but allocate on the heap.

### 8.2 TinyML

| Library | Contents | Reason |
|---|---|---|
| Signal front-end | Windowing, fixed-point FFT, mel features | A model needs the same preprocessing it was trained with. The code must give bit-identical results on the host and on the device |
| Sampling pipeline | Fixed-rate capture into windows, handed to a model | The glue from sensor to Steady |
| Data capture | Device library and a host tool that records sensor data to files | Users need data from their own sensor before they can train |
| Starter drivers | One accelerometer, one I2S microphone, one environmental sensor, the addressable LED | They power the demos and are the template for third-party drivers. The accelerometer is done first, as `lutra_lsm6ds33` (§11, M3) |

### 8.3 Connectivity

| Library | Contents | Reason |
|---|---|---|
| Framed serial link | Packet framing with a checksum over a ByteLink | Data capture, host tools, and Krill's links between chips |
| AT command engine | Send a command, parse replies, handle unsolicited messages | Covers cellular modules, LoRaWAN modules, and Wi-Fi and BLE through a second ESP32 |
| Sockets and MQTT | The Socket interface and a small MQTT client | What most IoT backends expect |
| LoRa driver | Raw packets on a Semtech SX126x or SX127x over SPI | Small, pure Nim, needs no network infrastructure |

### 8.4 System

| Library | Contents | Reason |
|---|---|---|
| Settings store | Key-value storage in flash | Credentials and calibration |
| Measurement | Cycle and energy measurement helpers, taken from Steady's benchmark | Users will want the numbers |

### 8.5 Deliberately later

- **Over-the-air updates.** They need a bootloader and a second image slot. The only action now is to reserve space in the memory description (§5.2).
- **Low-power helpers.** Wanted soon after the first release; the battery demo depends on them.
- **Displays, cameras, a full IP stack.**

---

## 9. Wireless

**Decided:** target radios that are separate modules. Defer the chip's own radio.

| Technology | Form | What Lutra needs |
|---|---|---|
| LoRa, raw packets | SPI transceiver | The LoRa driver |
| LoRaWAN | Module with the stack built in, AT commands over UART | AT engine and a module driver |
| NB-IoT, LTE-M | Cellular module, AT commands over UART; the module runs TCP, TLS and often MQTT | AT engine and a module driver |
| Wi-Fi and BLE | A second ESP32 running Espressif's stock AT firmware | AT engine and a module driver |

Design consequences:

- The Socket interface must allow the module to run the network stack. No IP stack or TLS on the microcontroller at first.
- Two network interfaces, PacketRadio and Socket, so an MQTT library works over Wi-Fi or cellular unchanged.

For TinyML the cost of a second chip is acceptable: inference happens on the device and the radio carries only small results.

### 9.1 The chip's own radio

The ESP32-C3's Wi-Fi, BLE and ESP-NOW are driven by Espressif's closed binary libraries, which expect operating-system services. The Rust project `esp-hal` shows it can be done without esp-idf. Lutra would need preemptive tasking, a heap, timers, queues, semaphores, radio calibration, and an IP stack for Wi-Fi. The binaries change between vendor releases, so the maintenance is continuous.

Nothing in the design should prevent this. The trap entry in §5.5 is the main thing that keeps it possible.

Unchecked: the current state of Espressif's AT firmware for the C3. Confirm before building on it.

---

## 10. Steady integration

Steady stays independent of Lutra. Steady defines a minimal board contract and Lutra implements it:

| Steady needs | Lutra provides |
|---|---|
| Write a character to the console | ByteLink send on the console |
| A 32-bit cycle counter and its frequency | CycleCounter, and the board's clock constant |
| Link send, receive, poll (for Krill) | ByteLink on UART or SPI |
| Weights in flash | Constants are placed in the flash constants region by the linker script |
| No allocator | The default memory model |

**Verified** on the seed code: Steady's `kws` benchmark, with its ten `board_*` entry points implemented in Nim on top of the Ratel port, gives output checksum `ab2fdbf1`, identical to the C build. Whole-model cycles were 44.40M against 45.15M for the C build. The C figure came from an older build of Steady, so part of that difference may be changes in Steady itself. Weights were in flash at `0x3C10xxxx` and no allocator symbols were linked. The adapter was about 20 lines.

**Verified** on Lutra: the same benchmark, run with `nim steady` in `checks/`, gives `ab2fdbf1` and 44.40M cycles, with weights in flash and no allocator symbols. Later changes to Lutra moved code about and the count became 44.26M; with Steady at `a9a2f44` it is 43.49M. The other five models have not been run.

**Verified** on the B-L475E-IOT01A: `nim -d:board=b_l475e_iot01a steady` gives `ab2fdbf1` and 41.65M cycles, with the prefetch and both of the chip's flash caches on. Steady's C path gave 43.32M at the same setting, from an older build of Steady. The C3 gave 43.64M the same day. The adapter is `checks/steady.nim` for both, with the chip's timebase, cache and LED chosen at the top.

Acceptance test for every board port: all six of Steady's reference models give the reference checksums, with cycle counts comparable to the C path.

---

## 11. Roadmap

Each milestone ends with an exit criterion.

### M0: Skeleton and seed

Done, October 2026.

- Repository, layout and build tasks (`build`, `flash`, `monitor`, `size`, `selfcheck`).
- Move the C3 seed code into the architecture, chip and board layers.
- Memory description generating the linker script and flash offsets.
- The self-check program.
- **Exit:** the self-check passes on the DevKitM-1, and Steady's `kws` benchmark gives `ab2fdbf1` on Lutra.

### M1: Core contract

Done, October 2026, as far as the exit criterion. Of the three libraries, only what something needed exists: printing without log levels, a ring buffer, and durations with `delay`. Deadlines, timeouts, a queue and a bounded string are still to write.

- Trap entry designed per §5.5; interrupts; critical sections.
- UART receive with a ring buffer; GPIO interrupts.
- Compile-time ownership.
- Printing, containers and time libraries.
- Build checks from §5.7.
- **Exit:** a UART echo test at high baud loses no bytes; a double pin claim fails to compile with a clear message; the default configuration links no allocator.

### M2: What Krill needs

Done, October 2026.

- SPI controller and target with DMA; hardware RNG; UART1.
- Framed serial link.
- Steady's link contract implemented.
- **Exit:** two boards exchange checksummed buffers over UART and over SPI. **Decided:** Krill's Phase 0 test (a dummy model split across two chips) is no longer part of this exit. It needs Send and Recv ops and a multi-board harness in Steady, which do not exist yet, and should then run on this with no change to Lutra.

**Verified** by `nim link` in `checks/`, on two DevKitM-1 boards joined by jumper wires: 200 exchanges of 1 to 2000 bytes each way over UART1 at 921600 baud, then 200 full-duplex exchanges of the same sizes over SPI at 10 MHz, every buffer checked against a known pattern and its CRC on both boards. `nim wiring` checks the wires first and names any that is missing or crossed.

| Piece | State |
|---|---|
| UART1 on any two pins | Verified |
| Hardware RNG | Verified to change between reads. Its entropy was not assessed |
| Framed serial link (`lutra/framing`) | Verified on the host and between boards |
| SPI controller | Verified. It moves 64 bytes at a time through the bus's own buffer, with chip-select held low, and does not use DMA |
| SPI target | Verified. It uses DMA, so a transfer can be any length up to 4092 bytes |
| `SpiDevice` interface | In `hal/`; the link check's controller side goes through it |

**Decided** for the links:

- Framing is COBS with a CRC-16, and a zero on both sides of each packet. A receiver is back in step at the next zero, noise between packets cannot damage the next packet, and zeros with nothing between them are skipped.
- Over SPI a target raises a "ready" wire while it has a transfer armed. The controller waits for it to rise before a transfer and to fall after, so it never clocks a target that is not listening.

**Verified** findings that shaped the drivers:

- **A board that resets disturbs its neighbour's lines.** A UART receiver hears stray bytes, mostly zeros, and an SPI target sees chip-select dip with no clock. So UART receive pins are pulled up, the framing skips empty packets, and a target ignores a transfer of no bytes.
- **SPI needs gentle edges and a filtered clock.** At the pins' default drive strength a target counts clock edges twice on jumper wires and every transfer is garbage. With the controller's pins at their weakest drive about one edge in tens of thousands is still miscounted. Adding the chip's glitch filter to the target's clock input makes it clean. Lutra sets both.
- **10 MHz is the fastest that works this way.** 16 and 20 MHz fail completely. Going faster probably needs the bus's own pins instead of the GPIO matrix, and a board instead of jumper wires. Not tried.
- **Lengths must agree.** If the controller clocks more bytes than the target armed, the target's count and its next transfer were wrong in testing. Not investigated further.

The two boards are wired pin to pin, except UART1, which crosses: IO0 to IO1 and IO1 to IO0, then IO3 (ready), IO5 (data into the controller), IO6 (clock), IO7 (data out of the controller), IO10 (chip-select) and ground.

### M3: First TinyML demo

Done, October 2026, on the reshaped exit below. "Left over" at the end is what it did not do.

- I2C, I2S, ADC, PWM, addressable LED.
- Fixed-point math, signal front-end, sampling pipeline, data capture.
- Starter drivers.
- **Exit:** keyword spotting runs end to end from microphone to LED, and the front-end is bit-identical between host and device.

**Decided:** the author has no microphone, so the exit is reshaped. Keyword spotting runs end to end from recorded speech held in flash to the LED, with the front-end bit-identical between host and device; and an I2C sensor is read through a driver in a package of its own. I2S waits for a microphone. ADC and PWM wait until something needs them.

What the author has on hand: no microphone and no multimeter; a soldering iron and a small portable oscilloscope; Adafruit's LSM6DS33 + LIS3MDL breakout, product 4485, which is an accelerometer and gyroscope at 0x6A and a magnetometer at 0x1C; and two DevKitM-1 boards wired together for M2, which uses IO0, IO1, IO3, IO5, IO6, IO7 and IO10 on both. Of the rest, IO18 and IO19 are for the sensor board, the self-check needs IO4 unconnected, IO8 is the LED, and IO2, IO8 and IO9 are strapping pins.

**Verified** by `nim keywords` in `checks/`. Twelve one-second clips from the Speech Commands test set, one for each word the model knows, are held in flash. Each goes through `lutra/signal` and Steady's `kws` model, on the host and then on the board. The board recognises all twelve, and its 490 features for each clip have the same checksum as the host's. A clip takes the board 184 ms for the features and 277 ms for the model.

**Verified** on the host by `nim -d:testset keywords`: of the 4890 clips in that test set, 4483 are recognised, 91.68%. This is the evidence that the front-end computes what the model was trained on. MLPerf Tiny's quality target for this model is 90%, quoted from memory.

| Piece | State |
|---|---|
| Arithmetic (`lutra/fixed`) | A square root and base-2 and natural logarithms of 64-bit whole numbers. Verified on the host against floating point |
| Front-end (`lutra/signal`) | Mel-frequency cepstral coefficients of one frame. Verified on the host against the same sums in floating point, and on the board against the host |
| Keyword spotting on recorded clips | Verified, as above |
| I2C controller | Verified, by the self-check with nothing attached and by `nim sensors` with the sensor board. With nothing attached: an address nobody has is refused in 110 µs at 100 kHz, a held line is given up on, and the bus works again afterwards. With the sensor board: 2000 of 2000 addresses acknowledged, a register written and read back 500 times of 500, reads of 1, 6, 12 and 16 bytes, and the transaction after a refused one working 800 times of 800 |
| `I2cBus` interface, `lutra_lsm6ds33` | Verified on the real chip, through the package's own example: 26.4 readings a second where 26 were asked for, and flat on a table −7, 11, 1023 thousandths of g with noise of 2 to 3. It starts cleanly 10 times of 10. The gyroscope reads a steady few degrees a second at rest, which is its usual offset; its scale has not been checked by turning it |
| `lutra_lis3mdl` | Verified on the real chip, through the package's own example: 10.5 readings a second where 10 were asked for, starting cleanly 6 times of 6, and a steady field of about 700 thousandths of a gauss with noise of 3 to 5. One axis moved by 400 when a scope probe was clipped on nearby; nobody has tried a magnet. Run together on the one bus, the two drivers gave 80.6 fields and 99.8 accelerations a second where 80 and 104 were asked for |
| IO18 and IO19 as ordinary pins | Verified |
| Addressable LED | Verified. The 24 pulses are checked on the pin, and the DevKitM-1's `rgb.nim` in `examples/` shows red, green and blue in that order |
| Sampling pipeline, data capture | Not written. Moved to M5 |
| I2S, ADC, PWM | Not written, as decided |

**Decided** along the way:

- How an I2C device is declared (§5.4), and the `I2cBus` interface (§6).
- The placement rule for libraries (§8), with `lutra_lsm6ds33` and `lutra_lis3mdl` as the first separate packages. A driver for the LIS3DH was written first, on the belief that the author's sensor was one, and deleted when it turned out not to be: nothing here could have tested it. The author's Ratel library, `ratel-lis3dhtr`, is for that other part.
- A reading is `(x, y, z)` in thousandths of the part's own unit: of g, of a degree a second, of a gauss.
- A front-end is described once, as a constant, and its tables are worked out when the program is compiled:

```nim
const mfcc = Mfcc(sampleRate: 16000, window: 480, melBins: 40, lowHz: 20, highHz: 4000, coefficients: 10)
mfcc.compute(samples, coefficients, fullScale = peak)
```

  It computes what `tf.signal` does with its defaults: a periodic Hann window, the magnitude of a Fourier transform zero-padded to a power of two, triangular bands evenly spaced in mel, the natural logarithm of each band plus a floor, and a cosine transform. Coefficients come back with 16 fractional bits. Cutting sound into frames and scaling coefficients to a model's input are left to the caller, since models differ in both.

**Verified** findings that shaped the front-end:

- **The training code scales each clip by its highest sample.** That needs no division. A band's logarithm is taken of the unscaled sum, with the floor scaled up instead, and the logarithm of the highest sample is subtracted. `fullScale` is that parameter.
- **The window needs more than 15 bits.** Rounded to 15, under a loud tone, it added as much noise to the quiet bands as the 16-bit samples themselves carry. It is held in 31.
- **Magnitudes have to be rounded to the nearest.** Rounded down, the bias showed in bands holding little.
- **What is left is a noise floor.** A band is good to about a hundred-thousandth of the loudest thing in its frame. Recorded sound has more noise than that in every band. A pure tone does not, and against floating point its coefficients can be out by 0.2, a third of one step of the model's input.
- **The model's input is 0.5847 a step from 83, rounded towards zero.** The training code does this in floating point and lets a value past the ends wrap round. `checks/keywords.nim` holds it at the ends instead. The two numbers are written there by hand, because Steady's generated code does not carry them.
- **Binary data goes in as numbers.** The clips were first held as the strings `staticRead` gives, and going through an array of strings allocates (Appendix B).

**Verified** findings that shaped the I2C driver, the first three with no device attached and the last two with the sensor board:

- **A device that does not acknowledge costs nothing.** The bus sends the stop itself and reports the transaction complete, with a flag to say it was refused.
- **The bus's own timeouts are not enough.** With the clock line held low one of them fires. With the data line held low, a second attempt hangs with nothing raised at all. So a transaction has a deadline, of 50 ms and a millisecond a byte, after which the bus's state machine is reset. It works again as soon as the line is let go.
- **A line can be held low from the board itself**, by pointing the pin back at the GPIO output register. The self-check does that.
- **A reset of this chip in the middle of a read leaves the sensor holding the data line low.** It is still part-way through a byte. A quarter of resets did, with a program that read without pause, and every transaction after failed. So `init` clocks the bus by hand until the line is let go, and sends a stop, before the bus takes the pins: after that, 16 starts of 16 worked, 4 of them from a held line.
- **A refused transaction of more than an address poisons the next.** The controller has already taken the byte after the address, and sends it as the address of whatever comes next; that one fails too, and so on until the leftovers happen to run out. Resetting its FIFOs does not clear it, and nor does resetting its state machine, waiting, or both: the next read worked 0 times of 20 after each. Resetting the whole peripheral and putting its eight timing registers back does: 20 of 20, and then 800 of 800 in the driver, which now does that after any transaction that fails. Before this was found it sent stray writes to both chips on the sensor board, which is the likeliest reason the accelerometer spent an afternoon with its settings scrambled, reading 1.15 g on every axis until its power was cycled.

**Verified** about the author's sensor board, Adafruit's LSM6DS33 + LIS3MDL breakout, wired VIN to 3V3, GND to ground, SDA to IO18 and SCL to IO19 on the DevKitM-1 with MAC `7c:df:a1:59:c9:70`:

- **Its header had to be soldered.** Loose in its holes, nothing answered, and a test with the pins' weak pull-downs showed why: the breakout's pull-up resistors were not reaching the pins.
- **Its ADM pin has to be wired to ground.** Left alone, the magnetometer was at 0x1E whenever it had a measurement waiting and at 0x1C whenever it had not, in step with its own sampling: its address pin was following its data-ready pin, which is its neighbour both on the chip and on the board's four-hole row. Adafruit's design files (`github.com/adafruit/Adafruit-LSM6DS33-LIS3MDL-PCB`) give ADM a 10 kΩ resistor to ground, which on this board is evidently not doing its job. A scope across the two pins with the power off showed pickup, where a short would have shown nothing, and with the scope's ground clip left on ADM the address held still. A wire from ADM to GND holds it at 0x1C: 2000 of 2000 in every state.

Left over:

- **Sampling and data capture.** **Decided:** they wait for M5. Nothing yet says what shape they should have: a window of samples handed to a model wants designing against the gesture model of the demos, which does not exist. Until then a sensor is sampled at its own rate with `imu.ready`, and `nim monitor > file.csv` records what a program prints.
- **Ask Steady for a model's input scale and zero point** in its generated code, so that `checks/keywords.nim` need not repeat them.
- **Two scales nobody has checked.** The gyroscope's, which wants the board turned at a known rate, and the magnetometer's, which read about 700 thousandths of a gauss where the Earth's field alone is 250 to 650. A magnet brought near would at least show it responds.

### M4: Second architecture

Done, October 2026.

- One Cortex-M board through the same interfaces. Steady already targets the STM32L475 and SAMD51.
- **Exit:** the self-check, one sensor driver and the Steady benchmark run with no changes to library code.

**Decided:**

- The board is ST's B-L475E-IOT01A. Its ST-LINK gives flashing, reset and a console over one cable, and it carries a LIS3MDL of its own. The ItsyBitsy M4 has neither a probe nor a USB bridge, so even printing would have wanted a USB device written first.
- The port has what the exit needs and no more (§7).
- A fault gets a short report of Lutra's own (§5.5).
- The board's name in `config.nims` is `b_l475e_iot01a`, ST's name for it as printed.
- `examples/` has a folder for each board, each with its own `config.nims`, so that every example is true to its board's hardware and runs with no option. Sharing names such as `led` and `button` between boards was the alternative, and the DevKitM-1 has no plain LED of its own to give the name to. `hello.nim` is in both folders, and `blink.nim` and `button.nim` are near-copies. The DevKitM-1's `button.nim` now steps its own LED through red, green and blue, so neither board's examples need anything wired but the DevKitM-1's `blink.nim`. **Verified:** all seven build, and the author has seen the DevKitM-1's button change its LED's colour.

**Verified** on the board, with ST-LINK serial `066CFF3736324D5043223947`:

| Piece | State |
|---|---|
| Bring-up | The DevKitM-1's `hello.nim`, unchanged, prints at 115200 baud: 2812 bytes of flash, 392 of them the table of vectors, and no RAM |
| Self-check | Passes (§5.8) |
| A sensor driver, unchanged | `lutra_lis3mdl` reads the board's own LIS3MDL, at 0x1E on I2C2, through `nim sensors`: it answers, 200 starts of 200 each after a refused transaction, readings within a tenth of the 80 a second asked for, and a field between 0.1 and 2 gauss |
| Steady's benchmark | `ab2fdbf1`, 41.65M cycles (§10) |
| Mistakes as compile errors | A pin claimed twice, a pin that cannot carry a signal, and two handlers on one interrupt line each stop the build with a message (§5.5, §6) |
| Library code | `fmt`, `time`, `containers`, `framing`, `fixed`, `signal`, `hal/` and both driver packages are as they were. `claims` gained `first`, which says whether the program has come to something before |

What changed outside the new architecture, chip and board:

- **`lutra/project`.** `-d:board=...`; a board's `consolePorts`; reading a console drops what was sent before the port was opened; `selfcheck` accepts a last line that goes on (§4.3, §5.8).
- **A fix to the C3.** Two pin handlers in one program did not compile, with "redefinition of 'handler'", and nor would two buffered UARTs have. Nothing had tried. The procedures a template declares for them are now its own each time (Appendix B). **Verified:** a program with two handlers builds, and `nim echo` passes both ways.
- **`checks/sensors.nim` and `checks/steady.nim`** serve both boards, choosing at the top by what the board declares. On the C3 the refusal test now restarts the magnetometer, not the accelerometer, so that it is the same on both.

**Verified** findings that shaped the port. The facts themselves are in Appendix D.

- **A port of pins takes nothing in until it has its clock.** The console's transmit pin was given its function before port B's clock was on, the write was lost, and nothing came out. Every write to a pin's settings now switches its port's clock on first.
- **The board has to bring its console up.** Nothing has before a program starts, where the C3's boot ROM has. Doing it at the top level of the board's module cost every program 1 KB of RAM and 1.4 KB of flash (Appendix B), so the chip's startup calls the board's `lutraBoardStart` before the program.
- **Time is two timers in a chain.** Timer 2 counts cycles of the core's clock and comes round every 54 seconds. Timer 5 counts each time it does, which makes 64 bits with no interrupt. Forced to come round 200,000 times while being read, the pair never went backwards, and the high half was never seen behind the low. `micros()` takes 148 cycles, most of them a 64-bit division. Steady's notes are why it is timer 2 and not the core's own cycle counter, which stops when no debugger is attached.
- **The clock is 0.18% fast.** It comes from the chip's own oscillator, multiplied up, and measured 80.14 MHz against the board's crystal, steady to 0.02%. Nothing corrects it, so time on this board runs that much fast. The chip can trim the oscillator against the crystal by itself; that is not switched on.
- **The UART holds one received byte.** Left to itself it stops receiving for good once a byte arrives with the last unread: after eight bytes sent to a program that was looking away, it echoed the first and never another. It is now told to keep the newest instead, and goes on receiving. Read without pause it echoed 36 bytes sent together.
- **A refused I2C transaction is cleared by switching the bus off and on.** That also gives up on a held line, at the driver's deadline. Nobody at an address is found in 116 µs, and a byte takes 93 µs: 97 kHz where 100 was asked for.
- **An ST-LINK keeps what a board printed until the port is opened.** The self-check's first lines arrived twice, once from before the reset.
- **`print` works its arguments out as it goes.** A time taken in a later argument includes printing the earlier ones, which made a 110 µs transaction look like 1.4 ms. True on the C3 too.

Left over:

1. **What the two chips' host sides repeat.** Each `host.nim` has its own copy of reading a linked file's sections, naming a linker script after its contents and printing sizes, about twenty lines, and each `memory.nim` its own `KB` and `MB`. Left alone until a third chip shows what is really common. The author has not said.
2. **Nobody has looked at the board.** `led2` is driven by Steady's benchmark and read back by a test, and `userButton` reads high when not pressed. `led1` on PA5 is from ST's manual, from memory. Neither LED has been seen lit and the button has not been pressed.
3. **The other five of Steady's models**, on either board (§10).
4. **Tasking on a Cortex-M** (§5.5).
5. **Floating point.** The chip has a floating-point unit, which is left off: programs are built for software floating point, as Steady builds for this chip.

### M5: Tasking and connectivity

- Context primitive, cooperative tasks, the wait hook.
- AT engine, sockets, MQTT, LoRa driver, settings store.
- Sampling pipeline and data capture, carried over from M3 and designed against the gesture demo's model.
- **Exit:** a gesture-recognition demo publishing over MQTT, and an anomaly-detection demo sending a LoRa packet.

A first serious public release is M0 through M5.

### Demos

Three use models Steady already runs on the C3.

| Demo | Chain |
|---|---|
| Keyword spotting | Microphone, front-end, `kws` model, LED |
| Gesture recognition | Accelerometer, model, MQTT |
| Battery anomaly sensor | Sleep, sample, `ad` model, LoRa packet only on an anomaly |
| Krill | The cluster language model, as the flagship |

---

## 12. Open questions and risks

**Open design questions, each worth a small experiment early:**

- Which SVD generator to use, and whether generated register files are checked in. The C3 has about sixty hand-written addresses now, and each new peripheral adds several.
- How the heap opt-in is expressed.
- Whether `static` parameters cause unacceptable code duplication when a program uses several instances of one peripheral.
- What a sampling pipeline and data capture look like (§11, M5).

**Known gaps, none blocking:**

- The B-L475E-IOT01A has less than the DevKitM-1 (§7), and its clock is uncorrected (§11, M4).
- Building for one board and then the other in the same folder writes the same files in `build/`, so the second build starts again from nothing.
- Programs are built with `-d:danger`, because there is no panic handler to report a failed check.
- Nothing checks that `i2c0.init` frees a sensor cut off mid-read by a reset. It was tried by hand, with a program that read without pause and was reset 16 times.
- There are no deadlines or timeouts, so every wait is forever. A link that loses a packet hangs; the checks rely on the host's timeout. The wait hook of §5.5 is not there either. The one exception is an I2C transaction, which has a deadline of its own.
- An I2C transaction carries at most 254 bytes out and 256 in, and a longer one is refused.
- The front-end takes 3.8 ms a frame, a fifth of the time the sound takes to arrive. A transform that used its input being real, and band sums that skipped their zero weights, would cut that. Neither has been needed.
- The addressable LED driver lights one LED. A strip needs the pulse generator's memory refilled as it plays.
- The SPI controller copies through the bus's 64-byte buffer a byte at a time, which measured about 29% slower than the clock allows on a 300-byte transfer. Copying by words is the cheap fix. DMA is the full one, though it would not replace the copying path if, as believed and not tested, DMA cannot read from flash.
- The trap vector is in flash (§5.5).
- The tasks run on Linux only, and a board cannot be chosen by MAC address (§4.3).
- An SPI transfer longer than the target armed goes wrong (§11, M2).

**Risks:**

- **Scope.** A HAL is a classic way to avoid the project it was meant to serve. Lutra stays off Krill's critical path and grows only as programs need it.
- **Interface churn.** Mitigated by proving the contract on two architectures before inviting libraries.
- **One maintainer.** Favour fewer chips done well.
- **Vendor ROM dependence.** The C3 port calls three boot ROM routines for cache control. Their addresses are fixed per chip revision family and come from esp-idf's `esp32c3.rom.ld`.
- **Nim on bare metal.** Several compiler behaviours surprised the port. They are listed in Appendix B.

---

## Appendix A: ESP32-C3 bring-up facts

From the port in `garrettkinman/ratel`, itself ported from Steady's `tests/mcu/boards/esp32c3/`. Board: ESP32-C3-DevKitM-1, 4 MB flash, 40 MHz crystal, CP2102N USB bridge on UART0.

Everything in A.1, A.2 and A.4 was exercised on hardware unless marked otherwise.

### A.1 Boot and memory

- The core cannot address flash directly. It sees two 8 MB windows, data at `0x3C00_0000` and instructions at `0x4200_0000`, translated by a 128-entry page table of 64 KB pages through a 16 KB cache. Both windows share the table. Nothing is mapped at reset.
- The boot ROM loads an image from flash offset 0 into RAM and jumps to its entry point. That image must contain only RAM segments.
- The firmware is therefore flashed in three pieces:

| Flash offset | Contents | Address once mapped |
|---|---|---|
| `0x000000` | RAM-loaded image: startup code and `.data` | `0x4038_0000` (code), `0x3FC9_0000` (data) |
| `0x010000` | Code, up to 960 KB | `0x4201_0000` |
| `0x100000` | Constants, up to 3 MB | `0x3C10_0000` |

- The mapping is the identity: the low 23 bits of a mapped address are its flash offset.
- RAM is one 384 KB block seen through two windows: instruction address `0x4038_0000 + n` is data address `0x3FC8_0000 + n`. The port uses the first 64 KB for RAM code and the next 256 KB for data, heap and stack. The top 64 KB belongs to the boot ROM, whose data is still live because its routines are called.
- Stack top is `0x3FCD_0000`. The heap grows up from the end of `.bss`.

### A.2 Startup sequence

In order. Everything up to the cache being enabled runs from RAM and may not call or read anything in flash.

1. Set the global pointer (with linker relaxation disabled for that one instruction) and the stack pointer.
2. Clear `mstatus.MIE`. The boot ROM leaves interrupts enabled.
3. Enable the cycle counter: write 1 to CSR `0x7E0` and to CSR `0x7E1`. The count is read from CSR `0x7E2`.
4. Stop the watchdogs the boot ROM leaves running:

| Watchdog | Unlock register and key | Action |
|---|---|---|
| RTC | `0x6000_80A8` = `0x50D8_3AA1` | Write 0 to `0x6000_8090` |
| Timer group 0 | `0x6001_F064` = `0x50D8_3AA1` | Write 0 to `0x6001_F048` |
| Super watchdog | `0x6000_80B0` = `0x8F1D_312A` | Set bit 31 of `0x6000_80AC`. It cannot be stopped, only set to feed itself |

   The timer group 1 watchdog did not need disabling: a 150 s run with long silent waits saw no reset.

5. Switch the core to 160 MHz. The boot ROM has already started the 480 MHz PLL. In `0x600C_0008` set the low two bits to 1 and set bit 2. In `0x600C_0058` set bits 11:10 to 1. Measured result: 160.0 MHz.
6. Map flash. Call the ROM routine at `0x4000_051C` (disable cache). Write the page table at `0x600C_5000`: entry *n* = *n* for the first 64 entries, `0x100` (invalid) for the rest. Call `0x4000_04D8` (invalidate), then `0x4000_0520` with argument 0 (enable). Clear bits 0 and 1 of `0x600C_4004` to let both buses through.
7. Zero `.bss`. `.data` needs no copy; the boot ROM loaded it in place.
8. Call `NimMain`.

### A.3 Facts that matter for interrupts

The first two come from Steady's port notes. The rest were exercised on hardware by Lutra's self-check and echo test.

- The core does not implement the standard `mie` or `mcycle` registers. Accessing them traps. Interrupts are routed through an external controller.
- The core ignores the low 8 bits written to `mtvec` and forces vectored mode. A trap vector must be aligned to 256 bytes. Faults enter at the base, and interrupt line *n* at base + 4*n*. `mcause` has bit 31 set for an interrupt and the line number in its low bits.
- The controller is at `0x600C_2000`. A source is routed by writing a line number, 1 to 31, to `base + 4 × source`. Lines are enabled by bit in `+0x104`, given a priority at `+0x114 + 4 × line`, and fire when the priority is at least the threshold in `+0x194`. Lutra uses priority 1 and threshold 1, and clears the enable register first in case the boot ROM left lines of its own enabled; whether it does was not checked.
- Source numbers used so far: GPIO 16, UART0 21. UART1 is expected to be 22.
- GPIO: per pin at `0x6000_4074 + 4n`, bits 9:7 select the edge (1 rising, 2 falling, 3 either) and bit 13 enables the interrupt. Pending pins are read at `0x6000_4044` and cleared by writing ones to `0x6000_404C`. An output pin's own edges raise the interrupt, which is how the self-check tests it with nothing wired. Edges closer together than the handler takes are merged.

### A.4 Peripherals used

| Peripheral | Facts |
|---|---|
| UART0 | Base `0x6000_0000`. FIFO at `+0x00`, clock divider at `+0x14`, status at `+0x1C`. Transmit FIFO count is status bits 25:16; wait while it is 126 or more. Receive FIFO count is status bits 9:0, and reading `+0x00` takes a byte; the boot ROM leaves receive working on IO20. Interrupt enable at `+0x0C` and clear at `+0x10`: bit 0 is "receive FIFO reached its threshold" and bit 8 is "the line went quiet with bytes waiting". The threshold is bits 8:0 of `+0x24`, and bit 21 there enables the quiet-line timeout. 64 KB echoed at 921600 baud with no loss, polled and through the interrupt. The boot ROM leaves it at 115200 baud, clocked from the 40 MHz crystal, so it is unaffected by the core clock change. Divider = integer part in the low bits, 4-bit fraction at bit 20. 115200 and 921600 baud verified |
| GPIO | Output `0x6000_4004`, set `+0x08`, clear `+0x0C`; enable `0x6000_4020`, set `+0x24`, clear `+0x28`; input `0x6000_403C`. Per-pin output source select at `0x6000_4554 + 4n`; `0x80` means "driven by the output register" |
| IO MUX | Per pin at `0x6000_9004 + 4n`. Bit 7 pull-down, bit 8 pull-up, bit 9 input enable, bits 14:12 function; function 1 is GPIO on every pin. With input enable set, an output pin's level can be read back |
| System timer | Counts at 16 MHz regardless of core clock. Write bit 30 of `0x6002_3004` to latch, wait for bit 29, read high word at `0x6002_3040` and low word at `0x6002_3044`. Works without further setup |

On the DevKitM-1, IO9 is both the boot button and an input of the USB bridge's auto-download circuit. Opening or closing the serial port on the host pulls it low for about 2 µs, which an edge interrupt sees as a press. Its `button.nim` in `examples/` does not debounce, and says so.

Added for M2, on hardware unless marked:

| Peripheral | Facts |
|---|---|
| UART1 | Base `0x6001_0000`, interrupt source 22. Its clock is already enabled at reset (bit 5 of `0x600C_0010`). Set `+0x78` to `0x0370_0000` to clock it from the crystal undivided, as the boot ROM does for UART0; it resets to a divide by two. A receive pin with nothing driving it yet reads as noise, so Lutra pulls it up |
| GPIO matrix | Output: write a signal number to the pin's `0x6000_4554 + 4n`. Input: write the pin number with bit 6 set to `0x6000_4154 + 4 × signal`. Signals: UART0 6, UART1 9, both directions; SPI2 clock 63, data into the controller 64, data out 65, chip-select 68. A pin routed out can be routed back in, which tests a peripheral with nothing wired |
| RNG | Read `0x6002_60B0` |
| SPI2 as controller | Base `0x6002_4000`, clock already enabled at reset. `+0xE8` = 7 turns it on from the 80 MHz clock. `+0x10` bits 0, 27 and 28 give full duplex. `+0x0C` holds the divider *n* − 1 in bits 17:12 and 5:0, and *n*/2 − 1 in bits 11:6. Data goes in sixteen words from `+0x98`, low byte first. Length in bits, less one, at `+0x1C`. Then set bit 23 of `+0x00` and wait for it to clear, and the same for bit 24 |
| DMA | Base `0x6003_F000`. Its clock is off and it is held in reset at boot: set bit 6 of `0x600C_0014` and clear bit 6 of `0x600C_001C`. Channel 0: reset by pulsing bit 0 of `+0x70` (in) and `+0xD0` (out); source 0 is SPI2, at `+0xA0` and `+0x100`; a descriptor's address, low 20 bits, goes to `+0x80` then bit 22 starts it (in), or `+0xE0` and bit 21 (out). A descriptor is three words: size in bits 11:0, length in 23:12, last in 30, owner in 31; the buffer; the next descriptor. On the SPI side `+0x30` bits 27 and 28 enable receive and send by DMA, and bits 29 and 31 reset their FIFOs |

| SPI2 as a target | `+0xE0` bit 26 selects target mode and bit 27 resets it. Arm a transfer by resetting the DMA channel and the bus's FIFOs, starting both descriptors, clearing bit 12 of `+0x38`, then bits 23 and 24 of `+0x00` as for a controller. Bit 12 of `+0x3C` is set when chip-select rises, and `+0xE4` bits 17:0 hold the bits clocked. A receive descriptor's size need not be a multiple of four, and nothing is written past it |
| Pin drive and filter | In a pin's IO MUX register, bits 11:10 set the drive strength (0 weakest, 2 at reset) and bit 15 enables a filter that ignores pulses shorter than about 25 ns |

Added for M3, on hardware unless marked:

| Peripheral | Facts |
|---|---|
| IO18 and IO19 | At reset they are the pads of the chip's own USB port. IO19 is held high and neither can be driven low until bits 14 (pad enable) and 9 (pull-up) of `0x6004_3018` are cleared. After that they behave as any other pin, with function 1 as GPIO |
| Open drain | Bit 2 of a pin's `0x6000_4074 + 4n` makes it only ever pull low. Set for both I2C pins, which share their lines with a sensor without trouble |
| I2C0 | Base `0x6001_3000`, signals 53 (SCL) and 54 (SDA) in both directions. Its clock is off at reset: set bit 7 of `0x600C_0010`. It is timed from the 40 MHz crystal with no register written. With *h* = 20 MHz / rate: `+0x00` = *h* − 1, `+0x38` = (*h* − *h*/8) with *h*/8 in bits 15:9, `+0x30` = *h*/4, `+0x34` = *h*/2, `+0x40` = *h* − 1, and `+0x44`, `+0x48`, `+0x4C` = *h*. These are esp-idf's sums; at 100 kHz a refused address took 110 µs, which is the right length. `+0x04` bit 4 makes it the controller and bit 8 turns its clock on |
| I2C0, a transaction | Up to eight commands at `+0x58 + 4n`: operation in bits 13:11 (6 start, 1 write, 3 read, 2 stop), a byte count in 7:0, bit 8 to expect an acknowledgement of a write, bit 10 to leave a read unacknowledged. Bytes to send, each address included, go to `+0x1C`, which also gives the bytes read. The counts waiting are in `+0x08`, bits 23:18 out and 13:8 in, of 32 each way. Pulse bits 13:12 of `+0x18` to empty both, write ones to `+0x24` to clear events, then set bit 11 and bit 5 of `+0x04`. In `+0x20`, bit 7 is "complete" and bit 10 "not acknowledged". Bit 10 of `+0x04` resets the state machine, which is not enough after a refusal (§11, M3): bit 7 of `0x600C_0018`, set and cleared, resets the whole peripheral, timing registers included |
| I2C0, a held line | With SCL low: bit 13 of `+0x20` within a few milliseconds, and never bit 7. With SDA low: bits 5, 13 and 14 the first time, and nothing at all the second |
| Pulse generator (RMT) | Base `0x6001_6000`, channel 0 out is signal 51. Its clock is off at reset: set bit 9 of `0x600C_0010`. `+0x68` = bits 31, 26, 24 and 0: on, from the 80 MHz clock undivided, with its memory written directly. `+0x10` for channel 0: bit 16 for one block of memory, a divider of 1 in bits 15:8, bit 6 to hold the pin low when idle. The channel's 48 words are at `+0x400`; a word is a time in ticks in bits 14:0 and a level in bit 15, then the same again in 30:16 and 31, and a zero word ends the list. Pulse bits 2:1 of `+0x10` to rewind, set bit 24 and then bit 0 to play, and bit 0 of `+0x38` says it is done; clear it at `+0x44` |
| The board's LED | On IO8. Sent green, red, blue, high bit first, as 0.35 µs high and 0.9 µs low for a 0 and 0.7 µs high and 0.55 µs low for a 1, chosen to suit both WS2812 and SK6812 parts. The pulses were read back from the pin, and the LED shows red, green and blue when asked for each |

Not verified: the reset-default function of each pin. Take it from the ESP32-C3 Technical Reference Manual.

### A.5 Building and flashing

- Compiler flags: `-march=rv32imc_zicsr -mabi=ilp32 -ffunction-sections -fdata-sections`. GCC 11.2 accepts `rv32imc_zicsr`; newer toolchains require the `_zicsr`.
- Linker flags: `-nostartfiles -Wl,--gc-sections` and the linker script.
- Nim flags used by the port: `--cpu:riscv32 --os:any -d:useMalloc --opt:size --exceptions:goto -d:danger`.
- Packaging and flashing:

```
objcopy -O binary -j .flash.text   app app.text
objcopy -O binary -j .flash.rodata app app.rodata
objcopy -R .flash.text -R .flash.rodata app app.ram
esptool --chip esp32c3 elf2image --flash-mode dio --flash-freq 80m --flash-size 4MB -o app.bin app.ram
esptool --chip esp32c3 --port /dev/ttyUSB0 --baud 460800 write-flash \
        0x0 app.bin 0x10000 app.text 0x100000 app.rodata
```

- The flash mode and frequency in the image header configure the flash controller, so they affect weight-streaming speed. They are not just packaging.
- An empty constants file is accepted by `esptool` with a warning.
- Heap support needs two things from the C library that ships with the toolchain: a symbol named `end` at the end of `.bss`, and a `__getreent` function returning a zeroed `struct _reent`. Without the second, `malloc` writes through a null pointer.

### A.6 Measured sizes

From the seed code:

| Program | RAM code | Flash code | Constants |
|---|---|---|---|
| Hello world over serial | 248 B | 1.4 KB | 22 B |
| Steady `kws` benchmark | 248 B | 9.7 KB | 30.5 KB |

On Lutra, hello world is 254 B, 2.2 KB and 288 B. It prints a 64-bit millisecond count, and 64-bit division brings in about 1.7 KB of code and a 256 B table from the compiler's support library.

---

## Appendix B: Nim behaviours that surprised the port

- **`std/volatile` is unusable in early startup.** In Nim 2.2 `volatileLoad` and `volatileStore` are procedures, and with `--exceptions:goto` each call is followed by an error-flag check that calls into code in flash. Use the imported-type idiom in §5.1.
- **Calls through a procedure pointer get an error check even when the type is marked `raises: []`.** Calls to `importc` procedures do not. To call a ROM routine at a fixed address, import a C expression as the name:

```nim
proc cacheDisable() {.importc: "((void (*)(void))0x4000051c)", cdecl, nodecl.}
```

- **`asm` with an output operand is not `volatile`.** GCC treats it as pure and hoists it out of loops; a loop waiting on the cycle counter became an infinite loop. Use `emit`:

```nim
proc cycles*(): uint32 =
  {.emit: ["__asm__ volatile(\"csrr %0, 0x7e2\" : \"=r\"(", result, "));"].}
```

- **`asm` at the top level of a module is emitted outside any function**, not in the module's initialisation code.
- **A naked function needs `codegenDecl`.** `asmNoStackFrame` alone does not add the attribute under GCC:

```nim
proc start() {.exportc: "_start",
    codegenDecl: "__attribute__((naked, section(\".iram\"))) $# $#$#".} =
```

- **Iterating an array literal places the array in constant data**, which is in flash. Startup code must use immediates only.
- **`std/os` does not compile under `--os:any`.** Compute paths with string operations. `currentSourcePath` works inside an `include`d file.
- **With `--mm:arc` the runtime always links `malloc`, `free` and `exit`.**
- **Nimble installs only the extensions listed in `installExt`.** A linker script next to the sources needs its extension added.
- **`p"text\n"` is a raw string literal.** The `\n` is not an escape. This is Ratel's `progmem` syntax and is one reason not to carry it over. `cstring"text\n"` is raw for the same reason; write `cstring("text\n")`.
- **Setting `--os:any` in `config.nims` is too late to stop the host's libraries being linked.** Nim's own `nim.cfg` has already added `-ldl` for a Unix host. Clear it with `switch("gcc.options.linker", "")`.
- **Nim does not link again when only a linker script's contents change.** It compares the link command, not the files it names.
- **A generic procedure binds a name early if `system` already has one symbol by that name.** `link.send(c)` resolved to the channel `send` on the host, and `reset(port)` to `system.reset`. Declare such names with `mixin`. A library written against a concept needs this too, for `send` and `receive`, or it only compiles for the target.
- **A template parameter is substituted into field accesses.** With a parameter called `name`, `file.name` in the body becomes `file."the argument"`.
- **A `static` object parameter cannot size the return type.** `func table(m: static Mfcc): array[m.melBins, int32]` fails with "cannot evaluate at compile time: m". Pass the size as a `static int` of its own.
- **Going through a constant array of strings allocates.** Each string is copied on its way to the loop variable, and the program then fails to link, for want of `end`. Hold data from `staticRead` as an array of numbers, built in a `const` block.
- **`--skipProjCfg` builds for the host from a folder whose `config.nims` selects a board.** `nim keywords` uses it to build one source file both ways. That file tells them apart with `when defined(lutraBoard)`.
- **A module cannot import another of its own name**, wherever the other is. `checks/keywords.nim` is not `kws.nim` because Steady's generated module is.
- **Code at the top level of a module costs an error check.** With `--exceptions:goto` each module's own code ends by testing Nim's error flag, and that test keeps `exit` in the link. A program's main module loses it when it ends in a loop, as unreachable. A board's module that set its console up at the top level did not, and with the C library that ships for ARM `exit` brought 1 KB of RAM and 1.4 KB of flash into every program. Hence `lutraBoardStart`, a procedure the startup code calls.
- **A procedure declared in a template is visible to the next use of that template**, unlike a variable. Two `pin.onRising:` blocks in one program were a "redefinition of 'handler'". Mark such a procedure `{.gensym.}`.
- **A name a macro makes up is looked for where the macro is expanded, and inside a procedure with a `static` parameter that is the caller's module.** `sink.write "Fault: "` in the architecture layer failed with "undeclared identifier: 'put'" when a board's module instantiated it, because `write` builds calls to `put` by name. The fault report calls `put` itself.
- **A literal passed to a template's `uint32` parameter is still a literal.** `value shl 30` with 2 for `value` was worked out as an `int`, which is 32 bits on the target, and did not fit. Convert it in the template.

---

## Appendix C: Development environment on the author's machine

Machine-specific. Remove before publishing.

- Boards: two ESP32-C3-DevKitM-1, with MAC addresses `84:f7:03:0a:a8:08` (the one used for M0 and M1) and `7c:df:a1:59:c9:70`. They appear as `/dev/ttyUSB0` and `/dev/ttyUSB1`, and which is which changes when they are replugged. `esptool --port <port> chip-id` prints the MAC.
- The two are wired together as §11 describes for M2, and `nim wiring` confirms it.
- Before running Lutra's tasks: `export ESPTOOL=~/Documents/GitHub/Steady/.venv/bin/esptool`, and `~/.nimble/bin` on `PATH` for `nim`.
- Compiler: `~/.espressif/tools/riscv32-esp-elf/esp-2022r1-RC1-11.2.0/riscv32-esp-elf/bin/`, GCC 11.2. Not on `PATH`.
- `esptool` 5.3.1: `~/Documents/GitHub/Steady/.venv/bin/esptool`. Not on `PATH`.
- Nim 2.2.6.
- Reading the console:

```
stty -F /dev/ttyUSB0 115200 raw -echo -hupcl
timeout 5 cat /dev/ttyUSB0
```

- The same virtual environment's `python` has `pyserial`. Holding DTR asserted and releasing RTS pulls IO9 low, which presses the boot button from the host.
- `esptool` leaves the port set to return from a read at once when no byte is waiting, which `cat` takes as the end of the file. That is why a capture started before `esptool` runs goes silent after the reset. Lutra's `monitor` and `selfcheck` open the port once, hold it open across the reset and set the mode again afterwards, so they read from the boot ROM's first byte.
- Lutra's tasks find the compiler under `~/.espressif` without help. `esptool` has to be on `PATH` or named in `ESPTOOL`.
- Steady's reference results for the C board path are in `~/Documents/GitHub/Steady/build/mcu/esp32c3/<model>/serial.txt`.
- `~/Documents/GitHub/lutra-lsm6ds33` and `~/Documents/GitHub/lutra-lis3mdl` are the sensor drivers' packages, each on `main` with its remote on GitHub (§8).
- The Speech Commands test set is unpacked in `checks/build/keywords/`, 150 MB, so `nim keywords` does not download it again. Deleting `checks/build` brings the download back.
- The sensor board is on the DevKitM-1 with MAC `7c:df:a1:59:c9:70`, with a wire from its ADM pin to ground (§11, M3). The other DevKitM-1 was unplugged on 13 October, so `nim wiring` and `nim link` want it plugged in again, and with one board attached no port needs naming.
- Adafruit's design files for the sensor board, which settled what its pins join, are at `github.com/adafruit/Adafruit-LSM6DS33-LIS3MDL-PCB`.
- The B-L475E-IOT01A is attached by its ST-LINK's USB socket and appears as `/dev/ttyACM0`. With it and one DevKitM-1 attached, no port needs naming for either.
- `pyocd` 0.45.1: `~/Documents/GitHub/Steady/.venv/bin/pyocd`, beside `esptool`. Not on `PATH`, so `export PYOCD=~/Documents/GitHub/Steady/.venv/bin/pyocd`. It reaches the probe without `sudo`; Steady's `tests/mcu/boards/stm32l475/board.sh` has the udev rule that allows that.
- The ARM compiler is Ubuntu's `arm-none-eabi-gcc` 10.3.1, on `PATH`, with its `newlib`.
- `pyocd commander -t stm32l475xg -c halt -c "reg pc" -c "read32 0x40021000 16" -c go` reads the chip's registers while a program runs, which is how the first silent console was explained.

---

## Appendix D: STM32L475 bring-up facts

For the B-L475E-IOT01A: an STM32L475VG, a Cortex-M4 with 1 MB of flash, and an ST-LINK/V2-1 on the board. Addresses are from ST's reference manual RM0351, written from memory and confirmed by use. What came from Steady's port in `tests/mcu/boards/stm32l475/` says so.

Everything here was exercised on hardware unless marked otherwise.

### D.1 Memory and start

- Flash is at `0x0800_0000` and read where it is. RAM is two blocks: 96 KB at `0x2000_0000`, which Lutra uses, and 32 KB at `0x1000_0000`, which it leaves alone. Steady's notes: the second is not found above the first, and a stack placed there faults at once.
- The core reads a table of addresses from the start of flash: the stack to start on, the reset handler, fourteen entries for faults and system exceptions, then one for each of the chip's 82 interrupts. 392 bytes.
- In order, `lutraReset` copies what variables start out as from flash to RAM, zeroes `.bss`, raises the clock, starts the two timers, calls the board's `lutraBoardStart` and then `NimMain`.
- Interrupts are on at reset, with none enabled.
- `.word 0` is not a fault here: it is two instructions that do nothing. The self-check uses `udf #0`.

### D.2 Clock

- The chip starts on its own 4 MHz oscillator. Flash wants four wait states at 80 MHz, set before the clock is raised: `0x4002_2000` = `0x704`, which also has the prefetch and both of flash's caches on.
- `0x4002_100C` = `0x0100_2801` multiplies the oscillator by 40 and halves it. Set bit 24 of `0x4002_1000` and wait for bit 25, then set the low two bits of `0x4002_1008` and wait for bits 3:2 to read 3. Both peripheral buses then run at 80 MHz too.
- Measured against the board's crystal: 80.14 MHz, 0.18% fast.
- A peripheral's clock is switched on in `0x4002_104C` (ports A to E are bits 0 to 4), `0x4002_1058` (timer 2 is bit 0, timer 5 bit 3, I2C2 bit 22, power control bit 28, the low-power timer bit 31) or `0x4002_1060` (the register that picks pin interrupts' ports is bit 0, USART1 bit 14). The register is read back after writing, which Steady's notes say is what makes the peripheral usable on the next line; the port has not tried going without.
- The 32.768 kHz crystal: with power control's clock on, set bit 8 of `0x4000_7000`, then bit 0 of `0x4002_1090`, and wait for bit 1. That took 2 ms after a reset with the board already powered; from cold it was not measured. Bits 19:18 of `0x4002_1088` set to 3 give the crystal to the low-power timer at `0x4000_7C00`: `+0x10` = 1, `+0x18` = `0xFFFF`, `+0x10` = 5, and the count is at `+0x1C`, read until two readings agree.

### D.3 Pins and their interrupts

| What | Facts |
|---|---|
| A port | Port A is at `0x4800_0000` and the rest follow `0x400` apart. Mode at `+0x00`, two bits a pin: 0 input, 1 output, 2 a peripheral's, 3 analog. Open drain at `+0x04`, a bit a pin. Pulls at `+0x0C`, two bits: 1 up, 2 down. Input at `+0x10`, output at `+0x14`. Writing a bit in the low half of `+0x18` sets a pin and in the high half clears it. Function numbers at `+0x20` and `+0x24`, four bits a pin |
| Before its clock is on | A port's registers take nothing in. Reading a pin of an output gives the level at the pin |
| Functions | USART1 is function 7 on PB6 (out) and PB7 (in). I2C2 is function 4 on PB10 (clock) and PB11 (data). PA9, PA10, PB13 and PB14 are listed as their alternatives from the datasheet and have not been tried |
| Edge interrupts | Sixteen lines, one for pin *n* of whichever port bits 4*n* of `0x4001_0008 + 4 × (n div 4)` name. Rising edges at `0x4001_0408`, falling at `0x4001_040C`, enabled at `0x4001_0400`, pending at `0x4001_0414` and cleared there by writing a 1. Lines 0 to 4 are interrupts 6 to 10, lines 5 to 9 share interrupt 23, and 10 to 15 share 40. An output pin's own edges raise its line |
| The interrupt controller | In the core. Interrupt *n* is let through by bit *n* mod 32 of `0xE000_E100 + 4 × (n div 32)` |
| On this board | PB14 drives LED2. PC13 is the button and is held high by the board. PA4, PA5, PA15, PB2 and PC0 to PC5 follow their pulls, so nothing on the board drives them. PA5 as LED1, and which header pin is which, are from ST's manual UM2153, from memory |

### D.4 Peripherals used

| Peripheral | Facts |
|---|---|
| USART1 | Base `0x4001_3800`, to the ST-LINK on PB6 and PB7. `+0x0C` is the bus clock divided by the baud rate, 694 for 115200. `+0x00` = `0xD` enables it both ways. In `+0x1C`, bit 7 says there is room to send and bit 5 that a byte has come. Send at `+0x28`, receive at `+0x24`. Bit 12 of `+0x08`, set before it is enabled, makes a byte that arrives with the last unread replace it; without that the port stops receiving until an error flag is cleared |
| Timers 2 and 5 | Bases `0x4000_0000` and `0x4000_0C00`, both 32 bits, counting the 80 MHz bus clock when `+0x00` = 1. Count at `+0x24`. Timer 2's `+0x04` = `0x20` tells others when it comes round, and timer 5's `+0x08` = 7 makes it count that: its first internal trigger is timer 2 |
| I2C2 | Base `0x4000_5800`, clocked at 80 MHz. `+0x10` holds the timing: a divider less one in bits 31:28, then the data line's setup and hold in 23:20 and 19:16, and the clock's high and low times, each less one, in 15:8 and 7:0. `0x90F2_232B` is 100 kHz. `+0x00` = 1 enables it. A transfer is started by writing `+0x04`: the address in bits 7:1, bit 10 to read, a count of bytes in 23:16, bit 13 to start, and bit 25 to stop when the count is done. In `+0x18`, bit 1 asks for a byte to send (`+0x28`), bit 2 offers one received (`+0x24`), bit 4 says the device refused, bit 5 that a stop went out, which it does after a refusal too, and bit 6 that the count is done with no stop asked for. Bits 4 and 5 are cleared at `+0x1C` |
| I2C2, on this board | Seven addresses answer: 0x1E (the LIS3MDL, whose identity register reads `0x3D`), 0x29, 0x2D, 0x56, 0x5D (`0xB1`), 0x5F (`0xBC`) and 0x6A (`0x6A`, an LSM6DSL, which `lutra_lsm6ds33` does not know) |
| Faults | The status is at `0xE000_ED28`: bit 16 an undefined instruction, bits 12:9 a bad address read or written, bits 17, 8 and 0 a jump to one. Bit 15 says the address is at `0xE000_ED38`. The core pushes eight registers onto the stack in use, the instruction's address seventh and the link register sixth |

### D.5 Building and flashing

- Compiler flags: `-mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffunction-sections -fdata-sections`. Nim flags as for the C3, with `--cpu:arm`.
- Linker flags: `-nostartfiles --specs=nosys.specs -Wl,--gc-sections` and the linker script. The stubs are there because Nim's runtime refers to `exit`, which this C library builds on `_exit`. None is linked into hello world.
- `pyocd flash -t stm32l475xg app.elf` programs the linked file as it is and starts it. `pyocd reset -t stm32l475xg` resets it, and takes a second or so over it.
- Hello world over serial is 2812 bytes of flash and no RAM.

---

## References

- Ratel: `github.com/PMunch/ratel`. Fork with the C3 port: `github.com/garrettkinman/ratel`.
- Driver packages: `github.com/garrettkinman/Lutra-LSM6DS33` and `github.com/garrettkinman/Lutra-LIS3MDL`.
- Steady: `github.com/garrettkinman/Steady`. See `tests/mcu/boards/esp32c3/` for the original C port and its notes, and `tests/mcu/bench.nim.in` for the board contract.
- Krill & Reflex project doc, §7 "Track R" and §3 "Hardware budget".
- Espressif: ESP32-C3 Technical Reference Manual; SVD files; `esp32c3.rom.ld` in esp-idf for ROM routine addresses.
- `esp-hal` (Rust), as the reference for driving Espressif's radio without esp-idf.
- svd2rust, as the model for generated register definitions.
