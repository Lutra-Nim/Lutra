## What the host side shares between `lutra/project` and each chip's
## `host.nim`: how a task ends, the tools it needs, and building the programs
## for the host that do what NimScript can't.

import std/os
when defined(nimscript): import std/[strutils, hashes]

type
  Exit* = enum
    ## A task's exit code. The codes stay the same from release to release,
    ## so that a script or an agent can tell what went wrong without reading
    ## what was printed.
    passed      ## 0
    buildFailed ## 1: compiling, linking, or the checks on the image
    checkFailed ## 2: the board ran, and did not print what was expected
    noBoard     ## 3: no board found, more than one, or one that could not be reached
    notSetUp    ## 4: a tool or a setting is missing. `nim doctor` says which

  Tool* = object
    name*, path*: string ## `path` is empty when the tool is not found
    install*: string     ## How to get it

proc fail*(why: Exit, message: string) {.noreturn.} =
  echo message
  quit ord(why)

proc found*(name: string, install: string, env = ""): Tool =
  ## A tool on the PATH, or named in the environment variable `env`
  result = Tool(name: name, install: install)
  let exe = if env != "": getEnv(env, name) else: name
  result.path = findExe(exe)

proc need*(tool: Tool) =
  if tool.path == "":
    fail(notSetUp, "Error: " & tool.name & " not found. " & tool.install)

when defined(nimscript):
  const source = currentSourcePath().parentDir.parentDir ## Holds lutra.nim

  proc buildDir*(): string = thisDir() / "build"
    ## Next to the project's config.nims

  proc hostProgram*(program: string, sources: openArray[string]): string =
    ## A program for the host, built the first time it is needed. It is named
    ## after its sources, so that a changed one is built again.
    var text = ""
    for file in sources: text.add readFile(file)
    result = buildDir() / program.splitFile.name & "-" & toHex(hash(text).uint32) & ExeExt
    if not fileExists(result):
      mkDir buildDir()
      try:
        exec quoteShell(getCurrentCompilerExe()) & " c --skipProjCfg --hints:off -d:release --path:" &
          quoteShell(source) & " --nimcache:" & quoteShell(buildDir() / "nimcache" / program.splitFile.name) &
          " --out:" & quoteShell(result) & " " & quoteShell(program)
      except OSError: fail buildFailed, "Error: " & program.lastPathPart & " did not build for the host."
