extends Node3D

const BLOCK_SIZE := 0.92
const STARTING_AMMO := 24
const BALL_SPEED := 18.0
const TRAIL_SEGMENTS := 12
const TRAIL_SPACING := 0.14
const FLOOR_Y := -1.35
const LONG_PRESS_SECONDS := 0.18
const DRAG_THRESHOLD_PIXELS := 8.0
const ROTATION_SENSITIVITY_X := 0.01
const ROTATION_SENSITIVITY_Y := 0.007

var colors: Array[Color] = [
	Color("#ff335f"),
	Color("#ffd400"),
	Color("#009cff"),
	Color("#a855f7"),
	Color("#00d084")
]
const COLOR_NAMES := ["红色", "黄色", "蓝色", "紫色", "绿色"]

var blocks: Dictionary = {}
var block_color_ids: Dictionary = {}
var dropped_blocks: Array[Node3D] = []
var bullets: Array[Dictionary] = []
var color_targets: Dictionary = {}
var color_destroyed := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
var current_ball_color_id := 0
var next_ball_color_id := 0
var ammo := STARTING_AMMO
var shots_fired := 0
var current_level := 0
var level_scene_paths: Array[String] = []
var current_level_instance: Node3D
var current_level_data: Node
var score := 0
var combo := 0
var state := "playing"
var camera: Camera3D
var launch_anchor: Node3D
var current_ball_visual: MeshInstance3D
var model_pivot: Node3D
var model_root: Node3D
var aim_marker: MeshInstance3D
var aim_target := Vector3.ZERO
var ui: Dictionary = {}
var shake_time := 0.0
var shake_strength := 0.0
var status_time := 0.0
var mouse_was_down := false
var press_start_position := Vector2.ZERO
var press_start_time := 0.0
var is_rotating_model := false
var has_dragged := false
var model_yaw := 0.0
var model_pitch := 0.0

func _ready() -> void:
	_build_world()
	_build_ui()
	_discover_level_scenes()
	_reset_level()

func _process(delta: float) -> void:
	_update_aim()
	_update_bullets(delta)
	_update_effects(delta)
	_update_ui()

func _physics_process(_delta: float) -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_reset_level()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_start_position = event.position
			press_start_time = Time.get_ticks_msec() / 1000.0
			is_rotating_model = false
			has_dragged = false
		else:
			var held_time: float = Time.get_ticks_msec() / 1000.0 - press_start_time
			if not is_rotating_model and not has_dragged and held_time < LONG_PRESS_SECONDS and event.position.distance_to(press_start_position) < DRAG_THRESHOLD_PIXELS:
				_fire(aim_target)
			is_rotating_model = false
			has_dragged = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var held_time: float = Time.get_ticks_msec() / 1000.0 - press_start_time
		var moved_distance: float = event.position.distance_to(press_start_position)
		if not has_dragged and (held_time >= LONG_PRESS_SECONDS or moved_distance >= DRAG_THRESHOLD_PIXELS):
			has_dragged = true
			is_rotating_model = true
			status_time = 0.3
			ui["status"].text = "查看模型"
		if is_rotating_model:
			_rotate_model(event.relative)
		get_viewport().set_input_as_handled()

