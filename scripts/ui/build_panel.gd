class_name BuildPanel
extends CanvasLayer

## Side panel shown in build mode: the bench, the current selection and
## actions. Talks to a BuildMode node.

@export var build_mode_path: NodePath

var build_mode: BuildMode
var _panel: PanelContainer
var _bench_list: VBoxContainer
var _sel_title: Label
var _sel_info: Label
var _detach_btn: Button
var _scrap_btn: Button
var _auto_check: CheckBox
var _mirror_check: CheckBox
var _rot_label: Label


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_mode = get_node_or_null(build_mode_path) as BuildMode
	_build_ui()
	visible = false
	if build_mode != null:
		build_mode.toggled.connect(func(on: bool) -> void:
			visible = on
			_refresh())
		build_mode.selection_changed.connect(_refresh)
	RunState.inventory_changed.connect(_refresh)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ACCENT))
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -300
	_panel.offset_right = -14
	_panel.offset_top = 70
	_panel.offset_bottom = -200
	add_child(_panel)
	# Everything scrolls, so the panel never grows over the budget HUD.
	var outer := ScrollContainer.new()
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(outer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(col)

	col.add_child(UiStyle.label("BUILD MODE  (10% time)", 18, UiStyle.ACCENT))
	var help := UiStyle.label("Pick a bench part, hover a socket, Q/E rotate,\nclick to place. Click the robot to select a part.\nPink CoM, green footprint, cyan links,\norange weapon arcs, blue armor. [Tab] fight", 12, UiStyle.DIM)
	col.add_child(help)

	col.add_child(UiStyle.label("BENCH", 14, UiStyle.TEXT))
	_bench_list = VBoxContainer.new()
	_bench_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_bench_list)

	_sel_title = UiStyle.label("", 15, UiStyle.TEXT)
	col.add_child(_sel_title)
	_sel_info = UiStyle.label("", 12, UiStyle.DIM)
	_sel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_sel_info)

	var rot_row := HBoxContainer.new()
	var rl := UiStyle.button("[Q] <")
	rl.pressed.connect(func() -> void: build_mode.rotate_selection(-1))
	rot_row.add_child(rl)
	_rot_label = UiStyle.label("", 13)
	rot_row.add_child(_rot_label)
	var rr := UiStyle.button("> [E]")
	rr.pressed.connect(func() -> void: build_mode.rotate_selection(1))
	rot_row.add_child(rr)
	col.add_child(rot_row)

	var row := HBoxContainer.new()
	_detach_btn = UiStyle.button("Detach to bench")
	_detach_btn.pressed.connect(func() -> void: build_mode.detach_selected())
	row.add_child(_detach_btn)
	_scrap_btn = UiStyle.button("Scrap")
	_scrap_btn.pressed.connect(func() -> void: build_mode.scrap_selected())
	row.add_child(_scrap_btn)
	col.add_child(row)

	_auto_check = CheckBox.new()
	_auto_check.text = "Auto-install new parts"
	_auto_check.focus_mode = Control.FOCUS_NONE
	_auto_check.button_pressed = RunState.auto_install
	_auto_check.toggled.connect(func(on: bool) -> void: RunState.auto_install = on)
	col.add_child(_auto_check)

	_mirror_check = CheckBox.new()
	_mirror_check.text = "[M] Mirror placement"
	_mirror_check.focus_mode = Control.FOCUS_NONE
	_mirror_check.toggled.connect(func(on: bool) -> void: build_mode.set_mirror(on))
	col.add_child(_mirror_check)


func _refresh() -> void:
	if build_mode == null:
		return
	for c in _bench_list.get_children():
		c.queue_free()
	if RunState.inventory.is_empty():
		_bench_list.add_child(UiStyle.label("(empty - detach parts or pick some up)", 12, UiStyle.DIM))
	for i in RunState.inventory.size():
		var p := RunState.inventory[i]
		var fits := build_mode.get_compatible_sockets(p).size()
		var b := UiStyle.button("%s   m%.1f   %s" % [p.get_display_name(), p.mass, ("%d socket(s)" % fits) if fits > 0 else "no socket"], 13)
		b.toggle_mode = true
		b.button_pressed = i == build_mode.selected_bench
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(build_mode.select_bench.bind(i))
		_bench_list.add_child(b)

	var sel_data: PartData = null
	var on_robot := false
	if build_mode.get_selected_bench_part() != null:
		sel_data = build_mode.get_selected_bench_part()
	elif build_mode.selected_part != null and is_instance_valid(build_mode.selected_part):
		sel_data = build_mode.selected_part.data
		on_robot = true
	if sel_data == null:
		_sel_title.text = "Nothing selected"
		_sel_info.text = ""
	else:
		_sel_title.text = sel_data.get_display_name() + ("  (on robot)" if on_robot else "  (bench)")
		var lines := UiStyle.describe_part(sel_data)
		if on_robot and RunState.robot != null:
			var asm := RunState.robot.assembly
			var names: PackedStringArray = []
			for n in asm.get_links(build_mode.selected_part):
				if not (n as PartInstance).data.neighbor_mods.is_empty():
					names.append((n as PartInstance).data.get_display_name())
			if not names.is_empty():
				lines.append("Linked to: " + ", ".join(names))
		_sel_info.text = "\n".join(lines)
	var is_root := on_robot and RunState.robot != null and build_mode.selected_part == RunState.robot.assembly.root
	_detach_btn.disabled = not on_robot or is_root
	_scrap_btn.disabled = sel_data == null or is_root
	_scrap_btn.text = "Scrap (+%d)" % sel_data.scrap_value if sel_data != null else "Scrap"
	_auto_check.set_pressed_no_signal(RunState.auto_install)
	_mirror_check.set_pressed_no_signal(build_mode.mirror)
	var yaw := build_mode.placement_yaw
	if on_robot:
		yaw = build_mode.selected_part.yaw_steps
	_rot_label.text = "  rotation %d°  " % (posmod(yaw, 8) * 45)
