## Says when the board's button is pressed, held for a second, and released,
## with its contacts' bounce taken out.

import lutra, lutra/button

const key = bootButton.debounced(held = 1.sec)

for change in key.changes:
  case change
  of pressed: log.info "pressed"
  of held: log.info "held"
  of released: log.info "released"
