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
		"refit":
			_draw_refit(run, l)
		"wares":
			_draw_wares(run, l)
		"modules", "guns":
			_draw_gear(run, l)
		_:
			_draw_next(run, l)
	_draw_status(run, l)
	Pixel.menu_icon(self, l.menu_rect)


func _draw_status(run: Run, l: RunLayout) -> void:
	draw_rect(Rect2(0, 0, l.native.x, l.top - 4), Pixel.c("b"))
	draw_rect(Rect2(0, l.top - 4, l.native.x, 1), Pixel.c("d"))
	var me := run.ship
	var hull_col := Pixel.c("U") if me.hull <= me.max_hull / 3 else Pixel.c("h")
	_text(Vector2(4, 11), "%s %d/%d" % [tr("UI_HULL"), me.hull, me.max_hull], 5.0, hull_col)
	_text(
		Vector2(70, 11),
		"%s %d    %s %d" % [tr("UI_SCRAP"), run.scrap, tr("UI_LIGHT"), run.light],
		5.0,
		Pixel.c("w")
	)
	var reach := tr(str(run.reach().name))
	if l.kind == "tall":  # too narrow for one line: the Reach's name goes under
		_text(Vector2(4, 20), reach, 5.0, Pixel.c("g"))
		return
	_text(Vector2(l.native.x - 238, 11), reach, 5.0, Pixel.c("g"), HORIZONTAL_ALIGNMENT_RIGHT, 200)


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
	if main.coach_speaking():
		return  # the coach writes in the message line
	var msg := tr("UI_JUMP")
	if not run.messages.is_empty():
		msg = GearText.message(run.messages[-1])
	_text(
		Vector2(l.message_rect.position.x, l.message_rect.position.y + 12),
		msg,
		5.0,
		Pixel.c("w"),
		HORIZONTAL_ALIGNMENT_CENTER,
		l.message_rect.size.x
	)


