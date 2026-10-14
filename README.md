# Lutra
### A Nim-only bare-metal stack for TinyML microcontrollers

Lutra is a hardware abstraction layer and library ecosystem in pure Nim, RISC-V first. It is a spiritual successor to [Ratel](https://github.com/PMunch/ratel) and the board layer underneath [Steady](https://github.com/garrettkinman/Steady).

The plan is in [docs/design.md](docs/design.md). So far there are two boards. The ESP32-C3-DevKitM-1 has startup, GPIO and pin interrupts, both UARTs, I2C, SPI as controller and target, framed packets between boards, the board's RGB LED, a random number source, time, a cycle counter, tasks that take turns and compile-time pin ownership. On top of those is the audio front-end a keyword-spotting model needs, in whole numbers, so that a board computes the same bits as the host. That is enough to recognise recorded words with one of Steady's models, and to run the board's hardware self-check and Steady's benchmark.

ST's B-L475E-IOT01A, a Cortex-M4, is the second: startup, GPIO and pin interrupts, a console, I2C, time, a cycle counter, tasks and a report of faults. The same self-check, sensor driver and benchmark run on it.

## A first program

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
| `nim monitor` | Read the board's console. `nim -d:reset monitor` resets it first |
| `nim size hello.nim` | Build, and show what each memory region holds |
| `nim selfcheck` | Run the board's hardware self-check and compare its output |

An interrupt handler is a block, bound at compile time:

```nim
bootButton.onFalling:
  led.toggle()
```

So is a task. Tasks take turns with the program, each running until it waits:

```nim
task blink:
  while true:
    led2.toggle()
    delay 250.ms   # The program and the other tasks run meanwhile

if not wait(sensor.ready, within = 100.ms):
  print "No sensor\n"
```

Wiring mistakes stop the build. Using one pin for two things, here the console's transmit pin as an output, gives:

```
Error: IO21 is claimed as UART0 TX and as a GPIO at blink.nim(8)
```

The serial port is found when only one board of the kind is attached. Otherwise name it with `-d:port=/dev/ttyUSB1` before the command, or in `LUTRA_PORT`.

Needs Nim 2.2.6, and for each board its compiler and its flasher. The tasks use `sh`, `stty` and `awk`, so Linux for now.

| Board | Compiler | Flasher |
|---|---|---|
| `esp32c3_devkitm1` | Espressif's `riscv32-esp-elf` toolchain, on the `PATH` or where Espressif's installer puts it under `~/.espressif` | `esptool` 5, on the `PATH` or named in `ESPTOOL` |
| `b_l475e_iot01a` | `arm-none-eabi-gcc` with its `newlib`, on the `PATH` | `pyocd`, on the `PATH` or named in `PYOCD` |

[examples/](examples) has a folder for each board, and its programs are run from there. On the DevKitM-1, `nim flash rgb.nim`, `nim flash button.nim` and `nim flash tasks.nim` need nothing wired; on the B-L475E-IOT01A, nor do `nim flash blink.nim`, `nim flash button.nim` and `nim flash tasks.nim`.

The programs in [checks/](checks) are run from that folder and are set up for the DevKitM-1. `-d:board=b_l475e_iot01a` before a command builds for the other board.

Drivers for parts that are not on the board are packages of their own. The first are [lutra_lsm6ds33](https://github.com/garrettkinman/Lutra-LSM6DS33), for an accelerometer and gyroscope, and [lutra_lis3mdl](https://github.com/garrettkinman/Lutra-LIS3MDL), for a magnetometer.

## Checks

Run from `checks/`. With two boards of one kind attached, those for one board need the port named. The first three also run on the B-L475E-IOT01A, with `-d:board=b_l475e_iot01a` before the command.

| Command | Does |
|---|---|
| `nim selfcheck` | The board's own hardware: clock, time, pins, interrupts, flash, I2C, the LED's signal, tasks, the fault report |
| `nim steady` | Steady's benchmark for one model, from a checkout of Steady beside this repository |
| `nim sensors` | Reads an LSM6DS33 and a LIS3MDL on IO18 and IO19 through their driver packages, checked out beside this repository. On the B-L475E-IOT01A, the LIS3MDL the board carries |
| `nim echo` | Sends the board 64 KB at 921600 baud and checks that it all comes back |
| `nim wiring` | Checks the wires between two boards, listed at the top of [checks/wiring.nim](checks/wiring.nim) |
| `nim link` | The two boards exchange checksummed buffers over UART and SPI |
| `nim keywords` | Recognises twelve recorded words with Steady's `kws` model, and checks the board's features against the host's bit for bit. The first run downloads 112 MB of recordings. `nim -d:testset keywords` scores all 4890 on the host |

The host-side tests are the `t*.nim` files in `tests/`, each run with `nim r`.

## Layout

| Path | Holds |
|---|---|
| `src/lutra/arch/` | What depends only on the instruction set: trap entry, switching stacks, startup |
| `src/lutra/chips/` | What depends on the silicon: registers, clocks, memory map, peripherals |
| `src/lutra/boards/` | What depends on the circuit board: pin names, wiring, flash size |
| `src/lutra/hal/` | The interfaces libraries are written against |
| `src/lutra/*.nim` | Libraries: printing, time, tasks, containers, framing, arithmetic in whole numbers, audio features |
| `src/lutra/project.nim` | The host side: board selection and the tasks above |
| `tools/` | Empty so far; for the register generator |
| `checks/` | Hardware checks, for one board and for two wired together |
| `examples/` | Example programs, in a folder for each board |
| `tests/` | Host-side tests |
| `docs/` | Design documentation |
