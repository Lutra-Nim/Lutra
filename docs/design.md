# Lutra: a Nim-only bare-metal stack for TinyML microcontrollers

**A hardware abstraction layer and library ecosystem in pure Nim, RISC-V first, built so that running a model on a microcontroller is as approachable as blinking an LED on an Arduino.**

Status: design doc · v0.1 · October 2026

How to read the status of what follows:

- **Decided** means the author has settled it.
- **Proposed** means it is the current plan and has not been built or tested.
- **Verified** means it was observed on real hardware during the ESP32-C3 port described in Appendix A.

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

**Proposed.** Start as one repository and one Nimble package. Split chips into their own packages only once the interfaces have stopped moving.

```
lutra/
  src/lutra.nim              `import lutra` gives the selected board
  src/lutra/
    arch/riscv32/
    chips/esp32c3/
    boards/esp32c3_devkitm1.nim
    hal/                     the capability interfaces
    fmt, containers, time, fixed, task    core libraries (§8.1)
  tools/                     build, flash, monitor; register generator
  checks/                    per-board hardware self-check programs
  examples/
```

Separate packages, one per library, for everything in §8.2 to §8.4. Suggested naming: `lutra_<name>`, for example `lutra_lis3dh`, `lutra_at`, `lutra_mqtt`.

### 4.3 Build tooling

**Proposed.** Plain `nim` and Nimble tasks, pulled in by one line in `config.nims`. No interpreter dependency.

Commands every board provides:

| Command | Does |
|---|---|
| `build` | Compile and link |
| `flash` | Package the image and program the board |
| `monitor` | Read the console, with a reset option |
| `size` | Per-section sizes against the board's budgets |
| `check` | Build, flash and run the board's self-check, and compare the output |

`flash` and `monitor` should accept a board identity (serial port or MAC address) and an "all attached boards" mode. Krill flashes up to 16 boards at a time.

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

How the script is generated, at compile time or by the build task, is open (§12).

### 5.3 Startup and code that runs before flash is readable

On the ESP32-C3 the core cannot read flash until a page table is written, so startup code is loaded into RAM by the boot ROM and must not touch anything in flash. Other chips have similar early-boot constraints.

**Proposed:**

- A pragma, for example `{.ram.}`, that places a procedure in RAM.
- A build check that fails if RAM code references a flash address. In the port this was checked by reading the disassembly by hand.

The startup sequence itself is in Appendix A.

### 5.4 Compile-time ownership of pins and peripherals

**Proposed.** Every use of a pin or peripheral claims it at compile time. A second claim is a compile error that names both claimants, for example "IO21 is claimed by UART0 TX and by `statusLed`".

Requirements:

- Buses are shareable. Several devices may sit on one I2C bus. Several SPI devices may share clock and data pins, each owning its own chip-select.
- A claim records what a pin is used for, so the same information can print a wiring table for the user.

Suggested mechanism: a macro that records claims in a compile-time table. Whether Nim's compile-time state behaves well across modules for this needs an early experiment (§12).

### 5.5 Interrupts, trap entry and tasking

**Proposed.** Interrupts are off unless a program asks for them. Handlers are bound at compile time.

The trap entry is the one part that is expensive to change later, so it is designed for tasking from the start:

1. **Trap entry saves the full register context on the current stack and can return onto a different stack.** This allows preemptive task switching to be added without rewriting the interrupt path.
2. **The architecture layer exposes a small context primitive:** prepare a stack, switch to it. This is per architecture, not per chip: one RV32 implementation serves every RISC-V chip. The tasking library (§8.1) is pure Nim on top of it.
3. **Every blocking wait in every driver goes through one hook.** By default the hook spins. A scheduler replaces it with a yield, and no driver changes.

Chip-specific facts that affect this on the ESP32-C3 are in Appendix A.3.

Default trap behaviour: leave the vendor's handler in place where it is useful. **Verified:** on the C3 the boot ROM's handler prints a full register dump on a fault.

### 5.6 Memory model

**Decided:** no allocator unless requested.

**Verified** complication: with `--mm:arc`, Nim's runtime keeps `malloc`, `free` and `exit` reachable even for a program that never allocates, about 1.4 KB. Steady builds with `--mm:none --panics:on` and links no allocator. Lutra's default configuration should do the same, with the heap as an explicit opt-in.

