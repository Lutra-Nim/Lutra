# Package

version       = "0.1.0"
author        = "Garrett Kinman"
description   = "A Nim-only bare-metal stack for microcontrollers"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim", "expected"] # The self-checks' expected output


# Dependencies

requires "nim >= 2.2.6"
