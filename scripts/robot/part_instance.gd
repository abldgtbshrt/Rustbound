class_name PartInstance
extends Node3D

## A part attached to a robot. Child parts are attached as child nodes at the
## transform of the socket they occupy, turned by their own yaw (45° steps).

const YAW_STEP := PI / 4.0

var data: PartData
var parent_part: PartInstance
var parent_socket: StringName
## Player rotation around the socket's up axis, in 45° steps.
var yaw_steps: int = 0
var visual: Node3D
var behaviors: Array[PartBehavior] = []

var _socket_children: Dictionary = {} # StringName -> PartInstance


func _init(part_data: PartData = null) -> void:
	data = part_data
	if data != null:
		name = String(data.id) if data.id != StringName() else "Part"
		visual = PartVisuals.build(data)
		add_child(visual)


func get_socket_transform(socket: SocketDef) -> Transform3D:
	if visual != null and not socket.is_grid():
		var marker := visual.find_child(String(socket.marker_name), true, false) as Node3D
		if marker != null:
			return visual.transform * marker.transform
	return socket.get_transform()


func is_socket_free(socket_name: StringName) -> bool:
	return not _socket_children.has(socket_name)


func get_free_sockets() -> Array[SocketDef]:
	var out: Array[SocketDef] = []
	if data == null:
		return out
	for s in data.get_sockets():
		if is_socket_free(s.marker_name):
			out.append(s)
	return out


func get_child_in(socket_name: StringName) -> PartInstance:
	return _socket_children.get(socket_name, null)


func get_child_parts() -> Array[PartInstance]:
	var out: Array[PartInstance] = []
	for c in _socket_children.values():
		out.append(c)
	return out


## Local transform a child gets in `socket` with `steps` of yaw.
func child_transform(socket: SocketDef, steps: int) -> Transform3D:
	return get_socket_transform(socket) * Transform3D(Basis(Vector3.UP, float(steps) * YAW_STEP), Vector3.ZERO)


func attach_child_part(child_part: PartInstance, socket: SocketDef, steps: int = 0) -> void:
	if child_part.get_parent() != null:
		child_part.get_parent().remove_child(child_part)
	child_part.yaw_steps = posmod(steps, 8)
	child_part.transform = child_transform(socket, child_part.yaw_steps)
	child_part.parent_part = self
	child_part.parent_socket = socket.marker_name
	_socket_children[socket.marker_name] = child_part
	add_child(child_part)


## Re-applies this part's socket transform with a new yaw.
func set_yaw(steps: int) -> void:
	yaw_steps = posmod(steps, 8)
	if parent_part != null:
		var s := parent_part.data.get_socket(parent_socket)
		if s != null:
			transform = parent_part.child_transform(s, yaw_steps)


func detach_child_part(child_part: PartInstance) -> void:
	_socket_children.erase(child_part.parent_socket)
	child_part.parent_part = null
	child_part.parent_socket = &""
	remove_child(child_part)


func walk() -> Array[PartInstance]:
	var out: Array[PartInstance] = [self]
	for c in get_children():
		if c is PartInstance:
			out.append_array((c as PartInstance).walk())
	return out


## Upgrade tier, shared by every copy of this part in the run.
func get_tier() -> int:
	return RunState.get_tier(data.id) if data != null else 1


## The chosen upgrade path's data, or {}.
func get_chosen_path() -> Dictionary:
	if data == null:
		return {}
	var pid: StringName = RunState.get_path_id(data.id)
	return data.find_path(pid) if pid != &"" else {}


## A stat scaled by this part's tier. `base` is usually the PartData value.
func stat(key: String, base: float) -> float:
	return data.scaled(key, base, get_tier())


## World-space mass point (attach point + visual offset).
func get_mass_point_global() -> Vector3:
	return global_transform * data.visual_offset


## Horizontal world-space facing (-Z of the part), or ZERO if pointing up/down.
func get_facing_global() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.ZERO
