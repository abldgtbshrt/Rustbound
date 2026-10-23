class_name ModelUtil
extends RefCounted

## Helpers for authored models (see CONTRIBUTING_ART.md).

static var _merged: Dictionary = {} # PackedScene -> ArrayMesh


## Bakes every mesh in a model scene into one ArrayMesh (one surface per
## material), with node transforms applied. Used for enemies, which are drawn
## through a MultiMesh and so need a single Mesh. Cached per scene.
static func mesh_from_scene(scene: PackedScene) -> ArrayMesh:
	if scene == null:
		return null
	if _merged.has(scene):
		return _merged[scene]
	var root := scene.instantiate()
	var tools: Dictionary = {} # Material (or null) -> SurfaceTool
	var order: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not n is MeshInstance3D or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var xf := _relative_transform(root, mi)
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i)
			if mat == null:
				mat = mi.mesh.surface_get_material(i)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
				order.append(mat)
			(tools[mat] as SurfaceTool).append_from(mi.mesh, i, xf)
	root.free()
	var out := ArrayMesh.new()
	for mat in order:
		var st: SurfaceTool = tools[mat]
		st.commit(out)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	_merged[scene] = out
	return out


static func _relative_transform(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
