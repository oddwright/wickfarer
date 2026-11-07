extends SceneTree


func _init() -> void:
	ContentDB.load_all()
	var setups := {
		"stock (rivet+torch)": [[], ""],
		"rivet+frost_needle": [[], "frost_needle"],
		"rivet+rime_lance": [[], "rime_lance"],
		"stock + gyre_vanes": [["gyre_vanes"], ""],
		"stock + tallow_baffles": [["tallow_baffles"], ""],
		"stock + rivet_hopper": [["rivet_hopper"], ""],
		"stock + slag_plating": [["slag_plating"], ""],
		"stock + wick_bellows": [["wick_bellows"], ""],
	}
	for name: String in setups:
		var wins := 0
		var hull_left := 0
		var n := 60
		for seed_value in n:
			var c := Combat.create(seed_value + 1000, "tallow_wren")
			var me := c.player()
			for m: String in setups[name][0]:
				Gear.fit(me, m)
			if setups[name][1] != "":
				Gear.unmount(me, 1)
				Gear.mount(me, setups[name][1])
			me.enforce_power()
			for sys in ["weapons", "wards", "helm", "engines"]:
				while me.power_up(sys):
					pass
			var pilot := CombatAI.new()
			while c.state == "fighting" and c.time() < 300.0:
				c.tick()
				if c.tick_count % 10 == 0:
					pilot.think(c, 0)
			if c.state == "won":
				wins += 1
				hull_left += c.player().hull
		print(
			(
				"%-24s captain wins %3d%%  avg hull left %.1f"
				% [name, 100 * wins / n, float(hull_left) / maxf(1, wins)]
			)
		)
	quit()
