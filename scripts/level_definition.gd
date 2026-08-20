@tool
extends Node3D

const BLOCK_SIZE := 0.92
const COLORS: Array[Color] = [
	Color("#ff335f"),
	Color("#ffd400"),
	Color("#009cff"),
	Color("#a855f7"),
	Color("#00d084")
]

@export_category("关卡规则")
@export var ammo_limit: int = 24
@export var allowed_color_ids: Array[int] = [0, 1, 2, 3, 4]
@export var target_red: int = 3
@export var target_yellow: int = 3
@export var target_blue: int = 3
@export var target_purple: int = 0
@export var target_green: int = 0
@export var ball_color_sequence: Array[String] = []

@export_category("默认布局")
@export var default_layers: int = 5
@export var default_width: int = 5
@export var default_depth: int = 2

func _ready() -> void:
	if get_child_count() == 0:
		_build_default_layout()

func _build_default_layout() -> void:
	var block_scene := load("res://scenes/level_block.tscn") as PackedScene
	if block_scene == null:
		return
	var owner_node: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	for y in range(default_layers):
		for x in range(default_width):
			for z in range(default_depth):
				var coord := Vector3i(x - floori(default_width * 0.5), y, z)
				var block := block_scene.instantiate() as Node3D
				block.name = "Block_%d_%d_%d" % [coord.x, coord.y, coord.z]
				block.position = Vector3(coord.x, coord.y, coord.z) * BLOCK_SIZE
				block.set("color_id", _default_color(coord))
				add_child(block)
				if owner_node != null:
					block.owner = owner_node

func _default_color(coord: Vector3i) -> int:
	var fixed_clusters := {
		Vector3i(-1, 2, 0): 0,
		Vector3i(0, 2, 0): 0,
		Vector3i(1, 2, 0): 0,
		Vector3i(-2, 1, 0): 1,
		Vector3i(-2, 2, 0): 1,
		Vector3i(-2, 3, 0): 1,
		Vector3i(2, 1, 1): 2,
		Vector3i(2, 2, 1): 2,
		Vector3i(2, 3, 1): 2
	}
	if fixed_clusters.has(coord) and allowed_color_ids.has(fixed_clusters[coord]):
		return fixed_clusters[coord]
	var safe_colors: Array[int] = allowed_color_ids.duplicate()
	if safe_colors.is_empty():
		safe_colors.append(0)
	return safe_colors[absi(coord.x * 3 + coord.y * 2 + coord.z) % safe_colors.size()]
