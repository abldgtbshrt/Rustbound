class_name Hud
extends CanvasLayer

## Debug-style HUD: run stats, build budgets and the live physics readouts
## (center of mass, footprint, tip ratio) so build effects are visible.

const MESSAGE_TIME := 3.0

var _stats := Label.new()
var _build := Label.new()
var _messages := Label.new()
var _banner := Label.new()
var _tip_bar := ProgressBar.new()
var _hp_bar := ProgressBar.new()
var _log: Array[Dictionary] = [] # { text, t }


func _ready() -> void:
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 12)
	add_child(root)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root.add_child(col)

	_hp_bar.custom_minimum_size = Vector2(260, 14)
	_hp_bar.show_percentage = false
	_hp_bar.modulate = Color(1.0, 0.45, 0.35)
	col.add_child(_hp_bar)
	col.add_child(_stats)
	col.add_child(_build)

	var tip_row := HBoxContainer.new()
	var tip_label := Label.new()
	tip_label.text = "TILT "
	tip_row.add_child(tip_label)
	_tip_bar.custom_minimum_size = Vector2(200, 12)
	_tip_bar.max_value = 1.0
	_tip_bar.show_percentage = false
	tip_row.add_child(_tip_bar)
	col.add_child(tip_row)

	_messages.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_messages.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_messages.position = Vector2(12, -120)
	_messages.size = Vector2(600, 100)
	add_child(_messages)

	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.visible = false
	add_child(_banner)

	for l in [_stats, _build, _messages]:
		(l as Label).add_theme_font_size_override("font_size", 14)
		(l as Label).add_theme_color_override("font_outline_color", Color.BLACK)
		(l as Label).add_theme_constant_override("outline_size", 4)

	EventBus.message.connect(_push)
	EventBus.robot_knocked_down.connect(func() -> void: _push("KNOCKED DOWN: too top-heavy for that turn"))
	EventBus.robot_brownout.connect(func() -> void: _push("BROWNOUT: power draw exceeds generation"))
	RunState.run_ended.connect(_on_run_ended)


func _push(text: String) -> void:
	_log.append({"text": text, "t": MESSAGE_TIME})
	if _log.size() > 5:
		_log.pop_front()


func _on_run_ended(victory: bool) -> void:
	_banner.text = ("EXTRACTED" if victory else "SCRAPPED") + "\npress R to restart"
	_banner.visible = true
	_banner.position = get_viewport().get_visible_rect().size * 0.5 - _banner.size * 0.5


func _process(delta: float) -> void:
	var robot := RunState.robot
	if robot == null:
		return
	var a := robot.assembly
	var t := int(RunState.elapsed_time)
	var enemies := RunState.enemies.alive_count() if RunState.enemies != null else 0

	_hp_bar.max_value = maxf(robot.max_hp, 1.0)
	_hp_bar.value = robot.hp
	_stats.text = "HP %d/%d   SCRAP %d   KILLS %d   %02d:%02d   ENEMIES %d   FPS %d" % [
		int(robot.hp), int(robot.max_hp), RunState.scrap, RunState.kills, t / 60, t % 60,
		enemies, Engine.get_frames_per_second()]

	var prof := a.locomotion
	var loco := "ball (core only)" if prof.is_ball else "%d part(s)" % prof.part_count
	_build.text = "\n".join([
		"PARTS %d   LOCOMOTION %s" % [a.part_count, loco],
		"MASS %.1f / capacity %.1f  (%d%%)   speed %.1f m/s" % [a.total_mass, prof.mass_capacity, int(robot.get_load_ratio() * 100.0), robot.get_top_speed()],
		"POWER %.1f gen / %.1f draw%s   CPU %d / %d" % [a.power_gen, a.power_draw, "  BROWNOUT" if a.is_browned_out() else "", a.cpu_used, a.cpu_capacity],
		"CoM height %.2f  side %+.2f   footprint %.2f   height %.2f   gyro +%d%%" % [a.center_of_mass.y, a.center_of_mass.x, a.footprint, a.height, int(a.stability * 100.0)],
		"grip %.2f   jump %s" % [prof.grip, ("%.1f" % prof.jump_force) if prof.can_jump else "no"],
	])

	_tip_bar.value = clampf(robot.tip_ratio, 0.0, 1.0)
	_tip_bar.modulate = Color(1, 0.3, 0.3) if robot.tip_ratio > 0.8 or robot.is_knocked_down else Color(0.6, 1, 0.6)

	var lines: Array[String] = []
	var k := _log.size() - 1
	while k >= 0:
		_log[k]["t"] = float(_log[k]["t"]) - delta
		if float(_log[k]["t"]) <= 0.0:
			_log.remove_at(k)
		k -= 1
	for e in _log:
		lines.append(String(e["text"]))
	_messages.text = "\n".join(lines)
