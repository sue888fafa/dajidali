@tool
extends EditorPlugin

const BLOCK_SIZE := 0.92
const COLORS: Array[Color] = [
	Color("#ff335f"),
	Color("#ffd400"),
	Color("#009cff"),
	Color("#a855f7"),
	Color("#00d084")
]
const COLOR_NAMES := ["红色", "黄色", "蓝色", "紫色", "绿色"]
const LEVEL_SCRIPT := preload("res://scripts/level_definition.gd")
const BLOCK_SCENE := preload("res://scenes/level_block.tscn")

var panel: PanelContainer
var paint_toggle: CheckButton
var color_buttons: Array[Button] = []
var selected_color_id := 0
var stroke_active := false
var stroke_root: Node3D
var stroke_positions: Dictionary = {}

func _enter_tree() -> void:
	_build_panel()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, panel)

func _exit_tree() -> void:
	if is_instance_valid(panel):
		remove_control_from_docks(panel)
		panel.queue_free()
	panel = null

func _handles(_object: Object) -> bool:
	return _get_level_root() != null

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _is_painting() or camera == null:
		return AFTER_GUI_INPUT_PASS
	var level_root := _get_level_root()
	if level_root == null:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			stroke_active = true
			stroke_root = level_root
			stroke_positions.clear()
			_paint_at(camera, event.position)
			return AFTER_GUI_INPUT_STOP
		_commit_stroke()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and stroke_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_paint_at(camera, event.position)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "LevelPainterPanel"
	panel.custom_minimum_size = Vector2(180, 0)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)

	var title := Label.new()
	title.text = "关卡方块绘制"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	paint_toggle = CheckButton.new()
	paint_toggle.text = "绘制模式"
	paint_toggle.tooltip_text = "开启后，在3D视图点击或拖动生成方块"
	paint_toggle.toggled.connect(_on_paint_toggled)
	content.add_child(paint_toggle)

	var hint := Label.new()
	hint.text = "选择颜色后点击或拖动"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

	for index in range(COLORS.size()):
		var button := Button.new()
		button.text = COLOR_NAMES[index]
		button.tooltip_text = "使用%s绘制方块" % COLOR_NAMES[index]
		button.custom_minimum_size = Vector2(0, 32)
		button.modulate = COLORS[index].lightened(0.15)
		button.pressed.connect(_on_color_pressed.bind(index))
		content.add_child(button)
		color_buttons.append(button)
	_refresh_color_buttons()

func _on_paint_toggled(enabled: bool) -> void:
	if not enabled:
		_commit_stroke()
	_refresh_color_buttons()

func _on_color_pressed(color_id: int) -> void:
	selected_color_id = color_id
	_refresh_color_buttons()

func _refresh_color_buttons() -> void:
	for index in range(color_buttons.size()):
		var button := color_buttons[index]
		button.text = ("> " if index == selected_color_id else "") + COLOR_NAMES[index]

func _is_painting() -> bool:
	return is_instance_valid(paint_toggle) and paint_toggle.button_pressed and _get_level_root() != null

func _get_level_root() -> Node3D:
	var root := get_editor_interface().get_edited_scene_root()
	if root is Node3D and root.get_script() == LEVEL_SCRIPT:
		return root
	return null

func _get_layer_z(level_root: Node3D) -> float:
	var selection := get_editor_interface().get_selection()
	for node in selection.get_selected_nodes():
		if node is Node3D and node.is_in_group("level_block"):
			return level_root.to_local(node.global_position).z
	return 0.0

func _paint_at(camera: Camera3D, screen_position: Vector2) -> void:
	var level_root := stroke_root if is_instance_valid(stroke_root) else _get_level_root()
	if level_root == null:
		return
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	var layer_z := _get_layer_z(level_root)
	var plane_point := level_root.to_global(Vector3(0.0, 0.0, layer_z))
	var plane_normal := level_root.global_transform.basis * Vector3.FORWARD
	plane_normal = plane_normal.normalized()
	var denominator := plane_normal.dot(ray_direction)
	if abs(denominator) < 0.0001:
		return
	var distance := plane_normal.dot(plane_point - ray_origin) / denominator
	if distance <= 0.0:
		return
	var local_point := level_root.to_local(ray_origin + ray_direction * distance)
	var coord := Vector3i(
		roundi(local_point.x / BLOCK_SIZE),
		roundi(local_point.y / BLOCK_SIZE),
		roundi(layer_z / BLOCK_SIZE)
	)
	if stroke_positions.has(coord) or _find_block(level_root, coord) != null:
		return
	var position := Vector3(coord.x, coord.y, coord.z) * BLOCK_SIZE
	_add_block(level_root, position, selected_color_id)
	stroke_positions[coord] = position

func _add_block(level_root: Node3D, position: Vector3, color_id: int) -> Node3D:
	var block := BLOCK_SCENE.instantiate() as Node3D
	block.name = "Block_%d_%d_%d" % [roundi(position.x / BLOCK_SIZE), roundi(position.y / BLOCK_SIZE), roundi(position.z / BLOCK_SIZE)]
	block.set("color_id", color_id)
	block.set("snap_to_grid", true)
	level_root.add_child(block)
	var edited_root := get_editor_interface().get_edited_scene_root()
	if edited_root != null:
		block.owner = edited_root
	block.position = position
	get_editor_interface().mark_scene_as_unsaved()
	return block

func _remove_block(level_root: Node3D, position: Vector3) -> void:
	var coord := Vector3i(
		roundi(position.x / BLOCK_SIZE),
		roundi(position.y / BLOCK_SIZE),
		roundi(position.z / BLOCK_SIZE)
	)
	var block := _find_block(level_root, coord)
	if block != null:
		block.free()

func _find_block(node: Node, coord: Vector3i) -> Node3D:
	for child in node.get_children():
		if child is Node3D and child.is_in_group("level_block") and child.has_meta("coord") and child.get_meta("coord") == coord:
			return child
		var nested := _find_block(child, coord)
		if nested != null:
			return nested
	return null

func _commit_stroke() -> void:
	if not stroke_active:
		return
	stroke_active = false
	if stroke_root == null or stroke_positions.is_empty():
		stroke_positions.clear()
		return
	var undo_redo := get_undo_redo()
	undo_redo.create_action("绘制方块")
	for position_variant in stroke_positions.values():
		var position: Vector3 = position_variant
		undo_redo.add_do_method(self, "_add_block", stroke_root, position, selected_color_id)
		undo_redo.add_undo_method(self, "_remove_block", stroke_root, position)
	undo_redo.commit_action(false)
	stroke_positions.clear()
	stroke_root = null
