extends Control

enum State { DOCKED, EXPANDED }

const DOCKED_SIZE := Vector2(320.0, 320.0)
const DOCKED_MARGIN := 16.0
const EXPANDED_SIZE := Vector2(500.0, 500.0)
const CELL_GUTTER := 8.0
const ANIM_DURATION := 0.15

var _state: int = State.DOCKED
var _cells: Array = []          # ToolCell controls in slot order (0..8)
var _focused_index: int = -1
var _transitioning: bool = false

@onready var _frame: Panel = $Frame
@onready var _grid: GridContainer = $Frame/Grid

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # let arena clicks pass through outside Frame
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	# Build 9 empty cells.
	for i in 9:
		var cell := ToolCell.new()
		cell.slot_index = i
		_cells.append(cell)
		_grid.add_child(cell)

	_layout_for_state()

func _layout_for_state() -> void:
	var target: Rect2 = _target_rect(_state)
	_frame.position = target.position
	_frame.size = target.size
	_resize_cells()

func _target_rect(state: int) -> Rect2:
	var parent_size: Vector2 = size
	if state == State.DOCKED:
		var pos := Vector2(DOCKED_MARGIN, parent_size.y - DOCKED_MARGIN - DOCKED_SIZE.y)
		return Rect2(pos, DOCKED_SIZE)
	# EXPANDED — centered
	return Rect2((parent_size - EXPANDED_SIZE) * 0.5, EXPANDED_SIZE)

func _resize_cells() -> void:
	# Grid is 3 columns. Cell side = (frame_size - 4 * gutter) / 3.
	var side: float = (_frame.size.x - CELL_GUTTER * 4.0) / 3.0
	for cell in _cells:
		(cell as Control).custom_minimum_size = Vector2(side, side)
	_grid.add_theme_constant_override("h_separation", int(CELL_GUTTER))
	_grid.add_theme_constant_override("v_separation", int(CELL_GUTTER))


# ------------------------------------------------------------------
# Inner class — one cell of the pad.
# ------------------------------------------------------------------
class ToolCell extends Control:
	var tool_id: String = ""
	var slot_index: int = -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		# Empty silhouette: thin rounded outline + faint fill.
		var rect := Rect2(Vector2.ZERO, size)
		if tool_id == "":
			draw_rect(rect, Color(0.12, 0.13, 0.16, 0.55), true)
			draw_rect(rect, Color(0.35, 0.40, 0.50, 0.4), false, 1.0)
			return
		# Owned cell — placeholder background; real content lands in Task 4.
		draw_rect(rect, Color(0.18, 0.20, 0.26, 0.85), true)
		draw_rect(rect, Color(0.55, 0.65, 0.85, 0.6), false, 1.0)
