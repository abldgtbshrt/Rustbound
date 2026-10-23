@tool
extends EditorScenePostImportPlugin

## Runs on every model imported from res://assets/ (toggle per file in the
## Import dock: "rustbound/ps2_pipeline"). It makes an artist's .glb/.blend
## game-ready without anyone touching it by hand:
##   - The model is turned 180 degrees so its front (Blender's front, -Y,
##     which arrives as +Z) faces the game's forward, -Z.
##   - Empties named "Socket_<name>" become Marker3D nodes named <name>, so
##     PartData sockets with that marker_name snap to them.
##   - Every surface gets the PS2 material (vertex lighting, wobble, nearest
##     filtering), keeping its albedo texture and color.
## It runs before Godot builds the final scene (pre-process), so it only
## renames/replaces plain nodes and sets materials; it never frees nodes the
## importer still tracks. Collision from "-col" name hints isn't supported:
## gameplay collision comes from code. AssetValidator checks the result.

const OPTION := "rustbound/ps2_pipeline"
const SOCKET_PREFIX := "Socket_"
const PS2_SHADER := preload("res://shaders/ps2_vertex.gdshader")


func _get_import_options(path: String) -> void:
	add_import_option(OPTION, path.begins_with("res://assets/"))


func _pre_process(scene: Node) -> void:
	if not bool(get_option_value(OPTION)):
		return
	process(scene)


## Also callable directly (tests, tools): converts `scene` in place.
static func process(scene: Node) -> void:
	# Front: glTF/Blender models face +Z; the game's forward is -Z.
	var turn := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for c in scene.get_children():
		if c is Node3D:
			(c as Node3D).transform = turn * (c as Node3D).transform
	var converted: Dictionary = {} # source material -> PS2 material, so shared stays shared
	for node in _all_nodes(scene):
		if not is_instance_valid(node) or node == scene:
			continue
		if node is MeshInstance3D:
			_ps2_materials(node as MeshInstance3D, converted)
		elif node is ImporterMeshInstance3D:
			_ps2_importer_materials(node as ImporterMeshInstance3D, converted)
		elif node.get_class() == "Node3D" and String(node.name).begins_with(SOCKET_PREFIX):
			_to_marker(node as Node3D, scene)


static func ps2_material_from(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PS2_SHADER
	var tint := Color.WHITE
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		tint = b.albedo_color
		if b.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
		if b.emission_enabled:
			m.set_shader_parameter("emission_color", Vector3(b.emission.r, b.emission.g, b.emission.b) * b.emission_energy_multiplier)
	elif src is ShaderMaterial and (src as ShaderMaterial).shader == PS2_SHADER:
		return src as ShaderMaterial
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m


static func _convert(src: Material, converted: Dictionary) -> ShaderMaterial:
	if src == null:
		return ps2_material_from(null)
	if not converted.has(src):
		converted[src] = ps2_material_from(src)
	return converted[src]


static func _ps2_materials(mi: MeshInstance3D, converted: Dictionary) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var src := mi.get_surface_override_material(i)
		if src == null:
			src = mi.mesh.surface_get_material(i)
		mi.mesh.surface_set_material(i, _convert(src, converted))
		mi.set_surface_override_material(i, null)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _ps2_importer_materials(mi: ImporterMeshInstance3D, converted: Dictionary) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		mi.mesh.set_surface_material(i, _convert(mi.mesh.get_surface_material(i), converted))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _to_marker(node: Node3D, owner_root: Node) -> void:
	var marker := Marker3D.new()
	marker.name = String(node.name).substr(SOCKET_PREFIX.length())
	marker.transform = node.transform
	var parent := node.get_parent()
	var idx := node.get_index()
	parent.add_child(marker)
	parent.move_child(marker, idx)
	marker.owner = owner_root
	for c in node.get_children():
		node.remove_child(c)
		marker.add_child(c)
		_set_owner_recursive(c, owner_root)
	parent.remove_child(node)
	node.free()


static func _set_owner_recursive(n: Node, owner_root: Node) -> void:
	n.owner = owner_root
	for c in n.get_children():
		_set_owner_recursive(c, owner_root)


static func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var i := 0
	while i < out.size():
		out.append_array(out[i].get_children())
		i += 1
	return out
