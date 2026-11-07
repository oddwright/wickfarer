class_name EmberFlare
extends RefCounted
## Flaring the Ember: guns charge faster and every room warms for a few seconds,
## then the Ember cracks and costs power until someone patches it. The state
## (flare_time, flare_cool) lives on Ship; the rules live here, for both sides.


## A flare needs a working Ember and a rested one (the rest starts with the burn
## and lasts at least as long, so a burning Ember is never rested).
static func can(s: Ship) -> bool:
	var ember := s.system_room("ember")
	return ember != null and ember.effective_level() > 0 and s.flare_cool <= 0.0


static func light(s: Ship) -> bool:
	if not can(s):
		return false
	var f := Ship.flare_data()
	s.flare_time = float(f.seconds)
	s.flare_cool = float(f.cooldown)
	return true


static func tick(s: Ship, dt: float, events: Array) -> void:
	s.flare_cool = maxf(0.0, s.flare_cool - dt)
	if s.flare_time <= 0.0:
		return
	var ember := s.system_room("ember")
	# Orders land between ticks, where events are cleared: say it on the first tick.
	if s.flare_time >= float(Ship.flare_data().seconds):
		events.append({"type": "flare", "side": s.side, "room": ember.id})
	s.flare_time = maxf(0.0, s.flare_time - dt)
	if s.flare_time > 0.0:
		return
	ember.damage = minf(float(ember.level), ember.damage + float(Ship.flare_data().crack))
	events.append({"type": "flare_spent", "side": s.side, "room": ember.id})
