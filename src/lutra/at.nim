## Talking to a module that takes AT commands, such as a Wi-Fi or cellular
## module, over a `ByteLink`:
##
##   uart1.acquire()
##   uart1.command "+CWJAP=\"", network, "\""
##   while uart1.hear(within = 20.sec) and uart1.line != "OK": discard
##   uart1.release()
##
## A command goes out as `AT`, then its parts as `print` writes them, then a
## line ending. What comes back is heard a line at a time, without its line
## ending, and empty lines are passed over. A `>` at the start of a line, a
## module's prompt for data, is a line by itself.
##
## Only one task talks to a module at a time: `acquire` waits for its turn and
## `release` gives it up.

import std/macros
import fmt, tasks, time, hal/bytelink

const longest = 256 # Of what is kept of a line

type Lines = object
  text: array[longest, char]
  length: int
  whole: bool # `text` is a whole line, which the next byte heard replaces
  busy: bool

proc lines(link: static ByteLink): ptr Lines =
  var lines {.global.}: Lines
  addr lines

func startsWith*(line: openArray[char], prefix: string): bool =
  if line.len < prefix.len: return false
  for i, c in prefix:
    if line[i] != c: return false
  true

template line*(link: static ByteLink): openArray[char] =
  ## The line last heard
  link.lines.text.toOpenArray(0, link.lines.length - 1)

proc heard*(link: static ByteLink, binary: static string = ""): bool =
  ## Reads what has come, without waiting, until a whole line has. A line
  ## that starts with `binary` ends at the comma after it, where data that is
  ## not text follows, for the caller to receive.
  mixin poll, receive
  let lines = link.lines
  if lines.whole: (lines.length, lines.whole) = (0, false)
  while link.poll:
    let c = link.receive()
    if c == '\n': lines.whole = lines.length > 0
    elif c != '\r' and lines.length < longest:
      lines.text[lines.length] = c
      inc lines.length
      lines.whole = (c == '>' and lines.length == 1) or
        (binary.len > 0 and c == ',' and link.line.startsWith(binary))
    if lines.whole: return true

proc hear*(link: static ByteLink, within: Duration, binary: static string = ""): bool =
  ## Waits up to `within` for a whole line, letting the other tasks run
  mixin micros
  let start = micros()
  while not link.heard(binary):
    if micros() - start >= within.uint64: return false
    idle()
  true

macro command*(link: untyped, args: varargs[untyped]): untyped =
  ## Sends `AT`, then each of `args` as `print` writes them, then a line ending
  result = newCall(bindSym"write", link, newLit"AT")
  for arg in args: result.add arg
  result.add newLit("\r\n")

proc acquire*(link: static ByteLink) =
  ## Waits for any other task talking to the module to finish
  let lines = link.lines
  wait not lines.busy
  lines.busy = true

proc release*(link: static ByteLink) = link.lines.busy = false

proc busy*(link: static ByteLink): bool = link.lines.busy
  ## Whether a task is talking to the module
