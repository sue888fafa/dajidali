extends Node3D

const BLOCK_SIZE := 0.92
const LAYERS := 5
const WIDTH := 5
const DEPTH := 2
const STARTING_AMMO := 24
const BALL_SPEED := 18.0
const FLOOR_Y := -1.35
const LONG_PRESS_SECONDS := 0.18
const DRAG_THRESHOLD_PIXELS := 8.0
const ROTATION_SENSITIVITY_X := 0.01
const ROTATION_SENSITIVITY_Y := 0.007
const MAX_MODEL_PITCH := deg_to_rad(35.0)

var colors := [
    Color("#ff335f"),
    Color("#ffd400"),
    Color("#009cff"),
    Color("#a855f7"),
    Color("#00d084")
]

var blocks: Dictionary = {}
var block_color_ids: Dictionary = {}
var bullets: Array[Dictionary] = []
var color_targets := {0: 3, 1: 3, 2: 3}
var color_destroyed := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
var current_ball_color_id := 0
var next_ball_color_id := 0
var ammo := STARTING_AMMO
var score := 0
var combo := 0
var state := "playing"
var camera: Camera3D
var launch_anchor: Node3D
var current_ball_visual: MeshInstance3D
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

    model_root = Node3D.new()
    model_root.name = "ModelRoot"
    add_child(model_root)

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
    panel.size = Vector2(310, 188)
    layer.add_child(panel)

    ui["title"] = _label(layer, "BLOCKFALL CANNON", Vector2(42, 32), 24, Color("#ffffff"))
    ui["ammo"] = _label(layer, "炮弹：24", Vector2(42, 68), 20, Color("#ffd166"))
    ui["score"] = _label(layer, "得分：0    连击：0", Vector2(42, 96), 16, Color("#b9d7ff"))
    ui["current_ball"] = _label(layer, "当前：红色", Vector2(42, 128), 17, colors[0])
    ui["next_ball"] = _label(layer, "下一颗：红色", Vector2(42, 157), 17, colors[0].lightened(0.15))
    ui["target_red"] = _label(layer, "红色：0/3", Vector2(390, 28), 20, colors[0])
    ui["target_blue"] = _label(layer, "蓝色：0/3", Vector2(390, 58), 20, colors[2])
    ui["target_yellow"] = _label(layer, "黄色：0/3", Vector2(390, 88), 20, colors[1])
    ui["help"] = _label(layer, "鼠标瞄准 · 左键发射 · R 重置", Vector2(42, 665), 16, Color("#c5d4f2"))
    ui["status"] = _label(layer, "", Vector2(390, 600), 30, Color("#ffffff"))
    ui["combo"] = _label(layer, "", Vector2(390, 550), 22, Color("#ffd166"))

func _label(parent: Node, text: String, pos: Vector2, size: int, color: Color) -> Label:
    var label := Label.new()
    label.text = text
    label.position = pos
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
    return label

func _reset_level() -> void:
    for child in model_root.get_children():
        if child.name.begins_with("Block_"):
            child.queue_free()
    blocks.clear()
    block_color_ids.clear()
    for bullet in bullets:
        if is_instance_valid(bullet.node):
            bullet.node.queue_free()
    bullets.clear()
    ammo = STARTING_AMMO
    score = 0
    combo = 0
    color_destroyed = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
    current_ball_color_id = randi_range(0, colors.size() - 1)
    next_ball_color_id = randi_range(0, colors.size() - 1)
    state = "playing"
    status_time = 0.0
    mouse_was_down = false
    press_start_position = Vector2.ZERO
    press_start_time = 0.0
    is_rotating_model = false
    has_dragged = false
    model_yaw = 0.0
    model_pitch = 0.0
    model_root.rotation = Vector3.ZERO
    _create_blocks()
    _refresh_ball_ui()

func _create_blocks() -> void:
    for y in range(LAYERS):
        for x in range(WIDTH):
            for z in range(DEPTH):
                var coord := Vector3i(x - 2, y, z)
                var color_id := _color_for(coord)
                _spawn_block(coord, color_id)