Consequence: the core needs allocation-free formatting and fixed-size containers (§8.1), because `string` and `seq` are not available by default.

### 5.7 Build checks

Each of these was done by hand during the port and should be automatic:

- RAM code does not reference flash.
- Constant data is in flash, not RAM.
- No allocator symbols are linked unless the heap was requested.
- No orphan sections appear in the link.
- Image regions do not overlap.

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

---

## 6. The driver contract

Libraries are written against these interfaces and nothing else. This contract is the most important thing to get right, because changing it later breaks every driver.

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

How the interfaces are expressed in Nim, for example as concepts or as duck-typed `static` parameters, is open (§12).

---

## 7. HAL features

| Tier | Features | Reason |
|---|---|---|
| Core, every chip | Startup, clocks, memory layout; GPIO; UART transmit and receive; monotonic time, delays, cycle counter; interrupts and critical sections; console, panic and trap report; watchdog; reset reason; sleep | Nothing works without these |
| Buses | I2C controller; SPI controller and target; DMA behind them | Krill needs SPI target with DMA; most sensors use I2C or SPI |
| Timing and analog | PWM; ADC; pulse capture; addressable-LED output | Actuators, analog sensors, and the DevKitM-1's own LED |
| TinyML inputs | I2S; hardware RNG; raw flash storage | Microphones, sampling, weights and recorded data |
| Later | USB device; I2C target; low-power modes; SPI cameras | Useful, not blocking |

State of the seed code against this table: startup, clock, flash mapping, GPIO, UART0 transmit, time, delays and the cycle counter exist and are verified. Everything else is to be written.

---

## 8. Libraries

Rule for placement: if every other library must agree on it, it is in the core package. Otherwise it is a separate package.

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
| Starter drivers | One accelerometer, one I2S microphone, one environmental sensor, the addressable LED | They power the demos and are the template for third-party drivers. The author's existing LIS3DHTR Ratel library (`ratel-lis3dhtr`) is the natural first port |

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

Acceptance test for every board port: all six of Steady's reference models give the reference checksums, with cycle counts comparable to the C path.

---

## 11. Roadmap

Each milestone ends with an exit criterion.

### M0: Skeleton and seed

- Repository, layout and build tasks (`build`, `flash`, `monitor`, `size`, `check`).
- Move the C3 seed code into the architecture, chip and board layers.
- Memory description generating the linker script and flash offsets.
- The self-check program.
- **Exit:** the self-check passes on the DevKitM-1, and Steady's `kws` benchmark gives `ab2fdbf1` on Lutra.

### M1: Core contract

- Trap entry designed per §5.5; interrupts; critical sections.
- UART receive with a ring buffer; GPIO interrupts.
- Compile-time ownership.
- Printing, containers and time libraries.
- Build checks from §5.7.
- **Exit:** a UART echo test at high baud loses no bytes; a double pin claim fails to compile with a clear message; the default configuration links no allocator.

### M2: What Krill needs

- SPI controller and target with DMA; hardware RNG; UART1.
- Framed serial link.
- Steady's link contract implemented.
- **Exit:** two boards exchange checksummed buffers over UART and over SPI, and Krill's Phase 0 exit test (a dummy model split across two chips) runs on Lutra.

### M3: First TinyML demo

- I2C, I2S, ADC, PWM, addressable LED.
- Fixed-point math, signal front-end, sampling pipeline, data capture.
- Starter drivers.
- **Exit:** keyword spotting runs end to end from microphone to LED, and the front-end is bit-identical between host and device.

### M4: Second architecture

- One Cortex-M board through the same interfaces. Steady already targets the STM32L475 and SAMD51.
- **Exit:** the self-check, one sensor driver and the Steady benchmark run with no changes to library code.

### M5: Tasking and connectivity

- Context primitive, cooperative tasks, the wait hook.
- AT engine, sockets, MQTT, LoRa driver, settings store.
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

