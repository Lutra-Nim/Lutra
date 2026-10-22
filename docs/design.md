# Lutra: a Nim-only bare-metal stack for TinyML microcontrollers

**A hardware abstraction layer and library ecosystem in pure Nim, RISC-V first, built so that running a model on a microcontroller is as approachable as blinking an LED on an Arduino.**

Status: design doc · v0.3 · October 2026 · milestones M0 to M4 are built, and M5 is under way

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

Checked 14 October 2026: no package in Nimble's list, of about 3,000, is named for or mentions Lutra, so `lutra` and `lutra_*` are free there. On GitHub the name `lutra` belongs to someone's personal account, so Lutra's organisation is `Lutra-Nim`, since 16 October 2026 the home of all four repositories (§8). Trademarks have not been checked.

### 1.2 Where things stand

Three boards are supported: the ESP32-C3-DevKitM-1, a RISC-V, ST's B-L475E-IOT01A, a Cortex-M4, and, since 20 October, Sipeed's Lichee RV Dock, an Allwinner D1, a 64-bit RISC-V run with no operating system (Appendix E). Milestones M0 to M4 of §11 are done, and §11 says what each verified. The second board has all the first has but the SPI target, which Krill needs, and the addressable LED, which it does not carry; §7 sets the two side by side. M5 is under way: tasks, timer events and data capture are done on both boards (§5.5, §8.2), and MQTT over Wi-Fi on the DevKitM-1, through a second DevKitM-1 running Espressif's AT firmware (§8.3).

On 16 and 17 October, on the branch `feature/agents`, in the order the author chose: the repositories moved to the `Lutra-Nim` organisation (§8); bounded commands, exit codes, `nim doctor` and `AGENTS.md` (§4.4); a panic report, with Nim's checks on by default (§5.6); and two rounds of the libraries in §8.1. Then code for the B-L475E-IOT01A's second UART, receiving through an interrupt, SPI and random numbers (§7). That branch is merged.

Later on 17 October, on the branch `feature/libs-and-watchdog`, in one session with the B-L475E-IOT01A and the sensor board's DevKitM-1 attached: everything written for the B-L475E-IOT01A ran, and two bugs were fixed on the way (§11, M5); the tasks stopped needing `sh`, `stty` and `awk`, through a program for the host, `lutra/host/monitor` (§4.3); filters, statistics, trigonometry and a spectrum (§8.1); the watchdog, the reset reason and `restart` on both boards (§7), with a check of their own, `nim resets`; and `nim capture` no longer takes records from before a reset (§8.2). The session ended by putting the next steps to the author, below, and noting ideas for later (§11, "Later").

Then, in the next session: Lutra and its three drivers made ready for Nimble's list (§8). Lutra installs, its self-check with it; the drivers ask for `lutra ^= 0.1` and use it as an installed package; `CHANGELOG.md` begins; and "TinyML" left the packages' descriptions, at the author's asking.

On 20 October, on the branch `feature/lichee-rv-dock-support`, with only the Dock attached: the third board, for a TinyTTS demo with Steady, as the author's notes plan it ("TinyTTS on Lutra + Steady", not in this repository). The author chose to run the D1 bare rather than under Linux. `arch/riscv64`, `chips/d1` and `boards/lichee_rv_dock` have startup, clocks, caches, the FPU and the vector unit, GPIO, UART0, time, the cycle counter, interrupts through the chip's PLIC, timer events, tasks, the addressable LED, panics, a fault report and `restart`, and `nim selfcheck` passes on it. Programs are loaded into DRAM over USB by `xfel`, through `lutra/host/fel`; the host starts a running one again by a break on its console, which every program on the Dock answers by restarting into the boot ROM's loader, as the author chose, having no wire for the reset (Appendix E). Shared code gained `halt`, whose loop a board can hook as `lutraHalted`, and `buildDir` and `hostProgram` moved into `lutra/tooling`. Steady's `kws` gives `ab2fdbf1` on the D1, and with `steady-xtheadvector`, a backend for the vector unit in a repository of its own beside Steady, 2.4 times as fast (§10). The author committed all of it on that branch.

Later on 20 October, in a second session, with only the Dock attached, in the order the author chose:

- **`steady-xtheadvector`'s requantising vectorised**, which made `kws` 5.3 times as fast as without the backend (§10).
- **The TinyTTS demo has a repository of its own**, `tinytts-lutra` beside this one, not yet under git: the author's plan as `docs/plan.md`, with a note that the Dock runs bare, and the export from PyTorch, whose README says what it found. TinyTTS's Python feeds BERT zeros and uses the plain duration predictor, so two of the plan's risks are gone. The decoder for a chunk is built in Keras straight from the folded weights, as the author chose over `onnx2tf`, with VALID padding, which the author chose after it was measured against padding inside the chunk: 1.2 to 2 times fewer multiply-adds, at the cost of crops. It matches TinyTTS's decoder within 2e-5 in float; quantized with 16-bit activations, 23 dB from TinyTTS's own audio, and with 8-bit, 7.6 dB.
- **Steady's 16x8 policy**, in the shape the author chose: `AffineI16x8`, with a `Weight(P)` beside `Store(P)` and a `finishRescaled` for additions; TFLite's own integer tanh and LeakyReLU; `StridedSlice` as a copy. TinyTTS's decoder is `tinytts_decoder` among Steady's test models, and every one of its 300 tensors agrees with TFLite's reference kernels, bit for bit. The harness now also compares the tensors the importer renames, which it had skipped, and every int8 model's newly compared tensors agree too.
- **The 16x8 kernels in `steady-xtheadvector`**: convolutions, additions, LeakyReLU and crops. On the Dock the decoder takes 355M cycles for a chunk of 0.37 s of speech, 5% faster than speech, against 1771M without the backend, and gives `5936432b` either way, as TFLite does (§10).

On 21 October, with the Dock and the author's speaker, a PUI AST-1732MR-R (32 Ω, 0.2 W, from 1.7 kHz) on its SPK socket: **sound out**, `chips/d1/audio`, in the shape the author chose, a buffer the codec's interrupt plays from, as the UART's receiving has. The Dock's schematic, which the author downloaded past its captcha, settled the path (Appendix E): the codec's headphone output into an NS4150 amplifier that is always on. The self-check measures the rate, silently; `examples/lichee_rv_dock/tone.nim` and `tinytts-lutra`'s `dock/hello.nim`, which plays the 16x8 decoder's sentence rendered on the host, were heard, and the sentence was clear. The author committed this and the 16x8 work in Lutra (`c8a89c4`) and Steady (`7a94998`). `steady-xtheadvector` and `tinytts-lutra` are not yet under git: the author's to set up.

Later on 21 October, in a third session, with the Dock and the speaker, in the order and the shapes the author chose, **text to speech on the Dock, every step on the board**, and heard right by the author. Nothing in Lutra changed; the work is in Steady, `steady-xtheadvector` and `tinytts-lutra`, whose READMEs have the detail, none of it committed:

