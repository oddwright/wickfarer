class_name StoreFocus
extends RefCounted
## Which store option the player is looking at. A phone has no hover, so the
## first tap on something that costs or moves (a ware, a refit, a piece of gear)
## opens its card, and a second tap on the same button does it. Paging and
## leaving act on the first tap. This is view state, never saved; changing page
## or docking at another store closes the card.

## Options that change page or mode: nothing to explain, nothing to lose.
const AT_ONCE: Array[String] = ["back", "leave", "refit", "wares", "modules", "guns", "sell"]

var _state := ""
var _option := ""
var _at := ""  ## the beacon, so the next store opens with no card


## True when the tap should act, false when it only opened the card.
func tap(run: Run, option: String) -> bool:
	if option in AT_ONCE or ItemCard.build(run, option).is_empty():
		clear()
		return true
	if _state == run.state and _at == run.at and _option == option:
		# Gear moves or sells, so the same button shows another piece next:
		# that one needs its own look. Repairs, Light and refits repeat.
		if ":" in option:
			clear()
		return true
	_state = run.state
	_at = run.at
	_option = option
	return false


## The option whose card is open, or "" if none is (or the page moved on).
func current(run: Run) -> String:
	if _option == "" or _state != run.state or _at != run.at:
		return ""
	if not run.page_options().has(_option):
		return ""
	return _option


func clear() -> void:
	_state = ""
	_option = ""
