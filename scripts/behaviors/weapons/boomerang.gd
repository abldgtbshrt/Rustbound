class_name BoomerangBehavior
extends PartBehavior

## Throws a spinning blade that swings out in an arc and comes back. It hits
## every enemy it passes, once on the way out and once on the way back.
## Params: damage, range, curve (sideways bulge), flight_time, interval,
## blades (Twin Blades path: mirrored arcs), slow_* (Razor Wind path).

var throws: int = 0
var hits: int = 0
var _cooldown := 0.5
var _blades: Array[Dictionary] = [] # { node, t, dir, side, hit_out, hit_back }


func on_detached() -> void:
	for b in _blades:
		(b["node"] as Node).queue_free()
	_blades.clear()


func in_flight() -> int:
	return _blades.size()


func on_tick(delta: float) -> void:
	_fly(delta)
	_cooldown -= delta
	if _cooldown > 0.0 or not _blades.is_empty():
		return
	var enemies := RunState.enemies
	if enemies == null or robot == null:
		return
	var reach := float(param("range", 9.0)) * robot.assembly.get_mod(part, "range_mult")
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		fwd = -robot.global_basis.z
	if enemies.find_nearest(part.global_position, reach, fwd, cos(deg_to_rad(70.0))) < 0:
		return
	var n := int(param("blades", 1))
	for k in n:
		var side := 1.0 if k % 2 == 0 else -1.0
		_throw(fwd, side)
	throws += 1
	fired()
	robot.add_heat(float(param("heat_per_throw", 2.0)) * robot.assembly.get_mod(part, "heat_mult"))
	_cooldown = float(param("interval", 2.2)) / maxf(robot.assembly.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult(), 0.1)


func _throw(dir: Vector3, side: float) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.9, 0.06, 0.18)
	mi.mesh = m
	mi.material_override = PartVisuals.material_for(Color(0.85, 0.85, 0.9))
	mi.top_level = true
	part.add_child(mi)
	mi.global_position = part.global_position
	_blades.append({"node": mi, "t": 0.0, "dir": dir, "side": side, "hit_out": {}, "hit_back": {}})


## Position along an oval loop: out along `dir` swinging to one side, tip at
## full range on the centre line, back along the other side to wherever the
## part is now.
func _blade_pos(b: Dictionary, f: float) -> Vector3:
	var reach := float(param("range", 9.0)) * robot.assembly.get_mod(part, "range_mult")
	var bulge := float(param("curve", 1.2))
	var dir: Vector3 = b["dir"]
	var side_v := dir.cross(Vector3.UP) * float(b["side"])
	var th := f * TAU
	var home := part.global_position
	return home + dir * (reach * 0.5 * (1.0 - cos(th))) + side_v * (bulge * sin(th)) + Vector3(0, 0.3, 0)


func _fly(delta: float) -> void:
	if robot == null:
		return
	var enemies := RunState.enemies
	var flight := float(param("flight_time", 1.4))
	var dmg := float(param("damage", 16.0)) * robot.assembly.get_mod(part, "damage_mult")
	var fx := hit_fx()
	var k := _blades.size() - 1
	while k >= 0:
		var b: Dictionary = _blades[k]
		b["t"] = float(b["t"]) + delta
		var f := clampf(float(b["t"]) / flight, 0.0, 1.0)
		var node := b["node"] as Node3D
		node.global_position = _blade_pos(b, f)
		node.rotate_y(delta * 25.0)
		if enemies != null:
			var seen: Dictionary = b["hit_out"] if f < 0.5 else b["hit_back"]
			for i in enemies.query_radius(node.global_position, 1.6):
				if seen.has(i):
					continue
				var d := Vector2(enemies.get_pos(i).x - node.global_position.x, enemies.get_pos(i).z - node.global_position.z).length()
				if d > 0.9 + enemies.get_radius(i): # spinning blade ~0.9 m reach
					continue
				seen[i] = true
				enemies.damage(i, dmg)
				enemies.apply_hit_fx(i, fx)
				hits += 1
		if f >= 1.0:
			node.queue_free()
			_blades.remove_at(k)
		k -= 1
