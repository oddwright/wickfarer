class_name HelpPages
extends RefCounted
## The Help page in the title and pause menus: how the game works, one topic a
## page, from data/tutorial.json "help". Normal play stays free of explanations;
## they live here and in the training flight. Like the other views it only reads.

static var page := 0  ## the topic on show; kept while the menu is closed, so Back and return


static func topics() -> Array:
	return ContentDB.tutorial.get("help", [])


static func items() -> Array[String]:
	var out: Array[String] = ["help_prev", "help_next", "back"]
	return out


static func tap(main: Node, id: String) -> bool:
	var n := maxi(topics().size(), 1)
	match id:
		"help_prev":
			page = posmod(page - 1, n)
		"help_next":
			page = posmod(page + 1, n)
		"back":
			main.open_menu(main.menu_base)
			return true
		_:
			return false
	main.open_menu("help")  # redraws the new topic
	return true


## The topic's heading, where it falls ("3 of 16"), then its paragraphs.
static func lines(at := page) -> Array[String]:
	var all := topics()
	var out: Array[String] = []
	if all.is_empty():
		out.append(TranslationServer.translate("UI_HELP_TITLE"))
		return out
	var i := posmod(at, all.size())
	var t: Dictionary = all[i]
	out.append(TranslationServer.translate(str(t.title)))
	out.append(TranslationServer.translate("UI_HELP_PAGE") % [i + 1, all.size()])
	for key: Variant in t.get("text", []):
		out.append(TranslationServer.translate(str(key)))
	return out
