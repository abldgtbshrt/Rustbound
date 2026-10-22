extends Node

## Placeholder save/load interface for meta progression.

const SAVE_PATH := "user://meta_save.json"

func save_meta(data: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true

func load_meta() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	var parsed := JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
