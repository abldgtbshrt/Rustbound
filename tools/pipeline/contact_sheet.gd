extends Node

## Renders every part and enemy (authored model or placeholder) into one PNG,
## for reviewing art in a PR at a glance. Needs a real renderer, not
## --headless. Locally just run the scene; in CI:
##   xvfb-run godot --rendering-driver opengl3 res://tools/pipeline/contact_sheet.tscn -- --out=contact_sheet.png
## Default output: user://contact_sheet.png. A * after a name means it still
## uses the generated placeholder.

const TILE := 160
const COLUMNS := 8

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _label: Label


func _ready() -> void:
	var out := "user://contact_sheet.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_build_stage()
	var items := _items()
	var rows := ceili(float(items.size()) / COLUMNS)
	var sheet := Image.create(TILE * COLUMNS, TILE * maxi(rows, 1), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.11, 0.1))
	for k in items.size():
		var it: Dictionary = items[k]
		var img: Image = await _render(it["node"], it["label"])
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i((k % COLUMNS) * TILE, (k / COLUMNS) * TILE))
	var err := sheet.save_png(out)
	print("contact sheet: %d item(s) -> %s (%s)" % [items.size(), ProjectSettings.globalize_path(out), error_string(err)])
	get_tree().quit(0 if err == OK else 1)


func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parts: Array[PartData] = []
	for f in DirAccess.get_files_at("res://data/parts/"):
		var p := load("res://data/parts/" + f.trim_suffix(".remap")) as PartData
		if p != null:
			parts.append(p)
	parts.sort_custom(func(a: PartData, b: PartData) -> bool: return String(a.id) < String(b.id))
	for p in parts:
		out.append({"node": PartVisuals.build(p), "label": "%s%s" % [p.id, "" if p.scene != null else " *"]})
	for f in DirAccess.get_files_at("res://data/enemies/"):
		var e := load("res://data/enemies/" + f.trim_suffix(".remap")) as EnemyData
		if e == null:
			continue
		var mi := MeshInstance3D.new()
		var mesh := e.get_mesh()
		if mesh == null:
			var wedge := PrismMesh.new()
			wedge.size = Vector3(e.radius * 2.0, e.radius * 2.4, e.radius * 1.6)
			wedge.material = PartVisuals.material_for(e.color)
			mi.mesh = wedge
			mi.rotation_degrees.x = -90.0
			mi.position.y = e.radius
		else:
			mi.mesh = mesh
			mi.scale = Vector3.ONE * e.model_scale
		var holder := Node3D.new()
		holder.add_child(mi)
		out.append({"node": holder, "label": "enemy %s%s" % [e.id, "" if e.model != null else " *"]})
	# Reference models from the asset contract.
	for kind in ["parts", "enemies"]:
		var dir := "res://assets/%s/_examples/" % kind
		for sub in DirAccess.get_directories_at(dir):
			var path := "%s%s/%s.glb" % [dir, sub, sub]
			if ResourceLoader.exists(path):
				out.append({"node": (load(path) as PackedScene).instantiate(), "label": "example " + sub})
	return out


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(TILE, TILE)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.19, 0.18)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	_vp.add_child(sun)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_vp.add_child(_cam)
	var layer := CanvasLayer.new()
	_vp.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(4, TILE - 18)
	_label.add_theme_font_size_override("font_size", 11)
	layer.add_child(_label)


func _render(node: Node3D, text: String) -> Image:
	for c in _pivot.get_children():
		c.free()
	_pivot.add_child(node)
	var aabb: AABB = AssetValidator.measure(node)["aabb"]
	var size := maxf(aabb.size.length(), 0.3)
	var center := aabb.get_center()
	_cam.position = center + Vector3(1.0, 0.8, 1.2).normalized() * size * 1.6
	_cam.look_at(center, Vector3.UP)
	_label.text = text
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()
