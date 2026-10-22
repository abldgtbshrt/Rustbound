class_name SocketDef
extends Resource

## One attachment point on a part. Until parts ship as .glb scenes with baked
## Marker3D nodes, the socket transform lives here. When a part has a scene with
## a Marker3D called `marker_name`, that marker's transform wins.

@export var marker_name: StringName
@export_enum("Structural", "Mount", "Internal", "Locomotion") var type: int = 0
@export_range(1, 3, 1) var size: int = 1
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO


static func make(p_name: StringName, p_type: int, p_pos: Vector3, p_size: int = 1, p_rot: Vector3 = Vector3.ZERO) -> SocketDef:
	var s := SocketDef.new()
	s.marker_name = p_name
	s.type = p_type
	s.position = p_pos
	s.size = p_size
	s.rotation_degrees = p_rot
	return s


func get_transform() -> Transform3D:
	var b := Basis.from_euler(rotation_degrees * (PI / 180.0))
	return Transform3D(b, position)
