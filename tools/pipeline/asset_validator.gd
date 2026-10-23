class_name AssetValidator
extends RefCounted

## Checks art and audio against the asset contract (CONTRIBUTING_ART.md).
## Runs from the editor (Project > Tools > Validate assets), headless in CI
## (tools/pipeline/validate_assets.tscn, exit code 1 on errors) and in tests.
##
## Errors break the build: budgets blown, sockets the code expects missing.
## Warnings are worth a look: odd scale, origin far from the attach point,
## files nobody references.

const PART_TRIS := 800
const ENEMY_TRIS := 400
const PROP_TRIS := 1500
const PART_TEX := 128
const ENEMY_TEX := 128
const MAX_PART_SIZE := 4.0 # metres, longest side
const MAX_SOUND_SECONDS := 3.0

const PARTS_DIR := "res://data/parts/"
const ENEMIES_DIR := "res://data/enemies/"
const ASSETS_DIR := "res://assets/"
const SFX_DIR := "res://assets/audio/sfx/"


## { "errors": PackedStringArray, "warnings": PackedStringArray, "checked": int }
static func validate_all() -> Dictionary:
	var report := {"errors": PackedStringArray(), "warnings": PackedStringArray(), "checked": 0}
	var part_ids: Dictionary = {}
	for path in _files(PARTS_DIR, ["tres"]):
		var p := load(path) as PartData
		if p == null:
			continue
		part_ids[String(p.id)] = true
		_merge(report, validate_part(p))
	var enemy_ids: Dictionary = {}
	for path in _files(ENEMIES_DIR, ["tres"]):
		var e := load(path) as EnemyData
		if e == null:
			continue
		enemy_ids[String(e.id)] = true
		_merge(report, validate_enemy(e))
	_merge(report, validate_layout(part_ids, enemy_ids))
	_merge(report, validate_sounds(part_ids))
	return report


static func validate_part(p: PartData) -> Dictionary:
	var r := _new_report()
	if p.scene == null:
		return r # placeholder visuals are generated in code
	r["checked"] = 1
	var tag := "part %s (%s)" % [p.id, p.scene.resource_path]
	var root := p.scene.instantiate()
	for n in _descendants(root):
		if n is CollisionObject3D:
			r["warnings"].append("%s: has a physics body '%s'; collision comes from code, remove '-col' style suffixes" % [tag, n.name])
			break
	if not root is Node3D:
		r["errors"].append("%s: root node must be a Node3D" % tag)
		root.free()
		return r
	var stats := measure(root as Node3D)
	if stats["tris"] > PART_TRIS:
		r["errors"].append("%s: %d triangles, budget is %d" % [tag, stats["tris"], PART_TRIS])
	if stats["tris"] == 0:
		r["errors"].append("%s: no visible mesh" % tag)
	for t in stats["textures"]:
		_check_texture(r, tag, t, PART_TEX)
	var size: Vector3 = (stats["aabb"] as AABB).size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest > MAX_PART_SIZE:
		r["warnings"].append("%s: %.1f m long; check the export scale (1 unit = 1 m)" % [tag, longest])
	elif stats["tris"] > 0 and longest < 0.05:
		r["warnings"].append("%s: only %.3f m long; check the export scale (1 unit = 1 m)" % [tag, longest])
	var gap := _distance_to_aabb(Vector3.ZERO, stats["aabb"])
	if stats["tris"] > 0 and gap > 0.25:
		r["warnings"].append("%s: the model is %.2f m away from its origin; the origin should be the attach point" % [tag, gap])
	var markers: Dictionary = stats["markers"]
	for s in p.sockets:
		if s.is_grid():
			continue
		if not markers.has(String(s.marker_name)):
			r["errors"].append("%s: socket '%s' has no marker. Add an empty named Socket_%s" % [tag, s.marker_name, s.marker_name])
	root.free()
	return r


static func validate_enemy(e: EnemyData) -> Dictionary:
	var r := _new_report()
	if e.model == null:
		return r
	r["checked"] = 1
	var tag := "enemy %s (%s)" % [e.id, e.model.resource_path]
	var mesh := e.get_mesh()
	if mesh == null or mesh.get_surface_count() == 0:
		r["errors"].append("%s: no mesh in the model" % tag)
		return r
	var tris := mesh.get_faces().size() / 3
	if tris > ENEMY_TRIS:
		r["errors"].append("%s: %d triangles, budget is %d (there can be hundreds on screen)" % [tag, tris, ENEMY_TRIS])
	if mesh.get_surface_count() > 2:
		r["warnings"].append("%s: %d materials; enemies should use one (two at most)" % [tag, mesh.get_surface_count()])
	for i in mesh.get_surface_count():
		for t in _material_textures(mesh.surface_get_material(i)):
			_check_texture(r, tag, t, ENEMY_TEX)
	var aabb := mesh.get_aabb()
	if aabb.position.y < -0.1 or aabb.position.y > 0.1:
		r["warnings"].append("%s: model's lowest point is at y=%.2f; its origin should be at its feet" % [tag, aabb.position.y])
	var height := aabb.size.y * e.model_scale
	if height > e.radius * 8.0 or height < e.radius * 0.5:
		r["warnings"].append("%s: %.2f m tall for a %.2f m collision radius; check model_scale" % [tag, height, e.radius])
	return r


