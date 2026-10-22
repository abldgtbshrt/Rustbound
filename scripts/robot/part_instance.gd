class_name PartInstance
extends Node3D

var data: PartData

var _socket_children: Dictionary = {}

func _init(part_data: PartData = null) -> void:
	data = part_data

func attach_child_part(child_part: PartInstance, socket_name: StringName) -> void:
	if child_part.get_parent() != null:
		child_part.get_parent().remove_child(child_part)
	add_child(child_part)
	_socket_children[socket_name] = child_part

func walk() -> Array[PartInstance]:
	var out: Array[PartInstance] = [self]
	for c in get_children():
		if c is PartInstance:
			out.append_array((c as PartInstance).walk())
	return out
