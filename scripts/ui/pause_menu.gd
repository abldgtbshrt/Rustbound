class_name PauseMenu
extends CanvasLayer

## Esc pauses the run: resume, settings, restart, quit. Only opens when nothing
## else (level-up cards, chassis pick, build mode) is holding the pause.

const LINES_OPTIONS := [270, 360, 480]
const FPS_OPTIONS := [0, 30, 60, 120, 144]

var _root: Control
var _main_col: VBoxContainer
var _settings_col: VBoxContainer
var _was_down := false
var _paused_by_me := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_build_ui()
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible or get_tree().paused:
		return # someone else's modal owns the pause
	visible = true
	_paused_by_me = true
	get_tree().paused = true
	_show_settings(false)
	Sfx.play(&"ui_open")


func close() -> void:
	if not visible:
		return
	visible = false
	if _paused_by_me:
		get_tree().paused = false
	_paused_by_me = false
	Sfx.play(&"ui_close")


func toggle() -> void:
	if visible:
		if _settings_col.visible:
			_show_settings(false)
		else:
			close()
	else:
		open()


# Polled so Esc works whichever viewport has focus.
func _process(_delta: float) -> void:
	var down := Input.is_action_pressed("pause")
	if down and not _was_down:
		toggle()
	_was_down = down


func restart_run() -> void:
	close()
	get_tree().reload_current_scene()


func quit_game() -> void:
	get_tree().quit()


func _show_settings(on: bool) -> void:
	_main_col.visible = not on
	_settings_col.visible = on


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.ACCENT))
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	_main_col = VBoxContainer.new()
	_main_col.add_theme_constant_override("separation", 10)
	stack.add_child(_main_col)
	var title := UiStyle.label("PAUSED", 28, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_col.add_child(title)
	for spec in [["Resume  [Esc]", close], ["Settings", _show_settings.bind(true)], ["Restart run", restart_run], ["Quit to desktop", quit_game]]:
		var b := UiStyle.button(spec[0], 16)
		b.pressed.connect(spec[1])
		_main_col.add_child(b)

	_settings_col = VBoxContainer.new()
	_settings_col.add_theme_constant_override("separation", 8)
	stack.add_child(_settings_col)
	var st := UiStyle.label("SETTINGS", 22, UiStyle.ACCENT)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_col.add_child(st)
	for spec in [["Master volume", "volume_master"], ["Music volume", "volume_music"], ["Effects volume", "volume_sfx"], ["Interface volume", "volume_ui"]]:
		_settings_col.add_child(_slider_row(spec[0], spec[1]))
	_settings_col.add_child(_check_row("PS2 filter  [F4]", "ps2_filter"))
	_settings_col.add_child(_option_row("PS2 resolution", "ps2_lines", LINES_OPTIONS, func(v: int) -> String: return "%d lines" % v))
	_settings_col.add_child(_check_row("Fullscreen", "fullscreen"))
	_settings_col.add_child(_check_row("V-Sync", "vsync"))
	_settings_col.add_child(_option_row("FPS cap", "max_fps", FPS_OPTIONS, func(v: int) -> String: return "Unlimited" if v == 0 else str(v)))
	var row := HBoxContainer.new()
	var defaults := UiStyle.button("Defaults", 14)
	defaults.pressed.connect(func() -> void:
		Settings.reset_to_defaults()
		_refresh_controls())
	row.add_child(defaults)
	var back := UiStyle.button("Back", 14)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_show_settings.bind(false))
	row.add_child(back)
	_settings_col.add_child(row)


var _controls: Dictionary = {} # key -> Control


func _refresh_controls() -> void:
	for key in _controls:
		var c: Control = _controls[key]
		var v: Variant = Settings.get_value(key)
		if c is HSlider:
			(c as HSlider).set_value_no_signal(float(v))
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(v))
		elif c is OptionButton:
			var ob := c as OptionButton
			for i in ob.item_count:
				if ob.get_item_id(i) == int(v):
					ob.select(i)


func _slider_row(text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	var l := UiStyle.label(text, 14)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Settings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void: Settings.set_value(key, v))
	row.add_child(s)
	_controls[key] = s
	return row


func _check_row(text: String, key: String) -> Control:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 14)
	c.button_pressed = bool(Settings.get_value(key))
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	_controls[key] = c
	return c


func _option_row(text: String, key: String, options: Array, fmt: Callable) -> Control:
	var row := HBoxContainer.new()
	var l := UiStyle.label(text, 14)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for v in options:
		ob.add_item(fmt.call(v), v)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value(key, ob.get_item_id(i)))
	row.add_child(ob)
	_controls[key] = ob
	_refresh_controls.call_deferred()
	return row
