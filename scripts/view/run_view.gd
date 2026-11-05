class_name RunView
extends TextLayer
## Draws the run screens between fights: the star chart, events, the store
## and the endings. Like WorldView it only reads the sim; taps go back to
## Main, which calls the Run's action methods.


func _draw() -> void:
	if main == null or main.run_layout == null or main.run == null:
		return
	var run: Run = main.run
	var l: RunLayout = main.run_layout
	draw_rect(Rect2(Vector2.ZERO, l.native), Pixel.c("a"))
	for s in main.world.stars:
		draw_rect(Rect2(s[0], Vector2.ONE), Pixel.c(s[1]))
	match main.run_screen():
		"chart":
			_draw_chart(run, l)
		"event":
			_draw_event(run, l)
		"store":
			_draw_store(run, l)
		_:
			_draw_next(run, l)
	_draw_status(run, l)


func _draw_status(run: Run, l: RunLayout) -> void:
	draw_rect(Rect2(0, 0, l.native.x, RunLayout.TOP - 4), Pixel.c("b"))
	draw_rect(Rect2(0, RunLayout.TOP - 4, l.native.x, 1), Pixel.c("d"))
	var me := run.ship
	var hull_col := Pixel.c("U") if me.hull <= me.max_hull / 3 else Pixel.c("h")
	_text(Vector2(4, 11), "%s %d/%d" % [tr("UI_HULL"), me.hull, me.max_hull], 5.0, hull_col)
	_text(
		Vector2(70, 11),
		"%s %d    %s %d" % [tr("UI_SCRAP"), run.scrap, tr("UI_LIGHT"), run.light],
		5.0,
		Pixel.c("w")
	)
	_text(
		Vector2(l.native.x - 204, 11),
		tr(str(run.reach().name)),
		5.0,
		Pixel.c("g"),
		HORIZONTAL_ALIGNMENT_RIGHT,
		200
	)


# ------------------------------------------------------------------ chart


func _draw_chart(run: Run, l: RunLayout) -> void:
	_draw_hush(run, l)
	var targets := run.jump_targets()
	for n in run.chart.nodes:
		for id: String in n.links:
			var a := l.beacon_pos(n)
			var b := l.beacon_pos(run.chart.node(id))
			var hot: bool = n.id == run.at and targets.has(id)
			draw_line(a, b, Pixel.c("v") if hot else Pixel.c("d"), 1.0)
	var blink := int(main.world.anim_time * 3.0) % 2 == 0
	for n in run.chart.nodes:
		_draw_beacon(run, l, n, targets.has(n.id), blink)
	var msg := tr("UI_JUMP")
	if not run.messages.is_empty():
		msg = tr(run.messages[-1])
	_text(
		Vector2(l.message_rect.position.x, l.message_rect.position.y + 12),
		msg,
		5.0,
		Pixel.c("w"),
		HORIZONTAL_ALIGNMENT_CENTER,
		l.message_rect.size.x
	)


## The Hush swallows the chart from the left, a column at a time.
func _draw_hush(run: Run, l: RunLayout) -> void:
	if run.hush < 0.0:
		return
	var edge := float(run.hush + 0.3) / float(run.chart.columns - 1)
	var x := l.beacon_pos({"x": minf(edge, 1.0), "y": 0.0}).x
	var area := Rect2(0, RunLayout.TOP - 3, x, l.native.y - RunLayout.TOP + 3)
	draw_texture_rect(Pixel.dither("m", 2), area, true)
	draw_rect(Rect2(x, area.position.y, 1, area.size.y), Pixel.c("n"))


func _draw_beacon(run: Run, l: RunLayout, n: Dictionary, target: bool, blink: bool) -> void:
	var c := l.beacon_pos(n)
	var swallowed := run.is_swallowed(n.id)
	var col := Pixel.c("f")
	if run.visited.has(n.id):
		col = Pixel.c("g")
	if n.kind == "store":
		col = Pixel.c("y")
	if n.kind == "gate":
		col = Pixel.c("w")
	if swallowed:
		col = Pixel.c("n")
	var core := Rect2(c - Vector2i(2, 2), Vector2(5, 5))
	draw_rect(core, col, run.visited.has(n.id) or n.kind in ["store", "gate"])
	if n.kind == "gate":
		draw_rect(core.grow(2), col, false, 1.0)
	if n.id == run.at:
		draw_rect(core.grow(3), Pixel.c("w"), false, 1.0)
	elif target and blink:
		var box := Rect2i(c - Vector2i(5, 5), Vector2i(11, 11))
		Pixel.corners(self, box, Pixel.c("o") if swallowed else Pixel.c("v"), 2)


# ------------------------------------------------------------------ panels


