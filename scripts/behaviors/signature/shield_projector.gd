class_name ShieldProjectorBehavior
extends PartBehavior

## Projects an energy wall in its facing arc. Hits from that side are
## absorbed by the battery instead of your HP (RobotController.take_damage),
## and enemies touching the wall get shoved back. Empty battery = no shield.
## Params: shield_arc_deg, shield_radius, energy_per_damage, push.

var _wall: MeshInstance3D
var _mat: StandardMaterial3D
var _flash := 0.0


func on_attached() -> void:
	var arc := deg_to_rad(float(param("shield_arc_deg", 120.0)))
	var r := float(param("shield_radius", 2.2))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	for k in segs:
		var a0 := -arc * 0.5 + arc * float(k) / segs
		var a1 := -arc * 0.5 + arc * float(k + 1) / segs
		var p0 := Vector3(-sin(a0), 0, -cos(a0)) * r
		var p1 := Vector3(-sin(a1), 0, -cos(a1)) * r
		var up := Vector3(0, 1.4, 0)
		for v in [p0, p1, p1 + up, p0, p1 + up, p0 + up]:
			st.add_vertex(v - Vector3(0, 0.6, 0))
	_wall = MeshInstance3D.new()
	_wall.mesh = st.commit()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(0.4, 0.85, 1.0, 0.18)
	_wall.material_override = _mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.add_child(_wall)


func flash() -> void:
	_flash = 0.15


func is_up() -> bool:
	return robot != null and robot.energy > 0.5 and not robot.browned_out


func on_tick(delta: float) -> void:
	if _wall == null:
		return
	_flash -= delta
	_wall.visible = is_up()
	_mat.albedo_color.a = 0.45 if _flash > 0.0 else 0.18
	var enemies := RunState.enemies
	if enemies == null or not is_up():
		return
	var origin := part.global_position
	var fwd := part.get_facing_global()
	if fwd == Vector3.ZERO:
		return
	var r := float(param("shield_radius", 2.2))
	var cos_half := cos(deg_to_rad(float(param("shield_arc_deg", 120.0)) * 0.5))
	var push := float(param("push", 5.0))
	for i in enemies.query_radius(origin, r + 0.6):
		var to := enemies.pos[i] - origin
		to.y = 0.0
		var d := to.length()
		if d < 0.01 or fwd.dot(to / d) < cos_half:
			continue
		if d < r + enemies.get_radius(i):
			enemies.pos[i] += (to / d) * push * delta
