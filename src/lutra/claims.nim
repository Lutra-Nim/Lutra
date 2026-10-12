## Ownership of pins and peripherals, settled at compile time. Whatever
## configures one claims it for a role, and claiming it again for a different
## role stops the build:
##
##   IO21 is claimed as UART0 TX and as a GPIO at blink.nim(8)

import std/[macros, macrocache]

const claims = CacheTable"lutra.claims"

func at*(site: tuple[filename: string, line: int, column: int]): string =
  ## Where a claim was made, from a template's `instantiationInfo`
  " at " & site.filename & "(" & $site.line & ")"

macro once*(what: static string, where: static string) =
  ## For what a program may only do once
  if what in claims:
    error what & " twice," & claims[what].strVal & " and" & where
  claims[what] = newLit(where)

macro claim*(resource, role: static string, where: static string = "") =
  ## `where` is the line of the user's code that made the claim, when known
  if resource notin claims:
    claims[resource] = newTree(nnkPar, newLit(role), newLit(where))
  elif claims[resource][0].strVal != role:
    error resource & " is claimed as " & claims[resource][0].strVal &
      claims[resource][1].strVal & " and as " & role & where
