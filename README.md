# Lutra
### A Nim-only bare-metal stack for TinyML microcontrollers

Lutra is a hardware abstraction layer and library ecosystem in pure Nim, RISC-V first. It is a spiritual successor to [Ratel](https://github.com/PMunch/ratel) and the board layer underneath [Steady](https://github.com/garrettkinman/Steady).

**Nothing is implemented yet.** The plan is in [docs/design.md](docs/design.md). The first target is the ESP32-C3-DevKitM-1, starting from the working port in [this Ratel fork](https://github.com/garrettkinman/ratel).

## Layout

| Path | Holds |
|---|---|
| `src/lutra/arch/` | What depends only on the instruction set: trap entry, context switch, startup |
| `src/lutra/chips/` | What depends on the silicon: registers, clocks, memory map, peripherals |
| `src/lutra/boards/` | What depends on the circuit board: pin names, wiring, flash size |
| `src/lutra/hal/` | The interfaces libraries are written against |
| `tools/` | Build, flash and monitor tasks; the register generator |
| `checks/` | Per-board hardware self-check programs |
| `examples/` | Example programs |
| `tests/` | Host-side tests |
| `docs/` | Design documentation |
