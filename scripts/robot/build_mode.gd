class_name BuildMode
extends Node3D

## Tab toggles a close-up assembly view while the world runs at 10% speed.
## Select a part on the bench, then click a glowing socket to attach it.
## Click a part on the robot to select it, then detach (to bench) or scrap it.
## Overlays show the center of mass and the support footprint, so the
## physical effect of each change is visible immediately.

signal toggled(active: bool)
signal selection_changed

@export var time_scale: float = 0.1
## Screen-space pick radius, in pixels of the 3D viewport.
@export var pick_radius_px: float = 22.0

var active: bool = false
## Index into RunState.inventory, or -1.
var selected_bench: int = -1
## A part on the robot, or null.
var selected_part: PartInstance

var _markers: Array[Dictionary] = [] # { node, inst, socket, compatible }
var _overlay := Node3D.new()
var _com_marker: MeshInstance3D
var _support_lines: MeshInstance3D
var _highlight_mat: ShaderMaterial
var _marker_mesh := SphereMesh.new()
var _toggle_was_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.name = "Overlay"
	_overlay.visible = false
	add_child(_overlay)

	_marker_mesh.radius = 0.09
	_marker_mesh.height = 0.18
	_marker_mesh.radial_segments = 8
	_marker_mesh.rings = 4

	_com_marker = MeshInstance3D.new()
	var com_mesh := SphereMesh.new()
	com_mesh.radius = 0.12
	com_mesh.height = 0.24
	_com_marker.mesh = com_mesh
	_com_marker.material_override = _flat_material(Color(1.0, 0.2, 0.9))
	_overlay.add_child(_com_marker)

	_support_lines = MeshInstance3D.new()
	_support_lines.mesh = ImmediateMesh.new()
	_support_lines.material_override = _flat_material(Color(0.45, 0.95, 0.4))
	_overlay.add_child(_support_lines)

	_highlight_mat = PartVisuals.material_for(Color.WHITE).duplicate() as ShaderMaterial
	_highlight_mat.set_shader_parameter("tint", Vector3(1.0, 0.9, 0.5))
	_highlight_mat.set_shader_parameter("emission_color", Vector3(0.6, 0.45, 0.1))

	RunState.inventory_changed.connect(_on_inventory_changed)


func _process(_delta: float) -> void:
	# Polled so Tab works regardless of which viewport has focus.
	var down := Input.is_action_pressed("build_mode")
	if down and not _toggle_was_down and not get_tree().paused:
		toggle()
	_toggle_was_down = down

	if not active:
		return
	var robot := RunState.robot
	if robot == null or not robot.alive:
		exit()
		return
	_update_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if not active or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pick_at((event as InputEventMouseButton).position)
		get_viewport().set_input_as_handled()


# --- Public API ---------------------------------------------------------------

func toggle() -> void:
	if active:
		exit()
	else:
		enter()


func enter() -> void:
	var robot := RunState.robot
	if active or robot == null or not robot.alive:
		return
	active = true
	Engine.time_scale = time_scale
	_overlay.visible = true
	if not robot.assembly.assembly_changed.is_connected(_rebuild_markers):
		robot.assembly.assembly_changed.connect(_rebuild_markers)
	_set_camera_build_view(true)
	_rebuild_markers()
	toggled.emit(true)


func exit() -> void:
	if not active:
		return
	active = false
	Engine.time_scale = 1.0
	_set_selected_part(null)
	selected_bench = -1
	_overlay.visible = false
	_clear_markers()
	_set_camera_build_view(false)
	var robot := RunState.robot
	if robot != null and robot.assembly.assembly_changed.is_connected(_rebuild_markers):
		robot.assembly.assembly_changed.disconnect(_rebuild_markers)
	toggled.emit(false)
	selection_changed.emit()


func select_bench(index: int) -> void:
	_set_selected_part(null)
	selected_bench = index if index >= 0 and index < RunState.inventory.size() else -1
	_rebuild_markers()
	selection_changed.emit()


func get_selected_bench_part() -> PartData:
	if selected_bench < 0 or selected_bench >= RunState.inventory.size():
		return null
	return RunState.inventory[selected_bench]


func select_part(inst: PartInstance) -> void:
	selected_bench = -1
	_set_selected_part(inst)
	_rebuild_markers()
	selection_changed.emit()


## Attaches the selected bench part to `socket_name` on `parent`.
func attach_selected(parent: PartInstance, socket_name: StringName) -> bool:
	var part := get_selected_bench_part()
	var robot := RunState.robot
	if part == null or robot == null:
		return false
	var inst := robot.assembly.attach(part, parent, socket_name)
	if inst == null:
		return false
	RunState.take_from_inventory(selected_bench)
	EventBus.message.emit("Attached %s to %s" % [part.get_display_name(), String(socket_name)])
	# Keep the same kind of part selected if there's another, for fast building.
	var next := RunState.inventory.find(part)
	selected_bench = next
	_rebuild_markers()
	selection_changed.emit()
	return true


## Moves a part (and everything on it) to the bench. Overflow is scrapped.
func detach_selected() -> bool:
	var robot := RunState.robot
	if selected_part == null or robot == null or selected_part == robot.assembly.root:
		return false
	var inst := selected_part
	_set_selected_part(null)
	var removed := robot.assembly.detach(inst)
	for p in removed:
		if not RunState.add_to_inventory(p):
			RunState.add_scrap(p.scrap_value)
			EventBus.message.emit("Bench full: %s salvaged" % p.get_display_name())
	EventBus.message.emit("Detached %d part(s) to bench" % removed.size())
	_rebuild_markers()
	selection_changed.emit()
	return not removed.is_empty()


