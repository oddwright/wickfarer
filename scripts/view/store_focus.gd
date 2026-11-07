class_name StoreFocus
extends RefCounted
## Which store option the player is looking at. A phone has no hover, so the
## first tap on something that costs or moves (a ware, a refit, a piece of gear)
## opens its card, and a second tap on the same button does it. Options with no
## card (paging, Sell, Back, Leave) act on the first tap. This is view state,
## never saved; a new page, another store, a new run, or a different piece
## sliding under the button closes the card.

var _option := ""
var _state := ""
var _at := ""  ## the beacon, so the next store opens with no card
var _run_id := 0  ## so a new run opens with no card either
## What sat under the button when the card opened: after a buy, a sale or a move
## another piece slides into that slot, and it needs its own look.
var _item: Dictionary = {}


## True when the tap should act, false when it only opened the card.
func tap(run: Run, option: String) -> bool:
	if ItemCard.build(run, option).is_empty():
		clear()
		return true
	if current(run) == option:
		return true  # a refused tap keeps the card, which says why
	_option = option
	_state = run.state
	_at = run.at
	_run_id = run.get_instance_id()
	_item = Market.item_at(run, option)
	return false


## The option whose card is open, or "" if none is (or the page moved on).
func current(run: Run) -> String:
	if _option == "" or _state != run.state or _at != run.at:
		return ""
	if _run_id != run.get_instance_id() or Market.item_at(run, _option) != _item:
		return ""
	return _option if run.page_options().has(_option) else ""


func clear() -> void:
	_option = ""
	_item = {}
