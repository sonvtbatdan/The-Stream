extends Control

@onready var edit_mode = $EditMode
@onready var arena = $StreamArena

func _ready() -> void:
	# Pause/resume the arena whenever edit mode opens or closes, regardless of
	# whether it was via the F4 keypress, the unsaved dialog, or the X button.
	edit_mode.opened_changed.connect(arena.set_paused)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_edit_mode"):
		edit_mode.toggle()
		get_viewport().set_input_as_handled()
