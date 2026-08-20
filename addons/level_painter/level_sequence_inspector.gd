@tool
extends VBoxContainer

const COLOR_NAMES := ["红色", "黄色", "蓝色", "紫色", "绿色"]

var target: Object
var undo_redo: EditorUndoRedoManager
var mark_unsaved: Callable
var last_signature := ""

func setup(level: Object, editor_undo_redo: EditorUndoRedoManager, unsaved_callback: Callable) -> void:
	target = level
	undo_redo = editor_undo_redo
	mark_unsaved = unsaved_callback
	_refresh()
	set_process(true)

func _process(_delta: float) -> void:
	if not is_instance_valid(target):
		return
	var signature := _sequence_signature()
	if signature != last_signature:
		_refresh()

func _sequence_signature() -> String:
	if not is_instance_valid(target):
		return ""
	var values: Array = target.get("ball_color_sequence")
	return ",".join(values.map(func(value: Variant) -> String: return str(value)))

func _refresh() -> void:
	if not is_instance_valid(target):
		return
	last_signature = _sequence_signature()
	for child in get_children():
		child.queue_free()

	var sequence: Array = target.get("ball_color_sequence")
	for index in range(sequence.size()):
		_add_sequence_row(index, _value_to_name(sequence[index]))

	if sequence.is_empty():
		var empty_label := Label.new()
		empty_label.text = "未配置：使用随机颜色"
		empty_label.modulate = Color(0.65, 0.65, 0.65)
		add_child(empty_label)

	var add_button := Button.new()
	add_button.text = "+ 添加颜色"
	add_button.tooltip_text = "在序列末尾添加一个颜色"
	add_button.pressed.connect(_on_add_pressed)
	add_child(add_button)

func _add_sequence_row(index: int, selected_name: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)

	var index_label := Label.new()
	index_label.text = "第 %d 个" % (index + 1)
	index_label.custom_minimum_size = Vector2(62, 0)
	row.add_child(index_label)

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for color_name in COLOR_NAMES:
		option.add_item(color_name)
	option.select(maxi(0, COLOR_NAMES.find(selected_name)))
	option.item_selected.connect(_on_color_selected.bind(index))
	row.add_child(option)

	var remove_button := Button.new()
	remove_button.text = "删除"
	remove_button.tooltip_text = "删除这一项"
	remove_button.pressed.connect(_on_remove_pressed.bind(index))
	row.add_child(remove_button)

func _value_to_name(value: Variant) -> String:
	if value is int or value is float:
		var numeric_id := int(value)
		return COLOR_NAMES[numeric_id] if numeric_id >= 0 and numeric_id < COLOR_NAMES.size() else COLOR_NAMES[0]
	var text := String(value).strip_edges()
	if text.is_valid_int():
		var numeric_id := int(text)
		return COLOR_NAMES[numeric_id] if numeric_id >= 0 and numeric_id < COLOR_NAMES.size() else COLOR_NAMES[0]
	return text if COLOR_NAMES.has(text) else COLOR_NAMES[0]

func _on_add_pressed() -> void:
	var sequence: Array[String] = _current_sequence()
	sequence.append(COLOR_NAMES[0])
	_commit_sequence(sequence)

func _on_color_selected(color_index: int, sequence_index: int) -> void:
	var sequence: Array[String] = _current_sequence()
	if sequence_index < sequence.size():
		sequence[sequence_index] = COLOR_NAMES[color_index]
		_commit_sequence(sequence)

func _on_remove_pressed(sequence_index: int) -> void:
	var sequence: Array[String] = _current_sequence()
	if sequence_index < 0 or sequence_index >= sequence.size():
		return
	sequence.remove_at(sequence_index)
	_commit_sequence(sequence)

func _current_sequence() -> Array[String]:
	var result: Array[String] = []
	for value in target.get("ball_color_sequence"):
		result.append(_value_to_name(value))
	return result

func _commit_sequence(new_sequence: Array[String]) -> void:
	var old_sequence: Array = target.get("ball_color_sequence")
	undo_redo.create_action("修改炮弹颜色顺序")
	undo_redo.add_do_property(target, "ball_color_sequence", new_sequence)
	undo_redo.add_undo_property(target, "ball_color_sequence", old_sequence)
	undo_redo.commit_action()
	if mark_unsaved.is_valid():
		mark_unsaved.call()