func _build_world() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 3.5, 11.5)
	add_child(camera)
	camera.look_at(Vector3(0, 2.0, 0), Vector3.UP)

	var world_env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#0d1422")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#ffffff")
	environment.ambient_light_energy = 0.65
	world_env.environment = environment
	add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48, -25, 0)
	key_light.light_color = Color("#fff2d0")
	key_light.light_energy = 1.5
	key_light.shadow_enabled = true
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-5, 5, 6)
	fill_light.light_color = Color("#e8f1ff")
	fill_light.light_energy = 0.9
	fill_light.omni_range = 18.0
	add_child(fill_light)

	var floor := StaticBody3D.new()
	floor.name = "Floor"
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(18, 0.3, 18)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = _material(Color("#151a24"), 0.9)
	floor.add_child(floor_mesh)
	var floor_shape := CollisionShape3D.new()
	var floor_collision := BoxShape3D.new()
	floor_collision.size = Vector3(18, 0.3, 18)
	floor_shape.shape = floor_collision
	floor.add_child(floor_shape)
	floor.position.y = FLOOR_Y
	add_child(floor)

	launch_anchor = Node3D.new()
	launch_anchor.name = "LaunchAnchor"
	launch_anchor.position = Vector3(0, -0.6, 7.5)
	add_child(launch_anchor)
	current_ball_visual = MeshInstance3D.new()
	current_ball_visual.name = "CurrentBall"
	var current_ball_mesh := SphereMesh.new()
	current_ball_mesh.radius = 0.36
	current_ball_mesh.height = 0.72
	current_ball_visual.mesh = current_ball_mesh
	launch_anchor.add_child(current_ball_visual)

	model_pivot = Node3D.new()
	model_pivot.name = "ModelPivot"
	model_pivot.position = Vector3.ZERO
	add_child(model_pivot)

	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	model_root.position = Vector3.ZERO
	model_pivot.add_child(model_root)

	aim_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.11
	marker_mesh.height = 0.22
	aim_marker.mesh = marker_mesh
	aim_marker.material_override = _material(Color("#ffffff"), 0.1, true)
	add_child(aim_marker)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.02, 0.04, 0.1, 0.72)
	panel.position = Vector2(24, 20)
	panel.size = Vector2(310, 220)
	layer.add_child(panel)

	ui["title"] = _label(layer, "BLOCKFALL CANNON", Vector2(42, 32), 24, Color("#ffffff"))
	ui["ammo"] = _label(layer, "炮弹：24", Vector2(42, 68), 20, Color("#ffd166"))
	ui["score"] = _label(layer, "得分：0    连击：0", Vector2(42, 96), 16, Color("#b9d7ff"))
	ui["current_ball"] = _label(layer, "当前：红色", Vector2(42, 128), 17, colors[0])
	ui["next_ball"] = _label(layer, "下一颗：红色", Vector2(42, 157), 17, colors[0].lightened(0.15))
	ui["shots_fired"] = _label(layer, "发球次数：0", Vector2(42, 186), 17, Color("#b9d7ff"))
	ui["target_red"] = _label(layer, "红色：0/3", Vector2(390, 28), 20, colors[0])
	ui["target_blue"] = _label(layer, "蓝色：0/3", Vector2(390, 58), 20, colors[2])
	ui["target_yellow"] = _label(layer, "黄色：0/3", Vector2(390, 88), 20, colors[1])
	ui["target_purple"] = _label(layer, "紫色：0/0", Vector2(390, 148), 20, colors[3])
	ui["target_green"] = _label(layer, "绿色：0/0", Vector2(390, 178), 20, colors[4])
	ui["level"] = _label(layer, "第 1 / 3 关", Vector2(390, 118), 20, Color("#ffffff"))
	ui["help"] = _label(layer, "鼠标瞄准 · 左键发射 · R 重置", Vector2(42, 665), 16, Color("#c5d4f2"))
	ui["status"] = _label(layer, "", Vector2(390, 600), 30, Color("#ffffff"))
	var next_level_button := Button.new()
	next_level_button.name = "NextLevelButton"
	next_level_button.text = "开始下一关"
	next_level_button.position = Vector2(390, 640)
	next_level_button.size = Vector2(220, 44)
	next_level_button.visible = false
	next_level_button.pressed.connect(_on_next_level_pressed)
	layer.add_child(next_level_button)
	ui["next_level_button"] = next_level_button

