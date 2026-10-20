# Lutra
### A Nim-only bare-metal stack for microcontrollers

Lutra is a hardware abstraction layer and library ecosystem in pure Nim, RISC-V first. It is a spiritual successor to [Ratel](https://github.com/PMunch/ratel) and the board layer underneath [Steady](https://github.com/garrettkinman/Steady).

The plan is in [docs/design.md](docs/design.md). So far there are two boards. The ESP32-C3-DevKitM-1 has startup, GPIO and pin interrupts, both UARTs, I2C, SPI as controller and target, framed packets between boards, the board's RGB LED, a random number source, time, timer events, a cycle counter, tasks that take turns, records for capturing data on the host, MQTT over Wi-Fi through a second ESP32 running Espressif's AT firmware, and compile-time pin ownership. On top of those is the audio front-end a keyword-spotting model needs, in whole numbers, so that a board computes the same bits as the host. That is enough to recognise recorded words with one of Steady's models, and to run the board's hardware self-check and Steady's benchmark.

ST's B-L475E-IOT01A, a Cortex-M4, is the second: startup, GPIO and pin interrupts, two UARTs, I2C, SPI as controller, a random number source, time, timer events, a cycle counter, tasks, records and a report of faults. The same self-check, sensor driver and benchmark run on it. Both boards have a watchdog, say why they last started, and can restart themselves.

The third, begun for a speech demo with Steady, is Sipeed's Lichee RV Dock: an Allwinner D1, a 64-bit RISC-V at 1008 MHz with 512 MB of DRAM, run with no operating system. It has startup, GPIO, its console, time, a cycle counter, interrupts, timer events, tasks, its addressable LED, panics, a report of faults, restarting and a self-check. Programs are loaded into its DRAM over USB, and a break on its console asks a running one to make way for the next.

## A first program

```
nimble install lutra
```

Then, in a folder of its own:

```nim
# config.nims
import lutra/project
board "esp32c3_devkitm1"   # or "b_l475e_iot01a"
```

```nim
# hello.nim
import lutra

while true:
  print "Hello from Lutra, up ", millis(), " ms\n"
  delay 1.sec
```

```
nim flash hello.nim
nim monitor
```

| Command | Does |
|---|---|
| `nim build hello.nim` | Compile, link and check the image. `nim c hello.nim` skips the checks |
| `nim flash hello.nim` | Build, and write to the board |
| `nim monitor` | Read the board's console. `-d:reset` resets it first, `-d:send=...` sends it a line, and `-d:until=PASS` or `-d:timeout=30s` end it |
| `nim capture > data.csv` | Reset the board, and write its records as CSV |
| `nim size hello.nim` | Build, and show what each memory region holds |
| `nim selfcheck` | Run the board's hardware self-check and compare its output. Each board's says at its top what must not be wired |
| `nim doctor` | Check that this machine has the board's compiler, its flasher and access to its port |

Each ends with an exit code that says what went wrong: 1 the build, 2 a check, 3 the board, 4 a missing tool. [AGENTS.md](AGENTS.md) has more for coding agents.

An interrupt handler is a proc that says what calls it, bound at compile time and switched on by `start`:

```nim
proc pressed() {.interrupt: bootButton.falling.} =
  led.toggle()

start pressed
```

A task is a proc too, started the same way. Tasks take turns with the program, each running until it waits:

```nim
proc blink() {.task.} =
  while true:
    led2.toggle()
    delay 250.ms   # The program and the other tasks run meanwhile

start blink

if not wait(sensor.ready, within = 100.ms):
  print "No sensor\n"
```

Something done at a steady rate is a loop in a task, or a timer's interrupt:

```nim
for turn in every(10.ms):       # Waits for each turn, letting other tasks run
  console.record(turn, x, y, z) # For `nim capture > data.csv`

proc tick() {.interrupt: every(1.ms).} =
  inc ticks

start tick
```

Readings are smoothed, summed up and turned into spectra in whole numbers, which give the same bits on a board as on the host, and a watchdog restarts a board that stops feeding it:

```nim
import lutra, lutra/[filters, stats]

var
  slow = lowPass(hz = 2, sampleHz = 100) # Worked out when the program is compiled
  normal: Stats

print "Started after ", resetReason(), "\n"
watchdog.start(within = 1.sec)
for turn in every(10.ms):
  slow.add sensor.read().x
  normal.add slow.value
  watchdog.feed()
```

Messages go to and from an MQTT broker through a socket, here one of a Wi-Fi module's:

```nim
import lutra, lutra/mqtt, lutra_espat

const
  wifi = espAt(uart1)
  broker = mqtt(wifi.socket, "test.mosquitto.org")

uart1.buffer(1024)
uart1.init(tx = IO6, rx = IO7, baud = 115_200)
if wifi.init() and wifi.join("network", "password") and broker.connect():
  broker.subscribe("lutra/led")
  broker.publish("lutra/up", millis(), " ms")
  for message in broker.messages:
    print message.topic, ": ", message.payload, "\n"
```

Nim's checks stay on. A failed one stops the board, and `nim monitor` names the line:

```
Panic: index out of bounds at 0x420102f4, blink.nim(12)
```

`-d:danger` before a command turns them off.

Wiring mistakes stop the build. Using one pin for two things, here the console's transmit pin as an output, gives:

```
Error: IO21 is claimed as UART0 TX and as a GPIO at blink.nim(8)
```

The serial port is found when only one board of the kind is attached. Otherwise name it with `-d:port=/dev/ttyUSB1` before the command, or in `LUTRA_PORT`.

Needs Nim 2.2.6 or later, and has also been run on 2.2.12, and for each board its compiler and its flasher. The tasks need no shell tools: the first that reads a port builds a small program for the host, in a few seconds, once. They have been run on Linux; on Windows, the program that reads the port has been tried under Wine, and on macOS it builds and has not run.

| Board | Compiler | Flasher |
|---|---|---|
| `esp32c3_devkitm1` | Espressif's `riscv32-esp-elf` toolchain, on the `PATH` or where Espressif's installer puts it under `~/.espressif` | `esptool` 5, on the `PATH` or named in `ESPTOOL` |
| `b_l475e_iot01a` | `arm-none-eabi-gcc` with its `newlib`, on the `PATH` | `pyocd`, on the `PATH` or named in `PYOCD` |
| `lichee_rv_dock` | xPack's `riscv-none-elf-gcc` 14 or later, on the `PATH` or unpacked under `~/.local/xPacks` | `xfel`, on the `PATH` or named in `XFEL`. The board's console wants a 3.3 V USB serial adapter on the pins marked TX and RX underneath, and its programs go over the module's USB-C port |

[examples/](examples) has a folder for each board, and its programs are run from there. On the DevKitM-1, `nim flash rgb.nim`, `nim flash button.nim`, `nim flash debounced.nim`, `nim flash tasks.nim` and `nim flash record.nim` need nothing wired; on the B-L475E-IOT01A, nor do `nim flash blink.nim`, `nim flash button.nim`, `nim flash debounced.nim`, `nim flash tasks.nim` and `nim flash record.nim`.

The programs in [checks/](checks) are run from that folder and are set up for the DevKitM-1. `-d:board=b_l475e_iot01a` before a command builds for the other board.

Drivers for parts that are not on the board are packages of their own, installed the same way, as `nimble install lutra_lis3mdl`. The first are [lutra_lsm6ds33](https://github.com/Lutra-Nim/Lutra-LSM6DS33), for an accelerometer and gyroscope, [lutra_lis3mdl](https://github.com/Lutra-Nim/Lutra-LIS3MDL), for a magnetometer, and [lutra_espat](https://github.com/Lutra-Nim/Lutra-ESPAT), for Wi-Fi through an ESP32 running Espressif's AT firmware. Every package of Lutra's is tagged `lutra` in Nimble's list.

Lutra is at 0.1, and will change. While its version starts with 0, a release that breaks a program goes up in its second number, 0.2.0, and the drivers ask for the 0.1 releases only, so an upgrade of Lutra can't break them unawares. [CHANGELOG.md](CHANGELOG.md) says what each release changed.

## Checks

Run from `checks/` in a clone of this repository, but for `nim selfcheck`, which runs from any project. With two boards of one kind attached, those for one board need the port named. The first five also run on the B-L475E-IOT01A, with `-d:board=b_l475e_iot01a` before the command.

| Command | Does |
|---|---|
| `nim selfcheck` | The board's own hardware: clock, time, pins, interrupts, flash, I2C, the LED's signal, tasks, timers, the fault report |
| `nim steady` | Steady's benchmark for one model, from a checkout of Steady beside this repository |
| `nim sensors` | Reads an LSM6DS33 and a LIS3MDL on IO18 and IO19 through their driver packages, checked out beside this repository. On the B-L475E-IOT01A, the LIS3MDL the board carries |
| `nim echo` | Sends the board 64 KB at 921600 baud and checks that it all comes back |
| `nim resets` | The watchdog resets the board when it is not fed, the board restarts itself, and each time it says why it started |
| `nim loopback` | On the B-L475E-IOT01A only, with jumpers from D11 to D12 and from D1 to D0: SPI1 and UART4 bring back what they send |
| `nim wiring` | Checks the wires between two boards, listed at the top of [checks/wiring.nim](checks/wiring.nim) |
| `nim link` | The two boards exchange checksummed buffers over UART and SPI |
| `nim wifi` | Publishes and subscribes through test.mosquitto.org, over Wi-Fi through a second DevKitM-1 running Espressif's AT firmware, wired as for `nim wiring`. Needs `lutra-espat` checked out beside this repository, and the network in `LUTRA_WIFI_NETWORK` and `LUTRA_WIFI_PASSWORD` |
| `nim keywords` | Recognises twelve recorded words with Steady's `kws` model, and checks the board's features against the host's bit for bit. The first run downloads 112 MB of recordings. `nim -d:testset keywords` scores all 4890 on the host |

The host-side tests are the `t*.nim` files in `tests/`, each run with `nim r`.

## Layout

| Path | Holds |
|---|---|
| `src/lutra/arch/` | What depends only on the instruction set: trap entry, switching stacks, startup |
| `src/lutra/chips/` | What depends on the silicon: registers, clocks, memory map, peripherals |
| `src/lutra/boards/` | What depends on the circuit board: pin names, wiring, flash size |
| `src/lutra/hal/` | The interfaces libraries are written against |
| `src/lutra/*.nim` | Libraries: printing, text, logging, reading numbers, checksums, time, tasks, records, containers, framing, arithmetic and trigonometry in whole numbers, filters, statistics, audio features and spectra, AT commands, MQTT |
| `src/lutra/project.nim` | The host side: board selection and the tasks above |
| `src/lutra/host/` | Programs for the host that the tasks build: `monitor.nim` reads, resets and talks to a board on any of the three systems |
| `src/lutra/selfcheck/` | Each board's hardware self-check, and what it should print |
| `tools/` | Empty so far; for the register generator |
| `checks/` | Hardware checks, for one board and for two wired together |
| `examples/` | Example programs, in a folder for each board |
| `tests/` | Host-side tests |
| `docs/` | Design documentation |
