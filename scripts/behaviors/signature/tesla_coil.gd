class_name TeslaCoilBehavior
extends PartBehavior

## Zaps the nearest enemy in range, then arcs to more enemies near each hit.
## Ignores facing (it's a coil). Params: damage, range, chains, chain_range,
## interval, heat_per_zap.

var zaps: int = 0
var _cooldown := 0.0
var _bolt: MeshInstance3D
var _bolt_t := 0.0


func on_attached() -> void:
	_bolt = MeshInstance3D.new()
	_bolt.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.9, 1.0)
	_bolt.material_override = m
	_bolt.top_level = true
	part.add_child(_bolt)


func on_detached() -> void:
	if _bolt != null:
		_bolt.queue_free()


func on_tick(delta: float) -> void:
	_bolt_t -= delta
	if _bolt != null and _bolt_t <= 0.0:
		(_bolt.mesh as ImmediateMesh).clear_surfaces()
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var enemies := RunState.enemies
	if enemies == null or robot == null:
		return
	var origin := part.global_position
	var first := enemies.find_nearest(origin, float(param("range", 7.0)))
	if first < 0:
		return
	if robot.browned_out and randf() > robot.get_power_supply():
		_cooldown = 0.4
		return
	var dmg := float(param("damage", 14.0)) * robot.assembly.get_mod(part, "damage_mult")
	var chain_range := float(param("chain_range", 3.5))
	var hit: Array[int] = [first]
	var points: Array[Vector3] = [origin, enemies.pos[first]]
	var current := first
	for k in int(param("chains", 4)):
		var best := -1
		var best_d := chain_range
		for j in enemies.query_radius(enemies.pos[current], chain_range):
			if hit.has(j):
				continue
			var d := enemies.pos[j].distance_to(enemies.pos[current])
			if d < best_d:
				best_d = d
				best = j
		if best < 0:
			break
		hit.append(best)
		points.append(enemies.pos[best])
		current = best
	for i in hit:
		enemies.damage(i, dmg)
	robot.add_heat(float(param("heat_per_zap", 1.5)) * robot.assembly.get_mod(part, "heat_mult"))
	zaps += 1
	_draw(points)
	_cooldown = float(param("interval", 0.9)) / maxf(robot.assembly.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult(), 0.1)


func _draw(points: Array[Vector3]) -> void:
	var im := _bolt.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in points.size() - 1:
		var a := points[k] + Vector3(0, 0.5, 0)
		var b := points[k + 1] + Vector3(0, 0.5, 0)
		var mid := (a + b) * 0.5 + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3))
		im.surface_add_vertex(a)
		im.surface_add_vertex(mid)
		im.surface_add_vertex(mid)
		im.surface_add_vertex(b)
	im.surface_end()
	_bolt_t = 0.12