func _story(l: RunLayout, s: String) -> void:
	var r := l.text_rect
	draw_rect(Rect2(r.grow(4)), Pixel.c("a", 0.85))
	_text_block(r, s, Pixel.c("h"))


## Wrapped text whose first line starts at the top of the rect.
func _text_block(r: Rect2i, s: String, col: Color) -> void:
	var lines := _wrap(s.to_upper(), r.size.x, 1)
	for i in lines.size():
		_text(Vector2(r.position.x, r.position.y + 6 + i * LINE), lines[i], 5.0, col)


## A red note means the player is short of it; a grey one is just the price.
func _button(r: Rect2i, label: String, enabled := true, note := "", short := false) -> void:
	Pixel.panel(self, r, enabled)
	var col := Pixel.c("w") if enabled else Pixel.c("f")
	var note_col := Pixel.c("U") if short else (Pixel.c("g") if enabled else Pixel.c("f"))
	var y := r.position.y + r.size.y / 2 + 3
	if note == "":
		_text(Vector2(r.position.x, y), label, 5.0, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var inner := r.size.x - 12
	if text_width(label.to_upper()) + text_width(note.to_upper()) + 8 <= inner:
		_text(Vector2(r.position.x + 6, y), label, 5.0, col)
		_text(
			Vector2(r.position.x, y), note, 5.0, note_col, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6
		)
		return
	# Too long for one line: the label on top, what it needs underneath.
	var lines := _wrap(label.to_upper(), inner, 1)
	_text(Vector2(r.position.x + 6, r.position.y + 10), lines[0], 5.0, col)
	var last := "" if lines.size() < 2 else lines[1]
	_text(Vector2(r.position.x + 6, r.end.y - 5), last, 5.0, col)
	_text(
		Vector2(r.position.x, r.end.y - 5),
		note,
		5.0,
		note_col,
		HORIZONTAL_ALIGNMENT_RIGHT,
		r.size.x - 6
	)


func _draw_event(run: Run, l: RunLayout) -> void:
	var ev := run.event()
	_story(l, tr(str(ev.get("text", ""))))
	var choices: Array = ev.get("choices", [])
	for b in l.buttons:
		var i := int(b.id)
		if i >= choices.size():
			continue
		var ok := run.can_choose(i)
		var needs := _needs(choices[i].get("requires", {}))
		_button(b.rect, tr(str(choices[i].text)), ok, needs, not ok)


## A short note of what a choice needs, so locked choices explain themselves.
func _needs(req: Dictionary) -> String:
	var parts: Array[String] = []
	if req.has("scrap"):
		parts.append("%d %s" % [int(req.scrap), tr("UI_SCRAP")])
	if req.has("light"):
		parts.append("%d %s" % [int(req.light), tr("UI_LIGHT")])
	if req.has("species"):
		parts.append(tr(str(ContentDB.species[str(req.species)].name)))
	return ", ".join(parts)


func _draw_store(run: Run, l: RunLayout) -> void:
	_story(l, tr("UI_STORE_TEXT"))
	var items := run.store_items()
	for b in l.buttons:
		var i := int(b.id)
		if i >= items.size():
			_button(b.rect, tr("UI_LEAVE"))
			continue
		var item := items[i]
		var note := "%d %s" % [run.price(item), tr("UI_SCRAP")]
		var short := run.scrap < run.price(item)
		_button(b.rect, tr("UI_STORE_" + item.to_upper()), run.can_buy(item), note, short)


func _draw_next(run: Run, l: RunLayout) -> void:
	var title := ""
	var body := ""
	var label := "UI_CONTINUE"
	match main.run_screen():
		"outcome":
			body = tr(run.outcome)
		"reach_done":
			title = tr("UI_REACH_DONE_TITLE")
			body = tr("UI_REACH_DONE")
			label = "UI_NEW_RUN"
		"lost":
			title = tr("UI_RUN_LOST_TITLE")
			body = tr("UI_RUN_LOST")
			label = "UI_NEW_RUN"
	var r := l.text_rect
	if title != "":
		_text(Vector2(r.position.x, r.position.y + 10), title, 10.0, Pixel.c("w"))
		r = Rect2i(r.position.x, r.position.y + 20, r.size.x, r.size.y - 20)
	draw_rect(Rect2(r.grow(4)), Pixel.c("a", 0.85))
	_text_block(r, body, Pixel.c("h"))
	if run.state in ["lost", "reach_done"]:
		_text_block(
			Rect2i(r.position.x, r.end.y - 10, r.size.x, 10),
			"%s %d   %s %d" % [tr("UI_JUMPS"), run.jumps, tr("UI_SEED"), run.rng.run_seed],
			Pixel.c("g")
		)
	_button(l.buttons[0].rect, tr(label))