## Folders under assets/parts and assets/enemies should be named after an id.
static func validate_layout(part_ids: Dictionary, enemy_ids: Dictionary) -> Dictionary:
	var r := _new_report()
	for spec in [["parts", part_ids], ["enemies", enemy_ids]]:
		var dir := ASSETS_DIR + String(spec[0]) + "/"
		for sub in DirAccess.get_directories_at(dir):
			if sub.begins_with("_"):
				continue # _examples and other non-game folders
			if not (spec[1] as Dictionary).has(sub):
				r["warnings"].append("assets/%s/%s: no %s with id '%s'" % [spec[0], sub, "part" if spec[0] == "parts" else "enemy", sub])
	return r


## Every sound file should be one the game asks for, and short.
static func validate_sounds(part_ids: Dictionary) -> Dictionary:
	var r := _new_report()
	var known: Dictionary = {}
	for k in preload("res://autoload/Sfx.gd").SOUNDS:
		known[String(k)] = true
	for path in _files(SFX_DIR, ["wav", "ogg"]):
		r["checked"] += 1
		var id := path.get_file().get_basename()
		var weapon := id.begins_with("fire_") and part_ids.has(id.substr(5))
		if not known.has(id) and not weapon:
			r["warnings"].append("%s: no sound id '%s' in Sfx.SOUNDS and no part '%s'; typo?" % [path, id, id.substr(5)])
		var s := load(path) as AudioStream
		if s == null:
			r["errors"].append("%s: not a readable audio file" % path)
		elif s.get_length() > MAX_SOUND_SECONDS:
			r["warnings"].append("%s: %.1f s long; one-shots should be under %.0f s" % [path, s.get_length(), MAX_SOUND_SECONDS])
	return r


## Triangles, textures, bounds and Marker3D names of a scene.
static func measure(root: Node3D) -> Dictionary:
	var tris := 0
	var textures: Array[Texture2D] = []
	var markers: Dictionary = {}
	var aabb := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Marker3D:
			markers[String(n.name)] = true
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			tris += mi.mesh.get_faces().size() / 3
			for i in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(i)
				if m == null:
					m = mi.mesh.surface_get_material(i)
				for t in _material_textures(m):
					if not textures.has(t):
						textures.append(t)
			var box := _relative_transform(root, mi) * mi.mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
	return {"tris": tris, "textures": textures, "markers": markers, "aabb": aabb}


static func format_report(report: Dictionary) -> String:
	var lines := PackedStringArray()
	for e in report["errors"]:
		lines.append("ERROR  " + e)
	for w in report["warnings"]:
		lines.append("WARN   " + w)
	lines.append("%d asset(s) checked: %d error(s), %d warning(s)" % [report["checked"], report["errors"].size(), report["warnings"].size()])
	return "\n".join(lines)


static func _check_texture(r: Dictionary, tag: String, t: Texture2D, limit: int) -> void:
	var w := t.get_width()
	var h := t.get_height()
	if w > limit or h > limit:
		r["errors"].append("%s: texture %s is %dx%d, limit is %d px" % [tag, t.resource_path, w, h, limit])
	elif w & (w - 1) != 0 or h & (h - 1) != 0:
		r["warnings"].append("%s: texture %s is %dx%d; use powers of two" % [tag, t.resource_path, w, h])


static func _material_textures(m: Material) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
		out.append((m as BaseMaterial3D).albedo_texture)
	elif m is ShaderMaterial:
		var t: Variant = (m as ShaderMaterial).get_shader_parameter("albedo_tex")
		if t is Texture2D:
			out.append(t)
	return out


static func _relative_transform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _distance_to_aabb(p: Vector3, box: AABB) -> float:
	var q := p.clamp(box.position, box.end)
	return p.distance_to(q)


static func _files(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		# Exported builds list "x.tres.remap" / imported files keep their name.
		var name := f.trim_suffix(".remap")
		if exts.has(name.get_extension()):
			out.append(dir + name)
	return out


static func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	var i := 0
	while i < out.size():
		out.append_array(out[i].get_children())
		i += 1
	return out


static func _new_report() -> Dictionary:
	return {"errors": PackedStringArray(), "warnings": PackedStringArray(), "checked": 0}


static func _merge(into: Dictionary, r: Dictionary) -> void:
	into["errors"].append_array(r["errors"])
	into["warnings"].append_array(r["warnings"])
	into["checked"] += r["checked"]
