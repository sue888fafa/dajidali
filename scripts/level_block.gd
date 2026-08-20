@tool
extends StaticBody3D

const BLOCK_SIZE := 0.92
const COLORS: Array[Color] = [
	Color("#ff335f"),
	Color("#ffd400"),
	Color("#009cff"),
	Color("#a855f7"),
	Color("#00d084")
]

@export var snap_to_grid := true

@export_enum("红色:0", "黄色:1", "蓝色:2", "紫色:3", "绿色:4") var color_id: int = 0:
	set(value):
		color_id = clampi(value, 0, COLORS.size() - 1)
		_apply_color()

func _ready() -> void:
	add_to_group("level_block")
	set_notify_transform(true)
	_ensure_visuals()
	_apply_color()

func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED or not Engine.is_editor_hint():
		return
	if snap_to_grid:
		var snapped_position := Vector3(
			round(position.x / BLOCK_SIZE) * BLOCK_SIZE,
			round(position.y / BLOCK_SIZE) * BLOCK_SIZE,
			round(position.z / BLOCK_SIZE) * BLOCK_SIZE
		)
		if position != snapped_position:
			position = snapped_position
	_update_block_metadata()

func _ensure_visuals() -> void:
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		add_child(mesh_instance)
		if Engine.is_editor_hint() and owner != null:
			mesh_instance.owner = owner
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * (BLOCK_SIZE * 0.86)
		mesh_instance.mesh = mesh
	if get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = Vector3.ONE * (BLOCK_SIZE * 0.86)
		collision.shape = shape
		add_child(collision)
		if Engine.is_editor_hint() and owner != null:
			collision.owner = owner

func _apply_color() -> void:
	if not is_inside_tree():
		return
	var mesh_instance := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_instance == null:
		return
	var color: Color = COLORS[color_id]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.12
	mesh_instance.material_override = material
	_update_block_metadata()

func _update_block_metadata() -> void:
	set_meta("coord", Vector3i(
		roundi(position.x / BLOCK_SIZE),
		roundi(position.y / BLOCK_SIZE),
		roundi(position.z / BLOCK_SIZE)
	))
	set_meta("color_id", color_id)
	set_meta("base_color", COLORS[color_id])
	set_meta("hp", 1)
