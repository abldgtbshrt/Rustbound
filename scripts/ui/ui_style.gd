class_name UiStyle
extends RefCounted

## Shared look for the HUD and menus: dark rust panels, chunky bars.

const BG := Color(0.09, 0.08, 0.07, 0.86)
const BORDER := Color(0.55, 0.38, 0.2)
const TEXT := Color(0.93, 0.88, 0.8)
const DIM := Color(0.65, 0.6, 0.55)
const ACCENT := Color(0.95, 0.6, 0.2)

const C_HP := Color(0.85, 0.3, 0.25)
const C_XP := Color(0.4, 0.85, 0.95)
const C_POWER := Color(0.95, 0.85, 0.3)
const C_HEAT := Color(0.95, 0.45, 0.2)
const C_CPU := Color(0.55, 0.75, 1.0)
const C_MASS := Color(0.7, 0.7, 0.65)
const C_TILT := Color(0.6, 0.95, 0.55)
const C_BAD := Color(1.0, 0.25, 0.2)

const SOCKET_COLORS := [Color(0.75, 0.75, 0.75), Color(0.95, 0.6, 0.2), Color(0.3, 0.85, 0.95), Color(0.45, 0.95, 0.4)]
const SOCKET_NAMES := ["Structural", "Mount", "Internal", "Locomotion"]


static func panel(border: Color = BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	return sb


static func bar(color: Color, min_size: Vector2 = Vector2(180, 12)) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = min_size
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.border_color = Color(0.3, 0.27, 0.24)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


static func set_bar_color(b: ProgressBar, color: Color) -> void:
	var fill := b.get_theme_stylebox("fill") as StyleBoxFlat
	if fill != null and fill.bg_color != color:
		fill = fill.duplicate()
		fill.bg_color = color
		b.add_theme_stylebox_override("fill", fill)


static func label(text: String = "", size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


## One-line-per-stat summary used on level-up cards and the build panel.
static func describe_part(p: PartData) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("%s  |  %s socket, size %d" % [PartData.Category.keys()[p.category].capitalize(), SOCKET_NAMES[int(p.attach_type)], p.attach_size])
	out.append("Mass %.1f" % p.mass)
	if p.hp > 0.0: out.append("+%d HP" % int(p.hp))
	if p.power_output > 0.0: out.append("+%.0f power" % p.power_output)
	if p.power_draw > 0.0: out.append("-%.0f power" % p.power_draw)
	if p.cpu_output > 0: out.append("+%d CPU" % p.cpu_output)
	if p.cpu_cost > 0: out.append("uses %d CPU" % p.cpu_cost)
	if p.top_speed > 0.0: out.append("speed %.0f  grip %.2f  carries %.0f" % [p.top_speed, p.grip, p.mass_capacity])
	if p.jump_force > 0.0: out.append("can jump")
	if p.stability > 0.0: out.append("+%d%% tip resistance" % int(p.stability * 100.0))
	if p.pickup_radius > 0.0: out.append("+%.0f m pickup radius" % p.pickup_radius)
	if p.heat_per_sec > 0.0: out.append("+%.1f heat/s" % p.heat_per_sec)
	if p.heat_capacity > 0.0: out.append("+%.0f heat capacity" % p.heat_capacity)
	if p.heat_dissipation > 0.0: out.append("+%.0f cooling/s" % p.heat_dissipation)
	if p.params.has("damage"):
		out.append("%.0f dmg x %.1f/s, range %.0f" % [float(p.params["damage"]), float(p.params.get("fire_rate", 1.0)), float(p.params.get("range", 0.0))])
	if float(p.params.get("heat_per_shot", 0.0)) > 0.0:
		out.append("%.1f heat/shot" % float(p.params["heat_per_shot"]))
	if not p.sockets.is_empty():
		out.append("%d socket(s) of its own" % p.sockets.size())
	if p.tags.has("anchored"):
		out.append("resists recoil")
	return out
