class_name FlamethrowerBehavior
extends PartBehavior

## Short-range cone of fire in bursts: burns for burst_time, then sputters
## for pause_time. Damages everything in the cone every tick. Params: dps,
## range, arc_deg, burst_time, pause_time, heat_per_sec, burn_dps/burn_dur
## (Napalm path).

var ticks: int = 0
var _phase := 0.0
var _firing := false
var _tick := 0.0
var _cone: MeshInstance3D
var _t := 0.0


func on_attached() -> void:
	_cone = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.05
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 8
	m.rings = 1
	_cone.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cone.material_override = mat
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cone.visible = false
	part.add_child(_cone)


func is_firing() -> bool:
	return _firing


func on_tick(delta: float) -> void:
	_t += delta
	var enemies := RunState.enemies
	if enemies == null or robot == null:
		return
	var asm := robot.assembly
	var reach := float(param("range", 5.0)) * asm.get_mod(part, "range_mult")
	var arc := arc_param(50.0)
	var origin := part.global_position
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		fwd = -robot.global_basis.z
	var cos_half := cos(deg_to_rad(arc * 0.5))

	# Burst cycle: only runs while something is in reach.
	var target := enemies.find_nearest(origin, reach, fwd, cos_half)
	var stalled := robot.browned_out and randf() > robot.get_power_supply()
	_phase -= delta
	if _phase <= 0.0 and not _firing and target < 0:
		_phase = 0.0 # ready: light up as soon as something walks in
	elif _phase <= 0.0:
		_firing = not _firing
		var rate := asm.get_mod(part, "fire_rate_mult") * robot.get_overcharge_mult()
		_phase = float(param("burst_time", 1.2)) * rate if _firing else float(param("pause_time", 0.8)) / maxf(rate, 0.1)
	var on := _firing and not stalled
	_draw_cone(on, reach, arc)
	if not on:
		return
	robot.add_heat(float(param("heat_per_sec", 3.0)) * asm.get_mod(part, "heat_mult") * delta)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.1
	var dmg := float(param("dps", 40.0)) * asm.get_mod(part, "damage_mult") * 0.1
	var fx := hit_fx()
	for i in enemies.query_radius(origin, reach + 0.5):
		var to := enemies.pos[i] - origin
		to.y = 0.0
		var d := to.length()
		if d > reach + enemies.get_radius(i) or (d > 0.1 and fwd.dot(to / d) < cos_half):
			continue
		enemies.damage(i, dmg)
		enemies.apply_hit_fx(i, fx)
	ticks += 1


func _draw_cone(on: bool, reach: float, arc: float) -> void:
	if _cone == null:
		return
	_cone.visible = on
	if not on:
		return
	var flick := 0.85 + 0.15 * sin(_t * 41.0)
	var w := tan(deg_to_rad(arc * 0.5)) * reach * flick
	# Cylinder's narrow top is +Y. Rotate +Y onto +Z (back toward the
	# nozzle) so the narrow end sits at the robot and the wide end flares out.
	_cone.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(w, reach, w * 0.5)), Vector3(0, 0.1, -reach * 0.5))
