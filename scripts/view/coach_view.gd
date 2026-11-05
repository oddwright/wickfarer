class_name CoachView
extends TextLayer
## Draws the coach over the fight and run screens: a blinking frame on what to tap,
## and the step's words in the screen's message line. It only reads Main and the
## Tutorial; taps go through Main as usual.

const BLINK := 3.0  ## frame blinks a second


func _draw() -> void:
	if main == null or main.menu != "" or main.tutorial == null or main.roster.open:
		return
	var d: Dictionary = main.tutorial.display
	if d.is_empty():
		return
	var fighting: bool = main.combat != null and main.layout != null
	var hud: HudLayout = main.layout if fighting else null
	var run_l: RunLayout = null if fighting else main.run_layout
	if hud == null and run_l == null:
		return
	var feet: Array[Vector2i] = []
	if fighting:
		for c in main.combat.player().alive_crew():
			feet.append(Vector2i(main.world.crew_pos(0, c)))
	# a steady outline so a glance finds it, and corners that blink so it reads as "tap"
	var lit := int(main.world.anim_time * BLINK) % 2 == 0
	for r in CoachLayout.targets(str(d.target), hud, run_l, main.run, main.combat, feet):
		draw_rect(Rect2(r.grow(1)), Pixel.c("v"), false, 1.0)
		if lit:
			Pixel.corners(self, r.grow(3), Pixel.c("w"), 3)
	_words(CoachLayout.text_rect(hud, run_l), d)


func _words(r: Rect2i, d: Dictionary) -> void:
	var s := tr(str(d.text))
	if main.combat == null and not main.run.messages.is_empty():
		# The coach has the message line, so it carries the last jump's news first,
		# or only the news where both don't fit (a short chart): the news is what hurt.
		var news := tr(main.run.messages[-1])
		s = news + " " + s
		if not fits(s, r):
			s = news
	if d.get("tip", false) and str(d.target) == "pause":
		s += " " + tr("TIP_GO_ON")
	var lines := _wrap(s.to_upper(), r.size.x - 4, 1)
	var h := lines.size() * LINE + 3
	var top := r.position.y + maxi(0, (r.size.y - h) / 2)
	var w := 0
	for line in lines:
		w = maxi(w, text_width(line))
	var box := Rect2i(r.position.x + (r.size.x - w) / 2 - 3, top - 1, w + 6, h + 1)
	draw_rect(Rect2(box), Pixel.c("a", 0.9))
	draw_rect(Rect2(box), Pixel.c("v"), false, 1.0)
	for i in lines.size():
		_text(
			Vector2(r.position.x, top + 7 + i * LINE),
			lines[i],
			5.0,
			Pixel.c("w"),
			HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x
		)


## Whether s, in 3x5 text, fits the coach's line r (tests check every step does).
func fits(s: String, r: Rect2i) -> bool:
	return _wrap(s.to_upper(), r.size.x - 4, 1).size() * LINE + 3 <= r.size.y + 2
