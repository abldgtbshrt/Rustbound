class_name VentEffect
extends MeshInstance3D

## Expanding, fading steam ring for the heat vent. Self-frees.

const DURATION := 0.45

var _radius: float = 3.0
var _t: float = 0.0
var _mat: StandardMaterial3D


static func spawn(parent: Node, at: Vector3, radius: float) -> VentEffect:
	if parent == null:
		return null
	var fx := VentEffect.new()
	fx._radius = radius
	parent.add_child(fx)
	fx.global_position = at + Vector3(0.0, 0.6, 0.0)
	return fx


func _ready() -> void:
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 0.6
	m.radial_segments = 16
	m.rings = 1
	m.cap_top = false
	m.cap_bottom = false
	mesh = m
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(1.0, 0.75, 0.45, 0.8)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3(0.3, 1.0, 0.3)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var r := lerpf(0.3, _radius, 1.0 - pow(1.0 - k, 3.0))
	scale = Vector3(r, 1.0 + k, r)
	_mat.albedo_color.a = 0.8 * (1.0 - k)
	if k >= 1.0:
		queue_free()