- How to express the interfaces in Nim: concepts, or duck-typed `static` parameters as Ratel does. The second is verified to be zero cost; the first gives better error messages.
- Whether compile-time ownership can be built on a compile-time table mutated by macros across modules.
- How the linker script is generated: written at compile time, or by a build task.
- Which SVD generator to use, and whether generated register files are checked in.
- How the heap opt-in is expressed.
- How interrupt handlers are bound at compile time.
- Whether `static` parameters cause unacceptable code duplication when a program uses several instances of one peripheral.

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

These come from Steady's port notes and were not re-tested in the Ratel port.

- The core does not implement the standard `mie` or `mcycle` registers. Accessing them traps. Interrupts are routed through an external controller.
- The core ignores the low 8 bits written to `mtvec` and forces vectored mode. A trap vector must be aligned to 256 bytes.

### A.4 Peripherals used

| Peripheral | Facts |
|---|---|
| UART0 | Base `0x6000_0000`. FIFO at `+0x00`, clock divider at `+0x14`, status at `+0x1C`. Transmit FIFO count is status bits 25:16; wait while it is 126 or more. The boot ROM leaves it at 115200 baud, clocked from the 40 MHz crystal, so it is unaffected by the core clock change. Divider = integer part in the low bits, 4-bit fraction at bit 20. 115200 and 921600 baud verified |
| GPIO | Output `0x6000_4004`, set `+0x08`, clear `+0x0C`; enable `0x6000_4020`, set `+0x24`, clear `+0x28`; input `0x6000_403C`. Per-pin output source select at `0x6000_4554 + 4n`; `0x80` means "driven by the output register" |
| IO MUX | Per pin at `0x6000_9004 + 4n`. Bit 8 pull-up, bit 9 input enable, bits 14:12 function; function 1 is GPIO on every pin |
| System timer | Counts at 16 MHz regardless of core clock. Write bit 30 of `0x6002_3004` to latch, wait for bit 29, read high word at `0x6002_3040` and low word at `0x6002_3044`. Works without further setup |

Not verified: UART1 (expected base `0x6001_0000`), the reset-default function of each pin, and anything about SPI, I2C, DMA, RNG or the interrupt controller. Take these from the ESP32-C3 Technical Reference Manual.

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

| Program | RAM code | Flash code | Constants |
|---|---|---|---|
| Hello world over serial | 248 B | 1.4 KB | 22 B |
| Steady `kws` benchmark | 248 B | 9.7 KB | 30.5 KB |

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
- **`p"text\n"` is a raw string literal.** The `\n` is not an escape. This is Ratel's `progmem` syntax and is one reason not to carry it over.

---

## Appendix C: Development environment on the author's machine

Machine-specific. Remove before publishing.

- Board: ESP32-C3-DevKitM-1 on `/dev/ttyUSB0`, 115200 baud.
- Compiler: `~/.espressif/tools/riscv32-esp-elf/esp-2022r1-RC1-11.2.0/riscv32-esp-elf/bin/`, GCC 11.2. Not on `PATH`.
- `esptool` 5.3.1: `~/Documents/GitHub/Steady/.venv/bin/esptool`. Not on `PATH`.
- Nim 2.2.6.
- Reading the console:

```
stty -F /dev/ttyUSB0 115200 raw -echo -hupcl
timeout 5 cat /dev/ttyUSB0
```

- Do not read the console while `esptool` is using the port; the capture goes silent after the reset. Flash first, then read, and make test programs repeat their output.
- Steady's reference results for the C board path are in `~/Documents/GitHub/Steady/build/mcu/esp32c3/<model>/serial.txt`.

---

## References

- Ratel: `github.com/PMunch/ratel`. Fork with the C3 port: `github.com/garrettkinman/ratel`.
- Steady: `github.com/garrettkinman/Steady`. See `tests/mcu/boards/esp32c3/` for the original C port and its notes, and `tests/mcu/bench.nim.in` for the board contract.
- Krill & Reflex project doc, §7 "Track R" and §3 "Hardware budget".
- Espressif: ESP32-C3 Technical Reference Manual; SVD files; `esp32c3.rom.ld` in esp-idf for ROM routine addresses.
- `esp-hal` (Rust), as the reference for driving Espressif's radio without esp-idf.
- svd2rust, as the model for generated register definitions.
