class_name JetBehavior
extends PartBehavior

## Visual side of a jet: a flickering flame while the robot is thrusting.
## The thrust itself is applied by RobotController (all jets together), using
## params jet_thrust (upward force) and jet_energy (battery per second).

var _flame: MeshInstance3D
var _t := 0.0


func on_attached() -> void:
	_flame = MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.13
	m.bottom_radius = 0.0
	m.height = 0.6
	m.radial_segments = 6
	m.rings = 1
	_flame.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.65, 0.2)
	_flame.material_override = mat
	_flame.position = Vector3(0.0, -0.55, 0.0)
	_flame.visible = false
	part.add_child(_flame)


func on_tick(delta: float) -> void:
	if _flame == null or robot == null:
		return
	_t += delta
	_flame.visible = robot.is_jetting
	if robot.is_jetting:
		var s := 0.85 + 0.3 * absf(sin(_t * 37.0))
		_flame.scale = Vector3(1.0, s, 1.0)
