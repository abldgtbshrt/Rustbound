class_name LevelUpScreen
extends CanvasLayer

## Pauses the game and offers 3 parts. The pick goes through
## RunState.acquire_part (auto-install, else bench). Keys 1-3 or click.

signal choice_made(part: PartData)

const CHOICES := 3
const REPAIR_FRAC := 0.3

var offers: Array[PartData] = []
var _root: Control
var _cards: HBoxContainer
var _title: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_ui()
	visible = false
	RunState.leveled_up.connect(_on_leveled_up)


func is_open() -> bool:
	return visible


func _on_leveled_up(_lvl: int) -> void:
	if not visible:
		open()


func open() -> void:
	if RunState.pending_levelups <= 0:
		return
	offers = LootTable.roll_choices(CHOICES)
	_fill_cards()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


## index in offers, or -1 to take the repair instead.
func choose(index: int) -> void:
	if not visible:
		return
	if index >= 0 and index < offers.size():
		var p := offers[index]
		RunState.acquire_part(p)
		choice_made.emit(p)
	else:
		var robot := RunState.robot
		if robot != null:
			robot.heal(robot.max_hp * REPAIR_FRAC)
		EventBus.message.emit("Repaired %d%%" % int(REPAIR_FRAC * 100.0))
		choice_made.emit(null)
	RunState.consume_levelup()
	if RunState.pending_levelups > 0:
		offers = LootTable.roll_choices(CHOICES)
		_fill_cards()
	else:
		close()


# Polled through the Input singleton so keys work no matter which viewport
# this layer renders into.
var _keys_down: Dictionary = {}


func _process(_delta: float) -> void:
	if not visible:
		_keys_down.clear()
		return
	for k in [KEY_1, KEY_2, KEY_3, KEY_R]:
		var down := Input.is_physical_key_pressed(k)
		if down and not _keys_down.get(k, false):
			_keys_down[k] = true
			choose(-1 if k == KEY_R else k - KEY_1)
			return
		_keys_down[k] = down


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	_title = UiStyle.label("LEVEL UP", 32, UiStyle.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	col.add_child(_cards)
	var repair := UiStyle.button("[R] Skip: repair %d%%" % int(REPAIR_FRAC * 100.0))
	repair.pressed.connect(choose.bind(-1))
	repair.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(repair)


func _fill_cards() -> void:
	for c in _cards.get_children():
		c.queue_free()
	_title.text = "LEVEL %d  -  pick a part%s" % [RunState.level - RunState.pending_levelups + 1,
		"  (+%d more)" % (RunState.pending_levelups - 1) if RunState.pending_levelups > 1 else ""]
	var asm: RobotAssembly = RunState.robot.assembly if RunState.robot != null else null
	for i in offers.size():
		var p := offers[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.panel(p.visual_color))
		card.custom_minimum_size = Vector2(250, 290)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		v.add_child(UiStyle.label("[%d]  %s" % [i + 1, p.get_display_name()], 18, UiStyle.TEXT))
		for line in UiStyle.describe_part(p):
			var l := UiStyle.label(line, 13, UiStyle.DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(l)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(spacer)
		var fit := ""
		if asm != null and RunState.auto_install and not asm.find_best_socket(p).is_empty():
			fit = "Installs on %s" % String(asm.find_best_socket(p)[1])
		else:
			fit = "Goes to bench (no free socket)" if asm != null and asm.find_best_socket(p).is_empty() else "Goes to bench"
		v.add_child(UiStyle.label(fit, 13, UiStyle.C_TILT))
		var pick := UiStyle.button("Take")
		pick.pressed.connect(choose.bind(i))
		v.add_child(pick)
		_cards.add_child(card)
