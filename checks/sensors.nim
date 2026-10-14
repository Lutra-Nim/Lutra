## The I2C bus against real devices: Adafruit's LSM6DS33 + LIS3MDL breakout on
## IO18 (SDA) and IO19 (SCL), lying still, each chip read through its own
## driver package. Run it with `nim sensors`, with `lutra-lsm6ds33` and
## `lutra-lis3mdl` checked out beside this repository.
##
## On the author's breakout the ADM pin has to be wired to GND, or the
## magnetometer's address will not hold still.

import lutra, lutra_lsm6ds33, lutra_lis3mdl

const
  imu = lsm6ds33(i2c0)
  compass = lis3mdl(i2c0)

proc check(name: cstring, passed: bool) =
  print name, (if passed: cstring(" ok\n") else: cstring(" FAILED\n"))

func squared(v: tuple[x, y, z: int32]): int64 =
  int64(v.x) * v.x + int64(v.y) * v.y + int64(v.z) * v.z

i2c0.init(sda = IO18, scl = IO19)
print "BEGIN sensors\n"
check "accelerometer answers", imu.init(hz = 104)
check "magnetometer answers", compass.init(hz = 80)

# A device that refuses more than its address must not spoil the transaction
# after. Nothing may have the address asked here.
block:
  var
    register: array[1, byte]
    kept = true
  for round in 0..<200:
    discard i2c0.writeRead(0x7F, [0x0F'u8], register)
    if not imu.init(hz = 104): kept = false
  check "after a refusal", kept

block:
  var
    acceleration, field: tuple[x, y, z: int32]
    (accelerations, fields) = (0, 0)
  let start = millis()
  while millis() - start < 3000:
    if imu.ready:
      acceleration = imu.acceleration()
      inc accelerations
    if compass.ready:
      field = compass.read()
      inc fields
  # Each within a tenth of what was asked for, over three seconds
  check "accelerometer's rate", accelerations in 280..344
  check "magnetometer's rate", fields in 216..264
  check "gravity", acceleration.squared in 810_000'i64..1_210_000'i64 # 0.9 to 1.1 g
  check "a magnetic field", field.squared in 10_000'i64..4_000_000'i64 # 0.1 to 2 gauss

print "END sensors\n"
while true: discard