func scrap_selected() -> bool:
	var robot := RunState.robot
	if robot == null:
		return false
	var total := 0
	if selected_bench >= 0:
		var p := RunState.take_from_inventory(selected_bench)
		if p == null:
			return false
		total = p.scrap_value
		selected_bench = -1
	elif selected_part != null and selected_part != robot.assembly.root:
		var inst := selected_part
		_set_selected_part(null)
		for p in robot.assembly.detach(inst):
			total += p.scrap_value
	else:
		return false
	RunState.add_scrap(total)
	EventBus.message.emit("Scrapped for +%d scrap" % total)
	_rebuild_markers()
	selection_changed.emit()
	return true


## Free sockets on the robot that `part` fits, as [PartInstance, SocketDef].
func get_compatible_sockets(part: PartData) -> Array:
	var out: Array = []
	var robot := RunState.robot
	if robot == null or part == null:
		return out
	for inst in robot.assembly.get_all_parts():
		for s in inst.get_free_sockets():
			if RobotAssembly.can_fit(part, s):
				out.append([inst, s])
	return out


## Click handling, in the 3D viewport's pixel coordinates.
func pick_at(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if get_selected_bench_part() != null:
		var best: Dictionary = {}
		var best_d := pick_radius_px
		for m in _markers:
			if not m["compatible"]:
				continue
			var wp: Vector3 = (m["node"] as Node3D).global_position
			if cam.is_position_behind(wp):
				continue
			var d := cam.unproject_position(wp).distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = m
		if not best.is_empty():
			attach_selected(best["inst"], (best["socket"] as SocketDef).marker_name)
			return
	# Otherwise select the robot part nearest the cursor.
	var robot := RunState.robot
	var best_part: PartInstance = null
	var best_pd := pick_radius_px * 1.6
	for inst in robot.assembly.get_all_parts():
		var wp := inst.get_mass_point_global()
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(screen_pos)
		if d < best_pd:
			best_pd = d
			best_part = inst
	select_part(best_part)


# --- Internals ----------------------------------------------------------------

func _set_camera_build_view(on: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.get_parent() is CameraRig:
		(cam.get_parent() as CameraRig).build_view = on


func _on_inventory_changed() -> void:
	if selected_bench >= RunState.inventory.size():
		selected_bench = -1
	if active:
		_rebuild_markers()
		selection_changed.emit()


func _set_selected_part(inst: PartInstance) -> void:
	if selected_part != null and is_instance_valid(selected_part):
		_apply_highlight(selected_part, false)
	selected_part = inst
	if selected_part != null:
		_apply_highlight(selected_part, true)


func _apply_highlight(inst: PartInstance, on: bool) -> void:
	if inst.visual == null:
		return
	var mi := inst.visual.get_node_or_null("Mesh") as MeshInstance3D
	if mi != null:
		mi.material_override = _highlight_mat if on else PartVisuals.material_for(inst.data.visual_color)


func _clear_markers() -> void:
	for m in _markers:
		(m["node"] as Node).queue_free()
	_markers.clear()


func _rebuild_markers() -> void:
	_clear_markers()
	if not active or RunState.robot == null:
		return
	var sel := get_selected_bench_part()
	for inst in RunState.robot.assembly.get_all_parts():
		for s in inst.get_free_sockets():
			var compatible := sel != null and RobotAssembly.can_fit(sel, s)
			var mi := MeshInstance3D.new()
			mi.mesh = _marker_mesh
			var col: Color = UiStyle.SOCKET_COLORS[clampi(s.type, 0, 3)]
			if sel != null and not compatible:
				col = Color(col.r, col.g, col.b, 0.25)
			mi.material_override = _flat_material(col)
			var sc := 1.0 + 0.5 * float(s.size - 1)
			if compatible:
				sc *= 1.8
			mi.scale = Vector3.ONE * sc
			_overlay.add_child(mi)
			_markers.append({"node": mi, "inst": inst, "socket": s, "compatible": compatible})
	_update_overlay()


func _update_overlay() -> void:
	var robot := RunState.robot
	if robot == null:
		return
	var asm := robot.assembly
	for m in _markers:
		var inst: PartInstance = m["inst"]
		if not is_instance_valid(inst):
			continue
		(m["node"] as Node3D).global_position = inst.global_transform * inst.get_socket_transform(m["socket"]).origin
	_com_marker.global_position = asm.to_global(asm.center_of_mass)

	# Support footprint rectangle on the ground (assembly space -> world).
	var im := _support_lines.mesh as ImmediateMesh
	im.clear_surfaces()
	var y := 0.03
	var a := asm.to_global(Vector3(asm.support_min.x, y, asm.support_min.y))
	var b := asm.to_global(Vector3(asm.support_max.x, y, asm.support_min.y))
	var c := asm.to_global(Vector3(asm.support_max.x, y, asm.support_max.y))
	var d := asm.to_global(Vector3(asm.support_min.x, y, asm.support_max.y))
	var com_ground := asm.to_global(Vector3(asm.center_of_mass.x, y, asm.center_of_mass.z))
	var com_top := _com_marker.global_position
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair in [[a, b], [b, c], [c, d], [d, a], [com_ground, com_top]]:
		im.surface_add_vertex(_support_lines.to_local(pair[0]))
		im.surface_add_vertex(_support_lines.to_local(pair[1]))
	im.surface_end()


static var _flat_cache: Dictionary = {}

static func _flat_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _flat_cache.has(key):
		return _flat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.no_depth_test = true
	m.render_priority = 10
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flat_cache[key] = m
	return m
