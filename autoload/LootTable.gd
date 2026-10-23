extends Node

## Loads every PartData in res://data/parts and rolls weighted drops.

const PARTS_DIR := "res://data/parts/"

## Used if the parts folder is empty.
@export var fallback_part_ids: Array[StringName] = [&"loco_biped_leg", &"gun_nail"]

var parts: Array[PartData] = []
var _by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	reload()


func reload() -> void:
	parts.clear()
	_by_id.clear()
	var dir := DirAccess.open(PARTS_DIR)
	if dir == null:
		push_warning("LootTable: %s not found" % PARTS_DIR)
		return
	for f in dir.get_files():
		# Exported builds list "x.tres.remap"; load() resolves the remap.
		var file := f.trim_suffix(".remap")
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res := load(PARTS_DIR + file)
		if res is PartData:
			parts.append(res)
			_by_id[res.id] = res


func reseed(p_seed: int) -> void:
	_rng.seed = p_seed ^ 0x5eed


func get_part(id: StringName) -> PartData:
	return _by_id.get(id, null)


func roll_part(context: Dictionary = {}) -> PartData:
	var total := 0.0
	for p in parts:
		total += _weight(p, context)
	if total <= 0.0:
		return null
	var r := _rng.randf() * total
	for p in parts:
		r -= _weight(p, context)
		if r <= 0.0:
			return p
	return parts.back()


## Up to `count` distinct parts for a level-up offer.
func roll_choices(count: int, context: Dictionary = {}) -> Array[PartData]:
	var out: Array[PartData] = []
	var attempts := 0
	while out.size() < count and attempts < count * 20:
		attempts += 1
		var p := roll_part(context)
		if p != null and not out.has(p):
			out.append(p)
	return out


## Kept for the original scaffold API.
func roll_part_id(rng: RandomNumberGenerator, context: Dictionary = {}) -> StringName:
	if parts.is_empty():
		if fallback_part_ids.is_empty():
			return &""
		return fallback_part_ids[rng.randi_range(0, fallback_part_ids.size() - 1)]
	var p := roll_part(context)
	return p.id if p != null else &""


## Rarer parts drop less; uniques you already have never come back.
const RARITY_WEIGHT := [1.0, 0.35, 0.12]


func _weight(p: PartData, _context: Dictionary) -> float:
	if p.unique and RunState.uniques_taken.has(p.id):
		return 0.0
	return maxf(p.drop_weight, 0.0) * RARITY_WEIGHT[clampi(p.rarity, 0, 2)]
