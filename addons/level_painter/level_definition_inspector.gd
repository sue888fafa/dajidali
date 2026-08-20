@tool
extends EditorInspectorPlugin

const LEVEL_SCRIPT := preload("res://scripts/level_definition.gd")
const SEQUENCE_EDITOR := preload("res://addons/level_painter/level_sequence_inspector.gd")

var undo_redo: EditorUndoRedoManager
var mark_unsaved: Callable

func setup(editor_undo_redo: EditorUndoRedoManager, unsaved_callback: Callable) -> void:
	undo_redo = editor_undo_redo
	mark_unsaved = unsaved_callback

func _can_handle(object: Object) -> bool:
	return object is Node and object.get_script() == LEVEL_SCRIPT

func _parse_property(object: Object, type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name != "ball_color_sequence":
		return false
	var editor := SEQUENCE_EDITOR.new()
	editor.setup(object, undo_redo, mark_unsaved)
	add_property_editor(name, editor)
	return true
