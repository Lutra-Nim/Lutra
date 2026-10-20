# Changelog

While Lutra's version starts with 0, a release that breaks a program goes up in its second number, and any other in its third. The driver packages ask for one second number at a time, as `requires "lutra ^= 0.1"`.

## Next

- A third board, Sipeed's Lichee RV Dock: an Allwinner D1, a 64-bit RISC-V at 1008 MHz with 512 MB of DRAM, run bare. Startup, GPIO, its console UART, time, the cycle counter, interrupts, timer events, tasks, its addressable LED, panics, a report of faults, restarting and its self-check. Programs are loaded into DRAM over USB by `xfel`, which `nim doctor` looks for with the compiler, xPack's `riscv-none-elf-gcc`. The host starts a program again by sending a break on the console, which every program on the board answers by restarting to be loaded. Not yet: pin interrupts, the watchdog and the reason the board started.
- A board may define `lutraHalted`, which a program stopped by a panic or a fault calls over and over: the Dock's looks for the host asking it to start again. Other boards stop as before.

## 0.1.0

The first release.

- Boards: the ESP32-C3-DevKitM-1 and ST's B-L475E-IOT01A.
- On both: startup, GPIO and pin interrupts, UARTs polled or through an interrupt, I2C, SPI as controller, random numbers, time, timer events, a cycle counter, tasks that take turns, the watchdog, the reason the board started, restarting, panics that name their line, and a hardware self-check. On the DevKitM-1 also SPI as a target with DMA and its addressable LED; on the B-L475E-IOT01A a report of faults.
- Interfaces for libraries: `Pin`, `ByteLink`, `I2cBus`, `SpiDevice` and `Socket`.
- Libraries: printing without a heap, `Text`, JSON, logging, reading numbers, CRCs, durations, containers, framing, records for `nim capture`, a debounced button, seeded random numbers and backoff, arithmetic and trigonometry in whole numbers, filters, statistics, a spectrum, the audio front-end of a keyword-spotting model, AT commands and MQTT.
- Tasks for the host: `build`, `flash`, `monitor`, `capture`, `size`, `selfcheck` and `doctor`, on Linux, macOS and Windows, each ending with an exit code that says what went wrong.
