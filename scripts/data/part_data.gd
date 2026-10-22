class_name PartData
extends Resource

enum Category {
	CORE,
	CHASSIS,
	LOCOMOTION,
	MOUNT,
	MODULE,
	HEAD,
	ADAPTER,
}

enum SocketType {
	STRUCTURAL,
	MOUNT,
	INTERNAL,
	LOCOMOTION,
}

@export var id: StringName
@export var display_name: String = ""
@export var category: Category = Category.MODULE
@export var scene: PackedScene

@export_group("Budgets")
@export var mass: float = 1.0
@export var power_draw: float = 0.0
@export var heat_per_sec: float = 0.0
@export var cpu_cost: int = 0

@export_group("Attachment")
@export var attach_type: SocketType = SocketType.STRUCTURAL
@export var sockets: Array[SocketDef] = []

@export_group("Customization")
@export_range(0, 4, 1) var component_slots: int = 1
@export var behaviors: Array[Script] = []
@export var tags: PackedStringArray = []
