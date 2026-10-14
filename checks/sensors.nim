## The I2C bus against real devices, each read through its own driver package.
## Run it with `nim sensors`, with `lutra-lsm6ds33` and `lutra-lis3mdl` checked
## out beside this repository, and the board lying still.
##
## On the DevKitM-1 the devices are Adafruit's LSM6DS33 + LIS3MDL breakout on
## IO18 (SDA) and IO19 (SCL). On the author's breakout the ADM pin has to be
## wired to GND, or the magnetometer's address will not hold still.
##
## The B-L475E-IOT01A carries a LIS3MDL of its own, at that part's other
## address, and nothing the accelerometer's driver knows.

import lutra, lutra_lis3mdl

when declared(i2c2):
  const
    bus = i2c2
    compass = lis3mdl(bus, address = 0x1E)
  bus.init(sda = PB11, scl = PB10)
else:
  import lutra_lsm6ds33
  const
    bus = i2c0
    imu = lsm6ds33(bus)
    compass = lis3mdl(bus)
  bus.init(sda = IO18, scl = IO19)

proc check(name: cstring, passed: bool) =
  print name, (if passed: cstring(" ok\n") else: cstring(" FAILED\n"))

func squared(v: tuple[x, y, z: int32]): int64 =
  int64(v.x) * v.x + int64(v.y) * v.y + int64(v.z) * v.z

print "BEGIN sensors\n"
when declared(imu): check "accelerometer answers", imu.init(hz = 104)
check "magnetometer answers", compass.init(hz = 80)

# A device that refuses more than its address must not spoil the transaction
# after. Nothing may have the address asked here.
block:
  var
    register: array[1, byte]
    kept = true
  for round in 0..<200:
    discard bus.writeRead(0x7F, [0x0F'u8], register)
    if not compass.init(hz = 80): kept = false
  check "after a refusal", kept

block:
  var
    field: tuple[x, y, z: int32]
    fields = 0
  when declared(imu):
    var
      acceleration: tuple[x, y, z: int32]
      accelerations = 0
  let start = millis()
  while millis() - start < 3000:
    when declared(imu):
      if imu.ready:
        acceleration = imu.acceleration()
        inc accelerations
    if compass.ready:
      field = compass.read()
      inc fields
  # Each within a tenth of what was asked for, over three seconds
  when declared(imu):
    check "accelerometer's rate", accelerations in 280..344
    check "gravity", acceleration.squared in 810_000'i64..1_210_000'i64 # 0.9 to 1.1 g
  check "magnetometer's rate", fields in 216..264
  check "a magnetic field", field.squared in 10_000'i64..4_000_000'i64 # 0.1 to 2 gauss

print "END sensors\n"
while true: discard
