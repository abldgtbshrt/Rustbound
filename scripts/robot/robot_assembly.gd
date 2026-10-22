class_name RobotAssembly
extends Node3D

signal assembly_changed

@export var root_part_data: PartData

var root: PartInstance
var total_mass: float = 0.0
var center_of_mass: Vector3 = Vector3.ZERO
var power_net: float = 0.0
var footprint: float = 0.0

func _ready() -> void:
	if root == null and root_part_data != null:
		root = PartInstance.new(root_part_data)
		root.name = "RootPart"
		add_child(root)
	recompute()

func attach(part: PartData, parent: PartInstance, socket: StringName) -> PartInstance:
	if part == null:
		return null
	if parent == null:
		parent = root
	if parent == null:
		return null

	var inst := PartInstance.new(part)
	inst.name = String(part.id) if part.id != StringName() else "Part"
	parent.attach_child_part(inst, socket)
	recompute()
	assembly_changed.emit()
	return inst

func recompute() -> void:
	total_mass = 0.0
	power_net = 0.0
	center_of_mass = Vector3.ZERO
	footprint = 0.0

	if root == null:
		assembly_changed.emit()
		return

	var weighted := Vector3.ZERO
	var feet: Array[Vector3] = []

	for p in root.walk():
		if p.data == null:
			continue
		total_mass += p.data.mass
		weighted += p.global_position * p.data.mass
		power_net -= p.data.power_draw
		if p.data.category == PartData.Category.LOCOMOTION:
			feet.append(p.global_position)

	if total_mass > 0.0001:
		center_of_mass = to_local(weighted / total_mass)

	footprint = _spread(feet)
	assembly_changed.emit()

func _spread(points: Array[Vector3]) -> float:
	if points.size() < 2:
		return 0.3
	var aabb := AABB(points[0], Vector3.ZERO)
	for p in points:
		aabb = aabb.expand(p)
	return Vector2(aabb.size.x, aabb.size.z).length()
