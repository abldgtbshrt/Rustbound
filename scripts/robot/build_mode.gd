class_name BuildMode
extends Node3D

## Tab toggles a close-up assembly view. The world pauses (pause_world), or
## runs at time_scale if that's turned off.
##
## - Pick a bench part, hover a socket to see a ghost, Q/E to rotate it in 45°
##   steps, click to attach. M toggles mirror placement: a second copy from the
##   bench goes on the mirrored socket, mirrored.
## - Click a part on the robot to select it; Q/E rotates it in place; detach
##   (to bench) or scrap it from the panel.
## - Overlays: center of mass (pink), support footprint (green), links between
##   parts (cyan), weapon arcs (orange) and armor arcs (blue).

signal toggled(active: bool)
signal selection_changed

## Stop the world entirely while building. Turn off to build in slow motion
## (time_scale) instead, as originally designed.
@export var pause_world: bool = true
@export var time_scale: float = 0.1
## Screen-space pick radius, in pixels of the 3D viewport.
@export var pick_radius_px: float = 22.0

var active: bool = false
## Index into RunState.inventory, or -1.
var selected_bench: int = -1
## A part on the robot, or null.
var selected_part: PartInstance
## Rotation (45° steps) the next placed part gets.
var placement_yaw: int = 0
var mirror: bool = false
## The compatible socket marker under the cursor, or {}.
var hovered: Dictionary = {}

var _markers: Array[Dictionary] = [] # { node, inst, socket, compatible }
var _overlay := Node3D.new()
var _com_marker: MeshInstance3D
var _lines: Dictionary = {} # "support"|"links"|"arcs"|"armor" -> MeshInstance3D
var _ghost: Node3D
var _ghost_part: PartData
var _highlight_mat: ShaderMaterial
var _ghost_mat: StandardMaterial3D
var _marker_mesh := SphereMesh.new()
var _keys_down: Dictionary = {}
var _paused_by_me := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.name = "Overlay"
	_overlay.visible = false
	add_child(_overlay)

	_marker_mesh.radius = 0.07
	_marker_mesh.height = 0.14
	_marker_mesh.radial_segments = 8
	_marker_mesh.rings = 4

	_com_marker = MeshInstance3D.new()
	var com_mesh := SphereMesh.new()
	com_mesh.radius = 0.12
	com_mesh.height = 0.24
	_com_marker.mesh = com_mesh
	_com_marker.material_override = _flat_material(Color(1.0, 0.2, 0.9))
	_overlay.add_child(_com_marker)

	for spec in [["support", Color(0.45, 0.95, 0.4)], ["links", UiStyle.C_LINK], ["arcs", UiStyle.C_ARC], ["armor", UiStyle.C_ARMOR]]:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = _flat_material(spec[1])
		_overlay.add_child(mi)
		_lines[spec[0]] = mi

	_highlight_mat = PartVisuals.material_for(Color.WHITE).duplicate() as ShaderMaterial
	_highlight_mat.set_shader_parameter("tint", Vector3(1.0, 0.9, 0.5))
	_highlight_mat.set_shader_parameter("emission_color", Vector3(0.6, 0.45, 0.1))

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.5, 1.0, 0.6, 0.45)
	_ghost_mat.no_depth_test = true

	RunState.inventory_changed.connect(_on_inventory_changed)


func _process(_delta: float) -> void:
	# Keys are polled so they work regardless of which viewport has focus.
	var can_act := not get_tree().paused or _paused_by_me
	if _pressed("build_mode") and can_act:
		toggle()
	if not active:
		return
	var robot := RunState.robot
	if robot == null or not robot.alive:
		exit()
		return
	if not get_tree().paused or _paused_by_me:
		if _pressed_key(KEY_Q):
			rotate_selection(-1)
		if _pressed_key(KEY_E):
			rotate_selection(1)
		if _pressed_key(KEY_M):
			set_mirror(not mirror)
		set_hover_at(get_viewport().get_mouse_position())
	_update_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if not active or (get_tree().paused and not _paused_by_me):
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
	if pause_world:
		get_tree().paused = true
		_paused_by_me = true
	else:
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
	if _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false
	_set_selected_part(null)
	selected_bench = -1
	hovered = {}
	_overlay.visible = false
	_clear_markers()
	_update_ghost()
	_set_camera_build_view(false)
	var robot := RunState.robot
	if robot != null and robot.assembly.assembly_changed.is_connected(_rebuild_markers):
		robot.assembly.assembly_changed.disconnect(_rebuild_markers)
	toggled.emit(false)
	selection_changed.emit()


func select_bench(index: int) -> void:
	_set_selected_part(null)
	selected_bench = index if index >= 0 and index < RunState.inventory.size() else -1
	hovered = {}
	_rebuild_markers()
	selection_changed.emit()


