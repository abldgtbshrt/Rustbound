class_name ProjectilePool
extends Node3D

## Pooled projectiles: packed arrays + one MultiMesh, hit-tested against the
## enemy spatial hash instead of using an Area3D per bullet.

@export var max_projectiles: int = 1200

var count: int = 0
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var life := PackedFloat32Array()
var dmg := PackedFloat32Array()
var radius := PackedFloat32Array()
var knock := PackedFloat32Array()
var pierce := PackedInt32Array()
var color := PackedColorArray()

## Total hits landed this run; handy for tests and stats.
var hits: int = 0

var _mm := MultiMesh.new()
var _mm_instance := MultiMeshInstance3D.new()


func _ready() -> void:
	RunState.projectiles = self
	# Packed arrays are value types, so resize each member directly.
	pos.resize(max_projectiles)
	vel.resize(max_projectiles)
	life.resize(max_projectiles)
	dmg.resize(max_projectiles)
	radius.resize(max_projectiles)
	knock.resize(max_projectiles)
	pierce.resize(max_projectiles)
	color.resize(max_projectiles)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.6)
	var mat := PartVisuals.material_for(Color.WHITE).duplicate() as ShaderMaterial
	mat.set_shader_parameter("emission_color", Vector3(0.8, 0.7, 0.4))
	mesh.material = mat
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = max_projectiles
	_mm.visible_instance_count = 0
	_mm_instance.multimesh = _mm
	_mm_instance.name = "ProjectileMultiMesh"
	_mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_instance)


func _exit_tree() -> void:
	if RunState.projectiles == self:
		RunState.projectiles = null


func fire(origin: Vector3, velocity: Vector3, damage: float, lifetime: float, p_radius: float = 0.25, p_pierce: int = 0, knockback: float = 1.0, p_color: Color = Color(1.0, 0.85, 0.4)) -> bool:
	if count >= max_projectiles:
		return false
	var i := count
	count += 1
	pos[i] = origin
	vel[i] = velocity
	life[i] = lifetime
	dmg[i] = damage
	radius[i] = p_radius
	pierce[i] = p_pierce
	knock[i] = knockback
	color[i] = p_color
	return true


func clear_all() -> void:
	count = 0
	_mm.visible_instance_count = 0


func _physics_process(delta: float) -> void:
	var enemies := RunState.enemies
	var i := count - 1
	while i >= 0:
		var p := pos[i] + vel[i] * delta
		pos[i] = p
		life[i] -= delta
		var dead := life[i] <= 0.0 or p.y < -0.5
		if not dead and enemies != null:
			var r := radius[i]
			for e in enemies.query_radius(p, r + 1.0):
				var er := enemies.get_radius(e)
				var dx := enemies.pos[e].x - p.x
				var dz := enemies.pos[e].z - p.z
				if dx * dx + dz * dz > (r + er) * (r + er) or p.y > er * 2.0 + 0.4:
					continue
				var push := Vector3(vel[i].x, 0.0, vel[i].z).normalized() * knock[i]
				enemies.damage(e, dmg[i], push)
				hits += 1
				pierce[i] -= 1
				if pierce[i] < 0:
					dead = true
					break
		if dead:
			_remove(i)
		i -= 1
	_update_multimesh()


func _remove(i: int) -> void:
	count -= 1
	if i == count:
		return
	pos[i] = pos[count]
	vel[i] = vel[count]
	life[i] = life[count]
	dmg[i] = dmg[count]
	radius[i] = radius[count]
	pierce[i] = pierce[count]
	knock[i] = knock[count]
	color[i] = color[count]


func _update_multimesh() -> void:
	_mm.visible_instance_count = count
	for i in count:
		var v := vel[i]
		var b := Basis.IDENTITY
		if v.length_squared() > 0.0001:
			b = Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)
		_mm.set_instance_transform(i, Transform3D(b, pos[i]))
		_mm.set_instance_color(i, color[i])