func _color_for(coord: Vector3i) -> int:
    var fixed_clusters := {
        Vector3i(-1, 2, 0): 0,
        Vector3i(0, 2, 0): 0,
        Vector3i(1, 2, 0): 0,
        Vector3i(-2, 1, 0): 1,
        Vector3i(-2, 2, 0): 1,
        Vector3i(-2, 3, 0): 1,
        Vector3i(2, 1, 1): 2,
        Vector3i(2, 2, 1): 2,
        Vector3i(2, 3, 1): 2,
        Vector3i(-1, 4, 1): 3,
        Vector3i(0, 4, 1): 3,
        Vector3i(1, 4, 1): 3,
        Vector3i(-1, 0, 1): 4,
        Vector3i(0, 0, 1): 4,
        Vector3i(1, 0, 1): 4
    }
    if fixed_clusters.has(coord):
        return fixed_clusters[coord]
    var pattern := [0, 1, 2, 3, 4, 1, 2, 3, 4, 0]
    return pattern[absi(coord.x * 3 + coord.y * 2 + coord.z) % pattern.size()]

func _spawn_block(coord: Vector3i, color_id: int) -> void:
    var body := StaticBody3D.new()
    body.name = "Block_%d_%d_%d" % [coord.x, coord.y, coord.z]
    body.position = Vector3(coord.x, coord.y, coord.z) * BLOCK_SIZE
    body.set_meta("coord", coord)
    body.set_meta("color_id", color_id)
    body.set_meta("hp", 1)
    body.set_meta("base_color", colors[color_id])

    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE * (BLOCK_SIZE * 0.86)
    mesh_instance.mesh = mesh
    mesh_instance.material_override = _material(colors[color_id], 0.75, true)
    body.add_child(mesh_instance)

    _add_outline_edges(body)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3.ONE * (BLOCK_SIZE * 0.86)
    collision.shape = shape
    body.add_child(collision)
    model_root.add_child(body)
    blocks[coord] = body
    block_color_ids[coord] = color_id

func _add_outline_edges(parent: Node3D) -> void:
    var edge_material := _material(Color("#080d16"), 0.9)
    var extent := BLOCK_SIZE * 0.90
    var half := extent * 0.5
    var thickness := 0.035
    var edges := [
        {"size": Vector3(extent, thickness, thickness), "position": Vector3(0, half, half)},
        {"size": Vector3(extent, thickness, thickness), "position": Vector3(0, half, -half)},
        {"size": Vector3(extent, thickness, thickness), "position": Vector3(0, -half, half)},
        {"size": Vector3(extent, thickness, thickness), "position": Vector3(0, -half, -half)},
        {"size": Vector3(thickness, extent, thickness), "position": Vector3(half, 0, half)},
        {"size": Vector3(thickness, extent, thickness), "position": Vector3(half, 0, -half)},
        {"size": Vector3(thickness, extent, thickness), "position": Vector3(-half, 0, half)},
        {"size": Vector3(thickness, extent, thickness), "position": Vector3(-half, 0, -half)},
        {"size": Vector3(thickness, thickness, extent), "position": Vector3(half, half, 0)},
        {"size": Vector3(thickness, thickness, extent), "position": Vector3(half, -half, 0)},
        {"size": Vector3(thickness, thickness, extent), "position": Vector3(-half, half, 0)},
        {"size": Vector3(thickness, thickness, extent), "position": Vector3(-half, -half, 0)}
    ]
    for index in range(edges.size()):
        var edge := MeshInstance3D.new()
        edge.name = "OutlineEdge_%d" % index
        var edge_mesh := BoxMesh.new()
        edge_mesh.size = edges[index]["size"]
        edge.mesh = edge_mesh
        edge.material_override = edge_material
        edge.position = edges[index]["position"]
        parent.add_child(edge)

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
    return ["红色", "黄色", "蓝色", "紫色", "绿色"][color_id]

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
    var target := ray_origin + ray_direction * 20.0
    if abs(ray_direction.z) > 0.001:
        target = ray_origin + ray_direction * ((0.0 - ray_origin.z) / ray_direction.z)
    target.y = clamp(target.y, -0.5, 5.2)
    aim_target = target
    aim_marker.position = target

func _rotate_model(relative_motion: Vector2) -> void:
    model_yaw += relative_motion.x * ROTATION_SENSITIVITY_X
    model_pitch = clamp(model_pitch + relative_motion.y * ROTATION_SENSITIVITY_Y, -MAX_MODEL_PITCH, MAX_MODEL_PITCH)
    model_root.rotation = Vector3(model_pitch, model_yaw, 0.0)

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
    bullets.append({"node": ball, "velocity": direction * BALL_SPEED, "life": 3.0, "color_id": fired_color_id})
    current_ball_color_id = next_ball_color_id
    next_ball_color_id = randi_range(0, colors.size() - 1)
    _refresh_ball_ui()

