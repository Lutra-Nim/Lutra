## A serial port, for the host's programs: opened, read with a time limit and
## written, on Linux, macOS and Windows alike. Raw bytes, 8 data bits, no
## parity, no flow control.

import std/[os, strutils]

when defined(windows):
  import std/winlean

  type
    Dcb = object # As windows.h has it
      length, baudRate: int32
      flags: uint32 # Bit fields: binary mode, parity, flow control, DTR and RTS
      reserved, xonLimit, xoffLimit: uint16
      byteSize, parity, stopBits: uint8
      xonChar, xoffChar, errorChar, eofChar, eventChar: char
      reserved1: uint16
    CommTimeouts = object
      readInterval, readMultiplier, readConstant, writeMultiplier, writeConstant: int32

  proc getCommState(h: Handle, dcb: ptr Dcb): WINBOOL {.importc: "GetCommState", dynlib: "kernel32", stdcall.}
  proc setCommState(h: Handle, dcb: ptr Dcb): WINBOOL {.importc: "SetCommState", dynlib: "kernel32", stdcall.}
  proc setCommTimeouts(h: Handle, t: ptr CommTimeouts): WINBOOL {.
    importc: "SetCommTimeouts", dynlib: "kernel32", stdcall.}

  type SerialPort* = object
    handle: Handle
    name: string

else:
  import std/[posix, termios]

  type SerialPort* = object
    fd: cint
    name: string

  proc cfmakeraw(t: ptr Termios) {.importc, header: "<termios.h>".}
  proc cfsetspeed(t: ptr Termios, speed: Speed): cint {.importc, header: "<termios.h>".}

  proc speed(baud: int): Speed =
    when defined(macosx): Speed(baud) # Its speeds are the rates themselves
    else:
      case baud
      of 9600: B9600
      of 57600: B57600
      of 115200: B115200
      of 230400: B230400
      of 460800: B460800
      of 921600: B921600
      of 1000000: B1000000
      of 2000000: B2000000
      else: raise newException(ValueError, "Can't set a serial port to " & $baud & " baud.")

proc fail(port: SerialPort, what: string) {.noreturn.} =
  raiseOSError(osLastError(), what & " " & port.name)

proc setBaud*(port: SerialPort, baud: int) =
  ## Sets the rate, and makes the port raw again. A flasher run in between may
  ## have changed both.
  when defined(windows):
    var dcb = Dcb(length: int32(sizeof(Dcb)))
    if getCommState(port.handle, addr dcb) == 0: port.fail "Can't read the settings of"
    dcb.baudRate = int32(baud)
    # Binary, no parity, no flow control, and DTR and RTS low, as they are
    # left on Linux: on a DevKitM-1 they reset the chip when they differ
    dcb.flags = 1
    dcb.byteSize = 8
    dcb.parity = 0
    dcb.stopBits = 0 # One
    if setCommState(port.handle, addr dcb) == 0: port.fail "Can't set"
    # A read returns once anything has come, or at its own time limit
    var t = CommTimeouts(readInterval: -1, readMultiplier: -1, readConstant: 1)
    if setCommTimeouts(port.handle, addr t) == 0: port.fail "Can't set"
  else:
    var t: Termios
    if tcGetAttr(port.fd, addr t) != 0: port.fail "Can't read the settings of"
    cfmakeraw(addr t)
    t.c_cflag = t.c_cflag or CLOCAL or CREAD
    t.c_cflag = t.c_cflag and not HUPCL # Closing the port must not reset the board
    t.c_cc[VMIN] = '\0'
    t.c_cc[VTIME] = '\0'
    discard cfsetspeed(addr t, speed(baud))
    if tcSetAttr(port.fd, TCSANOW, addr t) != 0: port.fail "Can't set"

proc openPort*(name: string, baud: int): SerialPort =
  ## Raises OSError when the port is not there or can't be opened
  result.name = name
  when defined(windows):
    # COM10 and above are only found by their full name
    let path = if name.startsWith("\\\\"): name else: "\\\\.\\" & name
    result.handle = createFileW(newWideCString(path), GENERIC_READ or GENERIC_WRITE, 0, nil,
      OPEN_EXISTING, 0, 0)
    if result.handle == INVALID_HANDLE_VALUE: result.fail "Can't open"
  else:
    result.fd = posix.open(name.cstring, O_RDWR or O_NOCTTY or O_NONBLOCK)
    if result.fd < 0: result.fail "Can't open"
  result.setBaud(baud)

proc close*(port: SerialPort) =
  when defined(windows): discard closeHandle(port.handle)
  else: discard posix.close(port.fd)