- **The decoder from z by itself**, `tinytts-lutra`'s `dock/speak.nim`, bit for bit with TFLite's reference kernels (whose 16x8 results are not its optimized kernels': those differ in 6495 samples of sentence 000).
- **The front through Steady**, quantized with 16-bit activations, as the author chose over float Nim: the text encoder with the duration predictor, and the flow, each one graph built in TensorFlow from TinyTTS's weights. With each matmul by a constant written as a 1x1 convolution (TFLite's 16-bit FULLY_CONNECTED requantizes in double), z is 42.9 dB from TinyTTS's; heard on the Dock as much the same as the decoder alone.
- **Steady**, for that: the 16x8 operators a transformer needs (broadcasting `Add`, `Sub` and `Mul`, `BatchMatMul` between activations through a new policy member, `ProductAccum(P)`, int64, the author's choice over a kernel-only one; int16 `Softmax`, `Rsqrt`, `Logistic`, `Mean` over the last axis, `Transpose`, `Gather`, `Split`), tensors of up to four dimensions, each input's and output's scale in the generated module, and, as the author chose for its value beyond TinyTTS, **a length given at run time**: `steadyc --bound N`, every size a polynomial in the length, `invoke(n)` and `macs(n)`, the arena planned at the bound. And **a rewrite stage**, which the author agreed to, whose first rewrites are relative attention's skew, its inverse, and the scores' addition of it. Every model in Steady's harness agrees as before, the existing models' generated code is byte for byte unchanged, and the seven TinyTTS models are exact, the two with an open length at every length tried from 1 to the bound.
- **G2P**, the dictionary and g2p_en's GRU together, the GRU through Steady a step at a time, as the author chose: `tinytts-lutra`'s `src/`, TinyTTS's normalization after `advanced_normalize`'s own patterns (the author's choice of scope), inflect's numbers, BERT's word splitting, and a 1.35 MB dictionary of what TinyTTS's own code makes of every reachable word. On the host, every test sentence's ids are TinyTTS's own, and 57,031 numbers are inflect's.
- **On the board**, `dock/tts.nim`: a line on the console to speech. `dock/say.nim` checks the whole chain against `export/chain.py`, which does it through TFLite's reference kernels: sentence 000's samples' CRC-32, `b431b178`, agree.
- **Faster**, in `steady-xtheadvector`, measured op by op with `dock/profile.nim`: attention's matmuls (the C906 has no 64-bit vector elements, so 32-bit sums that saturate are redone in 64 as two halves, and K's are split into bytes; columns in tiles that stay in the 32 KB data cache, the D1 having no second level), the int16 softmax, LayerNorm's broadcasting, and the fused band. The flow at 605 frames, 7 s of speech, went from 6390M cycles to 1390M; a 7 s sentence's first sound came 7.0 s after the line was sent, and comes 2.0 s after now; sentence 000's, 3.9 s of speech, 0.9 s after its phones. The whole sentence, after the first chunk, plays as it is decoded.

On 22 October, with the Dock and the speaker, **faster**, everything still bit for bit (`say.nim`'s `b431b178`, `nim steady`'s `5936432b` and `ab2fdbf1`, the self-check, the vector backend's differential test, and the text path's ids for all 20 test sentences, the same on the board as on the host):

- **The D1's prefetching**, which the boot ROM leaves off, on from the start (Appendix E): streams through DRAM twice as fast. The one change in Lutra.
- **`steady-xtheadvector`**, whose README has the detail: a GRU's step, a convolution of one pixel, summed along its taps instead of transposing its weights each time, 6.6M cycles to 1.5M; narrow layers from their input laid out a channel after another, a load serving four filters; four pixels a pass in the convolutions; Q times K with Q split into bytes rather than K, one load where there were two; and a matmul whose sums cannot pass 32 bits, as softmax's rows times V, with no saturating and no check.
- The decoder, a chunk of 0.37 s of speech, went from 355M cycles to 213M, 1.75 times as fast as speech; the flow at 605 frames from 1390M to 1040M; the text path from 221 ms to 51 ms. The 7 s sentence's first sound comes 1.33 s after the line, from 2.0 s; sentence 000's 645 ms after its phones, from 895.
- **Louder**, at the author's asking: TinyTTS's speech plays at -3 dB, from -6. Its samples peak at -4.5 dBFS and average -20; taking the NS4150's gain as 240 kΩ over the Dock's 33 kΩ, about 7.3, from an unreviewed copy of its datasheet, and the codec's full scale as 1 V rms, which is not measured, its loudest 100 ms come to about 40 mW into the 0.2 W speaker, and its peaks to about 4.4 V, short of the 5 V supply. At 0 dB its peaks would clip. `tone.nim`, a steady tone, stays at -12.

Where to pick up. **The Dock and TinyTTS**, which the author is after now. To put to the author:

1. **Fusing attention**, the one large saving left, and Steady's to decide, as it is a new op. The flow at 605 frames is 1040M cycles: matmuls 455M, convolutions 259M, softmax 150M, the band's addition 97M. Each layer's n by n scores, 1.46 MB at 605 frames, are written by Q times K, read and written by the band's addition and by softmax, and read by the matmul with V, six times through DRAM, about a quarter of the flow. A rewrite that fuses the band's addition into softmax would save two of the six; one op for the whole of relative attention, a few rows at a time, would save nearly all, and the arena at the bound would fall from 8.6 MB to tens of KB, but K and V would then be read once for every few rows, and the data cache is 32 KB, so it wants measuring first. The decoder's LeakyReLU and crops, which a rewrite could fold into the convolutions, are 14M of its 213M since the prefetching, so not worth it.
2. **A length produced by the graph**: the frames a sentence's durations add up to are worked out between two models, by the program. A graph that makes its own length, as an ONNX export of VITS would, is the next step for Steady's runtime length.
3. **Committing**: Steady's work is committed (`55c55a3`); `tinytts-lutra` and `steady-xtheadvector` are not yet under git, both the author's.
4. **Steady's int16 tanh table**, still to be settled, as before: Steady's own table when its own frontend comes, or now with a tolerance on that op. `Logistic` reads the same table.
5. **The ESP32-C3** (the plan's §3): the arena at 32 frames is 597 KB, so it wants a smaller chunk, and the C3's own measurement; the front's arenas at their bounds are 17 MB and 1 MB, so on the C3 the front stays on the host.
6. **Smaller gaps on the D1,** when something needs them: pin interrupts, which take the pin from its output, so a check of them needs a wire; the buffered UART, written and not run; the watchdog for programs; the reason it started; booting from the SD card without the host, which needs DRAM set up by the program (Appendix E).

Working with the Dock, on the author's machine (Appendix C): `LUTRA_PORT=/dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0`, which does not move as `/dev/ttyUSB4` did (two FPGA boards took the other four ports; on the evening of 21 October it was `ttyUSB0`), and `~/.local/bin` and `~/.nimble/bin` on the `PATH`. From `examples/lichee_rv_dock/`, `nim flash hello.nim` and `nim -d:reset -d:until=... -d:timeout=30s monitor` need no hands, nor does a program that panicked or faulted; one that hangs with interrupts off wants the board's reset button, and then a flash, which tells U-Boot `efex` itself. What cost time on 20 October:

- An image written to DRAM at `0x4000_0000` that does not start with Lutra's `fence.i` line runs stale instructions from the cache and hangs, until the reset button. Load only Lutra programs there.
- `print` works out its arguments as it sends them, so `print "label ", cycles() - start` counts the label's time on the wire, about 1.4M cycles for 16 characters. Take the time into a variable first.
- An `emit` or `asm` at the top level of a program is outside any function. Put it in a proc.
- GCC 15's `xtheadvector` support is young: it once placed a vector instruction under the wrong setting of the vector unit, which faulted as illegal. The fault report names the line; `objdump -d` shows what GCC did.

**Then, before the Dock,** in the order the author agreed on 17 October:

1. **Published** (§8). Since 19 October Lutra and its three drivers are in Nimble's list, at `v0.1.0`: `nimble install lutra_lis3mdl` into an empty Nimble directory fetched it and Lutra, and `nimble check` passes in all four repositories. A new release is a version in the `.nimble` file, a heading in `CHANGELOG.md`, and a tag (§8).
2. **Loose ends:**
   - `nim wifi` through the B-L475E-IOT01A's UART4: the sensor board's DevKitM-1 unplugged, the AT module's plugged in, and its IO6, IO7 and ground wired to the B-L475E-IOT01A's D1, D0 and ground in place of the D0 to D1 jumper.
   - With both DevKitM-1 attached, `nim wiring` and `nim link`, which have not run since the tasks changed (§4.3).
   - Steady's other five models on both boards, with `nim -d:model=... steady`: §10's acceptance test for a board, of which only `kws` has run.
   - The tasks on a real Windows or macOS machine, if the author has one: `nim doctor`, `nim flash`, `nim monitor -d:reset`, `nim capture`. Whether Windows ports are found by their drivers' names is a guess (§4.3).
3. **Keyword spotting from a live microphone**, on the B-L475E-IOT01A's own two MP34DT01s, through its DFSDM. The author has no I2S microphone, so the C3 waits. The front-end and Steady's `kws` already agree with the host bit for bit (`nim keywords`), so the new work is the DFSDM and a window of samples. This was M3's exit before it was reshaped (§11, M3).
4. **The board answering aloud**: the STM32L475's DAC, on PA4 or PA5, played from a timer, with the answers to the twelve words rendered on the host by TinyTTS and kept in flash as 4-bit ADPCM, about 4 KB a second (§11, "Later"). Ask first what the author's speaker is: a bare one needs a transistor or a small amplifier, such as a PAM8302.
5. **Then:** flash storage and the settings store, whose shape is to be put to the author first (below); the gesture demo, which has its filters and a spectrum and needs a model and the window of samples; PWM and ADC on both boards before a release; sleep, with the battery demo. Of §4.4, a host board and `nim size --budget` are left.

- **Left in M5:** raw flash storage on both chips and the settings store, which would also hold the Wi-Fi network, given for now when a program is built, from the environment; the LoRa driver; and the window of samples and the demos (§11).
- **Left by earlier milestones**, and worth going back to before a release: the table at the end of §11, M5.
- **Storage in flash** is set out in §8.4: how it works on each chip, what it opens up, three layers, and littlefs not yet. Before writing the settings store, put its shape to the author with an example of each: a small key-value store with wear-levelling, or a typed settings object saved and loaded whole and checked when the program is compiled. The second suits Lutra's way of settling things at compile time. `lutra/crc`'s `crc32` is there for it.
- **Hardware:** as of 20 October only the Lichee RV Dock is attached, its console through a CP2102 adapter and the module's USB-C to the computer, its SD card holding Sipeed's Linux, which does not start (Appendix E). The B-L475E-IOT01A, with jumpers from D0 to D1 and from D11 to D12, and the two DevKitM-1 are not (Appendix C).

What exists, all exercised on hardware:

| Area | What |
|---|---|
| Bring-up | Startup from the boot ROM, 160 MHz, flash mapping, a linker script generated from the board's memory description |
| Pins | GPIO, pulls, edge interrupts as `{.interrupt: pin.falling.}` procs, compile-time ownership |
| UART | Both ports, polled or received through an interrupt into a ring buffer, on any pins |
| SPI | Controller, and a target driven by DMA, with a ready line between them |
| I2C | Controller, on any pins. Reads and writes verified against a real sensor |
| LED | The board's addressable LED, as `rgbLed.color(green = 20)`. Its pulses are checked on the pin, and its colours were seen by eye |
| Other | Microsecond time and delays, the cycle counter, a random number source, `critical:` sections, timer events as `{.interrupt: every(10.ms).}` procs, a panic report that names the line of a failed check (§5.6), the watchdog, the reset reason and `restart` (§7) |
| Tasks | `{.task.}` procs that take turns, `wait cond` and `wait(cond, within = ...)`, a drift-free `for turn in every(10.ms)`, and a report of a task's stack overflowing (§5.5) |
| Libraries | Printing without a heap, into a fixed `Text` too, JSON, log levels, a debounced button, random numbers from a seed and waits for trying again, a fixed-size list, reading numbers, CRC-16 and CRC-32, a ring buffer, durations, COBS framing with a CRC, records for `nim capture`, a square root, logarithms and trigonometry in whole numbers, filters, running statistics, sorting, a median and percentiles, a spectrum, and the audio front-end a keyword-spotting model needs |
| Connectivity | A `Socket` interface, an engine for AT commands, and an MQTT client that publishes and subscribes (§8.3) |
| Beside this repository | Three driver packages, each verified on the real part: `lutra_lsm6ds33`, for an accelerometer and gyroscope, `lutra_lis3mdl`, for a magnetometer, and `lutra_espat`, for Wi-Fi through an ESP32 running Espressif's AT firmware. Each is a repository of its own (§8) |
| Host side | `build`, `flash`, `monitor`, `capture`, `size`, `selfcheck` and `doctor` tasks, with exit codes that say what failed; a `monitor` that ends at a line, a time or a panic and can send a line; and checks that stop a build that would not run (§4.4). They need no shell tools, through `lutra/host/monitor` (§4.3) |

On the B-L475E-IOT01A, also exercised on hardware: bring-up at 80 MHz, pins and their edge interrupts, the console on USART1 and a second UART, UART4, each polled or through an interrupt, SPI1 as controller, I2C, random numbers, time, the cycle counter, `critical:` sections, tasks, timer events, data capture, panics, a fault report of Lutra's own (§5.5), the watchdog, the reset reason and `restart`. `hello.nim` is the same program in both boards' folders of `examples/`.

How to confirm nothing is broken. Appendix C has the machine's set-up; with two boards of one kind attached, the single-board commands need `LUTRA_PORT` or `-d:port=...`. The checks run on the DevKitM-1 unless `-d:board=b_l475e_iot01a` comes before the command.

| Run | From | Proves |
|---|---|---|
| `nim r` on each `tests/t*.nim` | `tests/` | Formatting, `Text`, decimals and JSON, reading numbers, CRCs, framing, the ring buffer and the list, random numbers and backoff, the debounced button, claims, the memory layout, the arithmetic and trigonometry, filters, statistics, the front-end and the spectrum, and MQTT, on the host. `nim r -d:live tmqtt.nim` also runs MQTT against test.mosquitto.org |
| `nim selfcheck` | `checks/` | The board: clock, time, pins, interrupts, flash, I2C with nothing on it, the LED's pulses, tasks, timer events, no watchdog, the fault report. Takes 45 s |
| `nim steady` | `checks/` | Steady's `kws` gives checksum `ab2fdbf1` |
| `nim echo` | `checks/` | 64 KB at 921600 baud comes back intact, polled and buffered |
| `nim wiring`, then `nim link` | `checks/` | Two wired boards exchange 200 buffers over UART1 and 200 over SPI |
| `nim keywords` | `checks/` | Twelve recorded words are recognised on the board, from features that match the host's bit for bit. The first run downloads 112 MB of recordings |
| `nim sensors` | `checks/` | With the sensor board on IO18 and IO19, lying still: both chips answer through their drivers at the rates asked for, gravity is 1 g, and a refused transaction does not spoil the next |
| `nim -d:board=b_l475e_iot01a selfcheck` | `checks/` | The other board: its clock against its crystal, time, pins, interrupts, flash, I2C, tasks, timer events, no watchdog, the fault report. Takes 45 s |
| `nim -d:board=b_l475e_iot01a sensors` | `checks/` | That board's own LIS3MDL answers through the same driver, at the rate asked for, and a refused transaction does not spoil the next |
| `nim -d:board=b_l475e_iot01a steady` | `checks/` | Steady's `kws` gives `ab2fdbf1` there too |
| `nim -d:board=lichee_rv_dock selfcheck` | `checks/` or `examples/lichee_rv_dock/` | The Dock: clock, time, the cache, the FPU, the vector unit, a pin, constants in DRAM, the LED controller's word sent, tasks, timer events, interrupts held off, the audio codec taking a second of samples in a second through its buffer and interrupt, silently, no watchdog, the fault report. Takes 58 s, with the host loading it twice. Whether the LED shows the colours is for an eye, `nim flash rgb.nim`, and whether the speaker sounds for an ear, `nim flash tone.nim` |
| `nim -d:board=lichee_rv_dock steady`, and with `-d:backend=../../steady-xtheadvector/src` | `checks/` | `ab2fdbf1`, in 23.8M cycles, and 4.4M with the vector backend |
| `nim -d:board=lichee_rv_dock -d:model=tinytts_decoder steady`, and with `-d:backend=../../steady-xtheadvector/src` | `checks/` | TinyTTS's decoder, with `tinytts_decoder.tflite` copied into Steady's `tests/models/`: `5936432b`, as TFLite's reference kernels give, in 1722M cycles, and 213M with the vector backend |
| `nim flash differential.nim`, then `nim -d:reset -d:until=END -d:timeout=180s monitor` | `tests/` of `steady-xtheadvector` | The vector backend agrees with Steady's reference kernels on 300 random convolutions and 300 depthwise ones, its requantising with Steady's on sums at the ends of int32, and for 16-bit activations on 300 convolutions and 300 rounds of an addition, a LeakyReLU and a crop |
| `nim -d:board=b_l475e_iot01a loopback` | `checks/` | With jumpers from D11 to D12 and from D1 to D0: SPI1 brings back what it sends, into an input as long or shorter, and so does UART4, through its interrupt |
| `nim resets`, and with `-d:board=b_l475e_iot01a` | `checks/` | Each board says the host reset it; fed, the watchdog waits, and starved for 300 ms it resets the board, which says so; then the board restarts, and says so |
| `nim -d:board=b_l475e_iot01a echo` | `checks/` | 64 KB at 921600 baud through the ST-LINK comes back intact, polled and buffered |
| `nim flash record.nim`, then `nim capture > button.csv` | `examples/` of either board | The CSV has its header, then turns from 0 with none missing |
| `nim wifi` | `checks/` | With the second DevKitM-1 running Espressif's AT firmware and wired as for `nim wiring`, `lutra-espat` beside this repository, and the network in `LUTRA_WIFI_NETWORK` and `LUTRA_WIFI_PASSWORD`: the board joins it, and 20 messages to test.mosquitto.org come back in order, a long one whole; one too long is refused, the messages end when the connection does, and it connects again. With both boards attached it needs the port named |
| `nim r tlsm6ds33.nim` and `nim r tlis3mdl.nim` | `tests/` of `lutra-lsm6ds33` and `lutra-lis3mdl` | Each sensor's driver against a stand-in for the bus |
| `nim r tespat.nim` | `tests/` of `lutra-espat` | The AT driver against a stand-in module that answers as the real one was seen to |

Conventions the code follows:

- **A chip is a folder of small modules.** `registers.nim` holds every address. `peripherals.nim` holds the types and instances and has to stay pure Nim, because `config.nims` imports it too. `host.nim` is the NimScript side: compiler flags, linker script, flashing, the link audit. `memory.nim` is shared by both sides.
- **A chip's `host.nim` provides `configure`, `audit`, `size`, `flash`, `compiler`, `flasher` and `resetCommand`**, and a board provides `memory`, `console` and `consolePorts`. That is all `lutra/project` asks of them.
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
    arch/riscv32/            start.nim, trap.nim, context.nim
    arch/armv7m/             start.nim, interrupts.nim, fault.nim, context.nim
    arch/riscv64/            start.nim, trap.nim, fault.nim, context.nim
    chips/esp32c3.nim        and chips/esp32c3/, one module per peripheral
    chips/stm32l475.nim      and chips/stm32l475/
    chips/d1.nim             and chips/d1/
    boards/esp32c3_devkitm1.nim
    boards/b_l475e_iot01a.nim
    boards/lichee_rv_dock.nim
    hal/                     the interfaces: pin, bytelink, i2c, spi
    reg, claims              registers and compile-time ownership
    fmt, time, tasks, records, containers, framing, fixed, signal, ...   libraries (§8)
    host/                    programs for the host that the tasks build: the monitor (§4.3)
    selfcheck/               each board's self-check and its expected output (§5.8)
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
| `capture` | Reset the board and write its records as CSV to stdout, and everything else it says to stderr (§8.2) |
| `size` | Build, and show per-region sizes against the board's budgets |
| `selfcheck` | Build, flash and run the board's self-check, and compare the output |

The self-check command is not called `check` because `nim check` already exists.

Nim rejects flags it does not know, so options are defines placed before the command, for example `nim -d:port=/dev/ttyUSB1 flash hello.nim`. The serial port can also be named in `LUTRA_PORT`, and is found without help when only one board of the kind is attached: a board says what a host calls its console's port, `ttyUSB` for the DevKitM-1's bridge and `ttyACM` for an ST-LINK.

`-d:board=b_l475e_iot01a` builds a project for another board than its `config.nims` names. Lutra's own checks name the DevKitM-1 and serve the other board this way.

The DevKitM-1 is flashed with `esptool` and the B-L475E-IOT01A with `pyocd`, through its debug probe. Each is looked for on the `PATH`, or named in `ESPTOOL` or `PYOCD`.

Not built yet: selecting a board by MAC address, and an "all attached boards" mode. Krill flashes up to 16 boards at a time. Port names swap when boards are replugged, so the two-board checks simply take the two ports in name order.

`checks/config.nims` adds tasks that are not for every project: `steady`, `echo`, `resets`, `loopback`, `wiring`, `link`, `sensors`, `keywords` and `wifi`. These only work from Lutra's repository, because `checks/` is not installed with the package. `selfcheck` is installed: each board's program and its expected output are in `src/lutra/selfcheck/`, and the task copies the program into the project's `build/` folder to build it there, as Nim takes `config.nims` from a program's folder and those above it.

**Decided**, 17 October 2026: the tasks need no shell tools, so that they run on Linux, macOS and Windows. What NimScript cannot do (Appendix B) is done by `lutra/host/monitor`, a program for the host that the tasks build the first time they need it, named after its sources so that a change builds it again. It opens the port (termios on Linux and macOS, Win32 on Windows), lists the ports, resets the board, sends a line, reads until a line, a time or a panic, names the line of a panic, decodes records, and ends with an `Exit` code. It replaced a pipeline of `sh`, `stty`, `awk` and `timeout`, and `capture.nim`. On Windows a port is opened by one program at a time, so the monitor lets go of it while the board is reset, and what the board says straight after is lost; Linux and macOS hold it throughout. On Windows the kind of port is told by its driver's device name, `Silabser` for the DevKitM-1's bridge and `USBSER` for the ST-LINK, from memory and not tried.

**Verified** on Linux with both boards, every check in §1.2 that needs no second DevKitM-1. The Windows build, cross-compiled with Zig and run under Wine with COM5 mapped to the B-L475E-IOT01A, listed the ports, sent a line and read the answer, ended at a line and at a time, and decoded records; the reset there was not tried, as the reset command is a Linux program. The macOS build compiles and links, and has not run. The `link` check still runs one capture in the background with a POSIX shell's `&`.

### 4.4 Agents as users

**Proposed**, October 2026, from the author's notes on making Lutra and Steady easier for coding agents to use, and not yet agreed. Agents use Lutra two ways: writing firmware on top of it, and adding boards, chips and drivers. Most of what helps them helps people too.

The M5 session that added MQTT was evidence. `nim monitor` only listens and never ends, so talking to the AT module took a bridge program and a Python script, and every command was wrapped in `timeout`. With two boards attached each command needed the port named. Several of the Nim surprises in Appendix B were met again, though they were written down.

**Written**, 16 October 2026, of the table below: the bounded commands, `AGENTS.md` and `nim doctor`. `nim monitor` takes `-d:until=TEXT`, `-d:timeout=30s` and `-d:send=LINE`, as defines because Nim refuses an option it does not know before a task sees it, and as `-d:port` and `-d:reset` already were. The exit codes are `Exit` in `lutra/tooling`: 1 the build or the command line, 2 a check, or `until` not seen, 3 the board, 4 a missing tool or setting. A chip's `host.nim` now gives its `compiler` and `flasher` as `Tool`s, which the tasks and `nim doctor` both use, in place of `checkFlasher`.

Worth doing soon, most valuable first:

| Item | What |
|---|---|
| Bounded commands | `nim monitor` with an end, as `--until <pattern>` and `--timeout <duration>`, and a way to send the board a line. Exit codes that differ, and stay the same, for a failed build, a failed check, no board found and a missing tool |
| An `AGENTS.md` | Short, and pointing here: the commands that confirm a change, which checks need a board, and a crib of Nim on the target drawn from Appendix B. `CLAUDE.md` links to it |
| A host board | `board "host"`, with stand-ins for `Pin`, `ByteLink` and `I2cBus` that record what happens, and a real TCP connection as its `Socket`. Examples and libraries would run on a computer, with a record to check against, so CI and agents could test without a board. Libraries are already written against the interfaces, and the host tests already use stand-ins. Running real images under Espressif's QEMU or Renode would be a second step |
| `nim doctor` | Checks Nim, both compilers, `esptool`, `pyocd` and access to the serial ports, and says how to fix what is missing. Lutra and Steady should also want the same version of Nim |
| `nim size --budget` | A pass or a fail against a limit, rather than numbers to read |

Later: instructions for agents (skills) and templates for porting a board, adding a peripheral and writing a driver, once the interfaces stop moving; `{.deprecated: "use X".}` and a CHANGELOG from the first release; `nim pins` listing each pin's uses and claims.

Not now: a code for every error with a page each, since the errors already say what and where; a `lutra` program of its own wrapping the tasks; a registry of packages with manifests and conformance checks, with three drivers; a server for the Model Context Protocol, which should wrap the commands above once they print JSON; editor tooling. Dropping `sh`, `stty` and `awk` is done (§4.3).

The notes' items for Steady, such as checking a model for operators it lacks before generating code, belong in Steady's repository.

---

## 5. Key mechanisms

### 5.1 Registers

**Proposed:** generate typed register and field definitions from the vendor's SVD file. Evaluate existing `svd2nim` work in the EmbeddedNim community before writing a generator. Generated output lives with the chip and is not hand-edited.

**Verified** access idiom, from the seed code. It compiles to a direct volatile load or store with no function call:

```nim
type
  Volatile {.importc: "volatile unsigned int", nodecl.} = uint32
  Reg* = distinct uint32

proc load(address: uint32): uint32 {.importc: "*(volatile unsigned int *)", nodecl.}

template `[]`*(reg: Reg): uint32 = load(uint32(reg)) # Evaluated once, as a call
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

**Decided.** Interrupts are off unless a program asks for them. A handler is a proc whose pragma says what calls it, bound at compile time, and `start` switches it on:

```nim
proc pressed() {.interrupt: bootButton.falling.} =
  led.toggle()

proc either() {.interrupt: IO4.rising | IO5.falling.} =
  inc edges

start pressed
```

A timer is an event too: `proc tick() {.interrupt: every(10.ms).}` takes the next free hardware timer, and a program that wants more than the chip has does not compile: `every(3000 us) at a.nim(4) needs a timer, and the STM32L475's two are taken`. Neither does a period the timer cannot count. Without a timer, a task keeps a steady rate with `for turn in every(10.ms)`: each turn waits for its time counted from the first, so the rate does not drift, and a turn that would start late is skipped, its number with it. **Verified** on both boards (Appendices A and D): a 1 ms and a 250 ms event together, each counting what it should over 500 ms.

A second handler for the same source is a compile error, which names the lines of both. So is starting anything that is not a `{.task.}` or `{.interrupt.}` proc, and calling one as a proc. A variable a handler shares with the rest of the program has to be declared `{.volatile.}`. Events joined by `|` share one handler. A pin's events are `rising`, `falling` and `changing`.

**Decided**, October 2026: handlers and tasks are procs with a pragma, rather than the blocks they were first, `bootButton.onFalling: ...` and `task blink: ...`. They read as ordinary Nim, and the pragma puts a handler and what calls it in one place, where a mistake is a compile error. Declaring and starting are separate, so that a program can start one later or only sometimes. Nim cannot have a new keyword such as `task blink() =`; the parser rejects it before any macro sees it.

**Verified** on the C3:

- Binding is done by the linker. The chip's table of handlers refers to weak symbols, one per interrupt line and one per pin, and a handler is whatever defines the symbol. There is no table in RAM and nothing is registered at runtime.
- A program that uses no interrupts links none of this and keeps the vendor's trap vector.
- One level, no nesting: a handler runs to completion with interrupts off.
- `critical:` runs a block with interrupts off and leaves them as they were.
- A driver may own its interrupt. `uart0.buffer(4096)` receives through an interrupt into a ring buffer; without it, receiving is polled from the hardware FIFO and no interrupt exists. Which of the two a port uses is fixed at compile time.

The trap entry is the one part that is expensive to change later, so it is designed for tasking from the start:

1. **Trap entry saves the full register context on the current stack and can return onto a different stack.** This allows preemptive task switching to be added without rewriting the interrupt path. **Verified** as far as it goes: the entry passes the stack pointer to the chip's `lutraInterrupt` and resumes from the one it returns, which today is always the same.
2. **The architecture layer exposes a small context primitive:** prepare a stack, switch to it. This is per architecture, not per chip: one RV32 implementation serves every RISC-V chip. The tasking library (§8.1) is pure Nim on top of it. **Verified**, below.
3. **A driver's blocking waits go through one hook.** By default the hook does nothing and the wait spins. A scheduler replaces it with a hand-over, and no driver changes. **Verified**, with one rule added: a driver waits through the hook only on the world outside, as for a byte to arrive, and never part-way through something another task could break into (below).

Chip-specific facts that affect this on the ESP32-C3 are in Appendix A.3.

Default trap behaviour: leave the vendor's handler in place where it is useful. **Verified:** on the C3 the boot ROM's handler prints a full register dump on a fault. It then halts. It does not reset the chip.

**Decided:** once Lutra owns the vector, faults are still handed to the vendor's handler. **Verified:** Lutra's vector puts the vendor's `mtvec` back and returns to the faulting instruction with interrupts off, so it faults again into the boot ROM with every register as it was. No ROM address is hard-coded; the old `mtvec` is read when the vector is installed.

**Verified** on the STM32L475, where the core does more of this itself:

- The core reads its handlers from a table at the start of flash. The architecture layer writes the table, with a weak symbol for each of the chip's 82 interrupts, so binding is by the linker here too. A program that uses no interrupts links no handler; the table itself is 392 bytes and always there.
- The core saves the registers, so a handler is an ordinary procedure and there is no trap entry of Lutra's. Item 1 above is therefore still to do on this architecture, where a task switch belongs in the PendSV exception.
- Pin *n* of every port shares one line to the interrupt controller, so PA13 and PC13 cannot both have a handler. Asking for both stops the build: `Handling the interrupt that pin 13 of every port shares twice, at a.nim(9) and at a.nim(10)`.
- `critical:` and `{.interrupt: pin.rising.}` read the same as on the C3, and the self-check's test of them is the same source.

**Decided:** a Cortex-M has no vendor's handler to report a fault, so Lutra has a short one of its own in the architecture layer, which a board points at its console:

```
Fault: undefined instruction at 0x08000b66
       last call from 0x080004c6
```

It names an undefined instruction, a bad address (with the address, when the core knows it) and a jump to a bad address, and calls anything else unknown. The second line is the link register: where the last call made before the fault will return to. Then it halts. **Verified** with one of each, and with a fault inside an interrupt handler. The C3 keeps the boot ROM's report.

**Decided**, October 2026, for tasks:

```nim
proc blink() {.task.} =
  while true:
    led2.toggle()
    delay 250.ms

proc repeater() {.task(stack = 4.KB).} =
  while true:
    console.send console.receive() # Hands over until a byte comes

start blink
start repeater
if not wait(raised, within = 100.ms): print "Too slow\n"
```

- Tasks take turns: each runs until it waits, so the code between two waits is never interrupted by another task, and what tasks share needs no lock. `start` starts a task. The program itself takes turns with the tasks, and when it ends they go on.
- A new task joins the end of the line, so tasks take turns in the order they started. A task whose proc returns leaves the line. Starting a task that is running does nothing.
- Every wait hands over: `delay`, `wait cond`, `wait(cond, within = ...)`, which is false when the time ran out, and a driver's wait on the world outside. That is UART receive, an SPI device's ready line and an SPI target's wait for its controller. Sending on a UART, an I2C transaction, an SPI controller's transfer and the LED's pulses do not hand over, so a `print` comes out whole and two tasks can share a bus.
- A wait inside an interrupt handler does not hand over. On a Cortex-M the core says whether a handler is running. On RISC-V the trap entry sets a flag around the call to the chip's handler.
- A stack is 2 KB unless the pragma says otherwise. Its lowest word holds a known value, which is checked whenever its task hands over. If it has changed, `Task repeater overflowed its stack of 4096 bytes` goes to the console and everything stops.
- Tasks are cooperative only. Preemption would need locks around everything the bullet above leaves uninterrupted, and nothing asks for it yet.

**Verified** on both boards, by a section of each self-check and by `tasks.nim` in each board's `examples/`:

- The order of turns, a task ending, a `delay` in one task while another counts its own, `wait` with and without its time running out, and a handler that waits while a task is ready, which must not hand over.
- A hand-over takes 80 cycles on the STM32L475 and 77 on the C3: 1 µs and 0.5 µs.
- A program that starts no task is unchanged but for 8 to 12 bytes. The hook is a weak symbol, `lutraIdle`, that does nothing. The first `{.task.}` proc defines it again, as a call to the scheduler, and the linker takes that instead, as it binds interrupt handlers. Nothing else of the scheduler is linked without it.
- Switching stacks saves only the registers a call must keep: `ra` and `s0` to `s11` on RISC-V, `r4` to `r11` and `lr` on the Cortex-M, which has no floating-point registers to save while programs are built for software floating point. A new stack is set out as a switch leaves one, with the task's first instruction where it will return to. The library finds the architecture's three routines, `lutraSwitch`, `lutraPrepare` and `lutraInHandler`, by their names, through the linker.
- The overflow report, on both boards, from a task given 256 bytes that recursed far past them.

Where a stack goes decides whether its overflow can be reported. Task stacks, with what names each, go in a section of their own, after every other variable, and the scheduler's own two variables go above them. An overflow runs into the program's variables or a lower task's stack, never into what the report reads. **Verified** the hard way, with stacks first:

- On the B-L475E-IOT01A, below RAM is not RAM, and what is written there is lost without a fault (Appendix D). A task whose stack runs off the bottom of RAM jumps to address 0 on its next return. The fault report now starts on a stack of its own, the top of the program's, so it reports that jump once, rather than faulting again as it reports. That is still what happens when the lowest task overflows past every variable below it. On the C3 below the data is the window onto RAM code, which holds only startup code.
- The section the linker placed by its own size, at the top of RAM, would have avoided that: GNU `ld` cannot do it (Appendix B).

Not done: the trap vector and entry are in flash, so an interrupt can wait on a cache miss. Moving them to RAM needs the check in §5.3 to tell startup code from other RAM code.

### 5.6 Memory model

**Decided:** no allocator unless requested.

**Verified** complication: with `--mm:arc`, Nim's runtime keeps `malloc`, `free` and `exit` reachable even for a program that never allocates, about 1.4 KB. Steady builds with `--mm:none --panics:on` and links no allocator. Lutra's default configuration does the same. **Verified:** no allocator symbols are linked into the hello-world or the Steady benchmark. The heap opt-in is not built yet.

**Decided**, 16 October 2026: programs keep Nim's checks, and a failed one is reported on the console, and stops the board. `-d:danger` turns the checks off. Numeric code whose host tests already run with the checks on turns them off for the board, in its own module: Lutra's `signal` and `fixed`, and Steady's kernels.

```
Panic: index out of bounds at 0x420102f4, sensors.nim(42)
Panic: sensors.nim(12, 3) `x > 0` the sensor answered
```

**Verified** on the C3, for an index, an overflow, a range, a division by zero, an assertion and `quit`:

- Nim's own `system/fatal` raises a Defect, which allocates it and a message made with `&` and `$`. `lutra/project` puts Lutra's in its place with `patchFile`. Its `sysFatal` is a template, so the message is never made: it passes on Nim's text when that is a literal, the assertion's text, which already says where, or the Defect's name. It calls `lutraPanic`, which the board defines with `reportPanics console`, as it does `reportFaults`.
- Where the check failed is the return address of Nim's procedure that the check called, less 2 to fall inside the call. The image is built with debugging information, as DWARF 4 with Nim's line numbers, none of which is written to the board; `nim monitor` asks `addr2line`, in the image `nim flash` last wrote to that port, which line it is in. GCC merges the identical calls of different checks with `-Os`, and every overflow in a module was reported at the first; `-fno-tree-tail-merge` keeps them apart, and cost nothing in the self-check.
- Nim does not know that its check procedures never return, and goes on to the module's error test, which can call `exit`. The board defines `exit` too, as a panic, so the C library's is never linked. That saved 60 bytes even with `-d:danger` on the B-L475E-IOT01A.
- The cost, in the C3's self-check: 8,350 bytes of code with `-d:danger`, 8,690 with checks, 4%. In time, before the hot modules turned their checks off: the keyword front-end took 273 ms rather than 183, and Steady's `kws` model 847 ms rather than 277. After, 183 and 277.
- Checks found a bug at once: `char(uart.fifo[] and 0xff)` read the FIFO three times, once for each side of the range check and once for the value, and each read takes a byte. `Reg`'s `[]` now reads through an imported C expression that Nim takes for a call, and so evaluates once (§5.1). Reading into a `let` in the template did it too, but at a module's top level the `let` is a global, which cost 76 bytes and slowed a loop that times the LED's pulses until it missed them.

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

**Verified** on the B-L475E-IOT01A: the same list, in a program of its own, `src/lutra/selfcheck/b_l475e_iot01a.nim`. The clock is measured against the board's 32.768 kHz crystal, and the fault is reported by Lutra. A fault's report ends in an address, so the command accepts a last line that goes on past what was expected.

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
| `Socket` | connect to a host and port, send, receive, close. Receive waits, and gives 0 once the connection is gone | `lutra/mqtt`. Implemented by `lutra_espat`, outside this repository |

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
| Core | Startup, clock, memory layout, GPIO, UART both ways, time, delays, cycle counter, interrupts, timer events, critical sections, console, panics, the watchdog, reset reason, restarting | A trap report of Lutra's own, sleep |
| Buses | SPI controller, SPI target with DMA, I2C controller | DMA for the SPI controller; I2C target |
| Timing and analog | Addressable LED | PWM, ADC, pulse capture |
| TinyML inputs | Hardware RNG | I2S, raw flash storage |

And on the STM32L475:

| Tier | Verified | Not written |
|---|---|---|
| Core | Startup, clock, memory layout, GPIO, USART1 and UART4 both ways, polled or through an interrupt, time, delays, cycle counter, interrupts, timer events, critical sections, console, panics, a fault report, the watchdog, reset reason, restarting | Sleep |
| Buses | I2C controller, SPI1 as controller | DMA, SPI target, I2C target |
| Timing and analog | | PWM, ADC, pulse capture |
| TinyML inputs | The hardware RNG | I2S, raw flash storage |

Of what the C3 has, it lacks only the SPI target, which Krill needs and the B-L475E-IOT01A does not serve, and the addressable LED, which it does not carry.

**Decided**, 17 October 2026, for the watchdog and the reason a board started, and **verified** on both by `nim resets`:

```nim
print "Started after ", resetReason(), "\n" # powerOn, resetPin, watchdogTimeout, software, brownout, wake, other
watchdog.start(within = 2.sec)              # Once; it can't be stopped
for turn in every(100.ms):
  if healthy: watchdog.feed()               # The program feeds it, where it has shown it is well
restart()                                   # Once the console has sent what it was given
```

- The program feeds the watchdog rather than the scheduler, because a task stuck waiting forever, the usual hang, still lets the others run.
- It can't be stopped, because the STM32L475's can't. Its time is checked when the program is compiled: 1 ms to 49 days on the C3, 125 µs to 32 s on the STM32L475, whose oscillator is only roughly 32 kHz.
- The DevKitM-1's EN button and the host's reset both read as `powerOn`, and the STM32L475 can't tell a brownout from power coming on. Its reset flags are kept across resets, so its startup reads and clears them, which costs every program 44 bytes of flash and 4 of RAM. Flashing it leaves `software`, as the probe asks the core to reset.
- The enum's value is `watchdogTimeout`, not `watchdog`, which is the constant: Nim takes the one name as ambiguous. `print` now writes any enum by its name, from a table of `cstring`s in flash.

---

## 8. Libraries

**Decided** rule for placement, October 2026:

| Lives in | What | Examples |
|---|---|---|
| `lutra` itself, as `lutra/<name>` | Anything written only against the `hal/` interfaces, with no specific part number in it | Everything in §8.1; framing, the signal front-end, the sampling pipeline, the AT command engine, the settings store |
| Its own package, `lutra_<part>` | Anything tied to one external chip or module, or maintained by someone else | `lutra_lsm6ds33`, an SX126x LoRa driver, a driver for one cellular modem |

- Nim compiles only what a program imports, so a bundled library costs nothing in the image. What it costs is sharing Lutra's version: a breaking change in one bundled library is a breaking release of all.
- First-party drivers are separate packages from the start, to prove the interfaces can be used from outside this repository. The first two are for the chips on the author's sensor board: `lutra_lsm6ds33`, at `github.com/Lutra-Nim/Lutra-LSM6DS33`, and `lutra_lis3mdl`, at `github.com/Lutra-Nim/Lutra-LIS3MDL`. Each covers starting its sensor and reading it. Their examples and tests use Lutra as an installed package; `nim sensors` finds them as checkouts beside Lutra's, in `lutra-lsm6ds33` and `lutra-lis3mdl`.
- How settled a module is belongs in its documentation, not in where it lives.

**Proposed**, October 2026, for where the packages live and how they are found, and not yet agreed:

1. **A GitHub organisation.** **Done** 16 October 2026: `github.com/Lutra-Nim`, since `lutra` is taken (§1.1). The four repositories moved to it before the first release, so that the release's links are the lasting ones: every driver and tutorial pointing at the author's own account makes moving dearer later, and GitHub's redirects do not reach Nimble's list or other people's notes. It also lets someone else keep a driver without holding the keys to Lutra, which answers part of the one-maintainer risk (§12).
2. **Lutra installable by Nimble.** **Done**, see below.
3. **The packages in Nimble's own list**, `nim-lang/packages`, with a tag they share, `lutra`. Then `nimble install lutra_lis3mdl` works with nothing set up. A package list of Lutra's own would make every user add it to their configuration first. **Done**: merged on 19 October 2026, as `nim-lang/packages` pull request 3579, after the four repositories were tagged `v0.1.0`; installed from GitHub into an empty Nimble directory, all four came, the self-check with Lutra.
4. **A directory of Lutra's own, later**: when there are a dozen packages or so, or people the author does not know are writing them. Until then the README's list of drivers serves. When it comes, it is a repository in the organisation holding an index in JSON, an entry for each package: the interfaces it needs or provides, its bus and address, the boards it was tested on, and the checks it passes. A page is made from the index, and agents read the index itself (§4.4). Nimble's list holds only a name, an address and tags.

**Decided**, October 2026, for releases, after the author chose each:

- **Versions are git tags**, `v0.1.0` first, on all four repositories, which is how Nimble finds them. While Lutra is 0.x, a release that breaks a program goes up in its second number and any other in its third. The drivers ask for one second number, `requires "lutra ^= 0.1"`, so a breaking release of Lutra cannot break a driver someone has installed. `CHANGELOG.md` starts with 0.1.0, as §4.4 planned.
- **The self-check is installed** with the package, so `nim selfcheck` runs from any project.
- **The drivers' examples and tests use the installed Lutra.** `nimble install -d` in a driver's repository installs it. To work on Lutra and a driver together: `nimble develop -a:../lutra` and `nimble setup` in the driver's repository, once. That writes `nimble.develop` and `nimble.paths`, which hold the machine's own paths and are ignored, and a `config.nims` that reads `nimble.paths` where there is one, which is kept. Nimble's global develop link, `nimble develop -g`, was tried and Nim did not find Lutra through it: the link names the repository, not its `src`.
- **"TinyML" is not in what the packages say of themselves.** Lutra is for any microcontroller; TinyML is the author's aim with Lutra and Steady, and stays in this document.
- **The four packages go to Nimble's list in one pull request**, tagged `embedded`, `microcontroller` and `lutra` among others.

**Verified**, October 2026: the four packages install with `nimble install` into an empty Nimble directory, Lutra's self-check files with them, and each driver resolves `lutra ^= 0.1`. From a new project outside these repositories, with only the installed packages: `hello.nim` and a driver's example build, `nim doctor` builds the host's monitor from the installed copy, and `nim selfcheck` passes on both boards. A project's `config.nims` finds `lutra/project` because Nim reads Nimble's package folder, `~/.nimble/pkgs2`, from its own configuration before a project's; given on the command line as `--nimblePath`, the folder comes too late for `config.nims`. `nimble check` passes for Lutra; each driver's fails until `lutra` is in Nimble's list. Nim's list asks that a package build with the latest Nim, 2.2.12: with it, every host test and example of Lutra's and the drivers' builds and passes, both self-checks pass, and a panic names its line. Its `system/fatal`, which Lutra replaces (§5.6), changed only for `--os:standalone`, which Lutra does not use.

The earlier rule was narrower: only what every other library must agree on was core, and everything in §8.2 to §8.4 was a separate package.

Written so far: printing, into a `Text` and as decimals (`fmt`), logging (`lutra`), reading numbers (`parse`), CRCs (`crc`), durations and the `every` of timer events (`time`), tasks (`tasks`), records for capture (`records`), a ring buffer (`containers`), framing (`framing`), a square root, logarithms and trigonometry (`fixed`), filters (`filters`), statistics and sorting (`stats`), the audio front-end and a spectrum (`signal`), AT commands (`at`) and an MQTT client (`mqtt`). The third driver package is `lutra_espat`, at `github.com/Lutra-Nim/Lutra-ESPAT` and checked out beside this repository as `lutra-espat`, for Wi-Fi through an ESP32 running Espressif's AT firmware; it is a repository of its own because it is tied to one module's firmware.

### 8.1 Core

| Library | Contents | Reason |
|---|---|---|
| Printing and logging | Allocation-free formatting of integers, hex and fixed-point; log levels | Every program needs output and there is no heap by default. Steady's benchmark hand-rolls this today |
| Fixed-size containers | Ring buffer, queue, bounded string; safe between an interrupt and main code | UART receive, AT commands, sensor streams |
| Time | Durations, deadlines, timeouts, periodic timers. Durations, `wait(cond, within = ...)` and `every` are written | Every driver and protocol waits on something |
| Fixed-point math | Q-format arithmetic; table-based `sin`, `exp`, `sqrt` | No floating-point unit on the C3 |
| Tasking | Cooperative tasks with statically sized stacks; signals from interrupts | Lets "sample, infer, transmit" be written as straight-line code |

Tasking uses stackful tasks, not Nim's closure iterators. Closure iterators need no assembly but allocate on the heap. **Verified** on both boards (§5.5). A signal from an interrupt needs nothing of its own: the handler sets a `{.volatile.}` variable and a task waits on it.

**Proposed**, October 2026, and not yet agreed: libraries still missing, in the order they would come. Most of Nim's standard library cannot stand in for them on the board. `std/algorithm`'s `sort` is a merge sort that allocates, and `parseutils.parseInt` raises on overflow, which allocates (Appendix B).

**Written**, 16 October 2026, the four the settings store needs, after the author chose each shape:

```nim
var topic: Text[32]                  # In fmt. What does not fit is dropped; `full` says so
topic.write "lutra/", hex(id), "/temp"
broker.subscribe(topic.chars)        # A converter cannot give an openArray, so `chars` does

var n: int32
if line.parseInt(n, start = 5) == 0: ... # lutra/parse: std/parseutils' names, never raising

print decimal(field.x, 3)            # 712 prints as 0.712
log.info "joined ", network          # 1532 ms info  joined home; -d:log=debug|info|warn|error|off
crc32(data)                          # lutra/crc, beside the crc16 that moved there from framing
```

`checks/wifi.nim` and `lutra_espat` now use `Text` and `parseInt` in place of their own. `lutra/mqtt`'s `Payload` stays, as it writes straight into the packet. `log` is one name, so that `info` and `error` stay free for programs, and `std/math`'s `log` does not clash with it.

With the gesture demo and the window of samples, which will show which are used:

| Library | Contents |
|---|---|
| Filters and running statistics | A moving average, a one-pole low-pass, a biquad, a median for spikes; a running mean and variance, by Welford's method, and the least and greatest. The variance is the core of a simple anomaly detector, and of scaling features for a model |
| Trigonometry in whole numbers | `atan2`, `sin` and `cos` from tables, and Q-format multiplying with rounding and saturation, as the table above has. A compass heading from the LIS3MDL, and tilt from the accelerometer |
| The FFT, exported | It is written, private to `signal`. Vibration, gestures and the sound of machines want a spectrum |
| A sort that does not allocate | Insertion sort is enough for a window of samples; then a median and percentiles |
| Steadying a model's answers | Averaging scores over the last few frames, with a threshold and a pause after each answer, as TensorFlow Lite Micro's `RecognizeCommands` does for keyword spotting, which flickers without it. Argmax, the top few, and turning int8 values into numbers and back, perhaps in Steady instead |

**Written**, 16 October 2026, the small ones, after the author chose each shape:

```nim
import lutra/button                   # Not exported by `lutra`: `pressed` and `held` would clash with handlers' names
const key = bootButton.debounced(held = 1.sec)
for change in key.changes: ...        # pressed, released, held; waits in between, as `broker.messages` does

var dice = seeded(42)                 # lutra/chance: xorshift, 4 bytes, the same numbers each run
dice.below(6)
var retry = backoff(first = 100.ms, most = 30.sec) # Doubling, each moved by up to a tenth, seeded by the hardware
delay retry.next()

print json(ax = ax, temp = decimal(t, 2), ok = true, at = json(x = 1)) # In fmt: {"ax":12,"temp":21.50,...}

var readings: List[16, int32]         # In containers: add, len, [], items, del as seq.del
```

**Verified**: each against tests on the host, the button against a stand-in pin and clock, bouncing; and on the C3, a press of the boot button made from the host through the USB bridge's DTR line gave one `pressed`, a `held` a second later and one `released`. A change counts once the pin has read otherwise for `settle`, 20 ms unless it says, timed from the first reading that differed.

**Written**, 17 October 2026, four of the five above, ahead of the gesture demo, after the author chose each shape. Steadying a model's answers is left, perhaps for Steady.

```nim
import lutra/[filters, stats, fixed, signal] # filters and stats are not exported by `lutra`

var
  smooth: MovingAverage[8]                  # Every filter and statistic takes `add`,
  slow = lowPass(hz = 2, sampleHz = 100)    # and gives `value`, or `mean` and the rest
  hum = notch(hz = 50, sampleHz = 1000)     # Biquads: lowPass2, highPass, bandPass, notch
  spikes: MedianOf[5]
  normal: Stats                             # count, mean, variance, deviation, least, greatest
spikes.add x
slow.add spikes.value

sort(window)                                # Insertion sort, in place
let m = median(window)                      # These reorder `window`, which the `var` shows
let p90 = percentile(window, 90)            # The nearest rank: always one of the values

let heading = atan2(field.y, field.x)       # An Angle, a 65536th of a turn, which wraps
print heading.degrees                       # 0 to 359
let s = sin(30.degrees)                     # Q16, as `log2` is
let g = mulQ16(s, gain)                     # Rounded, and held at the ends of int32
const half = q16(0.5)                       # At compile time only

fft(re, im)                                 # In place, exported from signal
spectrum(samples, strength)                 # Hann window and magnitudes. A sine of
                                            # amplitude 1000 shows as about 1000
```

- A filter's settings are worked out when the program is compiled, so `lowPass` takes `static` frequencies and a cutoff too slow for whole numbers is a compile error.
- `sin` and `cos` are within one 65536th, from a table of a quarter turn, and `atan2` within one 65536th of a turn, by CORDIC; a biquad and `Stats` keep extra fractional bits in their sums, so a slow filter or a small spread is not lost to rounding. Each limit is in the procedure's comment.
- **Verified** against floating point on the host, and on both boards a program using each gave the host's numbers exactly.

Until something needs them: a command line on the console, types for physical units, CBOR and base64, a priority queue, and a fuller fusion of sensors, such as Madgwick's filter.

### 8.2 TinyML

| Library | Contents | Reason |
|---|---|---|
| Signal front-end | Windowing, fixed-point FFT, mel features | A model needs the same preprocessing it was trained with. The code must give bit-identical results on the host and on the device |
| Sampling pipeline | Fixed-rate capture into windows, handed to a model. The fixed rate is written, as `every`; the window is not | The glue from sensor to Steady |
| Data capture | Device library and a host tool that records sensor data to files. **Verified** (below) | Users need data from their own sensor before they can train |

**Decided**, October 2026, for data capture:

```nim
for turn in every(10.ms):
  console.record(turn, ms = millis(), pressed = not userButton.read())
```

```
nim capture > button.csv
```

- A record is a packet of `framing`, so it arrives whole or not at all, and the board's `print`s can go between records. `nim capture` writes records to stdout as CSV and everything else to stderr, the boot ROM's messages included.
- Values are whole numbers or `bool`s, each a signed varint: seven small ones take about 14 bytes with the packet's own.
- A record's columns are named in the program: a value's name if it is given one, or else its expression. The names go with the first record from each line of the program and every hundredth after, so a capture recovers from a damaged first one.
- Before the program's first record goes a packet of a third kind, saying it has started. `nim capture` resets the board, and takes records only from that packet on: a board goes on recording until the reset takes it, which on the B-L475E-IOT01A is about 0.3 s after the monitor stops dropping what came before, and its first output after the reset comes before the reset command returns, so no cut by time is safe. Before this, a names packet from before the reset that fell in that window made its records the capture's first. Without a reset, records before the first names are dropped.
- The host's side is in Lutra, as a task, because Lutra already finds the port, resets the board and decodes `framing` on the host. It is built for the host the first time it is run.

**Verified**: `record.nim` in each board's `examples/` captured at 100 Hz on both boards, from turn 0 and with no turn missing; and on the C3, records of seven values at 1 kHz with the console at 921600 baud, 10,755 of them over 11 s with none missing.
| Starter drivers | One accelerometer, one I2S microphone, one environmental sensor, the addressable LED | They power the demos and are the template for third-party drivers. The accelerometer is done first, as `lutra_lsm6ds33` (§11, M3) |

### 8.3 Connectivity

| Library | Contents | Reason |
|---|---|---|
| Framed serial link | Packet framing with a checksum over a ByteLink | Data capture, host tools, and Krill's links between chips |
| AT command engine | Send a command, parse replies, handle unsolicited messages | Covers cellular modules, LoRaWAN modules, and Wi-Fi and BLE through a second ESP32 |
| Sockets and MQTT | The Socket interface and a small MQTT client | What most IoT backends expect |
| LoRa driver | Raw packets on a Semtech SX126x or SX127x over SPI | Small, pure Nim, needs no network infrastructure |

**Decided**, October 2026, for MQTT, and **verified** on the DevKitM-1 with the second one as its Wi-Fi module:

```nim
import lutra, lutra/mqtt, lutra_espat

const
  wifi = espAt(uart1)
  broker = mqtt(wifi.socket, "test.mosquitto.org")

uart1.buffer(1024)
uart1.init(tx = IO6, rx = IO7, baud = 115_200)

proc listen() {.task.} =
  for message in broker.messages:
    if message.payload == "on": rgbLed.color(green = 20)

if wifi.init() and wifi.join(network, password) and broker.connect():
  broker.subscribe("lutra/demo/led")
  start listen
  for turn in every(1.sec):
    broker.publish("lutra/demo/up", millis(), " ms")
```

- MQTT is Lutra's own, version 3.1.1, written against `Socket`, so that it works unchanged over any module that gives a TCP connection. Espressif's firmware has an MQTT client of its own, which would have been less code once and again for every other module.
- Publishing and subscribing came together, at the author's asking. A message reaches the program through `for message in broker.messages`, in a task, rather than through a proc with a pragma that a hidden task calls: it is plain Nim, and the program sees when messages are read. A message's `topic` and `payload` are `openArray[char]`, good until the next turn of the loop, and the loop ends when the connection does.
- A payload is written as `print` writes. Every call that waits for the module or the broker lets the other tasks run, and gives `false` if it failed rather than stopping.
- A broker is a constant, with the host in it, and each `wifi.socket` is another of the module's five, counted when the program is compiled. A sixth does not compile.
- QoS 0 only, both ways. No user name or password, and no TLS, though the firmware can do TLS. No keep-alive of MQTT's own: the module checks a connection after 60 s without traffic, and one found dead is closed, which ends `messages` and fails `publish`.
- A packet either way takes up to the broker's `size`, 256 bytes unless said; a message longer is passed over, and one to publish is refused. The broker's answer to a subscription is not waited for, because a message can come before it, so a topic the broker turns down goes unnoticed.
- `at` is generic and small: a command written as `print` writes, lines heard with a timeout, the module's `>` prompt as a line, a way to stop a line where binary data starts, and a turn at the module for one task at a time. What the answers mean is the module driver's.

### 8.4 System

| Library | Contents | Reason |
|---|---|---|
| Settings store | Key-value storage in flash | Credentials and calibration |
| Measurement | Cycle and energy measurement helpers, taken from Steady's benchmark | Users will want the numbers |

**Proposed**, October 2026, for storage in flash, and not yet agreed.

A region of flash that no image uses is set aside in the memory description, and written while the program runs. The C3's description already has a region held back at the end of flash, `reservedSize` (§5.2), with no way yet to set it. Flash is written by three rules:

- **A block is erased before it is written.** Writing turns ones into zeros; only erasing a block turns them back.
- **A block wears out**, after some number of erases, so what is written often has to move about.
- **Power can go part-way through.** What was there before has to survive: two copies, each with a count and a check, or a log that is only added to.

What the datasheets say of the two chips, not yet checked and so not yet in Appendices A and D:

| | ESP32-C3-DevKitM-1 | B-L475E-IOT01A |
|---|---|---|
| Flash | The module's SPI flash, 4 MB | The chip's own, 1 MB in two banks of 512 KB |
| Erased in | 4 KB sectors, in tens of milliseconds | 2 KB pages, in about 22 ms |
| Written in | Any size up to 256 bytes | 8 bytes at once, each 8 once only between erases, as it keeps a check code |
| Erases a block lasts | About 100,000 | About 10,000 |
| While writing | Code cannot be read from flash, so the writing has to run from RAM. The trap vector is in flash (§5.5), so interrupts are off throughout, and an erase silences them for tens of milliseconds: a UART at 115200 baud fills its 128-byte FIFO in about 11 ms. Writes have to be rare, or the vector and handlers moved to RAM first. The boot ROM has routines for erasing and writing, as it has for the cache | Only the bank being written stops. With storage in the bank the program is not in, the program and its interrupts go on |

What it opens up: settings, such as the Wi-Fi network, out of the image (§12); calibration measured once and kept, such as a gyroscope's offset at rest; data recorded where a device lives, with no cable, and read back later, which is how training data from the field is had; examples kept for learning on the device, or what normal looks like to an anomaly detector; a model replaced without the firmware, and later updates over the air (§8.5); a count that survives a reset, and the last fault report.

Proposed in three layers:

1. **Raw storage**: a region of the memory description, with erase, write and read, behind an interface of its own.
2. **The settings store**, on that. The author is still to choose between a typed settings object saved whole, in two copies taken in turn, each with a count and a CRC, and checked when the program is compiled; and a small key-value store with wear-levelling (§1.2). The first is about a hundred lines.
3. **A log of records**, later and if wanted: `records` added in turn around a ring of blocks. A packet of `framing` is found again after damage, which suits a log that power can cut.

**Proposed** for littlefs (`github.com/littlefs-project/littlefs`): not now. It could sit on the first layer, as it asks only for read, write, erase and sync, and can run on buffers it is given with no heap. It survives power cuts, moves wear about, and needs little RAM. But it is about 6,000 lines of C, to be wrapped rather than ported, against Lutra's aim of pure Nim; it is 15 to 20 KB of code for what a few hundred lines of Nim covers; and on the C3 its own housekeeping erases when the program has not chosen to, each with interrupts off. If a program wants files by name, rewritten in parts, or folders, littlefs can be a package of its own, `lutra_littlefs`, as `lutra_espat` is.

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

**Verified**, October 2026, of Espressif's AT firmware for the C3, version 4.1.1.0 for the ESP32-C3-MINI-1, the module on the DevKitM-1. It is the newest one can download; 4.2 is had by asking Espressif.

- One file, `factory/factory_MINI-1_unfilled.bin`, written at 0 with `esptool`. Its UART0 stays the module's log, and commands go to UART1: IO6 receives, IO7 sends, 115200 baud. Flow control is RTS only, on IO4, so the module never waits on its CTS, IO5. The wires `nim wiring` checks between two DevKitM-1 serve, with the board's `uart1` on IO6 to send and IO7 to receive.
- It starts as an access point and echoing commands; `init` makes it a station, turns echoing off, and stops settings being saved to its flash (`AT+SYSSTORE=0`).
- Data comes held, not pushed (`AT+CIPRECVTYPE=5,1`, all five links at once). The module says `+IPD,<link>,<bytes>`, with the bytes it holds in all, and `AT+CIPRECVDATA=<link>,<most>` gives `+CIPRECVDATA:<bytes>,` then the data, raw, then `OK`. After a read that leaves some, it says what is left.
- `AT+CIPSEND` answers `OK`, then `>` with no line ending; after the data come `Recv <n> bytes` and `SEND OK`. A connection closed says `<link>,CLOSED`, and reading from it then is an `ERROR`.
- Its built-in MQTT client is not used (§8.3).

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

**Verified** on the Lichee RV Dock, 20 October 2026: `nim -d:board=lichee_rv_dock steady` gives `ab2fdbf1` and 23.80M cycles, 23.6 ms at 1008 MHz, with Steady at `b90ea6d`: about 9 cycles for each of the model's 2.66M multiply-adds, in plain RV64 code with T-Head's extra instructions and no vector unit. The model is in DRAM, behind the 32 KB caches. The C3 took 43.64M cycles, 273 ms, and the STM32L475 41.65M, 520 ms. The image takes the console's interrupt, for a break, which does not come while the benchmark runs.

**Verified** the same day, with a backend for T-Head's vector unit, `steady-xtheadvector` beside Steady, which the author chose to keep in a repository of its own: `-d:backend=<folder>` before `nim steady` builds with `-d:steadyBackend` and that folder on the path, for any board. Its convolutions and depthwise convolutions gave `ab2fdbf1` and 9.88M cycles, 2.4 times as fast, and agreed with Steady's reference kernels on 600 random layers. Requantising each output, still scalar, was then nearly half of that.

**Verified** later that day: with the backend's requantising vectorised, 4.47M cycles, 4.4 ms, 5.3 times as fast as the reference kernels, and `ab2fdbf1`. Its test agreed on 900 random cases, and was seen to fail when the rounding of negative ties was taken out. The first convolution, with one input channel, is now the slowest layer, at about 49 cycles a tap.

**Verified** the same evening, TinyTTS's decoder for a chunk of 32 frames, quantized with 16-bit activations under Steady's new `AffineI16x8` (§1.2): on the Dock, `5936432b`, which is what TFLite's reference kernels give for the benchmark's input on the host, in 1771M cycles with Steady's reference kernels and 355M with the vector backend. A chunk is 0.37 s of speech, so that is 4.7 times slower than speech and 5% faster. 194M multiply-adds, a 597 KB arena and 255 KB of constants.

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

Begun October 2026. Tasks, timer events and data capture were the branch `feature/tasks`, MQTT `feature/mqtt`, and the tooling, panics, libraries and the B-L475E-IOT01A's new peripherals `feature/agents`.

- Context primitive, cooperative tasks, the wait hook.
- AT engine, sockets, MQTT, LoRa driver, settings store.
- Sampling pipeline and data capture, carried over from M3 and designed against the gesture demo's model.
- **Exit:** a gesture-recognition demo publishing over MQTT, and an anomaly-detection demo sending a LoRa packet.

**Decided:**

- Tasks came first: they needed no new hardware, and the rest builds on them. The author chose `wait cond` over `waitUntil cond`, and asked for timeouts and the overflow report in the first piece.
- Tasks and interrupt handlers are procs with a pragma, started by `start`, rather than the blocks they were first (§5.5). The author wants Lutra to read as ordinary Nim, and mistakes to be compile errors.
- The gesture demo waits, perhaps to become a demo of Steady's. Of what it needs, a fixed rate, data capture and a window of samples are Lutra's; the model, and the preprocessing that suits it, are the demo's. When it comes back, the model is a public one, such as TensorFlow's `magic_wand`, rather than one trained here.
- So M5 does the plumbing first: timing, then data capture (both done), then raw flash storage and the settings store, then connectivity. The author then took connectivity before flash storage.
- Timer events were asked for now, rather than when something needs them (§5.5).
- Wi-Fi, for MQTT, is the author's second DevKitM-1 running Espressif's AT firmware, wired to the first by the wires M2 left, rather than the B-L475E-IOT01A's own module, which needs an SPI driver for that chip and speaks a command set of Inventek's own. That module may come later, as a second `Socket`. LoRa is an RFM95W, an SX1276 at 915 MHz, not yet soldered.
- For MQTT the author took each recommendation but one: Lutra's own client over `Socket`, not the firmware's; the ESP-AT driver as a package of its own, the AT engine in Lutra; messages through a loop in a task. He asked for subscribing in the first piece, with publishing (§8.3).
- The Wi-Fi network is given when a program is built, from `LUTRA_WIFI_NETWORK` and `LUTRA_WIFI_PASSWORD`, until the settings store can hold it.
- Later on 17 October the author agreed the next steps (§1.2): Nimble and the loose ends, then keyword spotting from the B-L475E-IOT01A's microphones, then its answering aloud, ahead of flash storage, PWM and ADC. Several cores, speech and clusters are noted for later (§11, "Later").
- On 17 October the author took every recommendation: tasks with no shell tools through a Nim program for the host, rather than a Python script on `pyserial` or Linux and macOS only (§4.3); four of §8.1's five libraries, each in the shape recommended; a jumper for UART4 as for SPI1, so that both are checked without the AT module; and, of what was left, the watchdog and the reset reason (§7), rather than flash storage or PWM and ADC.
- On 16 October the author took, in this order: the tooling for agents (§4.4), the panic report (§5.6), the libraries of §8.1, and then the B-L475E-IOT01A's missing pieces, in one swap of cables. Each shape was his choice among two or three, and he took the recommended one each time: `-d:` defines for `monitor`; print and halt on a failed check, with checks on and hot modules turning theirs off; a `Text` written to, `std/parseutils`' names, `log.info`; button changes in a task's loop, `json(name = value)`, generators and backoffs as values kept.

**Verified**, on both boards, with every check in §1.2 passing after each:

| Piece | Where |
|---|---|
| Tasks: `{.task.}`, `start`, `wait`, `wait(cond, within = ...)`, the overflow report | §5.5, the self-checks, `tasks.nim` in `examples/` |
| Handlers as `{.interrupt: ...}` procs, events joined by `\|` | §5.5, the self-checks, `button.nim` in `examples/` |
| Timer events, `{.interrupt: every(1.ms).}` | §5.5, the self-checks |
| A drift-free loop, `for turn in every(10.ms)`, which skips turns it would start late | The self-checks |
| Data capture: `console.record(...)` and `nim capture` | §8.2, `record.nim` in `examples/`, `tests/trecords.nim` |
| MQTT over Wi-Fi, publishing and subscribing, through Espressif's AT firmware. On the DevKitM-1; the B-L475E-IOT01A's UART4 now works, and `nim wifi` through it has not been run | §8.3, §9, `nim wifi`, `tests/tmqtt.nim`, and `mqtt.nim` in `examples/` of `lutra-espat` |
| The B-L475E-IOT01A's UART4, receiving through an interrupt, `setBaud` at 921600, SPI1, random numbers and panics | §7, Appendix D, `nim loopback`, `nim echo`, the self-check |
| The watchdog, the reset reason and `restart`, on both boards | §7, Appendices A and D, `nim resets` |
| Tasks that run on Linux, macOS and Windows, through `lutra/host/monitor` | §4.3 |
| Filters, statistics, trigonometry and a spectrum | §8.1, `tests/tfilters.nim`, `tests/tstats.nim`, `tests/tfixed.nim`, `tests/tsignal.nim` |

Found along the way, and fixed:

- **The self-check's pin test read a pin straight after setting it.** On the STM32L475 that read gives the old level almost every time (Appendix D); it passed only because the compiler happened to put other loads between. It now waits a microsecond, on both boards.
- **A task declared inside a procedure never ran.** The scheduler's hook, which the first task declares, was left out (Appendix B).
- **`pyocd reset` stopped the board's core for a third of a second**, about 5 s into a reset that took 5.75 s. A capture showed it as 37 missing turns. A reset by the chip's reset pin, `pyocd reset -m hw`, takes 0.8 s and stops nothing, and every task now uses it.
- **Changing a UART's rate under bytes still going out garbles them**, and a receiver can take several more to find its feet. The C3's boot ROM leaves its last line in the FIFO, so a program that went to 921600 baud at once lost its first five records, names included. `setBaud` now lets the FIFO and its last byte go first.
- **Every timer event on the STM32L475 fired once as it started**, until the timer was told that only coming round counts (Appendix D).
- **`write` failed inside a generic procedure of another package**, as `link.write "AT+CWJAP=\""` in `lutra_espat` did, because it named `put` for the caller's module to find. It now binds `put` itself, leaving it open to the caller's own (Appendix B).
- **On the B-L475E-IOT01A, `buffer` before `init` received nothing.** `buffer` asked for the interrupt while the port's clock was off, and `init` wrote over it. Every program that buffers a second UART, as `nim wifi` does, writes them in that order. Fixed when `nim loopback` first ran UART4.
- **`nim capture` on the B-L475E-IOT01A could begin with records from before the reset**, as turns 600 to 605 once did, when a names packet fell in the 0.3 s before `pyocd` pulled the reset line. The shell pipeline had the same window. A program now says it has started before its first record, and a capture counts from there (§8.2). Recording at 500 Hz, which puts names in that window nearly every time, each of five captures on each board began at turn 0.
- **`nim loopback` panicked as written**, converting `i * 7` to a byte past 255, once checks were on. It had never run.
- **`print` could not print an `openArray[char]`**, which a message's payload is. It can now, and string literals take that path too, which cost 26 bytes of code in `hello.nim` and 54 in `tasks.nim`.

Of Steady's models, `ad` is MLPerf Tiny's machine-sound autoencoder, 640 inputs from five frames of 128 log-mel bands. The battery anomaly demo would need a different model, or a microphone and the sound of a machine.

What is left, in the order planned, and what each needs of the author:

| Piece | Needs |
|---|---|
| Raw flash storage on both chips, then the settings store | Nothing new. How settings are written is still to put to the author (§1.2) |
| Wi-Fi on the B-L475E-IOT01A itself | ST's list for the board, not yet checked against the board, has an Inventek ISM43362 module, driven by AT-style commands over SPI. It would be a second `Socket`, and needs an SPI driver for the STM32L475 first |
| The B-L475E-IOT01A's two MP34DT01 microphones, from the same list | The chip's DFSDM. They would serve keyword spotting from a microphone, and `ad` |
| LoRa driver | The RFM95W soldered and wired, which the author will do only once it is needed, and a second radio or a gateway to hear it |
| A window of samples, handed to a model | Nothing new, but best designed with a model in hand |
| The demos | Models for them (above) |

Left by earlier milestones, and worth going back to before a release, most important first:

| Gap | Why it matters |
|---|---|
| Steady's other five models | §10's acceptance test for a board is all six of Steady's models giving their reference checksums. Only `kws` has been run, on either board |
| A microphone | M3's exit was keyword spotting from a microphone, reshaped for want of one (§11, M3). The B-L475E-IOT01A carries two, through its DFSDM, and an I2S microphone would serve the C3 |
| PWM and ADC | Left until something needs them (§11, M3). An Arduino user expects both early, and §7 has them as a tier of their own |
| Sleep | In §7's core tier, and what the battery demo needs. The watchdog and reset reason are done |
| Generated register files | About sixty addresses on the C3 are hand-written, and each peripheral adds several (§12). It matters once a third chip comes |

A first serious public release is M0 through M5.

### Demos

Three use models Steady already runs on the C3.

| Demo | Chain |
|---|---|
| Keyword spotting | Microphone, front-end, `kws` model, LED |
| Gesture recognition | Accelerometer, model, MQTT |
| Battery anomaly sensor | Sleep, sample, `ad` model, LoRa packet only on an anomaly |
| Krill | The cluster language model, as the flagship |

### Later

**Proposed**, 17 October 2026, from talking it over with the author, and not yet agreed. Nothing here is measured unless it says so.

**Speech out.** The author would like a board to speak, through a small speaker on a breadboard.

- **TinyTTS** (`github.com/tronghieuit/tiny-tts`, Apache-2.0) is the smallest neural voice found: by its README, 1.6M parameters, about 3.4 MB as FP16 ONNX, 44.1 kHz out, 53 times faster than real time on a laptop's CPU. Its words become phonemes through the CMU dictionary and `g2p_en`, a neural model of about 4.4 MB. Its training code is not yet published.
- **On these boards it is not practical as it is.** Even at 8 bits it does not fit the STM32L475's 1 MB of flash; it would fit the C3's 4 MB. Estimated from its size and not measured, either board would be 10 to 30 times slower than real time, mostly in making the waveform. A sentence of 4.9 s at 44.1 kHz is 215 KB, against 128 KB of RAM. Its output's length depends on the text, where Steady compiles for fixed shapes, and it would need operators Steady may not have.
- **What is practical now**: the board's answers rendered on the host by TinyTTS, at 8 kHz, and kept in flash as 4-bit ADPCM, about 4 KB a second, played through the STM32L475's 12-bit DAC from a timer. With keyword spotting from the board's microphones, the board hears one of twelve words and answers aloud, on one board and with no network (§1.2).
- **Real speech from text on the board** would be rules: English letters to phonemes by the US Naval Research Laboratory's rules of 1976, and a formant synthesiser after Klatt, in whole numbers, a few KB of tables. It runs in real time on both boards and sounds like a robot. SAM, the famous one, has no clear licence, and Speak & Spell's words are TI's. Its own package, as `lutra_espat` is.
- **Next step, if wanted:** count TinyTTS's operators and its multiplications per second of sound from the ONNX file, which settles how far from real time each board is.

**Several cores.** Lutra supports none yet; nothing in it rules them out.

- Tasks would be bound to a core when the program is compiled, as `proc sample() {.task: core1.}`, each core with its own scheduler. A peripheral used from two cores would be a compile error, as a pin claimed twice is (§5.4). `critical:` would take one of the chip's hardware spinlocks as well. A ring or the chip's FIFOs between cores would carry data across.
- For TinyML: one core samples and computes features while the other runs the model, each on half of a double buffer.
- The RP2350 of the Raspberry Pi Pico 2 has two cores that run as Cortex-M33 or as RISC-V; the RISC-V side would reuse `arch/riscv32`. The RP2040's Cortex-M0+ cores are ARMv6-M, which `arch/armv7m` does not cover. Either Pico needs Raspberry Pi's Debug Probe for flashing and a console, as it has no USB bridge (§11, M4, on the ItsyBitsy).

**Clusters, for Krill.** Krill is to be a family of small language models for clusters of microcontrollers of different sizes. Krill must never wait on Lutra (§2); what Lutra can give it:

- Flashing and reading many boards at once, and choosing one by its MAC address (§4.3, not built).
- Scatter, gather and all-reduce over the SPI target with DMA and `framing`, which `nim link` already exercises.
- A speech model divides across boards more easily than a language model. Its decoder, where the work is, makes any stretch of sound from its stretch of frames and a little either side, so each board can make its own stretch with the whole decoder in its flash. Little crosses the links: the frames out, likely tens of KB per second of sound, and the sound back, 8 to 16 KB a second at 8 kHz. Sixteen C3s might come near real time, by the estimate above.

**A larger board**, when one is wanted, and the third chip that §11, M4's leftovers wait for:

| Chip | Why |
|---|---|
| STM32H7 | A Cortex-M7 at 480 MHz with about 1 MB of RAM. ARMv7E-M, so it reuses `arch/armv7m`: the cheapest to add, and the likeliest to run TinyTTS alone |
| ESP32-P4 | Two RISC-V cores at 400 MHz, with vector instructions for int8 and PSRAM. Reuses `arch/riscv32`, has peripherals like the C3's, and brings several cores. No Wi-Fi of its own |
| RP2350 | Two cores, cheap, small (above) |

---

## 12. Open questions and risks

**Open design questions, each worth a small experiment early:**

- Which SVD generator to use, and whether generated register files are checked in. The C3 has about sixty hand-written addresses now, and each new peripheral adds several.
- How the heap opt-in is expressed.
- Whether `static` parameters cause unacceptable code duplication when a program uses several instances of one peripheral.
- What a window of samples, handed to a model, looks like. Data capture is settled (§8.2); the window is best designed with the microphone or the gesture model in hand (§1.2).

**Known gaps, none blocking:**

- The B-L475E-IOT01A's clock is uncorrected (§11, M4), so its time and timer events run 0.18% fast.
- Building for one board and then the other in the same folder writes the same files in `build/`, so the second build starts again from nothing.
- Nothing checks that `i2c0.init` frees a sensor cut off mid-read by a reset. It was tried by hand, with a program that read without pause and was reset 16 times.
- A driver's waits are forever: a link that loses a packet hangs, and the checks rely on the host's timeout. A program can bound its own with `wait(cond, within = ...)`, and an I2C transaction has a deadline of its own.
- On the B-L475E-IOT01A, a task whose stack overflows past every variable below it runs off RAM and is reported as a fault, not as an overflow (§5.5). The program's own stack is not checked at all.
- An I2C transaction carries at most 254 bytes out and 256 in, and a longer one is refused.
- The front-end takes 3.8 ms a frame, a fifth of the time the sound takes to arrive. A transform that used its input being real, and band sums that skipped their zero weights, would cut that. Neither has been needed.
- The addressable LED driver lights one LED. A strip needs the pulse generator's memory refilled as it plays.
- The SPI controller copies through the bus's 64-byte buffer a byte at a time, which measured about 29% slower than the clock allows on a 300-byte transfer. Copying by words is the cheap fix. DMA is the full one, though it would not replace the copying path if, as believed and not tested, DMA cannot read from flash.
- The trap vector is in flash (§5.5).
- The tasks have run on Linux only. The Windows build was tried under Wine, without a reset, and the macOS build not at all (§4.3). The `link` check needs a POSIX shell. A board cannot be chosen by MAC address.
- An SPI transfer longer than the target armed goes wrong (§11, M2).
- MQTT is QoS 0 only, with no user name, password or TLS, and a broker that turns a subscription down goes unnoticed (§8.3). A connection lost is not made again for the program.
- The Wi-Fi network's name and password are built into the image, in flash, until the settings store can hold them.
- A UART's `buffer` has to come before anything in the source that reads the port, a task's body included, so `uart1.buffer(...)` goes above `proc listen() {.task.}`. The build says so when it does not, but the rule surprises.
- The ESP-AT driver has worked on the DevKitM-1 only. The B-L475E-IOT01A's UART4 works, and `nim wifi` through it waits for the AT module to be wired to it.
- Answers from the AT module wait at most a few seconds, but the raw bytes after `+CIPRECVDATA:` are waited for without a limit.
- `lutra/patches/fatal.nim` stands in for a file of Nim's own, `system/fatal`, and declares what that file did in Nim 2.2.6. A new version of Nim may change the file or what calls it (§5.6).
- `nim monitor` names the line of a panic only in an image `nim flash` wrote from the same folder, to that port.
- A monitor started with `-d:reset` can show a line or two the board printed before the reset took it, as `pyocd reset` pulls the reset line about 0.3 s in. `nim capture` is not affected (§8.2).
- Builds carry debugging information, for `nim monitor`, which none of the board's memory holds but which makes the image file larger and the build a little slower.

**Risks:**

- **Scope.** A HAL is a classic way to avoid the project it was meant to serve. Lutra stays off Krill's critical path and grows only as programs need it.
- **Interface churn.** Mitigated by proving the contract on two architectures before inviting libraries.
- **One maintainer.** Favour fewer chips done well.
- **Vendor ROM dependence.** The C3 port calls three boot ROM routines for cache control. Their addresses are fixed per chip revision family and come from esp-idf's `esp32c3.rom.ld`.
- **Nim on bare metal.** Several compiler behaviours surprised the port. They are listed in Appendix B. Reporting a failed check depends on replacing one of Nim's own files (§5.6).

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
| System timer alarms | Three, *n* = 0 to 2, interrupt sources 37 to 39. An alarm repeats when bits 25:0 of `0x6002_3034 + 4n` hold its period in 16 MHz ticks and bit 30 is set: clear bit 24 − *n* of `0x6002_3000`, write the period, write 1 to `0x6002_3050 + 4n` to load it, set bit 30, set bit 24 − *n* again. Bit *n* of `0x6002_3064` enables its interrupt and `0x6002_306C` clears it. Added for M5 |

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

Added for M5, by `nim resets`:

| Peripheral | Facts |
|---|---|
| Watchdog | The first timer group's, at `0x6001_F048`. Write `0x50D8_3AA1` to `0x6001_F064` before writing its registers and 0 after. `+0x04` (`0x6001_F04C`) holds the prescale in bits 31:16; with bit 21 of `0x6001_F048` set it divides the 40 MHz crystal, so 40,000 is a millisecond. The first stage's time, in those ticks, is at `0x6001_F050`. `0x6001_F048` = bit 31 (on), 3 in bits 30:29 (the first stage resets the system), bit 21, and reset lengths of 7 in bits 20:18 and 17:15; then setting bit 22 takes it all up. Any write to `0x6001_F060` feeds it. 300 ms unfed reset the chip, which the boot ROM reported as `rst:0x7 (TG0WDT_SYS_RST)`; fed every 100 ms for a second, it did not |
| Reset reason | Bits 5:0 of `0x6000_8038`, the code the boot ROM prints as `rst:`. `0x1` after `esptool`'s reset, which works the EN line, `0x7` after the watchdog, `0x3` after a restart. The other codes are from esp-idf, not seen |
| Restart | Setting bit 31 of `0x6000_8000` resets the system; the boot ROM runs again and says `rst:0x3 (RTC_SW_SYS_RST)`. What the UART still had to send is lost, so `restart` waits for it first. Waiting one byte's time after the transmit FIFO's count reached 0 lost the last byte; two bytes' time was enough |

Not verified: the reset-default function of each pin. Take it from the ESP32-C3 Technical Reference Manual.

### A.5 Building and flashing

- Compiler flags: `-march=rv32imc_zicsr -mabi=ilp32 -ffunction-sections -fdata-sections`. GCC 11.2 accepts `rv32imc_zicsr`; newer toolchains require the `_zicsr`.
- Linker flags: `-nostartfiles -Wl,--gc-sections` and the linker script.
- Nim flags used by the port: `--cpu:riscv32 --os:any -d:useMalloc --opt:size --exceptions:goto -d:release --debugger:native --lineDir:on`, Lutra's `system/fatal` (§5.6), and for GCC `-gdwarf-4 -fno-tree-tail-merge`.
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
- **Nimble installs only the extensions listed in `installExt`.** A linker script next to the sources needs its extension added. Without `installExt`, `.nim` files are installed; with it, they are only if it lists `nim`. Lutra's lists `nim` and `expected`, for the self-checks.
- **A project's `config.nims` applies only to programs in its folder and below.** Nim takes `config.nims` and `nim.cfg` from the folder of the program being compiled and the folders above it, not from where `nim` was run. A program inside an installed package is compiled with none of the project's settings, so `nim selfcheck` copies the board's program into the project's `build/` first.
- **`p"text\n"` is a raw string literal.** The `\n` is not an escape. This is Ratel's `progmem` syntax and is one reason not to carry it over. `cstring"text\n"` is raw for the same reason; write `cstring("text\n")`. So is `newLit"\r\n"` in a macro, which sent AT commands ending in four characters `\`, `r`, `\`, `n`.
- **Setting `--os:any` in `config.nims` is too late to stop the host's libraries being linked.** Nim's own `nim.cfg` has already added `-ldl` for a Unix host. Clear it with `switch("gcc.options.linker", "")`.
- **Nim does not link again when only a linker script's contents change.** It compares the link command, not the files it names.
- **A generic procedure binds a name early if `system` already has one symbol by that name.** `link.send(c)` resolved to the channel `send` on the host, and `reset(port)` to `system.reset`. Declare such names with `mixin`. A library written against a concept needs this too, for `send` and `receive`, or it only compiles for the target.
- **A template parameter is substituted into field accesses.** With a parameter called `name`, `file.name` in the body becomes `file."the argument"`. A field named in a template is also bound to whatever has that name where the template is defined: a tuple field called `memory` was taken for the board's constant. A type declared outside the template has neither problem. The field names of an object built in the template are substituted too: `Payload(broker: broker)`, in a template whose parameter was `broker`, built a `Payload` with a field named after the argument.
- **A procedure declared inside another is left out unless something refers to it**, even one marked `exportc`. At the top level it is kept. A task declared inside a procedure declared the scheduler's hook, which nothing in Nim calls, so it was never generated; taking its address keeps it.
- **A macro used as a pragma cannot have a parameter with a default**: `{.task.}` is then an "invalid pragma". Two overloads instead make Nim check the proc before either macro runs, which declares its name, so the macro's own declaration of it is a redefinition. One macro taking `varargs[untyped]` has neither problem.
- **Inside `quote`, a name the macro has as a variable means that variable**, even when the generated code meant a constant of the same name elsewhere. Give it backticks and bind it with `bindSym`.
- **In `emit`, a word between backticks is taken for a Nim symbol**, in a C comment too. A comment in `steady-xtheadvector`'s emitted C that put two of its parameters' names between backticks stopped the compiler with "internal error: getTypeDescAux(tyGenericParam)", naming no line. Leave backticks out of emitted C, or quote only Nim's own names.
- **`quote` gives back a single node when its body is one statement**, not a statement list, and what is added to it goes inside that node. Wrap it in `newStmtList`.
- **GNU `ld` cannot place a section by its own size.** `.stacks (ORIGIN(ram) + LENGTH(ram) - SIZEOF(.stacks))` takes the size as 0 and then overflows the region.
- **A `static` object parameter cannot size the return type.** `func table(m: static Mfcc): array[m.melBins, int32]` fails with "cannot evaluate at compile time: m". Pass the size as a `static int` of its own.
- **Going through a constant array of strings allocates.** Each string is copied on its way to the loop variable, and the program then fails to link, for want of `end`. Hold data from `staticRead` as an array of numbers, built in a `const` block. A short list of commands to go through can be `cstring`s: `for setting in [cstring"E0", "+CWMODE=1"]` copies nothing.
- **Much of the standard library allocates or raises.** `std/algorithm`'s `sort` is a merge sort with a buffer from the heap, and `parseutils.parseInt` raises `ValueError` on overflow; an exception is allocated. Read in the library's source, not tried on the board, where the one allocation met so far failed to link.
- **`--skipProjCfg` builds for the host from a folder whose `config.nims` selects a board.** `nim keywords` uses it to build one source file both ways. That file tells them apart with `when defined(lutraBoard)`.
- **A module cannot import another of its own name**, wherever the other is. `checks/keywords.nim` is not `kws.nim` because Steady's generated module is.
- **Code at the top level of a module costs an error check.** With `--exceptions:goto` each module's own code ends by testing Nim's error flag, and that test keeps `exit` in the link. A program's main module loses it when it ends in a loop, as unreachable. A board's module that set its console up at the top level did not, and with the C library that ships for ARM `exit` brought 1 KB of RAM and 1.4 KB of flash into every program. Hence `lutraBoardStart`, a procedure the startup code calls.
- **A procedure declared in a template is visible to the next use of that template**, unlike a variable. Two pin handlers in one program, written as blocks as they were then, were a "redefinition of 'handler'". Mark such a procedure `{.gensym.}`.
- **A name a macro makes up is looked for where the macro is expanded, and inside a procedure with a `static` parameter that is the caller's module.** `sink.write "Fault: "` in the architecture layer failed with "undeclared identifier: 'put'" when a board's module instantiated it, because `write` builds calls to `put` by name. The fault report calls `put` itself. `write` now names `put` with `bindSym("put", brOpen)`, which is found where `write` is defined and stays open to a `put` of the caller's, so `lutra_espat` can use `write`; the fault report was left as it is.
- **A literal passed to a template's `uint32` parameter is still a literal.** `value shl 30` with 2 for `value` was worked out as an `int`, which is 32 bits on the target, and did not fit. Convert it in the template.
- **NimScript's `patchFile` can replace a file `system` includes.** `patchFile("stdlib", "fatal", ...)` swaps `system/fatal`, which is how a failed check reaches Lutra without allocating (§5.6). The replacement must declare what the original did, `gotoBasedExceptions` and `quirkyExceptions`, or `system` does not compile.
- **A range check repeats the expression it checks**, unless it is a call. `char(reg[] and 0xff)` became three volatile reads, for the low bound, the high bound and the value. A `let` in a template, to read once, is a global variable when the template is used at a module's top level.
- **Nim's check procedures are not `noreturn` to the C compiler.** After each call comes a jump to the module's error test, which can call `exit` and bring the C library's in. A program that defines `exit` itself keeps it out.
- **GCC 11 writes DWARF 5, which the `addr2line` of Espressif's binutils 2.35 cannot read**: every address was `??:?`. `-gdwarf-4` fixes it.
- **`fileExists` is false for a device**, such as `/dev/ttyUSB0` or a link to it in `/dev/serial/by-id/`. `test -e` in the shell is not.
- **Inside a task, NimScript's `getCommand()` is `nop`**, not the task's name.
- **`cast[string]` of a `seq[byte]` works only where the two are laid out alike.** The capture decoder named its columns that way, and on a 32-bit build the header gained two bytes. Copy the bytes.
- **NimScript cannot open a device, sleep, resolve a link, or see the exit code of what `exec` runs**, only that it was not 0. Hence `lutra/host/monitor`, a program the tasks build, which writes its exit code to a file for them.

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

- The same virtual environment's `python` has `pyserial`. Holding DTR asserted and releasing RTS pulls IO9 low, which presses the boot button from the host: that is how the debounced button was checked, with `nim monitor` reading meanwhile.
- `esptool` leaves the port set to return from a read at once when no byte is waiting, which `cat` takes as the end of the file. That is why a capture started before `esptool` runs goes silent after the reset. Lutra's `monitor` and `selfcheck` open the port once, hold it open across the reset and set the mode again afterwards, so they read from the boot ROM's first byte.
- Lutra's tasks find the compiler under `~/.espressif` without help. `esptool` has to be on `PATH` or named in `ESPTOOL`.
- Steady's reference results for the C board path are in `~/Documents/GitHub/Steady/build/mcu/esp32c3/<model>/serial.txt`.
- `~/Documents/GitHub/lutra-lsm6ds33`, `~/Documents/GitHub/lutra-lis3mdl` and `~/Documents/GitHub/lutra-espat` are the driver packages, the first two on `main` and the third on `master`, each with its remote in the `Lutra-Nim` organisation on GitHub (§8). Steady stays at `garrettkinman/Steady`.
- The Speech Commands test set is unpacked in `checks/build/keywords/`, 150 MB, so `nim keywords` does not download it again. Deleting `checks/build` brings the download back.
- The sensor board is on the DevKitM-1 with MAC `7c:df:a1:59:c9:70`, with a wire from its ADM pin to ground (§11, M3).
- Adafruit's design files for the sensor board, which settled what its pins join, are at `github.com/adafruit/Adafruit-LSM6DS33-LIS3MDL-PCB`.
- The B-L475E-IOT01A is attached by its ST-LINK's USB socket and appears as `/dev/ttyACM0`. With it and one DevKitM-1 attached, no port needs naming for either. The author has two USB cables, so only two boards are attached at once.
- As of the evening of 17 October the B-L475E-IOT01A and the sensor board's DevKitM-1 are attached, and the B-L475E-IOT01A has jumpers from D0 to D1 and from D11 to D12. The DevKitM-1 with MAC `84:f7:03:0a:a8:08` runs Espressif's AT firmware, 4.1.1.0, and is the Wi-Fi module for `nim wifi`; writing a Lutra program to it, as `nim wiring` and `nim link` do, erases the firmware, which is then written again as §9 says. The firmware's zip is from `dl.espressif.com/esp-at/firmwares/esp32c3/`. The other, MAC `7c:df:a1:59:c9:70`, has the sensor board and runs the programs. With both attached the port has to be named; `/dev/serial/by-id/` names each by its USB bridge's serial number, which does not swap on replug: `...4e11d5f2...` is the one with the sensor board, and `...64a0c207...` the AT module. ESP-AT takes its commands on IO6 and IO7, not on its USB port, which carries only its log.
- The Wi-Fi network for `nim wifi` and the examples is in `~/.lutra-wifi`, which exports `LUTRA_WIFI_NETWORK` and `LUTRA_WIFI_PASSWORD`: `. ~/.lutra-wifi` before running them.
- `pyocd` 0.45.1: `~/Documents/GitHub/Steady/.venv/bin/pyocd`, beside `esptool`. Not on `PATH`, so `export PYOCD=~/Documents/GitHub/Steady/.venv/bin/pyocd`. It reaches the probe without `sudo`; Steady's `tests/mcu/boards/stm32l475/board.sh` has the udev rule that allows that. A `pyocd` installed by `pipx` is now on `PATH` too, and is found without it.
- The ARM compiler is Ubuntu's `arm-none-eabi-gcc` 10.3.1, on `PATH`, with its `newlib`.
- `pyocd commander -t stm32l475xg -c halt -c "reg pc" -c "read32 0x40021000 16" -c go` reads the chip's registers while a program runs, which is how the first silent console was explained.
- The Windows build of `lutra/host/monitor` was tried from this machine, on 17 October, and nothing of it was kept: Zig, from `pip install ziglang` in a scratch virtual environment, as Nim's C compiler (`--os:windows --cpu:i386 --cc:clang` with `clang.exe` a script running `python -m ziglang cc -target x86-windows-gnu`), and Ubuntu's Wine 6, whose prefix is 32-bit. Wine maps COM ports from `HKLM\Software\Wine\Ports`, set with `wine reg add 'HKLM\Software\Wine\Ports' /v COM5 /d /dev/ttyACM0`; a link written in `dosdevices` by hand is replaced when Wine starts. The same Zig, with `-target aarch64-macos`, links the macOS build.
- The author has no I2S microphone, and has a small speaker for a breadboard, of a kind not yet known (§11, "Later").
- Since 20 October the Lichee RV Dock is attached twice: its console through a CP2102 adapter on the TX and RX pins underneath, `/dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0`, which was `/dev/ttyUSB4`; and the module's USB-C port, for FEL. Two Digilent FPGA boards on FT2232s take `/dev/ttyUSB0` to `3`, so `LUTRA_PORT=/dev/ttyUSB4` has to be set for the Dock. The SD card holds Sipeed's Linux, which does not start (Appendix E). Programs reach FEL without `sudo`: the logged-in user has the USB device through an ACL.
- The Dock's compiler is xPack's `riscv-none-elf-gcc` 15.2.0-1, unpacked in `~/.local/xPacks/riscv-none-elf-gcc/`, where Lutra finds it. `xfel` was built from `github.com/xboot/xfel` at `445e8ae` against `libusb.h` 1.0.25, as Mint has the library but not its header, and is in `~/.local/bin`, which the shell's profile puts on `PATH`.

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
- Just below RAM, around `0x1FFF_F800`, writes are lost and reads give junk, with no fault. A stack that runs down there loses what is pushed, and the next return goes to wherever the junk says: address 0, or `0xFFFFFFFF`.

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
| Functions | USART1 is function 7 on PB6 (out) and PB7 (in). I2C2 is function 4 on PB10 (clock) and PB11 (data). UART4 is function 8 on PA0 (out) and PA1 (in). SPI1 is function 5 on PA5 (clock), PA6 (data in) and PA7 (data out). PA9, PA10, PB13 and PB14, and SPI1's PB3, PB4 and PB5, are listed as alternatives from the datasheet and have not been tried |
| Edge interrupts | Sixteen lines, one for pin *n* of whichever port bits 4*n* of `0x4001_0008 + 4 × (n div 4)` name. Rising edges at `0x4001_0408`, falling at `0x4001_040C`, enabled at `0x4001_0400`, pending at `0x4001_0414` and cleared there by writing a 1. Lines 0 to 4 are interrupts 6 to 10, lines 5 to 9 share interrupt 23, and 10 to 15 share 40. An output pin's own edges raise its line |
| The interrupt controller | In the core. Interrupt *n* is let through by bit *n* mod 32 of `0xE000_E100 + 4 × (n div 32)` |
| Reading back | A pin's level reaches the input register a few cycles after it changes. Read on the next instruction after it is set, it gives the old level 99,999 times in 100,000 |
| On this board | PB14 drives LED2. PC13 is the button and is held high by the board. PA4, PA5, PA15, PB2 and PC0 to PC5 follow their pulls, so nothing on the board drives them. Of the Arduino header, D0 and D1 are PA1 and PA0, and D11 and D12 are PA7 and PA6: a jumper across each pair joined them. PA5 as LED1, and the other header pins, are from ST's manual UM2153, from memory |

### D.4 Peripherals used

| Peripheral | Facts |
|---|---|
| USART1 | Base `0x4001_3800`, to the ST-LINK on PB6 and PB7. `+0x0C` is the bus clock divided by the baud rate, 694 for 115200. `+0x00` = `0xD` enables it both ways. In `+0x1C`, bit 7 says there is room to send and bit 5 that a byte has come. Send at `+0x28`, receive at `+0x24`. Bit 12 of `+0x08`, set before it is enabled, makes a byte that arrives with the last unread replace it; without that the port stops receiving until an error flag is cleared |
| Timers 6 and 7 | Bases `0x4000_1000` and `0x4000_1400`, 16 bits with a 16-bit prescale, clocks in bits 4 and 5 of `0x4002_1058`, interrupts 54 and 55. Prescale less one at `+0x28`, count to less one at `+0x2C`, interrupt enable at `+0x0C`, status at `+0x10`, cleared by writing 0. Writing 1 to `+0x14` takes the prescale at once, and counts as a tick unless bit 2 of `+0x00` was set first: without it, every timer event fired once as it started. Added for M5 |
| Timers 2 and 5 | Bases `0x4000_0000` and `0x4000_0C00`, both 32 bits, counting the 80 MHz bus clock when `+0x00` = 1. Count at `+0x24`. Timer 2's `+0x04` = `0x20` tells others when it comes round, and timer 5's `+0x08` = 7 makes it count that: its first internal trigger is timer 2 |
| I2C2 | Base `0x4000_5800`, clocked at 80 MHz. `+0x10` holds the timing: a divider less one in bits 31:28, then the data line's setup and hold in 23:20 and 19:16, and the clock's high and low times, each less one, in 15:8 and 7:0. `0x90F2_232B` is 100 kHz. `+0x00` = 1 enables it. A transfer is started by writing `+0x04`: the address in bits 7:1, bit 10 to read, a count of bytes in 23:16, bit 13 to start, and bit 25 to stop when the count is done. In `+0x18`, bit 1 asks for a byte to send (`+0x28`), bit 2 offers one received (`+0x24`), bit 4 says the device refused, bit 5 that a stop went out, which it does after a refusal too, and bit 6 that the count is done with no stop asked for. Bits 4 and 5 are cleared at `+0x1C` |
| I2C2, on this board | Seven addresses answer: 0x1E (the LIS3MDL, whose identity register reads `0x3D`), 0x29, 0x2D, 0x56, 0x5D (`0xB1`), 0x5F (`0xBC`) and 0x6A (`0x6A`, an LSM6DSL, which `lutra_lsm6ds33` does not know) |
| UART4 | Base `0x4000_4C00`, its clock bit 19 of `0x4002_1058`, interrupt 52, otherwise as USART1. 300 bytes came back through a jumper from D1 to D0, at 115200 baud, through the interrupt. The receive interrupt asked for before the port's clock is on is lost, as any write is (§11, M4), so `buffer` switches the clock on first, and `init` keeps the bit |
| USART1 at 921600 baud | `setBaud` lets the last byte go, then turns the port off, writes the divider and turns it on: 64 KB echoed from the ST-LINK and back with none lost, polled and through the interrupt. The ST-LINK's port takes that rate |
| SPI1 | Base `0x4001_3000`, its clock bit 12 of `0x4002_1060`. `+0x04` = `0x1700` gives 8-bit frames and a flag for each byte received. `+0x00` = bits 2, 8, 9 and 6, and the halvings of 80 MHz in bits 5:3, makes it the controller choosing devices by plain pins. In `+0x08`, bit 0 is a byte received, bit 1 room to send and bit 7 busy. Bytes are written to `+0x0C` a byte wide: a wider write sends two. Through a jumper from D11 to D12, 300 bytes came back at 10 MHz, and 1000 took 1263 µs, against 800 µs for the clock alone |
| Random numbers | At `0x5006_0800`, its clock bit 18 of `0x4002_104C`. It wants 48 MHz, given by the second PLL from the same 4 MHz: `0x4002_1010` = 24 in bits 14:8 and bit 20, then bit 26 of `0x4002_1000`, waiting for bit 27, and 1 in bits 27:26 of `0x4002_1088`. Bit 2 of `+0x00` starts it; bit 0 of `+0x04` says a number is waiting at `+0x08`. The self-check's test of its numbers passes |
| Watchdog | The independent one, at `0x4000_3000`, counting a 32 kHz oscillator of its own. Write `0xCCCC` to `+0x00` to start it, `0x5555` to unlock, a prescale of 4 × 2^*n* as *n* to `+0x04` and a count less one to `+0x08`, wait for `+0x0C` to read 0, then `0xAAAA`, which also feeds it. 300 ms unfed reset the chip; fed every 100 ms for a second, it did not |
| Reset reason | Flags in bits 31:24 of `0x4002_1094`, kept across resets until bit 23 is written, so the startup reads and clears them. Bit 26, the reset pin, came with every reset seen: alone after `pyocd reset -m hw`, with bit 29 after the watchdog, with bit 28 after a restart. Bit 27, the supply, at power on is from the manual, not seen |
| Restart | `0x05FA_0004` written to `0xE000_ED0C`, the core's reset request. Bit 28 of the reset flags is then set |
| Faults | The status is at `0xE000_ED28`: bit 16 an undefined instruction, bits 12:9 a bad address read or written, bits 17, 8 and 0 a jump to one. Bit 15 says the address is at `0xE000_ED38`. The core pushes eight registers onto the stack in use, the instruction's address seventh and the link register sixth |

### D.5 Building and flashing

- Compiler flags: `-mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffunction-sections -fdata-sections`. Nim flags as for the C3, with `--cpu:arm`.
- Linker flags: `-nostartfiles --specs=nosys.specs -Wl,--gc-sections` and the linker script. The stubs are there because Nim's runtime refers to `exit`, which this C library builds on `_exit`. None is linked into hello world.
- `pyocd flash -t stm32l475xg app.elf` programs the linked file as it is and starts it. `pyocd reset -m hw -t stm32l475xg` resets it by its reset pin, in 0.8 s. Without `-m hw` it asks the core to reset itself, which took 5.75 s, and near the end the probe stopped the core for a third of a second.
- Hello world over serial is 2812 bytes of flash and no RAM.

## Appendix E: D1 bring-up facts

For Sipeed's Lichee RV Dock: the Lichee RV module, an Allwinner D1 with 512 MB of DDR3 and a green LED, on a carrier with an addressable LED and a speaker amplifier. Addresses are from mainline Linux's device tree and drivers for the D1 (`sunxi-d1s-t113.dtsi`, `sun20i-d1-lichee-rv*.dts`, `ccu-sun20i-d1.c`, `pinctrl-sunxi.h`, `pinctrl-sun20i-d1.c`, `leds-sun50i-a100.c`, `sunxi_wdt.c`), not from memory, and the audio codec's as its row says. Sipeed's schematic is behind a captcha; the author has it, `Lichee_RV_DOCK_3516(Schematic).pdf`.

Everything here was exercised on hardware on 20 October 2026, the audio codec and the speaker on 21 October, unless marked otherwise.

### E.1 Boot, and loading a program

- The boot ROM reads Allwinner's first stage, boot0, from the SD card. boot0 sets the DRAM up and loads OpenSBI 0.6, in machine mode at `0x4000_0400`, and then U-Boot 2018.05 in supervisor mode. With no boot medium the boot ROM waits for USB instead, as FEL, on the module's USB-C port, as `1f3a:efe8`.
- The card on the author's Dock reaches U-Boot, whose own SD driver then times out on every read and finds no partitions; boot0 reads it fine. U-Boot's log says its device tree has no `mmc0`. So Linux does not start, and U-Boot stops at its prompt.
- **How Lutra loads a program.** At U-Boot's prompt, `efex` starts the chip again; boot0 sees a flag and hands over to the boot ROM's FEL. `xfel ddr d1` then sets the DRAM up (DDR3 at 792 MHz), `xfel write 0x40000000` writes the image, and `xfel exec 0x40000000` calls it in machine mode. A program that returns, returns to FEL. 2 KB is written in under a second; 200 KB at 370 KB/s.
- Said during U-Boot's two-second countdown, `efex` loses its first letter to stopping the count, so `nim flash` says it twice when it must.
- **The instruction cache is on in FEL, and `xfel write` goes behind it.** A second, different program at the same address ran a mix of its own and the last one's instructions, and hung. `fence.i` empties the cache. A program can't run it before its first instructions are fetched, so the first 64-byte line of every Lutra program is the same, `fence.i` and a jump past the line, and a stale copy of it is still right. Moving from a program without that line needs a reset. A reset empties the cache: the first program after one has never been wrong.
- The data cache is off, and so are the FPU and the vector unit: `mstatus` reads `0xa_0000_0188`, its FS and VS fields 0. `mhcr` (`0x7c1`) reads `0x109`. `mxstatus` (`0x7c0`) reads `0xc040_8000`: machine mode, T-Head's own instructions on.
- `misa` reads `0x8000_0000_00b4_112d`: RV64 with A, C, D, F, I, M, S, U, V and X. `mvendorid` is `0x5b7`, T-Head.
- **How the host starts a running program again.** The program is in DRAM, which a reset does not keep, and the author's console adapter brings out no DTR to join to the reset, so it is done in software, as the author chose on 20 October. `0x5AA5A55A` in the RTC's spare register 2, `0x0709_0108`, which a reset keeps, and then a restart through the watchdog: boot0 starts, prints its two lines, sees the note, clears it and goes to FEL, with no U-Boot. That is what U-Boot's `efex` does too, which wrote it and was seen to leave it cleared. Every program on the Dock takes a break on its console, the line held low for longer than a byte, through UART0's interrupt, as asking for that, and so does a program stopped by a panic or a fault, by looking for it in its stop loop (§5.6). `lutra/host/fel`, a program for the host, sends the break, waits for FEL, says `efex` once a second if that brought nothing, as for U-Boot at its prompt, and loads the program: `nim flash` with the new one, the reset of `nim monitor -d:reset` and the checks with the one last flashed. From a running or a halted program to the new one running took 12 s, most of it the chip coming back on USB; the self-check task takes 57 s. A program that hangs with interrupts off needs the board's reset button.

### E.2 Core, cache and clock

- **Data cache.** `dcache.ciall` (`.word 0x0030000b`) and then setting bits 1, 2, 4, 5 and 12 of `mhcr`: the cache, its writes allocating, its refills and branch prediction. It then reads `0x13f`: bit 12 does not stick. A loop that reads and writes the stack took 206.6 cycles a turn before and 7.0 after. Peripherals' registers are not cached with the MMU off: the UART works with the cache on.
- **Prefetching.** T-Head's `mhint`, CSR `0x7c5`, reads `0x4000` as the boot ROM leaves it, with the data cache's prefetching off. Scalar loops over 4 MB, on 22 October: reading 240 MB/s, writing 193 and copying 187; with bit 2 set, reading 457; with bit 3 too, writing 384; at `0x650c`, which adds bits 8, 10, 13 and 14, reading 529 and copying 282. The startup writes `0x650c`. That bit 2 is the data cache's prefetch, bit 3 lets a run of stores pass the cache rather than allocate lines, and bits 14:13 are how far ahead it fetches, is T-Head's C906 manual as remembered, not checked against a copy; the rates are what was measured. TinyTTS's decoder went from 318M cycles a chunk to 257M with nothing else changed, its LeakyReLU from 36M to 12M.
- FS is bits 14:13 of `mstatus`, set to 1 at start. The C906's vector unit is the extension's draft 0.7.1, whose VS field is bits 24:23; with bit 23 set at start, the self-check's `th.vsetvli` for 32-bit elements in one register gives 4 lanes, 128 bits, and `th.vle.v`, `th.vadd.vv` and `th.vse.v` add four pairs. The assembler takes T-Head's instructions after `.option arch, +xtheadvector`.
- **What the vector unit costs**, timed by eight independent instructions a thousand times: a 16-byte load 1.7 cycles and a 32-byte one 3.4, whether aligned to 16 bytes or not; a 32-bit add of four lanes 1.4, of sixteen 7.4; a widening multiply-add of 16-bit lanes into 32-bit sums, 3.4 for eight and 7.4 for sixteen, and of 8-bit lanes into 16-bit, 3.4 for sixteen. A chain of multiply-adds into one sum costs the same as independent ones, and a scalar instruction, or a load whose result the next instruction uses, adds nothing. T-Head's `vlb.v` loads bytes and widens them to the element width.
- **Clock.** 1008 MHz from the CPU PLL at `0x0200_1000`: N less one is 41, in bits 15:8. The core is put on the crystal first by writing `0x100` to `0x0200_1D00` (the bus behind it at half), then the PLL is set with its regulator (bit 30), lock detection (29) and itself (31) on and its output (27) off, and when bit 28 says it has locked, its output is let through and the core moved onto it, `0x0500_0100`. Measured against the 24 MHz `time`: 1008.0 MHz, and within 1% in the self-check.
- `time` counts 24 MHz from the crystal, 64 bits, readable in machine mode, from the last reset. `mcycle` counts the core's clock.
- APB1, which the UARTs are on, is put straight on the crystal, `0x0200_1524` = 0, whatever loaded the program left there.

### E.3 Pins

| What | Facts |
|---|---|
| A port | Port B's block is at `0x0200_0030`, and the rest follow `0x30` apart, as if port A were first. Function at `+0x00` to `+0x0C`, four bits a pin: 0 input, 1 output, then the peripherals'. Levels at `+0x10`. Pulls at `+0x24`, two bits: 1 up, 2 down; not yet tried. There is no register that sets or clears one pin |
| Ports | B has 13 pins, C 8, D 23, E 18, F 7 and G 19 |
| Functions | UART0 is 6 on PB8 (out) and PB9 (in). The LED controller is 4 on PC0 |
| On this board | PC1 drives the module's green LED, and reads back what it drives. PC0 is the Dock's addressable LED. The console is PB8 and PB9, on the pins marked TX and RX underneath the Dock |

### E.4 Peripherals used

| Peripheral | Facts |
|---|---|
| Audio codec | Not in mainline Linux. Digital part at `0x0203_0000`, analog at `+0x300`, from Maksim Kiselev's unmerged patches of 2023, Allwinner's `sun20iw1-codec.h` and the D1 manual as the bare `hello-d1` quotes it. Its bus clock and reset are bits 0 and 16 of `0x0200_1A5C`; the DAC's clock `0x0200_1A50` = bit 31, from PLL_AUDIO0. That PLL, `0x0200_1078`, with N - 1 = 21 in bits 15:8, M - 1 = 5 in 21:16, the sigma-delta pattern on (bit 24) and `0xc001288d` in `0x0200_1178`, gives 22.5792 MHz, and the DAC's rate field 0 then 44.1 kHz: 44,100 samples a second, to the sample. It locked in 1.6 ms. DAC FIFO control at `+0x10`: bits 25:24 = 1 take a sample from bits 15:0 of what is written to `+0x20`, bit 6 is mono, one sample to both channels in 128 places, the trigger in 14:8, and bit 3 the interrupt when there is room for it, which is source 41: 691 a second at a trigger of 64. FIFO status at `+0x14`: free places in bits 22:8, flags cleared by a 1. `+0x24` counts samples written, not played. Out of the headphone output: bits 15 and 14 of `+0x310`, bit 30 of `+0x348`, bit 1 of `+0x31C`, and bits 21, 20 and 15 of `+0x340`, as Allwinner's driver sets them. With the headphone feedback bits 31, 19 and 17 set too, as `hello-d1` sets them, it sounded the same. The very first tone after the speaker was connected was not heard, and the same program was later: the speaker was then on jumper wires held by hand, which is the likeliest reason |
| Speaker | The Dock's schematic (Sipeed's `Lichee_RV_DOCK_3516`, page 4): both headphone outputs, through 22 µF and 47 Ω each, into one node, and from it through 100 nF and 33 kΩ into an NS4150, a 3 W class-D amplifier on 5 V, whose other input goes to ground the same way, so mono on both channels is right. Its enable is held on by 1 kΩ to 3.3 V against 10 kΩ to ground; R77, from PB12, is not fitted, so the amplifier is always on. Its bridged outputs go to J7, marked SPK, 2 pins of 1.25 mm, neither of them ground. The headphone feedback pin goes only to 100 nF |
| UART0 | Base `0x0250_0000`, a 16550 with its registers a word apart. Its bus clock is bit 0 of `0x0200_190C`, and bit 16 takes it out of reset. Clocked from APB1 at 24 MHz, the divider for 115200 is 13, 0.2% off; 921600 can't be made, and 1500000 can exactly. Line control at `+0x0C`, bit 7 to reach the divider at `+0x00` and `+0x04`. In the line status at `+0x14`, bit 0 is a byte waiting, bit 5 an empty transmit FIFO, bit 6 the line empty too |
| LED controller | Base `0x0200_8000`. Its bus clock is bit 0 of `0x0200_1BFC`, out of reset bit 16, and its own clock `0x0200_1BF0` = bit 31, from the crystal. Bit times at `+0x04` and the quiet after at `+0x0C`, in 41.7 ns ticks; `+0x00` takes a count of words in bits 28:16, the colour order in 8:6 (2 for green first) and bit 0 to send; each LED's word, red in 23:16, goes to `+0x14`; bit 0 of `+0x20` says it is sent. The author saw `rgb.nim` step red, green and blue, in that order. PC0 driven by hand from the cycle counter, as a check of the LED, came out white: each write to the pin takes long enough on the bus that every pulse was a 1 |
| Interrupt controller | A PLIC at `0x1000_0000`, its context 0 the core in machine mode: a source's priority at `+4 × n`, its bit to let it through at `0x1000_2000`, the threshold at `0x1020_0000`, and the claim at `0x1020_0004`, read for the next waiting source and written with it when handled. Bit 11 of `mie` lets it through to the core. Sources are Linux's numbers plus 16: UART0 is 18, the timers 75 and 76, the pin banks 85 to 95 |
| Taking an interrupt twice | A handler that clears its source's flag and returns at once was taken again: the timer's 1 ms events came 192 times in 100 ms. Reading the flag back after clearing it, so that the write has landed before the PLIC hears the interrupt is handled, made it 100. The UART's handler reads its port until it says nothing is waiting, and was never seen to |
| Timers | The timer block at `0x0205_0000`: interrupts enabled in `+0x00` and flagged in `+0x04`, a bit a timer, cleared by writing a 1. Timer *n*'s control at `+0x10 + 0x10n`, its interval at `+0x14 + 0x10n`. Control `0x7`, bit 2 for the 24 MHz crystal and bits 1 and 0 to take the interval and count, counts down from the interval and starts again. Events every 1 ms came within 1%, held off by `critical:` for 3 ms they came once on the way out, and `every` kept its turns |
| UART0's interrupt | Interrupt enable at `+0x04` with the divider not reached: bit 0 for bytes waiting, bit 2 for the line's status. Why it interrupted is in the low four bits of `+0x08`, read: 6 the line, cleared by reading the status at `+0x14`, whose bit 4 says a break came; 4 bytes waiting, 0xC some with the line gone quiet, 7 written to while busy, cleared by reading `+0x7C`; 1 nothing more. A break of a quarter of a second from the CP2102, by `tcsendbreak`, restarted every program it was sent to. The buffered receive is written and has not run |
| Restart | The watchdog of the timer block: `0x0205_00B4` with bits 1:0 set to 1 and the key `0x16AA` in 31:16, then `0x0205_00B8` the same way with bit 0 and the shortest time, then `0xA57 << 1 | 1` to `0x0205_00B0`. The chip restarted through boot0 into U-Boot |

### E.5 Building

- The compiler is xPack's `riscv-none-elf-gcc`, 15.2, with its newlib. Espressif's GCC 11 builds RV64 too, but has no RV64 libraries and takes `xtheadvector` without complaint and ignores it.
- Compiler flags: `-mcpu=thead-c906 -mabi=lp64d -mcmodel=medany -ffunction-sections -fdata-sections`. `thead-c906` brings T-Head's instructions for addresses, bit fields, multiplying and adding, and pairs of loads and stores, but in GCC 15 not `zifencei`: the startup asks for it, for its `fence.i`.
- Linker flags: `-nostartfiles --specs=nosys.specs -Wl,--gc-sections -Wl,--no-warn-rwx-segments` and the linker script. The whole image is in DRAM at `0x4000_0000`, `.data` included, so nothing is copied at start; the stack grows down from the top of DRAM.
- GCC 15 vectorizes nothing for `xtheadvector` at `-O3`: Steady's kernels for it will be written with its intrinsics.
- Hello world is 2 KB. The self-check, with its 200 KB table, is 205 KB.

---

## References

- Ratel: `github.com/PMunch/ratel`. Fork with the C3 port: `github.com/garrettkinman/ratel`.
- Driver packages: `github.com/Lutra-Nim/Lutra-LSM6DS33`, `github.com/Lutra-Nim/Lutra-LIS3MDL` and `github.com/Lutra-Nim/Lutra-ESPAT`.
- Steady: `github.com/garrettkinman/Steady`. See `tests/mcu/boards/esp32c3/` for the original C port and its notes, and `tests/mcu/bench.nim.in` for the board contract.
- Krill & Reflex project doc, §7 "Track R" and §3 "Hardware budget".
- Espressif: ESP32-C3 Technical Reference Manual; SVD files; `esp32c3.rom.ld` in esp-idf for ROM routine addresses.
- `esp-hal` (Rust), as the reference for driving Espressif's radio without esp-idf.
- svd2rust, as the model for generated register definitions.
