class_name SocketDef
extends Resource

## An attachment point on a part, or a grid of them (a "hardpoint grid").
## A grid expands at runtime into grid.x * grid.y cells named
## "<marker_name>_<i>_<j>", spread along grid_u and grid_v (part-local
## offsets between neighbouring cells). Every socket's +Y is up; its -Z is the
## default facing of whatever is attached, before the player rotates it.
## When a part has an authored scene with a Marker3D named `marker_name`,
## that marker's transform wins (single sockets only).

@export var marker_name: StringName
@export_enum("Structural", "Mount", "Internal", "Locomotion") var type: int = 0
@export_range(1, 3, 1) var size: int = 1
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO

@export_group("Grid")
@export var grid: Vector2i = Vector2i.ONE
@export var grid_u: Vector3 = Vector3(0.4, 0.0, 0.0)
@export var grid_v: Vector3 = Vector3(0.0, 0.0, 0.4)


static func make(p_name: StringName, p_type: int, p_pos: Vector3, p_size: int = 1, p_rot: Vector3 = Vector3.ZERO) -> SocketDef:
	var s := SocketDef.new()
	s.marker_name = p_name
	s.type = p_type
	s.position = p_pos
	s.size = p_size
	s.rotation_degrees = p_rot
	return s


static func make_grid(p_name: StringName, p_type: int, p_pos: Vector3, p_grid: Vector2i, p_u: Vector3, p_v: Vector3, p_size: int = 1, p_rot: Vector3 = Vector3.ZERO) -> SocketDef:
	var s := make(p_name, p_type, p_pos, p_size, p_rot)
	s.grid = p_grid
	s.grid_u = p_u
	s.grid_v = p_v
	return s


func is_grid() -> bool:
	return grid.x * grid.y > 1


## Individual cells. A plain socket returns itself.
func expand() -> Array[SocketDef]:
	var out: Array[SocketDef] = []
	if not is_grid():
		out.append(self)
		return out
	for j in grid.y:
		for i in grid.x:
			var c := SocketDef.new()
			c.marker_name = StringName("%s_%d_%d" % [marker_name, i, j])
			c.type = type
			c.size = size
			c.rotation_degrees = rotation_degrees
			c.position = position \
				+ grid_u * (float(i) - float(grid.x - 1) * 0.5) \
				+ grid_v * (float(j) - float(grid.y - 1) * 0.5)
			out.append(c)
	return out


func get_transform() -> Transform3D:
	var b := Basis.from_euler(rotation_degrees * (PI / 180.0))
	return Transform3D(b, position)
