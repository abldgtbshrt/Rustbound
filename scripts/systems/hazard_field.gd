class_name HazardField
extends Node3D

## Ground patches left behind by trail upgrades: fire burns enemies standing in
## it, oil and static slow them. Patches fade after `life` seconds. Drawn with
## one MultiMesh of flat discs.

enum Kind { FIRE, OIL, STATIC }

const COLORS := [Color(1.0, 0.45, 0.1, 0.8), Color(0.12, 0.1, 0.12, 0.85), Color(0.45, 0.75, 1.0, 0.7)]

@export var max_patches: int = 400
@export var tick_interval: float = 0.2

var count: int = 0
var pos := PackedVector3Array()
var radius := PackedFloat32Array()
var life := PackedFloat32Array()
var max_life := PackedFloat32Array()
var strength := PackedFloat32Array()
var kind := PackedInt32Array()

var _tick := 0.0
var _mm := MultiMesh.new()
var _mm_instance := MultiMeshInstance3D.new()


func _ready() -> void:
	RunState.hazards = self
	pos.resize(max_patches)
	radius.resize(max_patches)
	life.resize(max_patches)
	max_life.resize(max_patches)
	strength.resize(max_patches)
	kind.resize(max_patches)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 10
	disc.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	disc.material = mat
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = disc
	_mm.instance_count = max_patches
	_mm.visible_instance_count = 0
	_mm_instance.multimesh = _mm
	_mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_instance)


func _exit_tree() -> void:
	if RunState.hazards == self:
		RunState.hazards = null


## strength: fire = damage per second, oil/static = speed multiplier.
func spawn(at: Vector3, p_kind: int, p_radius: float, p_life: float, p_strength: float) -> void:
	var i := count
	if count >= max_patches:
		i = _oldest()
	else:
		count += 1
	pos[i] = Vector3(at.x, 0.03, at.z)
	radius[i] = p_radius
	life[i] = p_life
	max_life[i] = p_life
	strength[i] = p_strength
	kind[i] = p_kind


func clear_all() -> void:
	count = 0
	_mm.visible_instance_count = 0


func _oldest() -> int:
	var best := 0
	for i in count:
		if life[i] < life[best]:
			best = i
	return best


func _physics_process(delta: float) -> void:
	var i := count - 1
	while i >= 0:
		life[i] -= delta
		if life[i] <= 0.0:
			count -= 1
			pos[i] = pos[count]
			radius[i] = radius[count]
			life[i] = life[count]
			max_life[i] = max_life[count]
			strength[i] = strength[count]
			kind[i] = kind[count]
		i -= 1
	_tick -= delta
	if _tick <= 0.0:
		_tick = tick_interval
		_apply(tick_interval)
	_draw()


func _apply(dt: float) -> void:
	var em := RunState.enemies
	if em == null:
		return
	for k in count:
		for e in em.query_radius(pos[k], radius[k] + 0.4):
			match kind[k]:
				Kind.FIRE:
					em.apply_burn(e, strength[k], 0.6)
				_:
					em.apply_slow(e, strength[k], dt + 0.3)


func _draw() -> void:
	_mm.visible_instance_count = count
	for i in count:
		var fade := clampf(life[i] / maxf(max_life[i], 0.01), 0.0, 1.0)
		var r := radius[i] * (0.7 + 0.3 * fade)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), pos[i]))
		var c: Color = COLORS[kind[i]]
		c.a *= fade
		_mm.set_instance_color(i, c)