func _update_bullets(delta: float) -> void:
    for index in range(bullets.size() - 1, -1, -1):
        var bullet: Dictionary = bullets[index]
        var ball: Node3D = bullet.node
        if not is_instance_valid(ball):
            bullets.remove_at(index)
            continue
        var start := ball.global_position
        var step: Vector3 = bullet.velocity * delta
        var query := PhysicsRayQueryParameters3D.create(start, start + step)
        query.exclude = [ball]
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if not hit.is_empty():
            var collider: Object = hit.collider
            if collider is StaticBody3D and collider.has_meta("coord"):
                _hit_block(collider, bullet["color_id"])
            ball.queue_free()
            bullets.remove_at(index)
            _check_state()
            continue
        ball.global_position += step
        bullet.life -= delta
        bullets[index] = bullet
        if bullet.life <= 0.0:
            ball.queue_free()
            bullets.remove_at(index)
            _check_state()

func _hit_block(block: StaticBody3D, bullet_color_id: int) -> void:
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
    status_time = 0.35
    ui["status"].text = "同色命中"
    var color_id: int = block.get_meta("color_id")
    var same_color_neighbors := _same_color_neighbors(coord, color_id)
    _flash_block(block, true)
    shake_time = 0.08
    shake_strength = 0.025
    _destroy_block(coord)
    if same_color_neighbors.size() < 2:
        status_time = 0.8
        ui["status"].text = "还需要两个相邻同色方块"
    else:
        _resolve_groups_and_support(same_color_neighbors, color_id)
    _check_state()

func _destroy_block(coord: Vector3i) -> void:
    if not blocks.has(coord):
        return
    var block: Node3D = blocks[coord]
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
        if blocks.has(neighbor) and blocks[neighbor].get_meta("color_id") == color_id:
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
            if blocks.has(neighbor) and not visited.has(neighbor) and blocks[neighbor].get_meta("color_id") == color_id:
                visited[neighbor] = true
                queue.append(neighbor)
    return connected

func _resolve_groups_and_support(seeds: Array[Vector3i], color_id: int) -> void:
    var match_group := _collect_connected_same_color(seeds, color_id)
    if match_group.size() < 2:
        return
    for coord in match_group:
        _destroy_block(coord)
    combo += 1
    score += match_group.size() * 25
    ui["combo"].text = "三消 x%d" % (match_group.size() + 1)
    shake_time = 0.18
    shake_strength = 0.05
    await get_tree().create_timer(0.08).timeout
    _remove_unsupported()

func _neighbors(coord: Vector3i) -> Array[Vector3i]:
    return [coord + Vector3i.LEFT, coord + Vector3i.RIGHT, coord + Vector3i.UP, coord + Vector3i.DOWN, coord + Vector3i(0, 0, 1), coord + Vector3i(0, 0, -1)]

func _remove_unsupported() -> void:
    var supported := {}
    var queue := []
    for coord in blocks.keys():
        if coord.y == 0:
            supported[coord] = true
            queue.append(coord)
    while not queue.is_empty():
        var current: Vector3i = queue.pop_front()
        for neighbor in _neighbors(current):
            if blocks.has(neighbor) and not supported.has(neighbor):
                supported[neighbor] = true
                queue.append(neighbor)
    var unsupported := []
    for coord in blocks.keys():
        if not supported.has(coord):
            unsupported.append(coord)
    for coord in unsupported:
        _destroy_block(coord)
    if unsupported.size() > 0:
        score += unsupported.size() * 15
        combo += 1
        shake_time = 0.3
        shake_strength = 0.07

func _check_state() -> void:
    _update_target_ui()
    if color_destroyed[0] >= color_targets[0] and color_destroyed[1] >= color_targets[1] and color_destroyed[2] >= color_targets[2]:
        state = "won"
        ui["status"].text = "通关！红、蓝、黄三色目标全部完成\n按 R 再来一局"
    elif ammo <= 0 and bullets.is_empty():
        state = "lost"
        ui["status"].text = "炮弹耗尽 · 按 R 重试"

func _update_target_ui() -> void:
    ui["target_red"].text = "红色：%d/%d" % [mini(color_destroyed[0], color_targets[0]), color_targets[0]]
    ui["target_blue"].text = "蓝色：%d/%d" % [mini(color_destroyed[2], color_targets[2]), color_targets[2]]
    ui["target_yellow"].text = "黄色：%d/%d" % [mini(color_destroyed[1], color_targets[1]), color_targets[1]]

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
