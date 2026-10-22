extends Node

## Root scene. The 3D game renders into a low-resolution SubViewport that is
## upscaled with nearest-neighbor filtering plus dithering (PS2 look). The HUD
## and menus are children of this node, so they live in the main window at
## full resolution and get GUI input normally. F4 toggles the effect.

## Vertical resolution the 3D view aims for (picks an integer shrink factor).
@export var target_lines: int = 360
@export var ps2_enabled: bool = true

@onready var container: SubViewportContainer = $Screen
@onready var game_viewport: SubViewport = $Screen/GameViewport

var _toggle_was_down := false


func _ready() -> void:
	get_window().size_changed.connect(_apply)
	_apply()


func _process(_delta: float) -> void:
	var down := Input.is_action_pressed("toggle_ps2")
	if down and not _toggle_was_down:
		ps2_enabled = not ps2_enabled
		_apply()
	_toggle_was_down = down


func get_shrink() -> int:
	if not ps2_enabled:
		return 1
	var h := get_window().size.y
	return clampi(int(round(float(h) / float(target_lines))), 1, 6)


func _apply() -> void:
	container.stretch_shrink = get_shrink()
	var mat := container.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("enabled", ps2_enabled)
