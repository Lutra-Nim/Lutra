import std/[os, strutils, hashes]
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
    nonce = $(hash(CompileDate & CompileTime).uint32) # When this task started
  generate(model, work)
  writeFile(work / "bench.nim", readFile(steady / "tests/mcu/bench.nim.in").replace("@MODEL@", model))
  build(thisDir() / "steady.nim", "-d:steadyProfile -d:steadyNonce=" & nonce &
    " --path:" & steady / "src" & " --path:" & work)
  flash("steady", serialPort())
  let record = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END")
  if "nonce " & nonce notin record: fail checkFailed, "That is not the image that was just built."

task echo, "Send the board 64K at 921600 baud and check that it all comes back":
  let
    port = serialPort()
    host = hostProgram(thisDir() / "echo_host.nim",
      [thisDir() / "echo_host.nim", thisDir() / "../src/lutra/host/serialport.nim"])
  for (receive, switches) in [("polled", ""), ("buffered", "-d:buffered")]:
    build(thisDir() / "echo.nim", switches)
    flash("echo", port)
    try: exec quoteShell(host) & " " & quoteShell(port) & " " & quoteShell(resetCommand(port))
    except OSError: fail checkFailed, "The echo check FAILED, with receive " & receive & "."
    echo "All 65536 bytes came back, with receive ", receive, "."

proc twoBoards(): seq[string] =
  result = serialPorts()
  if result.len != 2: fail noBoard, "This needs two boards attached, and found " & $result.len & "."

task wiring, "Check the wires between two boards":
  let ports = twoBoards()
  # The listener goes on first, so that two boards are never both driving
  build(thisDir() / "wiring.nim")
  flash("wiring", ports[1])
  build(thisDir() / "wiring.nim", "-d:drive")
  flash("wiring", ports[0])
  let report = capture(ports[1], resetCommand(ports[1]), "BEGIN", "END", 30)
  if "wiring ok" notin report: fail checkFailed, "The boards are not wired as checks/wiring.nim describes."

task link, "Two wired boards exchange checksummed buffers over UART and SPI":
  let
    ports = twoBoards()
    work = buildDir() / "link"
  mkDir work
  # In this order whatever the boards ran before, no pin is driven from both ends
  build(thisDir() / "link.nim", "-d:first")
  flash("link", ports[0])
  build(thisDir() / "link.nim")
  flash("link", ports[1])
  # The second board is reset first and waits; the first board's reset starts
  # them. Running the second in the background takes a POSIX shell.
  exec captureCommand(ports[1], resetCommand(ports[1]), "BEGIN", "END", work / "second.txt", 60) &
    " > /dev/null & sleep 3"
  echo "The first board:"
  let first = capture(ports[0], resetCommand(ports[0]), "BEGIN", "END", 60)
  exec "sleep 2"
  let second = readFile(work / "second.txt")
  echo "\nThe second board:\n", second
  for report in [first, second]:
    if "uart 200 of 200" notin report or "spi 200 of 200" notin report:
      fail checkFailed, "The link check FAILED."
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
    let sha256 = when defined(windows): "certutil -hashfile " & archive & " SHA256"
                 elif defined(macosx): "shasum -a 256 " & archive
                 else: "sha256sum " & archive
    if "cc2a00c1147c2254e9be3fa0f779d8c17421dc349b86366567a8edfa9acd51df" notin gorge(sha256):
      fail notSetUp, "The test set is not the file this check was written against."
    exec "tar -xzf " & archive & " -C " & work
    rmFile archive
  if defined(testset):
    exec host & "-d:testset " & thisDir() / "keywords.nim"
    exec work / "host"
    return
  exec host & thisDir() / "keywords.nim"
  let expected = gorge(work / "host").strip
  build(thisDir() / "keywords.nim", paths)
  flash("keywords", serialPort())
  let report = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END").strip
  var got: seq[string]
  for line in report.splitLines:
    if not line.startsWith("time"): got.add line
  if got.join("\n") != expected:
    fail checkFailed, "\nThe board and the host DISAGREE. The host printed:\n" & expected
  echo "\nThe board and the host agree."

task sensors, "Read the board's sensors through their driver packages":
  # The packages are expected checked out beside this repository
  build(thisDir() / "sensors.nim", " --path:" & thisDir() / "../../lutra-lsm6ds33/src" &
    " --path:" & thisDir() / "../../lutra-lis3mdl/src")
  flash("sensors", serialPort())
  let report = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END", 30)
  if "FAILED" in report or "END" notin report: fail checkFailed, "The sensor check FAILED."
  echo "\nThe sensor check passed."

task resets, "The watchdog resets the board, the board restarts, and each says why it started":
  build(thisDir() / "resets.nim")
  flash("resets", serialPort())
  let report = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END", 30)
  for line in ["started by the host ok", "fed for a second ok", "starved for 250 ms ok",
      "the watchdog resets ok", "restart ok"]:
    if line notin report: fail checkFailed, "\nThe resets check FAILED: no \"" & line & "\"."
  echo "\nThe resets check passed."

task loopback, "The B-L475E-IOT01A's SPI1, through a jumper back to itself":
  build(thisDir() / "loopback.nim")
  flash("loopback", serialPort())
  let report = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END", 30)
  if "FAILED" in report or "END" notin report: fail checkFailed, "The loopback check FAILED."
  echo "\nThe loopback check passed."

task wifi, "Publish and subscribe over MQTT, through a second DevKitM-1 running Espressif's AT firmware":
  # The package is expected checked out beside this repository, and the
  # network in the environment, so that it is never written here
  if not existsEnv("LUTRA_WIFI_NETWORK"): fail notSetUp, "Name the network in LUTRA_WIFI_NETWORK and LUTRA_WIFI_PASSWORD."
  build(thisDir() / "wifi.nim", " --path:" & thisDir() / "../../lutra-espat/src" &
    " " & quoteShell("-d:network=" & getEnv("LUTRA_WIFI_NETWORK")) &
    " " & quoteShell("-d:password=" & getEnv("LUTRA_WIFI_PASSWORD")))
  flash("wifi", serialPort())
  let report = capture(serialPort(), resetCommand(serialPort()), "BEGIN", "END", 60)
  if "FAILED" in report or "END" notin report: fail checkFailed, "The Wi-Fi check FAILED."
  echo "\nThe Wi-Fi check passed."
