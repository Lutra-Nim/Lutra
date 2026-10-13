import std/[os, strutils]
import ../src/lutra/project
board "esp32c3_devkitm1"

const
  steady {.strdefine.} = thisDir() / "../../Steady" ## A checkout of Steady
  model {.strdefine.} = "kws"

proc generate(model, work: string) =
  ## Steady's code for one of its test models
  mkDir work
  exec "nim c --hints:off -d:release --out:" & buildDir() / "steadyc" & " " & steady / "src/steadyc.nim"
  exec buildDir() / "steadyc " & steady / "tests/models" / model & ".tflite -o " & work &
    " -n " & model & " --no-capi -q"

task steady, "Run Steady's benchmark for a model, e.g. nim -d:model=kws steady":
  let
    work = buildDir() / "steady" / model
    nonce = gorge("date +%s")
  generate(model, work)
  writeFile(work / "bench.nim", readFile(steady / "tests/mcu/bench.nim.in").replace("@MODEL@", model))
  build(thisDir() / "steady.nim", "-d:steadyProfile -d:steadyNonce=" & nonce &
    " --path:" & steady / "src" & " --path:" & work)
  flash(elf("steady"), memory, serialPort())
  let record = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END")
  echo record
  if "nonce " & nonce notin record: quit "That is not the image that was just built."

task echo, "Send the board 64K at 921600 baud and check that it all comes back":
  let
    port = serialPort()
    work = buildDir() / "echo"
    (sent, got) = (quoteShell(work / "sent"), quoteShell(work / "got"))
  mkDir work
  for (receive, switches) in [("polled", ""), ("buffered", "-d:buffered")]:
    build(thisDir() / "echo.nim", switches)
    flash(elf("echo"), memory, port)
    # The reset's own chatter, at the boot ROM's baud rate, is read and dropped
    exec "sh -c " & quoteShell("exec 3<>" & port & "; " & resetCommand(port) &
      "; stty 921600 raw -echo -hupcl <&3; sleep 1; timeout 1 cat <&3 >/dev/null" &
      "; head -c 65536 /dev/urandom > " & sent &
      "; (timeout 4 cat <&3 > " & got & ") & cat " & sent & " >&3; wait" &
      "; cmp " & sent & " " & got)
    echo "All 65536 bytes came back, with receive ", receive, "."

proc twoBoards(): seq[string] =
  result = serialPorts()
  if result.len != 2: quit "This needs two boards attached, and found " & $result.len & "."

task wiring, "Check the wires between two boards":
  let ports = twoBoards()
  # The listener goes on first, so that two boards are never both driving
  build(thisDir() / "wiring.nim")
  flash(elf("wiring"), memory, ports[1])
  build(thisDir() / "wiring.nim", "-d:drive")
  flash(elf("wiring"), memory, ports[0])
  let report = capture(ports[1], resetCommand(ports[1]), "BEGIN", "END", 30)
  echo report
  if "wiring ok" notin report: quit "The boards are not wired as checks/wiring.nim describes."

task link, "Two wired boards exchange checksummed buffers over UART and SPI":
  let
    ports = twoBoards()
    work = buildDir() / "link"
  mkDir work
  # In this order whatever the boards ran before, no pin is driven from both ends
  build(thisDir() / "link.nim", "-d:first")
  flash(elf("link"), memory, ports[0])
  build(thisDir() / "link.nim")
  flash(elf("link"), memory, ports[1])
  # The second board is reset first and waits; the first board's reset starts them
  exec captureCommand(ports[1], resetCommand(ports[1]), "BEGIN", "END", 60) & " > " &
    quoteShell(work / "second.txt") & " & sleep 3"
  let first = capture(ports[0], resetCommand(ports[0]), "BEGIN", "END", 60)
  exec "sleep 2"
  let second = readFile(work / "second.txt").replace("\r", "")
  echo "The first board:\n", first, "\nThe second board:\n", second
  for report in [first, second]:
    if "uart 200 of 200" notin report or "spi 200 of 200" notin report:
      quit "The link check FAILED."
  echo "The link check passed."

task keywords, "Recognise recorded words, and check the board against the host bit for bit":
  let
    work = buildDir() / "keywords"
    archive = work / "speech_commands_test_set_v0.02.tar.gz"
    paths = " --path:" & steady / "src --path:" & work
    host = "nim c --skipProjCfg --hints:off -d:release --path:" & thisDir() / "../src" & paths &
      " --nimcache:" & buildDir() / "nimcache/keywords_host" & " --out:" & work / "host "
  generate("kws", work)
  if not dirExists(work / "yes"):
    # 112 MB, once. It is someone else's to hand out, so it is not kept in the repository.
    exec "curl -L --fail -o " & archive & " http://download.tensorflow.org/data/speech_commands_test_set_v0.02.tar.gz"
    if "cc2a00c1147c2254e9be3fa0f779d8c17421dc349b86366567a8edfa9acd51df" notin gorge("sha256sum " & archive):
      quit "The test set is not the file this check was written against."
    exec "tar -xzf " & archive & " -C " & work
    rmFile archive
  if defined(testset):
    exec host & "-d:testset " & thisDir() / "keywords.nim"
    exec work / "host"
    return
  exec host & thisDir() / "keywords.nim"
  let expected = gorge(work / "host").strip
  build(thisDir() / "keywords.nim", paths)
  flash(elf("keywords"), memory, serialPort())
  let report = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END").strip
  echo report
  var got: seq[string]
  for line in report.splitLines:
    if not line.startsWith("time"): got.add line
  if got.join("\n") != expected:
    quit "\nThe board and the host DISAGREE. The host printed:\n" & expected
  echo "\nThe board and the host agree."

task sensors, "Read the board's sensors through their driver packages":
  # The packages are expected checked out beside this repository
  build(thisDir() / "sensors.nim", " --path:" & thisDir() / "../../lutra-lsm6ds33/src" &
    " --path:" & thisDir() / "../../lutra-lis3mdl/src")
  flash(elf("sensors"), memory, serialPort())
  let report = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END", 30)
  echo report
  if "FAILED" in report or "END" notin report: quit "The sensor check FAILED."
  echo "\nThe sensor check passed."