proc read*(port: SerialPort, buffer: var openArray[byte], ms: int): int =
  ## Waits up to `ms` for bytes, and gives how many it put in `buffer`: 0 when
  ## none came. Raises OSError when the port has gone, as when a board is
  ## unplugged.
  when defined(windows):
    var t = CommTimeouts(readInterval: -1, readMultiplier: -1, readConstant: int32(max(ms, 1)))
    discard setCommTimeouts(port.handle, addr t)
    var got: int32
    if readFile(port.handle, addr buffer[0], int32(buffer.len), addr got, nil) == 0:
      port.fail "Can't read"
    int(got)
  else:
    var waiting = TPollfd(fd: port.fd, events: POLLIN)
    let ready = poll(addr waiting, 1, cint(ms))
    if ready < 0 and osLastError() != OSErrorCode(EINTR): port.fail "Can't read"
    if ready <= 0: return 0
    if (waiting.revents and (POLLHUP or POLLERR or POLLNVAL)) != 0 and
        (waiting.revents and POLLIN) == 0:
      port.fail "Lost"
    let n = posix.read(port.fd, addr buffer[0], buffer.len)
    if n < 0:
      if osLastError() in [OSErrorCode(EAGAIN), OSErrorCode(EINTR)]: return 0
      port.fail "Can't read"
    if n == 0: port.fail "Lost" # Ready with nothing to read: it has gone
    n

proc write*(port: SerialPort, data: openArray[byte]) =
  var done = 0
  while done < data.len:
    when defined(windows):
      var n: int32
      if writeFile(port.handle, unsafeAddr data[done], int32(data.len - done), addr n, nil) == 0:
        port.fail "Can't write to"
      done += n
    else:
      let n = posix.write(port.fd, unsafeAddr data[done], data.len - done)
      if n < 0:
        if osLastError() != OSErrorCode(EAGAIN): port.fail "Can't write to"
        sleep 1
      else: done += n

proc write*(port: SerialPort, text: string) =
  port.write(text.toOpenArrayByte(0, text.high))

when defined(windows):
  proc regOpenKeyExW(key: uint, subKey: WideCString, options, sam: int32, result: ptr uint): int32 {.
    importc: "RegOpenKeyExW", dynlib: "advapi32", stdcall.}
  proc regEnumValueW(key: uint, index: int32, name: ptr uint16, nameLen: ptr int32, reserved: pointer,
    kind: ptr int32, data: ptr uint16, dataLen: ptr int32): int32 {.
    importc: "RegEnumValueW", dynlib: "advapi32", stdcall.}
  proc regCloseKey(key: uint): int32 {.importc: "RegCloseKey", dynlib: "advapi32", stdcall.}

proc ports*(): seq[tuple[name, device: string]] =
  ## Every serial port there is: its name, and what the system calls the
  ## device behind it, by which a board's kind of port is told from another's.
  ## On Linux and macOS the two are the same. On Windows the device is the
  ## driver's, such as `\Device\Silabser0` for a CP210x bridge.
  when defined(windows):
    const localMachine = 0x80000002'u
    var key: uint
    if regOpenKeyExW(localMachine, newWideCString("HARDWARE\\DEVICEMAP\\SERIALCOMM"), 0,
        0x20019, addr key) != 0: # KEY_READ
      return
    proc text(chars: openArray[uint16]): string =
      # Ports and devices are named in ASCII
      for c in chars:
        if c == 0: break
        result.add(if c < 128: char(c) else: '?')
    var index = 0'i32
    while true:
      var
        name, data: array[256, uint16]
        (nameLen, dataLen, kind) = (256'i32, 512'i32, 0'i32)
      if regEnumValueW(key, index, addr name[0], addr nameLen, nil, addr kind, addr data[0],
          addr dataLen) != 0:
        break
      result.add (text(data), text(name))
      inc index
    discard regCloseKey(key)
  else:
    for file in walkDir("/dev"):
      let name = file.path.extractFilename
      if name.startsWith("tty") or name.startsWith("cu."):
        result.add (file.path, file.path)

proc canonical*(name: string): string =
  ## One name for a port, however it was named: a link in /dev/serial/by-id
  ## and the device it points to are the same port
  when defined(windows): name.toUpperAscii
  else:
    try: expandFilename(name) except OSError: name

when not defined(windows):
  proc group*(name: string): string =
    ## The group a port belongs to, which may open it
    var info: Stat
    if stat(name.cstring, info) == 0:
      let g = getgrgid(info.st_gid)
      if g != nil: return $g.gr_name
