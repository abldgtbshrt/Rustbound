class_name PartInstance
extends Node3D

## A part attached to a robot. Child parts are attached as child nodes at the
## transform of the socket they occupy.

var data: PartData
var parent_part: PartInstance
var parent_socket: StringName
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
	if visual != null:
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
	for s in data.sockets:
		if is_socket_free(s.marker_name):
			out.append(s)
	return out


func get_child_in(socket_name: StringName) -> PartInstance:
	return _socket_children.get(socket_name, null)


func attach_child_part(child_part: PartInstance, socket: SocketDef) -> void:
	if child_part.get_parent() != null:
		child_part.get_parent().remove_child(child_part)
	child_part.transform = get_socket_transform(socket)
	child_part.parent_part = self
	child_part.parent_socket = socket.marker_name
	_socket_children[socket.marker_name] = child_part
	add_child(child_part)


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


## World-space mass point (attach point + visual offset).
func get_mass_point_global() -> Vector3:
	return global_transform * data.visual_offset
