extends RefCounted
## Beacon opener checks for tests/run_tests.gd, kept here so that file stays
## under the lint limit. Each takes the runner, whose check() records the result.

const J = preload("res://scripts/core/json_util.gd")


static func _check(t: SceneTree, cond: bool, what: String) -> void:
	t.call("check", cond, what)


static func every_beacon(t: SceneTree) -> void:
	var per_kind := {}  ## stories a new run can be told; others wait on flags or standing
	var fresh := Run.create(0)
	for eid: String in ContentDB.events:
		if not EventRules.is_open(fresh, ContentDB.events[eid]):
			continue
		var k := str(ContentDB.events[eid].get("beacon", "event"))
		per_kind[k] = int(per_kind.get(k, 0)) + 1
	# Enough openers that a run of five or six jumps rarely sees one twice.
	_check(t, int(per_kind.get("fight", 0)) >= 10, "at least 10 fight openers")
	_check(t, int(per_kind.get("store", 0)) >= 5, "at least 5 store openers")
	_check(t, int(per_kind.get("empty", 0)) >= 5, "at least 5 openers for empty beacons")
	for seed_value in 20:
		var r := Run.create(seed_value)
		for n in r.chart.nodes:
			if n.kind == "gate" or n.id == r.at:
				continue
			r.state = "chart"
			r.at = n.id
			r._arrive()
			var kind := str(r.event().get("beacon", "event"))
			_check(
				t,
				r.state == "event" and kind == n.kind,
				"seed %d: a %s beacon opens with a %s story" % [seed_value, n.kind, kind]
			)
	# Openers run out in a long run; then they repeat instead of skipping the story.
	var long := Run.create(3)
	long.chart.node(long.at).kind = "store"
	var seen := {}
	var last := ""
	for i in int(per_kind.store) * 3:
		long.state = "chart"
		long._arrive()
		_check(t, long.state == "event", "store opener %d still shows" % i)
		_check(t, long.event_id != last, "store opener %d isn't the one just shown" % i)
		last = long.event_id
		seen[long.event_id] = true
		if i == int(per_kind.store) - 1:
			_check(t, seen.size() == i + 1, "every store opener shows before one repeats")
	# A save on an opener that an update removed still gets its beacon's fight.
	var gone := Run.create(5)
	gone.chart.node(gone.at).kind = "fight"
	gone.state = "event"
	gone.event_id = "an_opener_removed_in_an_update"
	var loaded := Run.from_dict(JSON.parse_string(J.s(gone.to_dict())))
	_check(t, loaded.state == "fight" and loaded.combat != null, "a removed opener keeps its fight")


static func lead_in(t: SceneTree) -> void:
	var r := Run.create(40)
	r.state = "event"
	r.event_id = "false_distress"
	_check(t, r.choose(0) and r.state == "fight", "firing first starts the fight")
	var foe := r.combat.enemy()
	_check(t, foe.hull == foe.max_hull - 2, "striking first starts the enemy damaged")
	_check(t, r.reach().enemies.has(foe.content_id), "the enemy comes from the Reach's pool")
	_check(t, r.outcome != "", "the opener's result is read before the fight")
	var s := Run.create(41)
	s.state = "event"
	s.event_id = "lit_post"
	_check(t, s.choose(0) and s.state == "store", "docking opens the store")
	s.read_outcome()
	_check(t, s.leave_store() and s.state == "chart", "and leaving it goes back to the chart")
	var p := Run.create(42)
	p.state = "event"
	p.event_id = "lit_post"
	_check(t, p.choose(1) and p.state == "chart", "passing a store by skips it")
	var h := Run.create(43)
	h.state = "event"
	h.event_id = "heat_hunters"
	h.scrap = 12
	_check(
		t,
		h.choose(1) and h.state == "chart" and h.scrap == 0,
		"paying off hunters avoids the fight"
	)
	var back := Run.from_dict(JSON.parse_string(J.s(r.to_dict())))
	_check(t, back.combat.enemy().hull == foe.hull, "a damaged enemy stays damaged through a save")


static func effects_checked(t: SceneTree) -> void:
	var bad: Array[String] = []
	var ev: Dictionary = ContentDB.events.lit_post.duplicate(true)
	ev.beacon = "moon"
	ev.choices[0].outcomes[0].effects = {"store": true, "fight": "reach"}
	ev.choices[1].outcomes[0].effects = {"enemy_hull": -2}
	ContentDB._validate_event("bad", ev, bad)
	var all := " | ".join(bad)
	_check(t, all.contains("unknown beacon kind moon"), "an unknown beacon kind is caught")
	_check(t, all.contains("store is true"), "a store and a fight at once is caught")
	_check(t, all.contains("enemy_hull"), "enemy_hull without a fight is caught")
	ev.choices.append_array([ev.choices[0], ev.choices[1]])
	bad.clear()
	ContentDB._validate_event("bad", ev, bad)
	_check(t, " ".join(bad).contains("more than"), "too many choices for the screen is caught")


