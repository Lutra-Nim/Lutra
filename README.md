# Lutra
### A Nim-only bare-metal stack for TinyML microcontrollers

Lutra is a hardware abstraction layer and library ecosystem in pure Nim, RISC-V first. It is a spiritual successor to [Ratel](https://github.com/PMunch/ratel) and the board layer underneath [Steady](https://github.com/garrettkinman/Steady).

The plan is in [docs/design.md](docs/design.md). So far there is one board, the ESP32-C3-DevKitM-1, with startup, GPIO and pin interrupts, both UARTs, SPI as controller and target, framed packets between boards, a random number source, time, a cycle counter and compile-time pin ownership: enough to run its hardware self-check and Steady's benchmark.

## A first program

```nim
# config.nims
import lutra/project
board "esp32c3_devkitm1"
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

Wiring mistakes stop the build. Using one pin for two things, here the console's transmit pin as an output, gives:

```
Error: IO21 is claimed as UART0 TX and as a GPIO at blink.nim(8)
```

The serial port is found when only one is attached. Otherwise name it with `-d:port=/dev/ttyUSB1` before the command, or in `LUTRA_PORT`.

Needs Nim 2.2.6, Espressif's `riscv32-esp-elf` toolchain (on the `PATH`, or where Espressif's installer puts it under `~/.espressif`) and `esptool` 5 (on the `PATH`, or named in `ESPTOOL`). The tasks use `sh`, `stty` and `awk`, so Linux for now.

The programs in [examples/](examples) and [checks/](checks) are run from their own folders.

## Checks

Run from `checks/`. With two boards attached, the first three need the port named.

| Command | Does |
|---|---|
| `nim selfcheck` | The board's own hardware: clock, time, pins, interrupts, flash, the fault report |
| `nim steady` | Steady's benchmark for one model, from a checkout of Steady beside this repository |
| `nim echo` | Sends the board 64 KB at 921600 baud and checks that it all comes back |
| `nim wiring` | Checks the wires between two boards, listed at the top of [checks/wiring.nim](checks/wiring.nim) |
| `nim link` | The two boards exchange checksummed buffers over UART and SPI |

The host-side tests are the `t*.nim` files in `tests/`, each run with `nim r`.

## Layout

| Path | Holds |
|---|---|
| `src/lutra/arch/` | What depends only on the instruction set: trap entry, context switch, startup |
| `src/lutra/chips/` | What depends on the silicon: registers, clocks, memory map, peripherals |
| `src/lutra/boards/` | What depends on the circuit board: pin names, wiring, flash size |
| `src/lutra/hal/` | The interfaces libraries are written against |
| `src/lutra/*.nim` | Libraries: printing, time, containers, framing |
| `src/lutra/project.nim` | The host side: board selection and the tasks above |
| `tools/` | Empty so far; for the register generator |
| `checks/` | Hardware checks, for one board and for two wired together |
| `examples/` | Example programs |
| `tests/` | Host-side tests |
| `docs/` | Design documentation |
