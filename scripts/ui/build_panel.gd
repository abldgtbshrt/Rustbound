class_name BuildPanel
extends CanvasLayer

## Build mode side panel: the robot's drive status, the parts bench sorted
## into category tabs, a detail pane for whatever is selected (bench part or
## part on the robot), and the build actions.

@export var build_mode_path: NodePath

var build_mode: BuildMode
var group := "All"
var _panel: PanelContainer
var _tabs: TabBar
var _list: VBoxContainer
var _detail_title: Label
var _detail: Label
var _detach_btn: Button
var _scrap_btn: Button
var _melt_btn: Button
var _auto_check: CheckBox
var _mirror_check: CheckBox
var _rot_label: Label
var _title: Label
var _drive: Label


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
	_panel.offset_left = -430
	_panel.offset_right = -14
	_panel.offset_top = 64
	_panel.offset_bottom = -200
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size.x = 10
	_panel.add_child(col)

	var head := HBoxContainer.new()
	_title = UiStyle.label("BUILD MODE", 18, UiStyle.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(UiStyle.label("[Tab] fight", 12, UiStyle.DIM))
	col.add_child(head)
	_drive = UiStyle.label("", 13, UiStyle.C_TILT)
	_drive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_drive)

	# Bench, by category.
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.clip_tabs = true # never wider than the panel; arrows scroll the rest
	_tabs.add_theme_font_size_override("font_size", 12)
	for g in UiStyle.GROUPS:
		_tabs.add_tab(g)
	_tabs.tab_changed.connect(func(i: int) -> void:
		group = UiStyle.GROUPS[i]
		_refresh())
	col.add_child(_tabs)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size.y = 120
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list)

	# Detail pane.
	col.add_child(HSeparator.new())
	_detail_title = UiStyle.label("", 16, UiStyle.TEXT)
	col.add_child(_detail_title)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(detail_scroll)
	_detail = UiStyle.label("", 12, UiStyle.DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)

	# Actions.
	var rot_row := HBoxContainer.new()
	var rl := UiStyle.button("[Q] <", 12)
	rl.pressed.connect(func() -> void: build_mode.rotate_selection(-1))
	rot_row.add_child(rl)
	_rot_label = UiStyle.label("", 12)
	rot_row.add_child(_rot_label)
	var rr := UiStyle.button("> [E]", 12)
	rr.pressed.connect(func() -> void: build_mode.rotate_selection(1))
	rot_row.add_child(rr)
	_detach_btn = UiStyle.button("Detach", 12)
	_detach_btn.pressed.connect(func() -> void: build_mode.detach_selected())
	rot_row.add_child(_detach_btn)
	_scrap_btn = UiStyle.button("Scrap", 12)
	_scrap_btn.pressed.connect(func() -> void: build_mode.scrap_selected())
	rot_row.add_child(_scrap_btn)
	col.add_child(rot_row)

	_melt_btn = UiStyle.button("Melt into upgrade", 12)
	_melt_btn.pressed.connect(func() -> void:
		var i := build_mode.selected_bench
		if RunState.melt_into_upgrade(i):
			build_mode.select_bench(-1))
	col.add_child(_melt_btn)

	var row2 := HBoxContainer.new()
	var strip := UiStyle.button("Strip to chassis", 12)
	strip.pressed.connect(func() -> void: build_mode.strip_all())
	row2.add_child(strip)
	_mirror_check = CheckBox.new()
	_mirror_check.text = "[M] Mirror"
	_mirror_check.focus_mode = Control.FOCUS_NONE
	_mirror_check.add_theme_font_size_override("font_size", 12)
	_mirror_check.toggled.connect(func(on: bool) -> void: build_mode.set_mirror(on))
	row2.add_child(_mirror_check)
	_auto_check = CheckBox.new()
	_auto_check.text = "Auto-install level-ups"
	_auto_check.focus_mode = Control.FOCUS_NONE
	_auto_check.add_theme_font_size_override("font_size", 12)
	_auto_check.button_pressed = RunState.auto_install
	_auto_check.toggled.connect(func(on: bool) -> void: RunState.auto_install = on)
	row2.add_child(_auto_check)
	col.add_child(row2)


