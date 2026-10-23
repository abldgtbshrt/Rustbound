class_name ChassisSelect
extends CanvasLayer

## Run start: pick a chassis. It sets the robot's shape, hardpoints, a unique
## feature and the starting loadout, and it's locked in for the whole run.
## Keys 1-4 or click.

signal chosen(chassis: PartData)

const ORDER := [&"chassis_box", &"chassis_tower", &"chassis_ring", &"chassis_spine"]

@export var open_on_start: bool = true

var choices: Array[PartData] = []
var _cards: HBoxContainer
var _keys_down: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	for id in ORDER:
		var p := LootTable.get_part(id)
		if p != null:
			choices.append(p)
	_build_ui()
	visible = false
	if open_on_start:
		open.call_deferred()


func is_open() -> bool:
	return visible


func open() -> void:
	if choices.is_empty() or RunState.robot == null:
		return
	visible = true
	get_tree().paused = true


func choose(index: int) -> void:
	if not visible or index < 0 or index >= choices.size():
		return
	var c := choices[index]
	var robot := RunState.robot
	robot.assembly.rebuild_with_chassis(c)
	robot.hp = robot.max_hp
	robot.energy = robot.get_energy_capacity()
	RunState.chassis_id = c.id
	EventBus.message.emit("%s chassis locked in. %s" % [c.get_display_name(), String(c.params.get("feature", ""))])
	visible = false
	get_tree().paused = false
	chosen.emit(c)


func _process(_delta: float) -> void:
	if not visible:
		return
	for k in [KEY_1, KEY_2, KEY_3, KEY_4]:
		var down := Input.is_physical_key_pressed(k)
		if down and not _keys_down.get(k, false):
			_keys_down[k] = true
			choose(k - KEY_1)
			return
		_keys_down[k] = down


static func socket_summary(c: PartData) -> String:
	var counts := [0, 0, 0, 0]
	for s in c.get_sockets():
		counts[s.type] += 1
	return "%d mounts  |  %d drive slots (%d pairs)  |  %d internal" % [counts[1], counts[3], counts[3] / 2, counts[2]]


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	var title := UiStyle.label("CHOOSE YOUR CHASSIS", 30, UiStyle.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := UiStyle.label("It's locked in for the whole run.", 14, UiStyle.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 12)
	col.add_child(_cards)
	for i in choices.size():
		var c := choices[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.panel(c.visual_color.lightened(0.2)))
		card.custom_minimum_size = Vector2(230, 300)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		v.add_child(UiStyle.label("[%d]  %s" % [i + 1, c.get_display_name()], 20))
		var feat := UiStyle.label(String(c.params.get("feature", "")), 13, UiStyle.TEXT)
		feat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(feat)
		var info := UiStyle.label("%s\nMass %.1f  |  HP %d" % [socket_summary(c), c.mass, int(c.hp * float(c.params.get("hp_mult", 1.0)))], 12, UiStyle.DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(info)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(spacer)
		var b := UiStyle.button("Take %s" % c.get_display_name())
		b.pressed.connect(choose.bind(i))
		v.add_child(b)
		_cards.add_child(card)
