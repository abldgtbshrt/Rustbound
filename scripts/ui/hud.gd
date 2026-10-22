class_name Hud
extends CanvasLayer

## Run HUD: HP / XP, run stats, and the build budgets (power, heat, CPU, mass,
## tilt) as bars, so overloading on purpose is a readable choice.
## F3 toggles the detailed physics readout.

const MESSAGE_TIME := 3.0

var _hp_bar: ProgressBar
var _hp_text: Label
var _xp_bar: ProgressBar
var _lv_text: Label
var _run_text: Label
var _messages: Label
var _hint: Label
var _banner: Label
var _debug: Label
var _rows: Dictionary = {} # name -> { bar, value }
var _log: Array[Dictionary] = [] # { text, t }
var _debug_was_down := false
var _last_conflict := ""


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	EventBus.message.connect(_push)
	EventBus.robot_knocked_down.connect(func() -> void: _push("KNOCKED DOWN: too top-heavy for that move"))
	EventBus.robot_brownout.connect(func() -> void: _push("BROWNOUT: battery empty. Weapons stall, legs slow. Add a reactor or drop a gun"))
	EventBus.robot_power_restored.connect(func() -> void: _push("Power restored"))
	EventBus.robot_overheat.connect(func() -> void: _push("OVERHEAT: keep moving to cool, or vent with Shift"))
	EventBus.robot_vented.connect(func(amount: float, hits: int) -> void: _push("VENTED %d heat, scalded %d" % [int(amount), hits]))
	RunState.run_ended.connect(_on_run_ended)
	RunState.leveled_up.connect(func(l: int) -> void: _push("Level %d!" % l))


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top-left: HP and XP.
	var tl := VBoxContainer.new()
	tl.position = Vector2(14, 12)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	var hp_row := HBoxContainer.new()
	_hp_bar = UiStyle.bar(UiStyle.C_HP, Vector2(260, 16))
	hp_row.add_child(_hp_bar)
	_hp_text = UiStyle.label("", 14)
	hp_row.add_child(_hp_text)
	tl.add_child(hp_row)
	var xp_row := HBoxContainer.new()
	_xp_bar = UiStyle.bar(UiStyle.C_XP, Vector2(260, 8))
	xp_row.add_child(_xp_bar)
	_lv_text = UiStyle.label("", 13, UiStyle.C_XP)
	xp_row.add_child(_lv_text)
	tl.add_child(xp_row)
	_debug = UiStyle.label("", 12, UiStyle.DIM)
	_debug.visible = false
	tl.add_child(_debug)

	# Top-right: run stats.
	_run_text = UiStyle.label("", 15)
	_run_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_run_text.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_run_text.offset_left = -420
	_run_text.offset_right = -14
	_run_text.offset_top = 12
	root.add_child(_run_text)

	# Bottom-right: budgets.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -14
	panel.offset_bottom = -14
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	panel.add_child(grid)
	for spec in [["ENERGY", UiStyle.C_POWER], ["HEAT", UiStyle.C_HEAT], ["VENT", UiStyle.C_XP], ["CPU", UiStyle.C_CPU], ["MASS", UiStyle.C_MASS], ["TILT", UiStyle.C_TILT]]:
		grid.add_child(UiStyle.label(spec[0], 13, spec[1]))
		var b := UiStyle.bar(spec[1], Vector2(150, 10))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(b)
		var v := UiStyle.label("", 13)
		v.custom_minimum_size.x = 92
		grid.add_child(v)
		_rows[spec[0]] = {"bar": b, "value": v, "color": spec[1]}

	# Bottom-left: message log. Bottom-center: hint.
	_messages = UiStyle.label("", 14)
	_messages.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_messages.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_messages.offset_left = 14
	_messages.offset_top = -150
	_messages.offset_right = 620
	_messages.offset_bottom = -14
	root.add_child(_messages)

	_hint = UiStyle.label("", 15, UiStyle.ACCENT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -40
	_hint.offset_bottom = -16
	root.add_child(_hint)

	_banner = UiStyle.label("", 40, UiStyle.ACCENT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.visible = false
	root.add_child(_banner)


func _push(text: String) -> void:
	_log.append({"text": text, "t": MESSAGE_TIME})
	if _log.size() > 6:
		_log.pop_front()


func _on_run_ended(victory: bool) -> void:
	_banner.text = ("EXTRACTED" if victory else "SCRAPPED") + "\nlevel %d  -  %d kills\npress R to restart" % [RunState.level, RunState.kills]
	_banner.visible = true


func _set_row(row_name: String, frac: float, text: String, bad: bool) -> void:
	var r: Dictionary = _rows[row_name]
	var b: ProgressBar = r["bar"]
	b.max_value = 1.0
	b.value = clampf(frac, 0.0, 1.0)
	UiStyle.set_bar_color(b, UiStyle.C_BAD if bad else r["color"])
	(r["value"] as Label).text = text
	(r["value"] as Label).add_theme_color_override("font_color", UiStyle.C_BAD if bad else UiStyle.TEXT)


func _process(delta: float) -> void:
	var dbg := Input.is_action_pressed("toggle_debug")
	if dbg and not _debug_was_down:
		_debug.visible = not _debug.visible
	_debug_was_down = dbg

	var robot := RunState.robot
	if robot == null:
		return
	var a := robot.assembly
	var prof := a.locomotion

	_hp_bar.max_value = maxf(robot.max_hp, 1.0)
	_hp_bar.value = robot.hp
	_hp_text.text = " %d / %d" % [int(robot.hp), int(robot.max_hp)]
	_xp_bar.max_value = float(RunState.xp_to_next())
	_xp_bar.value = float(RunState.xp)
	_lv_text.text = " LV %d   %s" % [RunState.level, a.locomotion.mode_name().to_upper()]
	if a.locomotion.conflict != _last_conflict:
		_last_conflict = a.locomotion.conflict
		if _last_conflict != "":
			_push("Conflicting drive: " + _last_conflict)

	var t := int(RunState.elapsed_time)
	var enemies := RunState.enemies.alive_count() if RunState.enemies != null else 0
	_run_text.text = "%02d:%02d\nKILLS %d   SCRAP %d   ENEMIES %d" % [t / 60, t % 60, RunState.kills, RunState.scrap, enemies]

	var ecap := robot.get_energy_capacity()
	var oc := robot.get_overcharge_mult()
	var etext := "%+.0f/s" % robot.power_net
	if robot.browned_out:
		etext = "BROWNOUT"
	elif oc > 1.001:
		etext = "OVERCHARGE +%d%%" % int((oc - 1.0) * 100.0)
	_set_row("ENERGY", robot.energy / ecap, etext, robot.browned_out)
	UiStyle.set_bar_color(_rows["ENERGY"]["bar"], UiStyle.C_BAD if robot.browned_out else (UiStyle.C_XP if oc > 1.001 else UiStyle.C_POWER))
	var cap := robot.get_heat_capacity()
	_set_row("HEAT", robot.heat / cap, "%.0f / %.0f%s" % [robot.heat, cap, " HOT" if robot.is_overheated else ""], robot.is_overheated)
	var vent_text := "Shift"
	var vent_frac := 1.0
	if robot.vent_cooldown_left > 0.0:
		vent_frac = 1.0 - robot.vent_cooldown_left / maxf(robot.vent_cooldown, 0.01)
		vent_text = "%.1fs" % robot.vent_cooldown_left
	elif robot.heat < robot.vent_min_heat:
		vent_text = "need heat"
	else:
		vent_text = "Shift: r%.0fm" % robot.get_vent_radius(robot.heat)
	_set_row("VENT", vent_frac, vent_text, false)
	var pips := ""
	for i in maxi(a.cpu_capacity, 0):
		pips += "#" if i < a.cpu_used else "."
	var cpu_users := 0
	for p in a.get_all_parts():
		if p.data.cpu_cost > 0:
			cpu_users += 1
	var starved := cpu_users > 0 and a.cpu_used < cpu_users
	_set_row("CPU", float(a.cpu_used) / maxf(float(a.cpu_capacity), 1.0), "%d / %d %s" % [a.cpu_used, a.cpu_capacity, pips], starved)
	var load := robot.get_load_ratio()
	_set_row("MASS", load * 0.5, "%.1f / %.0f" % [a.total_mass, prof.mass_capacity], load > 1.0)
	_set_row("TILT", robot.tip_ratio, "DOWN" if robot.is_knocked_down else "%d%%" % int(robot.tip_ratio * 100.0), robot.tip_ratio > 0.8 or robot.is_knocked_down)

	var bench := RunState.inventory.size()
	var building := Engine.time_scale < 0.99 or (get_tree().paused and RunState.pending_levelups == 0)
	_hint.text = ("[Tab] build  -  %d part(s) on bench" % bench) if bench > 0 and not building else ""

	if _debug.visible:
		var loco := "%s, %d part(s)%s" % [prof.mode_name(), prof.part_count, (" [" + prof.conflict + "]") if prof.conflict != "" else ""]
		_debug.text = "\n".join([
			"parts %d   locomotion %s   speed %.1f m/s   grip %.2f   jump %s" % [a.part_count, loco, robot.get_top_speed(), prof.grip, ("%.1f" % prof.jump_force) if prof.can_jump else "no"],
			"CoM h %.2f side %+.2f   footprint %.2f   height %.2f   gyro +%d%%" % [a.center_of_mass.y, a.center_of_mass.x, a.footprint, a.height, int(a.stability * 100.0)],
			"heat +%.1f/s passive, -%.1f/s cooling (incl. airflow)   FPS %d" % [a.heat_passive, robot.get_heat_dissipation(), Engine.get_frames_per_second()],
			"power %.0f gen / %.0f draw   battery %.0f / %.0f   jets %.0f thrust (%.1f lift)" % [a.power_gen, a.power_draw, robot.energy, robot.get_energy_capacity(), a.jet_thrust, a.jet_thrust / robot.get_mass()],
		])

	var lines: Array[String] = []
	var k := _log.size() - 1
	while k >= 0:
		_log[k]["t"] = float(_log[k]["t"]) - delta / maxf(Engine.time_scale, 0.01)
		if float(_log[k]["t"]) <= 0.0:
			_log.remove_at(k)
		k -= 1
	for e in _log:
		lines.append(String(e["text"]))
	_messages.text = "\n".join(lines)
