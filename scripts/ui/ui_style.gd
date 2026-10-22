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
const C_LINK := Color(0.35, 0.95, 1.0)
const C_ARC := Color(1.0, 0.55, 0.25)
const C_ARMOR := Color(0.6, 0.7, 0.95)


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
	var types := [SOCKET_NAMES[int(p.attach_type)]]
	for t in p.alt_attach_types:
		types.append(SOCKET_NAMES[t])
	out.append("%s  |  %s socket, size %d" % [PartData.Category.keys()[p.category].capitalize(), " or ".join(types), p.attach_size])
	out.append(PartData.rarity_name(p.rarity) + ("  -  unique: one per run" if p.unique else ""))
	if p.drive != PartData.Drive.NONE:
		out.append(["", "Drive: legs (Walker). Put wheels/treads on its foot for Skater/Stomper", "Drive: wheels (Rover)", "Drive: treads (Tank)"][p.drive])
	var tier := RunState.get_tier(p.id)
	if tier > 1:
		out.append("%s (all copies)" % PartData.tier_name(tier))
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
	if p.energy_capacity > 0.0: out.append("+%.0f battery" % p.scaled("energy_capacity", p.energy_capacity, tier))
	if p.params.has("jet_thrust"): out.append("jet: hold jump to fly, %.0f thrust, %.0f energy/s" % [p.scaled("jet_thrust", float(p.params["jet_thrust"]), tier), float(p.params.get("jet_energy", 10.0))])
	if p.heat_per_sec > 0.0: out.append("+%.1f heat/s" % p.heat_per_sec)
	if p.heat_capacity > 0.0: out.append("+%.0f heat capacity" % p.heat_capacity)
	if p.heat_dissipation > 0.0: out.append("+%.0f cooling/s" % p.heat_dissipation)
	if p.params.has("reach"):
		out.append("melee %.0f dmg every %.1fs, reach %.1f m" % [float(p.params["damage"]), float(p.params.get("swing_time", 0.5)), float(p.params["reach"])])
	elif p.params.has("damage"):
		out.append("%.0f dmg x %.1f/s, range %.0f" % [float(p.params["damage"]), float(p.params.get("fire_rate", 1.0)), float(p.params.get("range", 0.0))])
	if p.params.has("arc_deg"):
		out.append("%.0f° arc in the direction it faces" % float(p.params["arc_deg"]))
	if p.armor_block > 0.0:
		out.append("blocks %d%% of hits from a %.0f° arc it faces" % [int(p.armor_block * 100.0), p.armor_arc_deg])
	if float(p.params.get("stomp", 0.0)) > 0.0: out.append("stomps on landing (heavier = harder)")
	if float(p.params.get("ram", 0.0)) > 0.0: out.append("rams enemies (faster = harder)")
	if float(p.params.get("crush", 0.0)) > 0.0: out.append("crushes small enemies")
	if p.drive == PartData.Drive.LEG: out.append("each leg past 2: +stability, -jump")
	if float(p.params.get("turn_rate_mult", 1.0)) != 1.0: out.append("+%d%% turn speed" % int((float(p.params["turn_rate_mult"]) - 1.0) * 100.0))
	if p.params.has("recover_pulse"): out.append("quick knockdown recovery + shockwave")
	if p.params.has("spin_deg_per_sec"): out.append("spins whatever is mounted on it")
	if p.params.has("pull_range"): out.append("pulls small enemies in its arc toward it; +%.0f m scrap pickup" % p.pickup_radius)
	if p.params.has("chains"): out.append("zaps the nearest enemy, arcs to %d more" % int(p.params["chains"]))
	if p.params.has("min_range") and p.params.has("flight_time"): out.append("lobs shells into crowds %.0f-%.0f m away" % [float(p.params["min_range"]), float(p.params["range"])])
	if p.params.has("shield_arc_deg"): out.append("energy shield: hits from its %.0f° arc drain battery, not HP" % float(p.params["shield_arc_deg"]))
	if p.params.has("heal_per_scrap"): out.append("bites what's in front; eats scrap to repair")
	for k in p.neighbor_mods.keys():
		out.append("linked parts: %s x%.2f" % [String(k).trim_suffix("_mult").replace("_", " "), float(p.neighbor_mods[k])])
	if float(p.params.get("heat_per_shot", 0.0)) > 0.0:
		out.append("%.1f heat/shot" % float(p.params["heat_per_shot"]))
	if not p.sockets.is_empty():
		out.append("%d socket(s) of its own" % p.sockets.size())
	if p.drive == PartData.Drive.TREAD:
		out.append("resists recoil")
	return out
