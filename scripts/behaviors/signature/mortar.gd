class_name MortarBehavior
extends PartBehavior

## Lobs shells over crowds (and obstacles) at enemies between min_range and
## range inside its arc; each lands for area damage. Params: damage, radius,
## min_range, range, arc_deg, interval, flight_time, heat_per_shot.

var shots: int = 0
var _cooldown := 0.0
var _shells: Array[Dictionary] = [] # { node, from, to, t }


func on_detached() -> void:
	for sh in _shells:
		(sh["node"] as Node).queue_free()
	_shells.clear()


func on_tick(delta: float) -> void:
	_fly(delta)
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var enemies := RunState.enemies
	if enemies == null or robot == null:
		return
	if robot.browned_out and randf() > robot.get_power_supply():
		_cooldown = 0.5
		return
	var origin := part.global_position
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		fwd = -robot.global_basis.z
	var cos_half := cos(deg_to_rad(float(param("arc_deg", 160.0)) * 0.5))
	var min_r := float(param("min_range", 6.0))
	var max_r := float(param("range", 20.0)) * robot.assembly.get_mod(part, "range_mult")
	# Aim at the enemy with the most neighbours: lob into the thick of it.
	var best := -1
	var best_n := -1
	for i in enemies.query_radius(origin, max_r):
		var to := enemies.pos[i] - origin
		to.y = 0.0
		var d := to.length()
		if d < min_r or fwd.dot(to / d) < cos_half:
			continue
		var n := enemies.query_radius(enemies.pos[i], float(param("radius", 2.5))).size()
		if n > best_n:
			best_n = n
			best = i
	if best < 0:
		return
	_launch(origin + Vector3(0, 0.4, 0), enemies.pos[best])
	robot.add_heat(float(param("heat_per_shot", 4.0)) * robot.assembly.get_mod(part, "heat_mult"))
	robot.apply_recoil(-fwd * 1.5)
	shots += 1
	_cooldown = float(param("interval", 1.6)) / maxf(robot.assembly.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult(), 0.1)


func _launch(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.16
	m.height = 0.32
	m.radial_segments = 6
	m.rings = 3
	mi.mesh = m
	mi.material_override = PartVisuals.material_for(Color(0.3, 0.3, 0.3))
	mi.top_level = true
	part.add_child(mi)
	mi.global_position = from
	_shells.append({"node": mi, "from": from, "to": Vector3(to.x, 0.0, to.z), "t": 0.0})


func _fly(delta: float) -> void:
	var flight := float(param("flight_time", 1.0))
	var k := _shells.size() - 1
	while k >= 0:
		var sh: Dictionary = _shells[k]
		sh["t"] = float(sh["t"]) + delta
		var f := clampf(float(sh["t"]) / flight, 0.0, 1.0)
		var from: Vector3 = sh["from"]
		var to: Vector3 = sh["to"]
		var p := from.lerp(to, f)
		p.y = lerpf(from.y, to.y, f) + sin(f * PI) * (3.0 + from.distance_to(to) * 0.25)
		(sh["node"] as Node3D).global_position = p
		if f >= 1.0:
			_explode(to)
			(sh["node"] as Node).queue_free()
			_shells.remove_at(k)
		k -= 1


func _explode(at: Vector3) -> void:
	var enemies := RunState.enemies
	var r := float(param("radius", 2.5))
	if enemies != null:
		var dmg := float(param("damage", 35.0)) * robot.assembly.get_mod(part, "damage_mult")
		enemies.damage_radius(at, r, dmg, 4.0)
	VentEffect.spawn(robot.get_parent(), at, r, Color(1.0, 0.55, 0.2, 0.9))