func get_selected_bench_part() -> PartData:
	if selected_bench < 0 or selected_bench >= RunState.inventory.size():
		return null
	return RunState.inventory[selected_bench]


func select_part(inst: PartInstance) -> void:
	selected_bench = -1
	hovered = {}
	_set_selected_part(inst)
	_rebuild_markers()
	selection_changed.emit()


func set_mirror(on: bool) -> void:
	mirror = on
	selection_changed.emit()


## Q/E: rotates the pending placement, or the selected part on the robot.
func rotate_selection(delta_steps: int) -> void:
	var robot := RunState.robot
	if get_selected_bench_part() != null:
		placement_yaw = posmod(placement_yaw + delta_steps, 8)
		_update_ghost()
	elif selected_part != null and robot != null and selected_part != robot.assembly.root:
		robot.assembly.rotate_part(selected_part, delta_steps)
		# Mirror the rotation onto the twin, if there is one.
		if mirror:
			var twin := _find_twin(selected_part)
			if twin != null:
				robot.assembly.rotate_part(twin, -delta_steps)
	selection_changed.emit()


## Attaches the selected bench part to `socket_name` on `parent` with the
## current placement rotation (and its mirror twin, when mirror is on).
func attach_selected(parent: PartInstance, socket_name: StringName) -> bool:
	var part := get_selected_bench_part()
	var robot := RunState.robot
	if part == null or robot == null:
		return false
	var asm := robot.assembly
	var socket := parent.data.get_socket(socket_name) if parent != null else null
	var twin_target: Array = []
	if mirror and socket != null and RunState.inventory.count(part) >= 2:
		twin_target = asm.find_mirror_socket(part, parent, socket)
	var inst := asm.attach(part, parent, socket_name, true, placement_yaw)
	if inst == null:
		return false
	RunState.take_from_inventory(selected_bench)
	var msg := "Attached %s" % part.get_display_name()
	if not twin_target.is_empty():
		var t_inst: PartInstance = twin_target[0]
		var t_sock: SocketDef = twin_target[1]
		if asm.attach(part, t_inst, t_sock.marker_name, true, -placement_yaw) != null:
			RunState.take_from_inventory(RunState.inventory.find(part))
			msg += " (mirrored pair)"
	EventBus.message.emit(msg)
	# Keep the same kind of part selected if there's another, for fast building.
	selected_bench = RunState.inventory.find(part)
	hovered = {}
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
		RunState.add_to_inventory(p, true) # detached parts always fit
	EventBus.message.emit("Detached %d part(s) to bench" % removed.size())
	_rebuild_markers()
	selection_changed.emit()
	return not removed.is_empty()


## Everything except the core goes to the bench, to rebuild from scratch.
func strip_all() -> int:
	var robot := RunState.robot
	if robot == null or robot.assembly.root == null:
		return 0
	_set_selected_part(null)
	selected_bench = -1
	var n := 0
	for child in robot.assembly.root.get_child_parts():
		for p in robot.assembly.detach(child):
			RunState.add_to_inventory(p, true)
			n += 1
	EventBus.message.emit("Stripped %d parts to the bench" % n)
	_rebuild_markers()
	selection_changed.emit()
	return n


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