## Every story and choice label fits its panel and buttons on every screen,
## so new content can't run off the bottom of a phone.
static func text_fits(t: SceneTree, screens: Dictionary) -> void:
	var tl := RunView.new()
	TextLayer.glyph_index = JSON.parse_string(
		FileAccess.get_file_as_string("res://art/font_3x5.json")
	)
	var probs: Array[String] = []
	var chart := Run.create(1).chart
	for name: String in screens:
		var scr: Dictionary = screens[name]
		var out := RunLayout.build(scr, chart, "next")
		for eid: String in ContentDB.events:
			var ev: Dictionary = ContentDB.events[eid]
			var l := RunLayout.build(scr, chart, "event", (ev.choices as Array).size())
			var story := t.tr(str(ev.text))
			if ev.has("faction"):  # the standing line goes first, at its longest
				story = _longest_standing(t, str(ev.faction)) + " " + story
			var lines := tl._wrap(story.to_upper(), l.text_rect.size.x, 1)
			if 6 + lines.size() * TextLayer.LINE > l.text_rect.size.y + 4:
				probs.append("%s: %s story is too long" % [name, eid])
			for i in (ev.choices as Array).size():
				var r: Rect2i = l.button("choice", i).rect
				var label := t.tr(str(ev.choices[i].text)).to_upper()
				var note := tl._needs(ev.choices[i].get("requires", {}))
				if ev.choices[i].has("check"):  # the widest odds a check can show
					var skill := t.tr(str(Skills.spec(str(ev.choices[i].check.skill)).name))
					note = RunView._join(note, t.tr("UI_CHECK") % [skill, 95])
				note = note.to_upper()
				if not _label_fits(tl, r, label, note):
					probs.append("%s: %s choice %d is too long" % [name, eid, i])
			for c: Dictionary in ev.choices:
				for o: Dictionary in c.outcomes:
					var result := t.tr(str(o.text))
					var rep: Dictionary = o.get("effects", {}).get("rep", {})
					for f: String in rep:  # each faction that moves says so after it
						var spec := Standing.spec(f)
						var up := t.tr(str(spec.up))
						var down := t.tr(str(spec.down))
						result += " " + (up if up.length() > down.length() else down)
					var ol := tl._wrap(result.to_upper(), out.text_rect.size.x, 1)
					if 6 + ol.size() * TextLayer.LINE > out.text_rect.size.y + 4:
						probs.append("%s: %s result is too long" % [name, o.text])
		var store := RunLayout.build(scr, chart, "store", 4)
		for f in Standing.ids():
			var text := _longest_standing(t, f) + " " + t.tr("UI_STORE_TEXT")
			var sl := tl._wrap(text.to_upper(), store.text_rect.size.x, 1)
			if 6 + sl.size() * TextLayer.LINE > store.text_rect.size.y + 4:
				probs.append("%s: the %s store's text is too long" % [name, f])
	tl.free()
	_check(t, probs.is_empty(), "story text fits: %s" % [probs.slice(0, 4)])


## "Faction: Tier." with the faction's name and the longest tier name.
static func _longest_standing(t: SceneTree, f: String) -> String:
	var tier := ""
	for tier_spec: Dictionary in Standing.data().tiers:
		var n := t.tr(str(tier_spec.name))
		tier = n if n.length() > tier.length() else tier
	return t.tr("UI_REP_LINE") % [t.tr(str(Standing.spec(f).name)), tier]


## Mirrors RunView._button: one centred line with no note, or two in a tall
## button; label and note on one line if they fit; else two label lines with
## the note on the second, which only a tall (Square) button has room for.
static func _label_fits(tl: RunView, r: Rect2i, label: String, note: String) -> bool:
	var inner := r.size.x - 12
	if note == "":
		if TextLayer.text_width(label) <= r.size.x - 4:
			return true
		return r.size.y >= 30 and tl._wrap(label, inner, 1).size() <= 2
	if TextLayer.text_width(label) + TextLayer.text_width(note) + 8 <= inner:
		return true
	var lines := tl._wrap(label, inner, 1)
	if r.size.y < 30 or lines.size() > 2:
		return false
	var second := lines[1] if lines.size() > 1 else ""
	return TextLayer.text_width(second) + TextLayer.text_width(note) + 8 <= inner
