# Lutra's `system/fatal`, put in place of Nim's by `lutra/project`. A failed
# check, such as an index out of range or an overflow, calls `sysFatal`, which
# in Nim's raises a Defect: that allocates the Defect and its message, and
# with no heap fails to link. These are templates, so the message, which the
# caller builds with `&` and `$`, is never made. What is said is Nim's own
# text when it is a literal, or the Defect's name. `lutraPanic` is the board's,
# from `reportPanics`.

{.push profiler: off.}

const
  gotoBasedExceptions = compileOption("exceptions", "goto")
  quirkyExceptions = compileOption("exceptions", "quirky")

proc lutraPanic(what: cstring, at: pointer) {.importc, cdecl, noreturn.}

template sysFatal(exceptn: typedesc[Defect], message: untyped) =
  # Called from a procedure of Nim's that the failed check called, so its
  # return address is just after the check's call. On ARM it says Thumb. An assertion's message already
  # says where it is.
  var at {.noinit.}: pointer
  {.emit: [at, " = (char *)((NU)__builtin_return_address(0) & ~1u) - 2;"].} # Inside the call
  when exceptn is AssertionDefect: lutraPanic(cstring(message), nil)
  elif compiles((const literal = message)): lutraPanic(cstring(message), at)
  elif exceptn is IndexDefect: lutraPanic(cstring("index out of bounds"), at)
  elif exceptn is RangeDefect: lutraPanic(cstring("value out of range"), at)
  elif exceptn is FieldDefect: lutraPanic(cstring("field not in the object's branch"), at)
  else: lutraPanic(cstring($exceptn), at)

template sysFatal(exceptn: typedesc[Defect], message, arg: untyped) =
  # `message` is a literal, as "value out of range: ", and `arg` is made
  const text = block:
    var s = message
    while s[s.len - 1] in {':', ' '}: s.setLen(s.len - 1)
    s
  var at {.noinit.}: pointer
  {.emit: [at, " = (char *)((NU)__builtin_return_address(0) & ~1u) - 2;"].} # Inside the call
  lutraPanic(cstring(text), at)

{.pop.}