## The Hush swallows the chart from the start, a column at a time.
func _draw_hush(run: Run, l: RunLayout) -> void:
	if run.hush < 0.0:
		return
	var edge := float(run.hush + 0.3) / float(run.chart.columns - 1)
	var area := Rect2(l.hush_rect(edge))
	draw_texture_rect(Pixel.dither("m", 2), area, true)
	if l.kind == "tall":
		draw_rect(Rect2(0, area.position.y, area.size.x, 1), Pixel.c("n"))
	else:
		draw_rect(Rect2(area.end.x, area.position.y, 1, area.size.y), Pixel.c("n"))


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
	var inner := r.size.x - 12
	if note == "":
		if text_width(label.to_upper()) <= r.size.x - 4 or r.size.y < 30:
			_text(Vector2(r.position.x, y), label, 5.0, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			return
		# A narrow page (a larger UI size): two centred lines in the tall button.
		var two := _wrap(label.to_upper(), inner, 1)
		for i in mini(two.size(), 2):
			var ly := r.position.y + 10 if i == 0 else r.end.y - 5
			_text(
				Vector2(r.position.x, ly), two[i], 5.0, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x
			)
		return
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
	var story := tr(str(ev.get("text", "")))
	var faction := str(ev.get("faction", ""))
	if faction != "":
		story = _standing_line(run, faction) + " " + story
	_story(l, story)
	var choices: Array = ev.get("choices", [])
	for b in l.buttons:
		var i := int(b.id)
		if i >= choices.size():
			continue
		var ok := run.can_choose(i)
		var note := _needs(choices[i].get("requires", {}))
		var pct := run.check_chance(i)
		if pct >= 0:  # the odds are shown, never hidden
			var skill := tr(str(Skills.spec(str(choices[i].check.skill)).name))
			note = _join(note, tr("UI_CHECK") % [skill, pct])
		_button(b.rect, tr(str(choices[i].text)), ok, note, not ok)


## "Ashmarket: Wary." for the faction an event or store belongs to.
func _standing_line(run: Run, faction: String) -> String:
	var fac := tr(str(Standing.spec(faction).name))
	return tr("UI_REP_LINE") % [fac, tr(str(run.standing.tier(faction).get("name", "")))]


static func _join(a: String, b: String) -> String:
	return b if a == "" else a + ", " + b


## A short note of what a choice needs, so locked choices explain themselves.
func _needs(req: Dictionary) -> String:
	var parts: Array[String] = []
	if req.has("scrap"):
		parts.append("%d %s" % [int(req.scrap), tr("UI_SCRAP")])
	if req.has("light"):
		parts.append("%d %s" % [int(req.light), tr("UI_LIGHT")])
	if req.has("species"):
		parts.append(tr(str(ContentDB.species[str(req.species)].name)))
	if req.has("skill"):
		var rank := tr(Skills.rank_name(int(req.get("rank", 1))))
		parts.append(tr("UI_NEED_SKILL") % [rank, tr(str(Skills.spec(str(req.skill)).name))])
	var rep: Dictionary = req.get("rep", {})
	for f: String in rep:
		var tier := tr(str(Standing.tier_for(int(rep[f])).get("name", "")))
		parts.append(tr("UI_NEED_REP") % [tier, tr(str(Standing.spec(f).name))])
	return ", ".join(parts)


func _draw_store(run: Run, l: RunLayout) -> void:
	_story(l, _store_text(run))
	var opts := run.store_options()
	for b in l.buttons:
		var option := opts[int(b.id)]
		match option:
			"refit":
				_button(b.rect, tr("UI_STORE_REFIT"))
			"leave":
				_button(b.rect, tr("UI_LEAVE"))
			"wares", "modules", "guns":
				_button(b.rect, tr("UI_STORE_" + option.to_upper()), Market.can(run, option))
			_:
				var note := "%d %s" % [run.price(option), tr("UI_SCRAP")]
				var short := run.scrap < run.price(option)
				_button(
					b.rect, tr("UI_STORE_" + option.to_upper()), run.can_buy(option), note, short
				)


## The price board, and if the store is a faction's, how that faction's view
## of the ship moves its prices.
func _store_text(run: Run) -> String:
	var text := tr("UI_STORE_TEXT")
	var f := run.store_faction
	if f == "":
		return text
	text = _standing_line(run, f) + " " + text
	var delta := run.standing.price_delta(f)
	if delta > 0:
		text += " " + tr("UI_REP_PRICE_UP") % delta
	elif delta < 0:
		text += " " + tr("UI_REP_PRICE_DOWN") % -delta
	return text


## One button per system the dock can raise, then Stoke the Ember, then Back.
## Each shows the level it buys and its price; a capped one says so.
func _draw_refit(run: Run, l: RunLayout) -> void:
	_story(l, tr("UI_REFIT_TEXT") + " " + tr("UI_REFIT_REACTOR") % run.ship.reactor)
	var opts := run.refit_options()
	for b in l.buttons:
		var option := opts[int(b.id)]
		match option:
			"stoke":
				_draw_stoke(run, b.rect)
			"back":
				_button(b.rect, tr("UI_MENU_BACK"))
			_:
				_draw_refit_system(run, option, b.rect)


func _draw_refit_system(run: Run, sys: String, r: Rect2i) -> void:
	var sys_name := tr(str(ContentDB.systems[sys].name))
	var room := run.ship.system_room(sys)
	if room == null:
		_button(r, tr("UI_REFIT_NONE") % sys_name, false)
		return
	var p := run.refit_price(sys)
	if p < 0:
		_button(r, tr("UI_REFIT_MAXED") % sys_name, false)
		return
	var label := tr("UI_REFIT_LEVEL") % [sys_name, room.level + 1]
	_button(r, label, run.can_refit(sys), "%d %s" % [p, tr("UI_SCRAP")], run.scrap < p)


func _draw_stoke(run: Run, r: Rect2i) -> void:
	var p := run.stoke_price()
	if p < 0:
		_button(r, tr("UI_STOKE_MAXED"), false)
		return
	_button(r, tr("UI_STOKE"), run.can_stoke(), "%d %s" % [p, tr("UI_LIGHT")], run.light < p)


func _draw_next(run: Run, l: RunLayout) -> void:
	var title := ""
	var body := ""
	var label := "UI_CONTINUE"
	match main.run_screen():
		"outcome":
			body = tr(run.outcome)
			for m in run.messages:  # how the factions took it
				body += " " + tr(m)
		"reach_done":
			title = tr("UI_REACH_DONE_TITLE")
			var ahead := tr(str(ContentDB.reaches[str(run.reach().next)].name))
			body = tr("UI_REACH_DONE") + " " + tr("UI_REACH_NEXT") % ahead
			if not run.messages.is_empty():  # what the Warden fight cost, e.g. sung-away Light
				body = tr(run.messages[-1]) + ". " + body
			label = "UI_JUMP_THROUGH"
		"won":
			title = tr("UI_RUN_WON_TITLE")
			body = tr("UI_RUN_WON")
			label = "UI_NEW_RUN"
		"lost":
			title = tr("UI_RUN_LOST_TITLE")
			body = tr("UI_RUN_LOST")
			label = "UI_NEW_RUN"
	if title != "" and main.profile and not main.fresh_unlocks.is_empty():
		var fresh := ProfilePages.fresh_lines(main.fresh_unlocks, main.profile)
		body += " " + " ".join(fresh)
	var r := l.text_rect
	if title != "":
		_text(Vector2(r.position.x, r.position.y + 10), title, 10.0, Pixel.c("w"))
		r = Rect2i(r.position.x, r.position.y + 20, r.size.x, r.size.y - 20)
	draw_rect(Rect2(r.grow(4)), Pixel.c("a", 0.85))
	_text_block(r, body, Pixel.c("h"))
	if run.is_over() or run.state == "reach_done":
		var stats := (
			"%s %d   %s %d   %s %d"
			% [
				tr("UI_GATES"),
				run.reaches_crossed,
				tr("UI_FIGHTS_WON"),
				run.fights_won,
				tr("UI_JUMPS"),
				run.jumps
			]
		)
		# Two short lines rather than one long one, so a narrow page doesn't wrap them.
		var seed_line := "%s %d" % [tr("UI_SEED"), run.rng.run_seed]
		_text_block(Rect2i(r.position.x, r.end.y - 20, r.size.x, 10), stats, Pixel.c("g"))
		_text_block(Rect2i(r.position.x, r.end.y - 10, r.size.x, 10), seed_line, Pixel.c("g"))
	_button(l.buttons[0].rect, tr(label))


# ------------------------------------------------------------------ gear pages


## The trader's wares: each one's numbers in the text, its price on its button.
func _draw_wares(run: Run, l: RunLayout) -> void:
	var lines: Array[String] = [tr("UI_WARES_TEXT"), _hold_count(run)]
	if run.stock.is_empty():
		lines.append(tr("UI_WARES_EMPTY"))
	for item in run.stock:
		lines.append(GearText.line(item) + ".")
	_story(l, " ".join(lines))
	var opts := run.page_options()
	for b in l.buttons:
		var option := opts[int(b.id)]
		if option == "back":
			_button(b.rect, tr("UI_MENU_BACK"))
			continue
		var item := Market.item_at(run, option)
		var p := Market.price(run, item)
		var note := "%d %s" % [p, tr("UI_SCRAP")]
		_button(b.rect, _name(item), Market.can(run, option), note, run.scrap < p)


## Modules or Guns: the ship's slots, then the hold, then Sell and Back. What
## each piece does is written out above, so nothing hides behind a long press.
func _draw_gear(run: Run, l: RunLayout) -> void:
	var guns := run.state == "guns"
	var head := "UI_SELL_TEXT" if run.selling else ("UI_GUNS_TEXT" if guns else "UI_MODULES_TEXT")
	var lines: Array[String] = [tr(head), _hold_count(run)]
	var opts := run.page_options()
	for option in opts:
		var item := Market.item_at(run, option)
		if not item.is_empty():
			var where := tr("UI_IN_HOLD") if option.begins_with("hold") else tr("UI_FITTED")
			lines.append("%s (%s)." % [GearText.line(item), where])
	_story(l, " ".join(lines))
	for b in l.buttons:
		_draw_gear_button(run, opts[int(b.id)], b.rect, guns)


func _draw_gear_button(run: Run, option: String, r: Rect2i, guns: bool) -> void:
	match option:
		"back":
			_button(r, tr("UI_MENU_BACK"))
			return
		"sell":
			_button(r, tr("UI_SELL_DONE" if run.selling else "UI_SELL"))
			return
	var item := Market.item_at(run, option)
	var in_hold := option.begins_with("hold")
	if item.is_empty():
		var free := "UI_HOLD_EMPTY" if in_hold else ("UI_MOUNT_FREE" if guns else "UI_SLOT_FREE")
		_button(r, tr(free), false)
		return
	var note := tr("UI_IN_HOLD") if in_hold else tr("UI_FITTED")
	if run.selling:
		note = tr("UI_SOLD_FOR") % Market.sell_price(item)
	_button(r, _name(item), Market.can(run, option), note)


func _hold_count(run: Run) -> String:
	return tr("UI_HOLD_COUNT") % [run.hold.size(), Run.HOLD_SIZE]


func _name(item: Dictionary) -> String:
	return tr(str(Gear.entry(item).get("name", "")))
