class_name LevelUpScreen
extends CanvasLayer

## Pauses the game and offers 3 cards. Early on most cards upgrade parts you
## already have (Mk I -> V); new parts get more common as you level.
## Keys 1-3 or click; R skips for a repair.

signal choice_made(offer: Dictionary)

const CHOICES := 3
const REPAIR_FRAC := 0.3

## Each: { "kind": "upgrade" | "new", "part": PartData }
var offers: Array[Dictionary] = []
var _root: Control
var _cards: HBoxContainer
var _title: Label
var _rng := RandomNumberGenerator.new()
var _keys_down: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_rng.randomize()
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
	_roll()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _roll() -> void:
	var lvl := RunState.level - RunState.pending_levelups + 1
	offers = UpgradeOffers.roll(CHOICES, lvl, _rng)
	_fill_cards()


## index in offers, or -1 to take the repair instead.
func choose(index: int) -> void:
	if not visible:
		return
	var picked: Dictionary = {}
	if index >= 0 and index < offers.size():
		picked = offers[index]
		var p: PartData = picked["part"]
		if picked["kind"] == "upgrade":
			RunState.upgrade_part(p)
		else:
			RunState.acquire_part(p)
	else:
		var robot := RunState.robot
		if robot != null:
			robot.heal(robot.max_hp * REPAIR_FRAC)
		EventBus.message.emit("Repaired %d%%" % int(REPAIR_FRAC * 100.0))
	choice_made.emit(picked)
	RunState.consume_levelup()
	if RunState.pending_levelups > 0:
		_roll()
	else:
		close()


# Polled through the Input singleton so keys work no matter which viewport
# this layer renders into.
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
	_title.text = "LEVEL %d" % (RunState.level - RunState.pending_levelups + 1)
	if RunState.pending_levelups > 1:
		_title.text += "  (+%d more)" % (RunState.pending_levelups - 1)
	var asm: RobotAssembly = RunState.robot.assembly if RunState.robot != null else null
	for i in offers.size():
		var o := offers[i]
		var p: PartData = o["part"]
		var upgrade: bool = o["kind"] == "upgrade"
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.C_XP if upgrade else p.visual_color))
		card.custom_minimum_size = Vector2(250, 300)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		card.add_child(v)
		var t := RunState.get_tier(p.id)
		if upgrade:
			v.add_child(UiStyle.label("UPGRADE", 12, UiStyle.C_XP))
			v.add_child(UiStyle.label("[%d]  %s" % [i + 1, p.get_display_name()], 18))
			v.add_child(UiStyle.label("%s  ->  %s" % [PartData.tier_name(t), PartData.tier_name(t + 1)], 15, UiStyle.C_XP))
			for line in UpgradeOffers.describe_upgrade(p):
				v.add_child(UiStyle.label(line, 13, UiStyle.DIM))
			v.add_child(UiStyle.label("applies to every copy you own", 12, UiStyle.DIM))
		else:
			v.add_child(UiStyle.label("NEW PART", 12, UiStyle.ACCENT))
			v.add_child(UiStyle.label("[%d]  %s  %s" % [i + 1, p.get_display_name(), PartData.tier_name(t) if t > 1 else ""], 18))
			for line in UiStyle.describe_part(p):
				var l := UiStyle.label(line, 13, UiStyle.DIM)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				v.add_child(l)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(spacer)
		if not upgrade:
			var fit := "Goes to bench"
			if asm != null:
				var best := asm.find_best_socket(p)
				if best.is_empty():
					fit = "Goes to bench (no free socket)"
				elif RunState.auto_install:
					fit = "Installs on %s" % String(best[1])
			v.add_child(UiStyle.label(fit, 13, UiStyle.C_TILT))
		var pick := UiStyle.button("Upgrade" if upgrade else "Take")
		pick.pressed.connect(choose.bind(i))
		v.add_child(pick)
		_cards.add_child(card)
