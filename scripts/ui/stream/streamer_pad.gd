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

	# Build 9 empty cells.
	for i in 9:
		var cell := ToolCell.new()
		cell.slot_index = i
		_cells.append(cell)
		_grid.add_child(cell)

	call_deferred("_layout_for_state")

	Upgrades.purchased.connect(_on_purchased)
	Upgrades.order_changed.connect(_rebuild_cells)
	GameManager.run_reset.connect(_on_run_reset)

	_rebuild_cells()

func _on_purchased(_id: String) -> void:
	_rebuild_cells()

func _on_run_reset(_run: int) -> void:
	_rebuild_cells()

func _rebuild_cells() -> void:
	var order: Array[String] = Upgrades.get_order()
	for i in 9:
		var cell: ToolCell = _cells[i]
		if i < order.size():
			cell.set_tool(order[i])
		else:
			cell.set_tool("")

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
	# Grid drawable width = _frame.size.x - 16 (.tscn insets the Grid by 8px
	# on each side). With 3 columns and 2 interior gutters of CELL_GUTTER:
	#   3 * side + 2 * CELL_GUTTER = _frame.size.x - 16
	#   => side = (_frame.size.x - 16 - 2 * CELL_GUTTER) / 3
	var side: float = (_frame.size.x - 16.0 - CELL_GUTTER * 2.0) / 3.0
	for cell in _cells:
		(cell as Control).custom_minimum_size = Vector2(side, side)
	_grid.add_theme_constant_override("h_separation", int(CELL_GUTTER))
	_grid.add_theme_constant_override("v_separation", int(CELL_GUTTER))

func _process(_delta: float) -> void:
	for cell in _cells:
		var c: ToolCell = cell
		if c.tool_id == "":
			continue
		var progress: float = Upgrades.get_cooldown_progress(c.tool_id)
		c.update_cooldown(progress)


# ------------------------------------------------------------------
# Inner class — one cell of the pad.
# ------------------------------------------------------------------
class ToolCell extends Control:
	var tool_id: String = ""
	var slot_index: int = -1
	var _cooldown_progress: float = 0.0

	var _label: Label

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		_label = Label.new()
		_label.anchor_left = 0.0
		_label.anchor_top = 0.0
		_label.anchor_right = 1.0
		_label.anchor_bottom = 1.0
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_label.add_theme_constant_override("outline_size", 3)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		_refresh_label()

	func set_tool(id: String) -> void:
		if tool_id == id:
			return
		tool_id = id
		_refresh_label()
		queue_redraw()

	func _refresh_label() -> void:
		if _label == null:
			return
		if tool_id == "" or not Upgrades.CATALOG.has(tool_id):
			_label.text = ""
			return
		_label.text = String(Upgrades.CATALOG[tool_id]["name"])

	func update_cooldown(progress: float) -> void:
		var clamped: float = clampf(progress, 0.0, 1.0)
		if absf(clamped - _cooldown_progress) < 0.005:
			return
		_cooldown_progress = clamped
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if tool_id == "":
			draw_rect(rect, Color(0.12, 0.13, 0.16, 0.55), true)
			draw_rect(rect, Color(0.35, 0.40, 0.50, 0.4), false, 1.0)
			return
		draw_rect(rect, Color(0.18, 0.20, 0.26, 0.85), true)
		draw_rect(rect, Color(0.55, 0.65, 0.85, 0.6), false, 1.0)
		if _cooldown_progress <= 0.0:
			return
		_draw_cooldown_mask()

	func _draw_cooldown_mask() -> void:
		var center: Vector2 = size * 0.5
		# Use a radius past the corners so the mask fully covers the square.
		var radius: float = size.length() * 0.6
		var steps: int = 32
		var sweep: float = _cooldown_progress * TAU
		var pts := PackedVector2Array()
		pts.append(center)
		for i in steps + 1:
			var t: float = float(i) / float(steps)
			var ang: float = -PI * 0.5 + sweep * t  # start at 12 o'clock, sweep clockwise
			pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
