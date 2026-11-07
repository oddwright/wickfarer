class_name FloaterWords
extends RefCounted
## The words that float up over a room when something happens there: what a
## sim event says, and in what colour. Empty for events that say nothing.


static func for_event(e: Dictionary) -> Dictionary:
	if not e.has("room") or not e.has("side") or str(e.room) == "":
		return {}
	match str(e.type):
		"hit":
			return _say("-%d" % int(e.damage), "U")
		"miss":
			return _say(_tr("UI_MISS"), "h")
		"ward_hit", "ward_block":
			return _say(_tr("UI_WARDED"), "j")
		"wave_gather":
			# The threat, named on the knot it gathers in.
			return _say(_tr("UI_WAVE_" + str(e.kind).to_upper()), "o")
		"wave_broken":
			return _say(_tr("UI_WAVE_BROKEN"), "w")
		"wave_landed":
			if int(e.left) <= 0:
				return _say(_tr("UI_WAVE_SOAKED"), "j")
	return {}


static func _say(text: String, colour: String) -> Dictionary:
	return {"text": text, "color": Pixel.c(colour)}


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
