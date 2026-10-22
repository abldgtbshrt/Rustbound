extends Node

## Minimal loot table interface.

@export var fallback_part_ids: Array[StringName] = ["core_scrapper", "leg_basic", "gun_nail"]

func roll_part_id(rng: RandomNumberGenerator, _context: Dictionary = {}) -> StringName:
	if fallback_part_ids.is_empty():
		return &""
	return fallback_part_ids[rng.randi_range(0, fallback_part_ids.size() - 1)]
