class_name PickupManager
extends Node3D

## Scrap gems (many, MultiMesh, magnet-pulled) and part pickups (few, real
## nodes you have to walk over, so you can choose to skip a part).
## Parts go through RunState.acquire_part: duplicates upgrade, else
## auto-install, else bench, else scrap.

@export var max_scrap: int = 1000
@export var collect_radius: float = 0.8
@export var magnet_speed: float = 14.0
@export var part_collect_radius: float = 1.6

var scrap_count: int = 0
var scrap_pos := PackedVector3Array()
var scrap_value := PackedInt32Array()
var scrap_pulled := PackedByteArray()

## Each entry: { "node": Node3D, "data": PartData, "age": float }
var parts: Array[Dictionary] = []

var _mm := MultiMesh.new()
var _mm_instance := MultiMeshInstance3D.new()
var _time := 0.0


func _ready() -> void:
	RunState.pickups = self
	scrap_pos.resize(max_scrap)
	scrap_value.resize(max_scrap)
	scrap_pulled.resize(max_scrap)
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 4
	mesh.rings = 2 # reads as a little diamond
	var mat := PartVisuals.material_for(Color.WHITE).duplicate() as ShaderMaterial
	mat.set_shader_parameter("emission_color", Vector3(0.5, 0.45, 0.1))
	mesh.material = mat
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = max_scrap
	_mm.visible_instance_count = 0
	_mm_instance.multimesh = _mm
	_mm_instance.name = "ScrapMultiMesh"
	_mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm_instance)


func _exit_tree() -> void:
	if RunState.pickups == self:
		RunState.pickups = null


func spawn_scrap(at: Vector3, value: int) -> void:
	if value <= 0:
		return
	if scrap_count >= max_scrap:
		RunState.add_scrap(value) # field is full: bank it directly
		return
	scrap_pos[scrap_count] = Vector3(at.x, 0.3, at.z)
	scrap_value[scrap_count] = value
	scrap_pulled[scrap_count] = 0
	scrap_count += 1


func spawn_part(at: Vector3, data: PartData) -> Node3D:
	var node := Node3D.new()
	node.name = "PartPickup_%s" % data.id
	var vis := PartVisuals.build(data)
	vis.position = -data.visual_offset # center the mesh on the pickup
	var holder := Node3D.new()
	holder.name = "Spin"
	holder.position.y = 1.0
	holder.add_child(vis)
	node.add_child(holder)

	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.04
	beam_mesh.bottom_radius = 0.04
	beam_mesh.height = 4.0
	beam_mesh.radial_segments = 4
	beam.mesh = beam_mesh
	beam.position.y = 2.0
	var beam_mat := PartVisuals.material_for(data.visual_color).duplicate() as ShaderMaterial
	beam_mat.set_shader_parameter("emission_color", Vector3(data.visual_color.r, data.visual_color.g, data.visual_color.b))
	beam.material_override = beam_mat
	node.add_child(beam)

	var label := Label3D.new()
	label.text = data.get_display_name()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.0
	label.pixel_size = 0.01
	label.font_size = 32
	label.outline_size = 8
	label.no_depth_test = true
	node.add_child(label)

	add_child(node)
	node.global_position = Vector3(at.x, 0.0, at.z)
	parts.append({"node": node, "data": data, "age": 0.0})
	EventBus.loot_spawned.emit(node.global_position)
	return node


func clear_all() -> void:
	scrap_count = 0
	for p in parts:
		(p["node"] as Node3D).queue_free()
	parts.clear()


func _physics_process(delta: float) -> void:
	_time += delta
	var robot := RunState.robot
	if robot != null and robot.alive:
		_update_scrap(delta, robot)
		_update_parts(delta, robot)
	_update_multimesh()


func _update_scrap(delta: float, robot: RobotController) -> void:
	var rp := robot.global_position + Vector3(0.0, 0.5, 0.0)
	var magnet := robot.get_pickup_radius()
	var magnet2 := magnet * magnet
	var collect2 := (collect_radius + robot.get_body_radius()) * (collect_radius + robot.get_body_radius())
	var i := scrap_count - 1
	while i >= 0:
		var p := scrap_pos[i]
		var to := rp - p
		var d2 := to.length_squared()
		if d2 <= collect2:
			RunState.add_scrap(scrap_value[i])
			RunState.add_xp(scrap_value[i])
			EventBus.scrap_collected.emit(scrap_value[i])
			scrap_count -= 1
			scrap_pos[i] = scrap_pos[scrap_count]
			scrap_value[i] = scrap_value[scrap_count]
			scrap_pulled[i] = scrap_pulled[scrap_count]
		else:
			# Once a gem is pulled it keeps homing even if you outrun the radius.
			if d2 <= magnet2 or scrap_pulled[i] == 1:
				scrap_pulled[i] = 1
				scrap_pos[i] = p + to.normalized() * minf(magnet_speed * delta, sqrt(d2))
		i -= 1


func _update_parts(delta: float, robot: RobotController) -> void:
	var rp := robot.global_position
	var reach := part_collect_radius + robot.get_body_radius() * 0.5
	var k := parts.size() - 1
	while k >= 0:
		var entry: Dictionary = parts[k]
		var node: Node3D = entry["node"]
		entry["age"] = float(entry["age"]) + delta
		var spin := node.get_node("Spin") as Node3D
		spin.rotation.y += delta * 1.5
		spin.position.y = 1.0 + sin(float(entry["age"]) * 3.0) * 0.15
		var d := Vector2(node.global_position.x - rp.x, node.global_position.z - rp.z).length()
		# Short grace period so a part dropped under you isn't grabbed instantly.
		if d <= reach and float(entry["age"]) > 0.4:
			_collect_part(entry["data"], robot)
			node.queue_free()
			parts.remove_at(k)
		k -= 1


func _collect_part(data: PartData, _robot: RobotController) -> void:
	# Walking over a part you already own upgrades it (duplicates merge).
	var result := RunState.acquire_part(data, true, true)
	EventBus.part_picked_up.emit(data, result == RunState.Acquired.ATTACHED)


func _update_multimesh() -> void:
	_mm.visible_instance_count = scrap_count
	var b := Basis(Vector3.UP, _time * 3.0)
	for i in scrap_count:
		var p := scrap_pos[i]
		p.y += sin(_time * 4.0 + float(i)) * 0.08
		_mm.set_instance_transform(i, Transform3D(b, p))
		var v := scrap_value[i]
		_mm.set_instance_color(i, Color(1.0, 0.85, 0.2) if v < 3 else Color(0.4, 1.0, 0.9))
