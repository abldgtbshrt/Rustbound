extends SceneTree

## Writes the reference assets in assets/parts/_examples/ and
## assets/enemies/_examples/: tiny models that follow the asset contract, for
## artists to open and copy, and for tests to run the import pipeline on.
##   godot --headless -s tools/pipeline/make_example_assets.gd


func _init() -> void:
	_part()
	_enemy()
	quit()


## 64 px checker, embedded in the .glb (Godot extracts it on import).
func _texture(a: Color, b: Color) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var stripe := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, a if stripe else b)
	return ImageTexture.create_from_image(img)


func _mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	return m


func _box(size: Vector3, at: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = at
	return mi


func _save(root: Node3D, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	print("%s: %s" % [path, "ok" if err == OK else error_string(err)])
	root.free()


## A small turret: origin at the attach point (bottom centre), front towards
## +Z like a model exported from Blender (the importer turns it to -Z), with a
## muzzle socket and a socket on top.
func _part() -> void:
	var dir := "res://assets/parts/_examples/example_turret/"
	DirAccess.make_dir_recursive_absolute(dir)
	var mat := _mat(_texture(Color(0.55, 0.5, 0.42), Color(0.35, 0.3, 0.26)))
	var root := Node3D.new()
	root.name = "ExampleTurret"
	root.add_child(_box(Vector3(0.5, 0.25, 0.5), Vector3(0, 0.125, 0), mat, "Base"))
	root.add_child(_box(Vector3(0.12, 0.12, 0.5), Vector3(0, 0.2, 0.35), mat, "Barrel"))
	var muzzle := Node3D.new()
	muzzle.name = "Socket_muzzle"
	muzzle.position = Vector3(0, 0.2, 0.6)
	root.add_child(muzzle)
	var top := Node3D.new()
	top.name = "Socket_top"
	top.position = Vector3(0, 0.25, 0)
	root.add_child(top)
	_save(root, dir + "example_turret.glb")


## A small bug: origin at its feet, front towards +Z (as exported).
func _enemy() -> void:
	var dir := "res://assets/enemies/_examples/example_bug/"
	DirAccess.make_dir_recursive_absolute(dir)
	var mat := _mat(_texture(Color(0.7, 0.25, 0.2), Color(0.45, 0.15, 0.12)))
	var root := Node3D.new()
	root.name = "ExampleBug"
	root.add_child(_box(Vector3(0.6, 0.35, 0.8), Vector3(0, 0.175, 0), mat, "Body"))
	root.add_child(_box(Vector3(0.3, 0.2, 0.25), Vector3(0, 0.25, 0.5), mat, "Head"))
	_save(root, dir + "example_bug.glb")
