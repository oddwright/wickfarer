class_name StarChart
extends RefCounted
## One Reach's map: columns of beacons from the start (column 0) to the Gate
## (last column). Links run forward to the next column, and sometimes
## sideways within a column, which costs a jump without making progress.

const SIDE_LINK_CHANCE := 0.3

var nodes: Array[Dictionary] = []  ## {id, col, row, x, y, kind, links}
var columns: int = 0


static func generate(reach: Dictionary, rng: RandomNumberGenerator) -> StarChart:
	var chart := StarChart.new()
	chart.columns = int(reach.columns)
	var by_col: Array = []
	for col in chart.columns:
		var count := 1
		if col > 0 and col < chart.columns - 1:
			count = rng.randi_range(int(reach.rows[0]), int(reach.rows[1]))
		var ids: Array[String] = []
		for row in count:
			var kind := "empty"
			if col == 0:
				kind = "start"
			elif col == chart.columns - 1:
				kind = "gate"
			else:
				kind = _pick_kind(reach.kinds, rng)
			var id := "n%d_%d" % [col, row]
			var y := (float(row) + 0.5) / float(count)
			y = clampf(y + rng.randf_range(-0.08, 0.08), 0.05, 0.95)
			(
				chart
				. nodes
				. append(
					{
						"id": id,
						"col": col,
						"row": row,
						"x": Q.q(float(col) / float(chart.columns - 1)),
						"y": Q.q(y),
						"kind": kind,
						"links": [],
					}
				)
			)
			ids.append(id)
		by_col.append(ids)
	chart._link(by_col, rng)
	chart._ensure_store(by_col, rng)
	return chart


static func _pick_kind(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var kinds: Array[String] = []
	var w: Array[int] = []
	for k: String in weights:
		kinds.append(k)
		w.append(int(weights[k]))
	var i := RngStreams.weighted_pick(w, rng)
	return kinds[i] if i >= 0 else "empty"


func _link(by_col: Array, rng: RandomNumberGenerator) -> void:
	for col in range(columns - 1):
		var here: Array = by_col[col]
		var there: Array = by_col[col + 1]
		# Every node gets one forward link to its nearest-by-row neighbour...
		for i in here.size():
			var j := int(round(float(i) / maxf(1.0, here.size() - 1) * (there.size() - 1)))
			_add_link(here[i], there[j])
			if there.size() > 1 and rng.randf() < 0.45:
				_add_link(
					here[i],
					there[clampi(j + (1 if rng.randf() < 0.5 else -1), 0, there.size() - 1)]
				)
		# ...and every node in the next column gets at least one way in.
		for j in there.size():
			if not _has_incoming(there[j]):
				var i := int(round(float(j) / maxf(1.0, there.size() - 1) * (here.size() - 1)))
				_add_link(here[i], there[j])
		for i in range(here.size() - 1):
			if col > 0 and rng.randf() < SIDE_LINK_CHANCE:
				_add_link(here[i], here[i + 1])
				_add_link(here[i + 1], here[i])


func _ensure_store(by_col: Array, rng: RandomNumberGenerator) -> void:
	for n in nodes:
		if n.kind == "store":
			return
	var col := clampi(columns / 2, 1, columns - 2)
	var ids: Array = by_col[col]
	node(ids[rng.randi_range(0, ids.size() - 1)]).kind = "store"


func _add_link(a: String, b: String) -> void:
	var n := node(a)
	if not n.links.has(b):
		n.links.append(b)


func _has_incoming(id: String) -> bool:
	for n in nodes:
		if n.links.has(id):
			return true
	return false


func node(id: String) -> Dictionary:
	for n in nodes:
		if n.id == id:
			return n
	return {}


func start_id() -> String:
	return nodes[0].id


func gate_id() -> String:
	return nodes[nodes.size() - 1].id


## Every node id reachable from `from` (including itself).
func reachable(from: String) -> Dictionary:
	var seen := {from: true}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for nxt: String in node(cur).links:
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
	return seen


func to_dict() -> Dictionary:
	return {"columns": columns, "nodes": nodes.duplicate(true)}


static func from_dict(d: Dictionary) -> StarChart:
	var c := StarChart.new()
	c.columns = int(d.columns)
	for n: Dictionary in d.nodes:
		var links: Array = []
		for l in n.links:
			links.append(str(l))
		(
			c
			. nodes
			. append(
				{
					"id": str(n.id),
					"col": int(n.col),
					"row": int(n.row),
					"x": float(n.x),
					"y": float(n.y),
					"kind": str(n.kind),
					"links": links,
				}
			)
		)
	return c
