class_name PartVisuals
extends RefCounted

## Builds low-poly placeholder meshes for parts that have no authored scene,
## and shares PS2-style materials between them.

const PS2_SHADER := preload("res://shaders/ps2_vertex.gdshader")

static var _materials: Dictionary = {}


static func material_for(color: Color) -> ShaderMaterial:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = PS2_SHADER
	m.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))
	_materials[key] = m
	return m


static func make_mesh(data: PartData) -> Mesh:
	match data.visual_shape:
		PartData.VisualShape.CYLINDER:
			var c := CylinderMesh.new()
			c.top_radius = data.visual_size.x * 0.5
			c.bottom_radius = data.visual_size.x * 0.5
			c.height = data.visual_size.y
			c.radial_segments = 8
			c.rings = 1
			return c
		PartData.VisualShape.SPHERE:
			var s := SphereMesh.new()
			s.radius = data.visual_size.x * 0.5
			s.height = data.visual_size.x
			s.radial_segments = 8
			s.rings = 4
			return s
		_:
			var b := BoxMesh.new()
			b.size = data.visual_size
			return b


## Returns a Node3D whose origin is the part's attach point.
static func build(data: PartData) -> Node3D:
	if data.scene != null:
		return data.scene.instantiate() as Node3D
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = make_mesh(data)
	mi.position = data.visual_offset
	mi.rotation_degrees = data.visual_rotation_degrees
	mi.material_override = material_for(data.visual_color)
	var root := Node3D.new()
	root.name = "Visual"
	root.add_child(mi)
	return root
