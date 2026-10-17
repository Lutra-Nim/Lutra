# Working on Lutra

Lutra is a bare-metal HAL and libraries in pure Nim. Two boards so far: `esp32c3_devkitm1` (RISC-V) and `b_l475e_iot01a` (Cortex-M4). The plan, the state of things and the conventions are in [docs/design.md](docs/design.md); read §1.2 before starting. [README.md](README.md) has the user's view and the repository layout.

## Commands

Run from a folder whose `config.nims` names a board: `examples/<board>/`, `checks/`, or a user's project. `-d:board=b_l475e_iot01a` before a command builds for the other board. With two boards attached, name the port: `-d:port=/dev/ttyUSB1` or `LUTRA_PORT`.

| Command | Does |
|---|---|
| `nim doctor` | Says what this machine is missing for the board, and how to get it |
| `nim build x.nim` | Compile, link and check the image. No board needed |
| `nim flash x.nim` | Build and write to the board |
| `nim -d:reset -d:until=PASS -d:timeout=30s monitor` | Reset the board, print its console, end at the first line holding `PASS` |
| `nim -d:timeout=5s monitor` | Print the console for 5 s |
| `nim -d:send="text" -d:until=OK -d:timeout=5s monitor` | Send a line, ended by CR LF, and wait for the answer |
| `nim capture > data.csv` | Reset the board and write its records as CSV |
| `nim size x.nim` | What each memory region holds |

Plain `nim monitor` ends only when the board stops, at a panic or a fault. Give it `-d:until` or `-d:timeout`.

Nim's checks are on. A failed one stops the board, and `nim monitor` names the line, from the image `nim flash` last wrote from this folder:

```
Panic: index out of bounds at 0x420102f4, sensors.nim(42)
```

`-d:danger` builds without checks. A hot loop that is tested on the host turns them off in its own module, as `lutra/signal` does: `when defined(lutraBoard): {.push checks: off.}`.

Every task ends with one of these codes, kept stable (`Exit` in [src/lutra/tooling.nim](src/lutra/tooling.nim)):

| Code | Means |
|---|---|
| 0 | Passed |
| 1 | The build failed, or the command was not understood |
| 2 | The board ran, and did not print what was expected: a check failed, `-d:until` was not seen in time, or the board panicked |
| 3 | No board, more than one, or it could not be reached or written to |
| 4 | A tool or setting is missing: run `nim doctor` |

## Confirming a change

Without a board: each `tests/t*.nim`, with `nim r` from `tests/`, and `nim build` of the examples for both boards. A change to the host side is confirmed by running the task it changes.

With a board, from `checks/`: `nim selfcheck` (45 s) for each board touched. The table in design.md §1.2 lists every check, what it proves and what it needs: a second board, wires, a sensor, Wi-Fi. Only two boards can be attached at once, so a check needing a board that is not attached waits for the user to swap cables. Say so rather than skipping it silently.

A hardware fact is not relied on until a check has exercised it; then it goes in design.md Appendix A (ESP32-C3) or D (STM32L475).

## Nim on the target

There is no heap (`--mm:none`), and programs are built for size. Appendix B of design.md has the full list of surprises; the ones met most:

- No `seq`, `string`, `ref` or closures at run time. Use arrays, `openArray`, `cstring`, and `lutra/containers`.
- Much of the standard library allocates or raises: `std/algorithm`'s `sort`, `parseutils.parseInt`, `std/strformat`. Use `print`, `log.info`, a `Text` from `lutra/fmt` for building strings, and `lutra/parse` for reading numbers.
- `cstring"a\n"` and `p"a\n"` are raw literals, so `\n` is two characters. Write `cstring("a\n")`.
- Going through a constant array of strings allocates. Use `cstring`s or numbers.
- `int` is 32 bits on the board and 64 on the host. Code that must agree with the host names its sizes: `int32`, `uint64`.
- In a generic proc or one written against a concept, declare `send`, `receive` and `reset` with `mixin`, or they bind to `system`'s.
- A proc declared in a template needs `{.gensym.}`, or a second use is a redefinition.
- What a board does before the program goes in a procedure the startup calls, not at a module's top level.

## Style

Code reads like ordinary Nim: procs with pragmas (`{.task.}`, `{.interrupt: pin.falling.}`) started by `start`, not DSL blocks. Mistakes are compile errors with a message saying what and where. Examples stay short; a wart is noted in a comment, not coded around. Comments say why, briefly.

Major design, scope and API decisions are the author's: bring options with a recommendation.