## The compatible marker nearest `screen_pos` (3D viewport pixels), or {}.
func marker_at(screen_pos: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
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
	return best


func set_hover_at(screen_pos: Vector2) -> void:
	var m := marker_at(screen_pos) if get_selected_bench_part() != null else {}
	if m != hovered:
		hovered = m
		_update_ghost()


## Click handling, in the 3D viewport's pixel coordinates.
func pick_at(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if get_selected_bench_part() != null:
		var m := marker_at(screen_pos)
		if not m.is_empty():
			attach_selected(m["inst"], (m["socket"] as SocketDef).marker_name)
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

func _pressed(action: StringName) -> bool:
	var down := Input.is_action_pressed(action)
	var was: bool = _keys_down.get(action, false)
	_keys_down[action] = down
	return down and not was


func _pressed_key(key: Key) -> bool:
	var down := Input.is_physical_key_pressed(key)
	var was: bool = _keys_down.get(key, false)
	_keys_down[key] = down
	return down and not was


func _find_twin(inst: PartInstance) -> PartInstance:
	var robot := RunState.robot
	var asm := robot.assembly
	var mine := asm.to_local(inst.global_position)
	for other in asm.get_all_parts():
		if other == inst or other.data != inst.data:
			continue
		var p := asm.to_local(other.global_position)
		if p.distance_to(Vector3(-mine.x, mine.y, mine.z)) < 0.06:
			return other
	return null


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


func _update_ghost() -> void:
	var part := get_selected_bench_part()
	var want := part if active and part != null and not hovered.is_empty() else null
	if want != _ghost_part:
		if _ghost != null:
			_ghost.queue_free()
			_ghost = null
		_ghost_part = want
		if want != null:
			_ghost = PartVisuals.build(want)
			for mi in _ghost.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = _ghost_mat
			_overlay.add_child(_ghost)
	if _ghost != null and not hovered.is_empty():
		var inst: PartInstance = hovered["inst"]
		var s: SocketDef = hovered["socket"]
		_ghost.global_transform = inst.global_transform * inst.child_transform(s, placement_yaw)


func _clear_markers() -> void:
	for m in _markers:
		(m["node"] as Node).queue_free()
	_markers.clear()


func _rebuild_markers() -> void:
	_clear_markers()
	if not active or RunState.robot == null:
		_update_ghost()
		return
	var sel := get_selected_bench_part()
	for inst in RunState.robot.assembly.get_all_parts():
		for s in inst.get_free_sockets():
			var compatible := sel != null and RobotAssembly.can_fit(sel, s)
			if sel != null and not compatible:
				continue # only show where the selected part can go
			var mi := MeshInstance3D.new()
			mi.mesh = _marker_mesh
			var col: Color = UiStyle.SOCKET_COLORS[clampi(s.type, 0, 3)]
			mi.material_override = _flat_material(col)
			var sc := 1.0 + 0.4 * float(s.size - 1)
			if compatible:
				sc *= 1.7
			mi.scale = Vector3.ONE * sc
			_overlay.add_child(mi)
			_markers.append({"node": mi, "inst": inst, "socket": s, "compatible": compatible})
	_update_ghost()
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
	_update_ghost()

	# Support footprint rectangle + plumb line from the center of mass.
	var y := 0.03
	var a := asm.to_global(Vector3(asm.support_min.x, y, asm.support_min.y))
	var b := asm.to_global(Vector3(asm.support_max.x, y, asm.support_min.y))
	var c := asm.to_global(Vector3(asm.support_max.x, y, asm.support_max.y))
	var d := asm.to_global(Vector3(asm.support_min.x, y, asm.support_max.y))
	var com_ground := asm.to_global(Vector3(asm.center_of_mass.x, y, asm.center_of_mass.z))
	_draw("support", [a, b, b, c, c, d, d, a, com_ground, _com_marker.global_position])

	# Links between parts that modify each other.
	var link_pts: Array = []
	var seen: Dictionary = {}
	for inst in asm.links.keys():
		if not is_instance_valid(inst):
			continue
		for n in asm.links[inst]:
			var key := [inst.get_instance_id(), (n as Object).get_instance_id()]
			key.sort()
			if seen.has(key) or ((inst as PartInstance).data.neighbor_mods.is_empty() and (n as PartInstance).data.neighbor_mods.is_empty()):
				continue
			seen[key] = true
			link_pts.append((inst as PartInstance).get_mass_point_global())
			link_pts.append((n as PartInstance).get_mass_point_global())
	_draw("links", link_pts)

	# Weapon and armor arcs, drawn at ground level.
	var arc_pts: Array = []
	var armor_pts: Array = []
	for inst in asm.get_all_parts():
		var dd := inst.data
		if dd.params.has("arc_deg"):
			var r := minf(float(dd.params.get("reach", dd.params.get("range", 3.0))), 3.0)
			_arc(arc_pts, inst.global_position, inst.get_facing_global(), float(dd.params["arc_deg"]), r)
		if dd.armor_block > 0.0:
			_arc(armor_pts, inst.global_position, inst.get_facing_global(), dd.armor_arc_deg, 1.2)
	if _ghost != null and _ghost_part != null and _ghost_part.params.has("arc_deg"):
		var gf := -_ghost.global_basis.z
		gf.y = 0.0
		_arc(arc_pts, _ghost.global_position, gf.normalized(), float(_ghost_part.params["arc_deg"]), 4.0)
	_draw("arcs", arc_pts)
	_draw("armor", armor_pts)


## Appends line segments for a wedge (two edges + curved rim) to `pts`.
func _arc(pts: Array, origin: Vector3, facing: Vector3, arc_deg: float, radius: float) -> void:
	if facing == Vector3.ZERO:
		return
	var o := Vector3(origin.x, 0.05, origin.z)
	var half := deg_to_rad(arc_deg * 0.5)
	var steps := 10
	var prev := o + facing.rotated(Vector3.UP, -half) * radius
	pts.append(o)
	pts.append(prev)
	for k in range(1, steps + 1):
		var ang := lerpf(-half, half, float(k) / float(steps))
		var p := o + facing.rotated(Vector3.UP, ang) * radius
		pts.append(prev)
		pts.append(p)
		prev = p
	pts.append(o)
	pts.append(prev)


func _draw(key: String, pts: Array) -> void:
	var mi: MeshInstance3D = _lines[key]
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	if pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in pts:
		im.surface_add_vertex(mi.to_local(p))
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
