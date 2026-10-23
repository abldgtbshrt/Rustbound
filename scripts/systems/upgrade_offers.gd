class_name UpgradeOffers
extends RefCounted

## Builds level-up offers. Early levels mostly upgrade what you already have,
## so the robot grows stronger before it grows chaotic; new parts become more
## common as you level.
## Each offer: { "kind": "upgrade" | "new", "part": PartData }

## Chance a card offers a new part at level 2, growing per level.
const NEW_PART_BASE := 0.08
const NEW_PART_PER_LEVEL := 0.04
const NEW_PART_MAX := 0.4


static func new_part_chance(level: int) -> float:
	return clampf(NEW_PART_BASE + NEW_PART_PER_LEVEL * float(level - 2), NEW_PART_BASE, NEW_PART_MAX)


## Distinct upgradable parts the player owns (robot + bench).
static func upgradable_owned() -> Array[PartData]:
	var out: Array[PartData] = []
	var pool: Array[PartData] = []
	if RunState.robot != null:
		for p in RunState.robot.assembly.get_all_parts():
			pool.append(p.data)
	pool.append_array(RunState.inventory)
	for d in pool:
		if RunState.can_upgrade(d) and not out.has(d):
			out.append(d)
	return out


static func roll(count: int, level: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var ups := upgradable_owned()
	ups.shuffle()
	var p_new := new_part_chance(level)
	var attempts := 0
	while offers.size() < count and attempts < count * 20:
		attempts += 1
		var want_new := ups.is_empty() or rng.randf() < p_new
		var offer: Dictionary = {}
		if want_new:
			var p := LootTable.roll_part()
			if p != null:
				offer = {"kind": "new", "part": p}
		else:
			offer = {"kind": "upgrade", "part": ups[rng.randi() % ups.size()]}
		if offer.is_empty() or _has(offers, offer):
			continue
		offers.append(offer)
	return offers


static func _has(offers: Array[Dictionary], o: Dictionary) -> bool:
	for x in offers:
		if x["kind"] == o["kind"] and x["part"] == o["part"]:
			return true
	return false


## "damage 11 -> 14" style lines for an upgrade card.
static func describe_upgrade(part: PartData) -> PackedStringArray:
	var out := PackedStringArray()
	var t := RunState.get_tier(part.id)
	for key in part.upgrade_per_tier.keys():
		var base := part.base_value(String(key))
		if base == 0.0:
			continue
		var a := part.scaled(String(key), base, t)
		var b := part.scaled(String(key), base, t + 1)
		if part.params.get(key) is int or String(key) == "cpu_output":
			a = round(a)
			b = round(b)
			if a == b:
				continue # whole-number stat that only ticks up every other Mk
		out.append("%s  %s -> %s" % [String(key).replace("_", " "), _fmt(a), _fmt(b)])
	return out


static func _fmt(v: float) -> String:
	return str(int(round(v))) if absf(v) >= 10.0 else ("%.2f" % v).rstrip("0").rstrip(".")
