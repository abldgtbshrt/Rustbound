class_name LaserBehavior
extends PartBehavior

## Charges up, then fires an instant beam that hits every enemy along a
## straight line. With CPU it aims at the nearest enemy in its arc; without,
## straight ahead. Params: damage, range, width, arc_deg, charge_time,
## heat_per_shot, beams + spread_deg (Prism path), burn_* (Burning Beam).

var shots: int = 0
var last_hits: int = 0
var _charge := 0.0
var _beam: MeshInstance3D
var _beam_t := 0.0


func on_attached() -> void:
	_beam = MeshInstance3D.new()
	_beam.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.25, 0.35)
	_beam.material_override = m
	_beam.top_level = true
	part.add_child(_beam)


func on_tick(delta: float) -> void:
	_beam_t -= delta
	if _beam_t <= 0.0 and _beam != null:
		(_beam.mesh as ImmediateMesh).clear_surfaces()
	var enemies := RunState.enemies
	if enemies == null or robot == null:
		return
	var asm := robot.assembly
	var reach := float(param("range", 22.0)) * asm.get_mod(part, "range_mult")
	var origin := part.global_position + Vector3(0, 0.15, 0)
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		fwd = -robot.global_basis.z
	var aim := fwd
	var target := enemies.find_nearest(origin, reach, fwd, cos(deg_to_rad(arc_param(40.0) * 0.5)))
	if target < 0:
		_charge = 0.0
		return
	if asm.has_cpu_for(part):
		aim = enemies.get_pos(target) - origin
		aim.y = 0.0
		aim = aim.normalized()
	var rate := asm.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult()
	if robot.browned_out:
		rate *= robot.get_power_supply()
	_charge += delta * rate
	if _charge < float(param("charge_time", 2.5)):
		return
	_charge = 0.0
	var beams := int(param("beams", 1))
	var spread := deg_to_rad(float(param("spread_deg", 12.0)))
	var lines: Array = []
	last_hits = 0
	for b in beams:
		var off := 0.0 if beams == 1 else lerpf(-spread, spread, float(b) / float(beams - 1))
		var d := aim.rotated(Vector3.UP, off)
		last_hits += _fire_beam(origin, d, reach)
		lines.append([origin, origin + d * reach])
	robot.add_heat(float(param("heat_per_shot", 8.0)) * asm.get_mod(part, "heat_mult"))
	shots += 1
	fired()
	_draw(lines)


func _fire_beam(origin: Vector3, dir: Vector3, reach: float) -> int:
	var enemies := RunState.enemies
	var width := float(param("width", 0.5))
	var dmg := float(param("damage", 45.0)) * robot.assembly.get_mod(part, "damage_mult")
	var fx := hit_fx()
	var hits := 0
	for i in enemies.query_segment(origin, dir, reach, width):
		enemies.damage(i, dmg, dir * 2.0)
		enemies.apply_hit_fx(i, fx)
		hits += 1
	return hits


func _draw(lines: Array) -> void:
	var im := _beam.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in lines:
		for k in 3: # a few parallel lines read as a thick beam
			var o := Vector3(0, 0.05 * k, 0)
			im.surface_add_vertex(l[0] + o)
			im.surface_add_vertex(l[1] + o)
	im.surface_end()
	_beam_t = 0.15
