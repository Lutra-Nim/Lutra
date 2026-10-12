import std/[os, strutils]
import ../src/lutra/project
board "esp32c3_devkitm1"

const
  steady {.strdefine.} = thisDir() / "../../Steady" ## A checkout of Steady
  model {.strdefine.} = "kws"

task steady, "Run Steady's benchmark for a model, e.g. nim -d:model=kws steady":
  let
    work = buildDir() / "steady" / model
    nonce = gorge("date +%s")
  mkDir work
  exec "nim c --hints:off -d:release --out:" & buildDir() / "steadyc" & " " & steady / "src/steadyc.nim"
  exec buildDir() / "steadyc " & steady / "tests/models" / model & ".tflite -o " & work &
    " -n " & model & " --no-capi -q"
  writeFile(work / "bench.nim", readFile(steady / "tests/mcu/bench.nim.in").replace("@MODEL@", model))
  build(thisDir() / "steady.nim", "-d:steadyProfile -d:steadyNonce=" & nonce &
    " --path:" & steady / "src" & " --path:" & work)
  flash(elf("steady"), memory, serialPort())
  let record = capture(resetCommand(serialPort()), "BEGIN", "END")
  echo record
  if "nonce " & nonce notin record: quit "That is not the image that was just built."

task echo, "Send the board 64K at 921600 baud and check that it all comes back":
  let (port, work) = (serialPort(), buildDir() / "echo")
  mkDir work
  for (receive, switches) in [("polled", ""), ("buffered", "-d:buffered")]:
    build(thisDir() / "echo.nim", switches)
    flash(elf("echo"), memory, port)
    # The reset's own chatter, at the boot ROM's baud rate, is read and dropped
    exec "sh -c " & quoteShell("exec 3<>" & port & "; " & resetCommand(port) &
      "; stty 921600 raw -echo -hupcl <&3; sleep 1; timeout 1 cat <&3 >/dev/null" &
      "; head -c 65536 /dev/urandom > sent; (timeout 4 cat <&3 > got) & cat sent >&3; wait" &
      "; cmp sent got").replace("sent", work / "sent").replace("got", work / "got")
    echo "All 65536 bytes came back, with receive ", receive, "."
