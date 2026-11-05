class_name ProfilePages
extends RefCounted
## The menu pages that read the Profile: the Hush Depth picker shown before a
## run once a depth is open, and the Wake Log of records and recent runs.
## Kept out of main.gd, which is at the lint line limit. Like the other views
## it only reads state; it changes the profile only through Profile's methods.

const PAGES: Array[String] = ["depth", "log"]


static func items(page: String) -> Array[String]:
	var out: Array[String] = []
	match page:
		"depth":
			out.assign(["depth_less", "depth_more", "set_out", "back"])
		"log":
			out.assign(["back"])
	return out


## Handles a tap on one of these pages' buttons. Returns false if the id isn't theirs.
static func tap(main: Node, id: String) -> bool:
	var profile: Profile = main.profile
	match id:
		"depth_less", "depth_more":
			if profile.step_depth(-1 if id == "depth_less" else 1):
				profile.save(main.save_dir)
			main.open_menu("depth")  # redraws the depth's rule
		"set_out":
			main.start_run()
		"back":
			main.open_menu(main.menu_base)
		_:
			return false
	return true


## The title and rule text of the depth page: what the chosen depth adds.
static func depth_text(profile: Profile) -> Array[String]:
	var title := TranslationServer.translate("UI_DEPTH") % profile.depth
	if profile.depth == 0:
		return [title, TranslationServer.translate("UI_DEPTH_NONE")]
	var d: Dictionary = ContentDB.depths.depths[profile.depth - 1]
	var rule := (
		"%s. %s"
		% [TranslationServer.translate(str(d.name)), TranslationServer.translate(str(d.text))]
	)
	if profile.depth > 1:
		rule += " " + TranslationServer.translate("UI_DEPTH_STACKS")
	return [title, rule]


## The Wake Log's lines: lifetime records, then the latest runs, newest first.
static func log_lines(profile: Profile) -> Array[String]:
	var s := profile.stats
	var deepest: String = str(int(s.deepest_win))
	if int(s.deepest_win) < 0:
		deepest = TranslationServer.translate("UI_LOG_NONE")
	var out: Array[String] = [
		TranslationServer.translate("UI_LOG_STATS") % [s.runs, s.wins, s.best_gates, deepest],
		TranslationServer.translate("UI_LOG_FIGHTS") % [s.fights_won, s.scrap_earned, s.jumps],
		"",
	]
	if profile.history.is_empty():
		out.append(TranslationServer.translate("UI_LOG_EMPTY"))
	for h in profile.history:
		var ship_name := str(h.ship)
		if ContentDB.ships.has(ship_name):
			ship_name = TranslationServer.translate(str(ContentDB.ships[ship_name].name))
		var end := TranslationServer.translate("UI_LOG_WON" if h.end == "won" else "UI_LOG_LOST")
		out.append(
			TranslationServer.translate("UI_LOG_RUN") % [end, ship_name, h.depth, h.gates, h.seed]
		)
	return out


## Lines for an end screen: what this run just opened.
static func fresh_lines(ids: Array[String], profile: Profile) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		if id == "depth":
			out.append(TranslationServer.translate("UI_DEPTH_UNLOCKED") % profile.depth_open)
			continue
		out.append(
			(
				TranslationServer.translate("UI_UNLOCKED")
				% TranslationServer.translate(str(ContentDB.unlocks[id].name))
			)
		)
	return out