func _label(parent: Node, text: String, pos: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _reset_level() -> void:
	_clear_dropped_blocks()
	_load_current_level()
	for bullet in bullets:
		_free_bullet_visuals(bullet)
	bullets.clear()
	ammo = _current_level_ammo()
	shots_fired = 0
	score = 0
	combo = 0
	color_destroyed = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	color_targets = _current_level_targets()
	var ball_sequence := _current_level_ball_sequence()
	if not ball_sequence.is_empty():
		current_ball_color_id = ball_sequence[0]
		next_ball_color_id = ball_sequence[1 % ball_sequence.size()]
	else:
		current_ball_color_id = _random_level_color()
		next_ball_color_id = _random_level_color()
	state = "playing"
	status_time = 0.0
	mouse_was_down = false
	press_start_position = Vector2.ZERO
	press_start_time = 0.0
	is_rotating_model = false
	has_dragged = false
	model_yaw = 0.0
	model_pitch = 0.0
	model_pivot.rotation = Vector3.ZERO
	ui["next_level_button"].hide()
	_refresh_ball_ui()
	_update_target_ui()

func _discover_level_scenes() -> void:
	level_scene_paths.clear()
	var directory := DirAccess.open("res://levels")
	if directory == null:
		return
	for filename in directory.get_files():
		if filename.begins_with("level_") and filename.ends_with(".tscn"):
			level_scene_paths.append("res://levels/" + filename)
	level_scene_paths.sort()

func _load_current_level() -> void:
	_clear_dropped_blocks()
	if is_instance_valid(current_level_instance):
		current_level_instance.queue_free()
		current_level_instance = null
	blocks.clear()
	block_color_ids.clear()
	model_pivot.position = Vector3.ZERO
	model_pivot.rotation = Vector3.ZERO
	model_root.position = Vector3.ZERO
	if level_scene_paths.is_empty():
		return
	current_level = clampi(current_level, 0, level_scene_paths.size() - 1)
	var packed_scene := load(level_scene_paths[current_level]) as PackedScene
	if packed_scene == null:
		return
	current_level_instance = packed_scene.instantiate() as Node3D
	model_root.add_child(current_level_instance)
	current_level_data = current_level_instance
	_collect_level_blocks(current_level_instance)
	_center_loaded_level()

func _collect_level_blocks(node: Node) -> void:
	if node is StaticBody3D and node.has_meta("coord"):
		var coord: Vector3i = node.get_meta("coord")
		blocks[coord] = node
		block_color_ids[coord] = node.get_meta("color_id")
	for child in node.get_children():
		_collect_level_blocks(child)

func _center_loaded_level() -> void:
	if blocks.is_empty():
		return
	var bounds := AABB()
	var has_bounds := false
	for block in blocks.values():
		var point: Vector3 = block.global_position
		if not has_bounds:
			bounds = AABB(point, Vector3.ZERO)
			has_bounds = true
		else:
			bounds = bounds.expand(point)
	var center := bounds.position + bounds.size * 0.5
	model_pivot.position = center
	model_root.position = -center

func _current_level_ammo() -> int:
	return int(current_level_data.get("ammo_limit")) if is_instance_valid(current_level_data) else STARTING_AMMO

func _current_level_targets() -> Dictionary:
	if not is_instance_valid(current_level_data):
		return {0: 3, 1: 3, 2: 3}
	return {
		0: int(current_level_data.get("target_red")),
		1: int(current_level_data.get("target_yellow")),
		2: int(current_level_data.get("target_blue")),
		3: int(current_level_data.get("target_purple")),
		4: int(current_level_data.get("target_green"))
	}

func _current_allowed_color_ids() -> Array[int]:
	if not is_instance_valid(current_level_data):
		return [0, 1, 2, 3, 4]
	var configured: Array = current_level_data.get("allowed_color_ids")
	var result: Array[int] = []
	for color_id in configured:
		result.append(int(color_id))
	return result if not result.is_empty() else [0, 1, 2, 3, 4]

func _current_level_ball_sequence() -> Array[int]:
	if not is_instance_valid(current_level_data):
		return []
	var configured: Array = current_level_data.get("ball_color_sequence")
	var result: Array[int] = []
	for value in configured:
		var color_id := _sequence_value_to_color_id(value)
		if color_id >= 0:
			result.append(color_id)
	return result

func _sequence_value_to_color_id(value: Variant) -> int:
	if value is int or value is float:
		var numeric_id := int(value)
		return numeric_id if numeric_id >= 0 and numeric_id < colors.size() else -1
	var text := String(value).strip_edges()
	if text.is_valid_int():
		var numeric_id := int(text)
		return numeric_id if numeric_id >= 0 and numeric_id < colors.size() else -1
	var name_index := COLOR_NAMES.find(text)
	return name_index if name_index >= 0 else -1

func _random_level_color() -> int:
	var allowed := _current_allowed_color_ids()
	return allowed[randi_range(0, allowed.size() - 1)]

func _material(color: Color, roughness: float, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.12
	return material

func _color_name(color_id: int) -> String:
	return COLOR_NAMES[color_id]

func _refresh_ball_ui() -> void:
	if not ui.has("current_ball"):
		return
	current_ball_visual.material_override = _material(colors[current_ball_color_id], 0.05, true)
	ui["current_ball"].text = "当前：%s" % _color_name(current_ball_color_id)
	ui["current_ball"].add_theme_color_override("font_color", colors[current_ball_color_id])
	ui["next_ball"].text = "下一颗：%s" % _color_name(next_ball_color_id)
	ui["next_ball"].add_theme_color_override("font_color", colors[next_ball_color_id].lightened(0.15))

func _update_aim() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(launch_anchor):
		return
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_direction := camera.project_ray_normal(mouse)
	var ray_end := ray_origin + ray_direction * 100.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3
	if not hit.is_empty() and hit.collider is StaticBody3D and hit.collider.has_meta("coord"):
		target = hit.position
	else:
		var model_center_z := model_pivot.global_position.z
		if abs(ray_direction.z) > 0.001:
			var distance_to_center_plane := (model_center_z - ray_origin.z) / ray_direction.z
			if distance_to_center_plane > 0.0:
				target = ray_origin + ray_direction * distance_to_center_plane
			else:
				target = ray_origin + ray_direction * 20.0
		else:
			target = ray_origin + ray_direction * 20.0
	aim_target = target
	aim_marker.position = target

func _rotate_model(relative_motion: Vector2) -> void:
	model_yaw += relative_motion.x * ROTATION_SENSITIVITY_X
	model_pitch -= relative_motion.y * ROTATION_SENSITIVITY_Y
	model_pivot.rotation = Vector3(model_pitch, model_yaw, 0.0)

func _fire(target: Vector3) -> void:
	if state != "playing" or ammo <= 0:
		return
	ammo -= 1
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	ball.mesh = sphere
	var fired_color_id := current_ball_color_id
	ball.material_override = _material(colors[fired_color_id], 0.05, true)
	add_child(ball)
	var origin := launch_anchor.global_position
	var direction := (target - origin).normalized()
	ball.global_position = origin
	var velocity := direction * BALL_SPEED
	var trail := _create_ball_trail(origin, colors[fired_color_id])
	bullets.append({"node": ball, "velocity": velocity, "life": 3.0, "color_id": fired_color_id, "trail": trail})
	shots_fired += 1
	current_ball_color_id = next_ball_color_id
	var ball_sequence := _current_level_ball_sequence()
	if not ball_sequence.is_empty():
		next_ball_color_id = ball_sequence[(shots_fired + 1) % ball_sequence.size()]
	else:
		next_ball_color_id = _random_level_color()
	_refresh_ball_ui()

func _update_bullets(delta: float) -> void:
	for index in range(bullets.size() - 1, -1, -1):
		var bullet: Dictionary = bullets[index]
		var ball: Node3D = bullet.node
		if not is_instance_valid(ball):
			_free_bullet_visuals(bullet)
			bullets.remove_at(index)
			continue
		var start := ball.global_position
		var step: Vector3 = bullet.velocity * delta
		var query := PhysicsRayQueryParameters3D.create(start, start + step)
		query.exclude = [ball]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var collider: Object = hit.collider
			var is_color_mismatch: bool = collider is StaticBody3D and collider.has_meta("coord") and collider.get_meta("color_id") != bullet["color_id"]
			if collider is StaticBody3D and collider.has_meta("coord"):
				_hit_block(collider, bullet["color_id"])
			if is_color_mismatch:
				_free_bullet_trail(bullet)
				_play_hard_impact(ball, hit["position"])
			else:
				_free_bullet_visuals(bullet)
			bullets.remove_at(index)
			_check_state()
			continue
		ball.global_position += step
		_update_ball_trail(bullet, ball.global_position)
		bullet.life -= delta
		bullets[index] = bullet
		if bullet.life <= 0.0:
			_free_bullet_visuals(bullet)
			bullets.remove_at(index)
			_check_state()

func _create_ball_trail(origin: Vector3, color: Color) -> Array[MeshInstance3D]:
	var trail: Array[MeshInstance3D] = []
	for index in range(TRAIL_SEGMENTS):
		var segment := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var size := 0.11 * (1.0 - float(index) / TRAIL_SEGMENTS * 0.65)
		mesh.radius = size
		mesh.height = size * 2.0
		segment.mesh = mesh
		var material := _material(color, 0.1, true)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.42 * (1.0 - float(index) / TRAIL_SEGMENTS * 0.75)
		segment.material_override = material
		segment.global_position = origin
		add_child(segment)
		trail.append(segment)
	return trail

func _update_ball_trail(bullet: Dictionary, ball_position: Vector3) -> void:
	var trail: Array = bullet["trail"]
	var direction: Vector3 = bullet["velocity"].normalized()
	for index in range(trail.size()):
		var segment: MeshInstance3D = trail[index]
		if is_instance_valid(segment):
			segment.global_position = ball_position - direction * TRAIL_SPACING * (index + 1)

func _free_bullet_visuals(bullet: Dictionary) -> void:
	if is_instance_valid(bullet.get("node")):
		bullet["node"].queue_free()
	_free_bullet_trail(bullet)

func _free_bullet_trail(bullet: Dictionary) -> void:
	for segment in bullet.get("trail", []):
		if is_instance_valid(segment):
			segment.queue_free()

func _play_hard_impact(ball: Node3D, impact_position: Vector3) -> void:
	if not is_instance_valid(ball):
		return
	ball.global_position = impact_position
	var impact_material := _material(Color.WHITE, 0.05, true)
	impact_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = impact_material
	ball.scale = Vector3.ONE
	var tween := create_tween()
	tween.tween_property(ball, "scale", Vector3(1.3, 0.5, 1.3), 0.06)
	tween.tween_property(ball, "scale", Vector3(0.72, 0.72, 0.72), 0.09)
	tween.parallel().tween_property(impact_material, "albedo_color", Color(1.0, 1.0, 1.0, 0.0), 0.15)
	tween.tween_callback(ball.queue_free)

func _hit_block(block: StaticBody3D, bullet_color_id: int) -> void:
	if not is_instance_valid(block):
		return
	if not blocks.has(block.get_meta("coord")):
		return
	var block_color_id: int = block.get_meta("color_id")
	if bullet_color_id != block_color_id:
		status_time = 0.45
		ui["status"].text = "颜色不匹配"
		shake_time = 0.05
		shake_strength = 0.012
		_spawn_burst(block.global_position, Color("#aab4c4"))
		return
	var coord: Vector3i = block.get_meta("coord")
	var color_id: int = block.get_meta("color_id")
	var same_color_neighbors := _same_color_neighbors(coord, color_id)
	_flash_block(block, true)
	shake_time = 0.08
	shake_strength = 0.025
	_destroy_block(coord)
	if same_color_neighbors.size() >= 2:
		_resolve_groups_and_support(same_color_neighbors, color_id)
	_check_state()

func _destroy_block(coord: Vector3i) -> void:
	var block := _get_valid_block(coord)
	if block == null:
		return
	blocks.erase(coord)
	var color_id: int = block.get_meta("color_id")
	block_color_ids.erase(coord)
	color_destroyed[color_id] += 1
	score += 10
	_spawn_burst(block.global_position, colors[color_id])
	block.queue_free()

func _same_color_neighbors(coord: Vector3i, color_id: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for neighbor in _neighbors(coord):
		var neighbor_block := _get_valid_block(neighbor)
		if neighbor_block != null and neighbor_block.get_meta("color_id") == color_id:
			result.append(neighbor)
	return result

func _collect_connected_same_color(seeds: Array[Vector3i], color_id: int) -> Array[Vector3i]:
	var connected: Array[Vector3i] = []
	var visited := {}
	var queue: Array[Vector3i] = []
	for seed in seeds:
		if blocks.has(seed) and not visited.has(seed):
			visited[seed] = true
			queue.append(seed)
	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		connected.append(current)
		for neighbor in _neighbors(current):
			var neighbor_block := _get_valid_block(neighbor)
			if neighbor_block != null and not visited.has(neighbor) and neighbor_block.get_meta("color_id") == color_id:
				visited[neighbor] = true
				queue.append(neighbor)
	return connected

func _get_valid_block(coord: Vector3i) -> StaticBody3D:
	if not blocks.has(coord):
		return null
	var block := blocks[coord] as StaticBody3D
	if is_instance_valid(block):
		return block
	blocks.erase(coord)
	block_color_ids.erase(coord)
	return null

func _resolve_groups_and_support(seeds: Array[Vector3i], color_id: int) -> void:
	var match_group := _collect_connected_same_color(seeds, color_id)
	if match_group.size() < 2:
		return
	for coord in match_group:
		_destroy_block(coord)
	var chain_clear_count := match_group.size() + 1
	combo += 1
	score += match_group.size() * 25
	shake_time = 0.18
	shake_strength = 0.05
	await get_tree().create_timer(0.08).timeout
	chain_clear_count += _remove_unsupported()
	_show_clear_rating(chain_clear_count)
	_check_state()

func _neighbors(coord: Vector3i) -> Array[Vector3i]:
	return [coord + Vector3i.LEFT, coord + Vector3i.RIGHT, coord + Vector3i.UP, coord + Vector3i.DOWN, coord + Vector3i(0, 0, 1), coord + Vector3i(0, 0, -1)]

func _remove_unsupported() -> int:
	var supported := {}
	var queue := []
	var block_coords := blocks.keys()
	for coord in block_coords:
		if _get_valid_block(coord) != null and coord.y == 0:
			supported[coord] = true
			queue.append(coord)
	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		for neighbor in _neighbors(current):
			if _get_valid_block(neighbor) != null and not supported.has(neighbor):
				supported[neighbor] = true
				queue.append(neighbor)
	var unsupported := []
	block_coords = blocks.keys()
	for coord in block_coords:
		if _get_valid_block(coord) != null and not supported.has(coord):
			unsupported.append(coord)
	for index in range(unsupported.size()):
		var coord: Vector3i = unsupported[index]
		var block := _get_valid_block(coord)
		if block != null:
			_drop_block(block, index)
	if unsupported.size() > 0:
		score += unsupported.size() * 15
		combo += 1
		shake_time = 0.3
		shake_strength = 0.07
	return unsupported.size()

func _drop_block(block: StaticBody3D, drop_index: int) -> void:
	if not is_instance_valid(block):
		return
	var coord: Vector3i = block.get_meta("coord")
	var color_id: int = int(block.get_meta("color_id"))
	blocks.erase(coord)
	block_color_ids.erase(coord)
	color_destroyed[color_id] += 1
	score += 10

	block.collision_layer = 0
	block.collision_mask = 0
	dropped_blocks.append(block)

	var mesh := block.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var material := mesh.material_override as StandardMaterial3D if mesh != null else null
	if material == null:
		material = _material(colors[color_id], 0.25, true)
		if mesh != null:
			mesh.material_override = material
	else:
		material = material.duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if mesh != null:
			mesh.material_override = material

	var start_position := block.global_position
	var drop_result := _find_drop_landing(start_position, block)
	var landing_position: Vector3 = drop_result["position"]
	var landing_rotation := block.global_rotation + Vector3(
		randf_range(-1.2, 1.2),
		randf_range(-1.2, 1.2),
		randf_range(-1.2, 1.2)
	)
	var fall_distance := absf(start_position.y - landing_position.y)
	var fall_duration := clampf(0.14 + fall_distance * 0.035, 0.14, 0.42)
	var faded_color := material.albedo_color
	faded_color.a = 0.0

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(minf(float(drop_index) * 0.025, 0.18))
	tween.tween_property(block, "global_position", landing_position, fall_duration)
	tween.parallel().tween_property(block, "global_rotation", landing_rotation, fall_duration)
	tween.tween_callback(_on_block_landed.bind(block, color_id))
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(block, "scale", Vector3(1.08, 0.45, 1.08), 0.06)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(block, "scale", Vector3.ZERO, 0.12)
	tween.parallel().tween_property(material, "albedo_color", faded_color, 0.12)
	tween.tween_callback(_finish_dropped_block.bind(block))

func _find_drop_landing(start_position: Vector3, block: StaticBody3D) -> Dictionary:
	var ground_position := start_position
	ground_position.y = FLOOR_Y + 0.15 + (BLOCK_SIZE * 0.86) * 0.5
	var ray_start := start_position + Vector3.UP * 0.05
	var ray_end := Vector3(start_position.x, FLOOR_Y - 1.0, start_position.z)
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1
	query.exclude = [block.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": ground_position, "hit_block": false}

	var collider := hit.get("collider") as Node
	if collider is StaticBody3D and _is_active_level_block(collider as StaticBody3D):
		var block_position: Vector3 = hit["position"]
		block_position.y += (BLOCK_SIZE * 0.86) * 0.5
		return {"position": block_position, "hit_block": true}
	return {"position": ground_position, "hit_block": false}

func _is_active_level_block(block: StaticBody3D) -> bool:
	if not is_instance_valid(block) or not block.has_meta("coord"):
		return false
	var coord: Vector3i = block.get_meta("coord")
	return _get_valid_block(coord) == block

func _on_block_landed(block: StaticBody3D, color_id: int) -> void:
	if is_instance_valid(block):
		_spawn_burst(block.global_position, colors[color_id].lightened(0.12))

func _finish_dropped_block(block: StaticBody3D) -> void:
	dropped_blocks.erase(block)
	if is_instance_valid(block):
		block.queue_free()

func _clear_dropped_blocks() -> void:
	for block in dropped_blocks:
		if is_instance_valid(block):
			block.queue_free()
	dropped_blocks.clear()

func _show_clear_rating(clear_count: int) -> void:
	if clear_count < 3:
		return
	var rating := "GOOD"
	if clear_count >= 5:
		rating = "EXCELLENT!"
	elif clear_count >= 4:
		rating = "GREAT"
	status_time = 0.9
	ui["status"].text = rating

func _check_state() -> void:
	_update_target_ui()
	if _targets_completed():
		state = "won"
		ui["status"].text = "第 %d 关通关！" % (current_level + 1)
		var next_level_button: Button = ui["next_level_button"]
		next_level_button.text = "开始下一关" if current_level < level_scene_paths.size() - 1 else "重新开始"
		next_level_button.show()
	elif ammo <= 0 and bullets.is_empty():
		state = "lost"
		ui["status"].text = "炮弹耗尽，任务未完成\n游戏失败"
		var retry_button: Button = ui["next_level_button"]
		retry_button.text = "重新开始本关"
		retry_button.show()

func _targets_completed() -> bool:
	for color_id in color_targets:
		if color_destroyed[color_id] < color_targets[color_id]:
			return false
	return true

func _on_next_level_pressed() -> void:
	if state == "lost":
		_reset_level()
		return
	if state != "won":
		return
	if current_level < level_scene_paths.size() - 1:
		current_level += 1
	else:
		current_level = 0
	_reset_level()

func _update_target_ui() -> void:
	ui["target_red"].text = "红色：%d/%d" % [_target_progress(0), color_targets.get(0, 0)]
	ui["target_blue"].text = "蓝色：%d/%d" % [_target_progress(2), color_targets.get(2, 0)]
	ui["target_yellow"].text = "黄色：%d/%d" % [_target_progress(1), color_targets.get(1, 0)]
	ui["target_purple"].text = "紫色：%d/%d" % [_target_progress(3), color_targets.get(3, 0)]
	ui["target_green"].text = "绿色：%d/%d" % [_target_progress(4), color_targets.get(4, 0)]

func _target_progress(color_id: int) -> int:
	return mini(color_destroyed.get(color_id, 0), color_targets.get(color_id, 0))

func _flash_block(block: StaticBody3D, destroyed: bool) -> void:
	var mesh := block.get_child(0) as MeshInstance3D
	if mesh == null:
		return
	var original := mesh.material_override
	mesh.material_override = _material(Color.WHITE, 0.05, true)
	await get_tree().create_timer(0.08 if destroyed else 0.12).timeout
	if is_instance_valid(mesh) and not destroyed:
		var damaged := block.get_meta("base_color") as Color
		mesh.material_override = _material(damaged.darkened(0.35), 0.3)

func _spawn_burst(position: Vector3, color: Color) -> void:
	for i in range(5):
		var shard := MeshInstance3D.new()
		var shard_mesh := BoxMesh.new()
		shard_mesh.size = Vector3.ONE * 0.12
		shard.mesh = shard_mesh
		shard.material_override = _material(color, 0.2, true)
		shard.position = position
		add_child(shard)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "position", position + Vector3(randf_range(-0.5, 0.5), randf_range(0.1, 0.8), randf_range(-0.5, 0.5)), 0.35)
		tween.tween_property(shard, "scale", Vector3.ZERO, 0.35)
		tween.chain().tween_callback(shard.queue_free)

func _update_effects(delta: float) -> void:
	if shake_time > 0.0:
		shake_time -= delta
		camera.position = Vector3(0, 3.5, 11.5) + Vector3(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength), 0)
	else:
		camera.position = Vector3(0, 3.5, 11.5)
	if status_time > 0.0:
		status_time -= delta
	elif state == "playing":
		ui["status"].text = ""

func _update_ui() -> void:
	if not ui.has("ammo"):
		return
	ui["ammo"].text = "炮弹：%d" % ammo
	ui["score"].text = "得分：%d    连击：%d" % [score, combo]
	ui["shots_fired"].text = "发球次数：%d" % shots_fired
	ui["level"].text = "第 %d / %d 关" % [current_level + 1, level_scene_paths.size()]
