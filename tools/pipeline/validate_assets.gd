extends Node

## Headless asset check for CI:
##   godot --headless res://tools/pipeline/validate_assets.tscn
## Exit code 1 if any asset breaks the contract.


func _ready() -> void:
	var report := AssetValidator.validate_all()
	print(AssetValidator.format_report(report))
	get_tree().quit(1 if not report["errors"].is_empty() else 0)
