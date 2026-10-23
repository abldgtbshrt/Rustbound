@tool
extends EditorPlugin

## Registers the model import step (ps2_scene_import.gd) and a
## Project > Tools > "Validate assets" menu item.

var _import: EditorScenePostImportPlugin


func _enter_tree() -> void:
	_import = preload("res://addons/rustbound_pipeline/ps2_scene_import.gd").new()
	add_scene_post_import_plugin(_import)
	add_tool_menu_item("Validate assets", _validate)


func _exit_tree() -> void:
	remove_scene_post_import_plugin(_import)
	remove_tool_menu_item("Validate assets")
	_import = null


func _validate() -> void:
	var report := AssetValidator.validate_all()
	print(AssetValidator.format_report(report))
	if report["errors"].is_empty():
		print("Assets OK (%d warning(s))" % report["warnings"].size())
	else:
		push_error("Asset validation failed: %d error(s). See the Output panel." % report["errors"].size())