func _refresh() -> void:
	if build_mode == null:
		return
	var asm: RobotAssembly = RunState.robot.assembly if RunState.robot != null else null

	# Tab labels with counts; a * marks tabs holding new pickups.
	for i in UiStyle.GROUPS.size():
		var g: String = UiStyle.GROUPS[i]
		var n := 0
		var fresh := false
		for k in RunState.inventory.size():
			var p := RunState.inventory[k]
			if g == "All" or UiStyle.part_group(p) == g:
				n += 1
				fresh = fresh or RunState.is_new(k)
		var title := ("%s %d" % [g, n]) if n > 0 else g
		_tabs.set_tab_title(i, title + ("*" if fresh else ""))

	for c in _list.get_children():
		c.queue_free()
	var shown := 0
	for i in RunState.inventory.size():
		var p := RunState.inventory[i]
		if group != "All" and UiStyle.part_group(p) != group:
			continue
		shown += 1
		var t := RunState.get_tier(p.id)
		var fits := build_mode.get_compatible_sockets(p).size()
		var b := UiStyle.button("%s%s%s%s   %s" % ["NEW  " if RunState.is_new(i) else "", p.get_display_name(), ("  " + PartData.tier_name(t)) if t > 1 else "",
			"  (pair)" if p.paired else "", "" if fits > 0 else "- no free socket"], 13)
		b.toggle_mode = true
		b.button_pressed = i == build_mode.selected_bench
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size.x = 10
		b.add_theme_color_override("font_color", PartData.rarity_color(p.rarity))
		b.pressed.connect(build_mode.select_bench.bind(i))
		_list.add_child(b)
	if shown == 0:
		_list.add_child(UiStyle.label("Nothing here. Pick parts up in the world, or detach some.", 12, UiStyle.DIM))

	# Detail pane.
	var sel_data: PartData = null
	var on_robot := false
	if build_mode.get_selected_bench_part() != null:
		sel_data = build_mode.get_selected_bench_part()
	elif build_mode.selected_part != null and is_instance_valid(build_mode.selected_part):
		sel_data = build_mode.selected_part.data
		on_robot = true
	if sel_data == null:
		_detail_title.text = "Select a part"
		_detail.text = "Pick one from the bench, or click a part on the robot.\nHover a glowing socket to preview, Q/E to rotate, click to place.\nOverlays: pink = center of mass, green = footprint, cyan = links, orange = weapon arcs, blue = armor."
	else:
		var t := RunState.get_tier(sel_data.id)
		_detail_title.text = "%s  %s%s" % [sel_data.get_display_name(), PartData.tier_name(t), "  (on robot)" if on_robot else ""]
		_detail_title.add_theme_color_override("font_color", PartData.rarity_color(sel_data.rarity))
		var lines := PackedStringArray([UiStyle.part_group(sel_data).to_upper()])
		if not on_robot:
			# Most useful first: what it does to your drive, and where it fits.
			var pd := UiStyle.predict_drive(sel_data, asm)
			if pd != "":
				lines.append(pd)
			var fits := build_mode.get_compatible_sockets(sel_data).size()
			lines.append("Fits %d free socket(s) on your robot" % fits if fits > 0 else "No free socket on your robot right now")
		lines.append_array(UiStyle.describe_part(sel_data))
		if on_robot and asm != null:
			var names: PackedStringArray = []
			for n in asm.get_links(build_mode.selected_part):
				if not (n as PartInstance).data.neighbor_mods.is_empty():
					names.append((n as PartInstance).data.get_display_name())
			if not names.is_empty():
				lines.append("Linked to: " + ", ".join(names))
			if build_mode.is_locked(build_mode.selected_part):
				lines.append("Locked for this run")
			if sel_data.category == PartData.Category.CHASSIS:
				lines.append(String(sel_data.params.get("feature", "")))
		_detail.text = "\n".join(lines)

	var locked := on_robot and build_mode.is_locked(build_mode.selected_part)
	_detach_btn.disabled = not on_robot or locked
	_scrap_btn.disabled = sel_data == null or locked
	_scrap_btn.text = "Scrap +%d" % sel_data.scrap_value if sel_data != null else "Scrap"
	var melt_why := RunState.melt_block_reason(build_mode.selected_bench) if not on_robot else "select a spare copy on the bench"
	_melt_btn.disabled = melt_why != ""
	if sel_data != null and not on_robot and melt_why == "":
		var t := RunState.get_tier(sel_data.id)
		_melt_btn.text = "Melt spare into upgrade: %s -> %s" % [PartData.tier_name(t), PartData.tier_name(t + 1)]
	else:
		_melt_btn.text = "Melt into upgrade (%s)" % melt_why
	_auto_check.set_pressed_no_signal(RunState.auto_install)
	_mirror_check.set_pressed_no_signal(build_mode.mirror)
	if asm != null:
		var prof := asm.locomotion
		var chassis_name := asm.chassis.data.get_display_name() if asm.chassis != null else "no chassis"
		_drive.text = "%s  |  DRIVE: %s" % [chassis_name.to_upper(), prof.mode_name().to_upper()]
		if prof.conflict != "":
			_drive.text += "\nConflicting drive: " + prof.conflict
		_drive.add_theme_color_override("font_color", UiStyle.C_BAD if prof.conflict != "" else UiStyle.C_TILT)
	_title.text = "BUILD MODE  (%s)" % ("paused" if build_mode.pause_world else "%d%% time" % int(build_mode.time_scale * 100.0))
	var yaw := build_mode.placement_yaw
	if on_robot:
		yaw = build_mode.selected_part.yaw_steps
	_rot_label.text = " %d° " % (posmod(yaw, 8) * 45)
