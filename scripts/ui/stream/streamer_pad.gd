extends Control

enum State { DOCKED, EXPANDED }

const DOCKED_SIZE := Vector2(320.0, 320.0)
const DOCKED_MARGIN := 16.0
const EXPANDED_SIZE := Vector2(500.0, 500.0)
const CELL_GUTTER := 8.0
const ANIM_DURATION := 0.15

var _state: int = State.DOCKED
var _cells: Array[ToolCell] = []   # ToolCell controls in slot order (0..8)
var _focused_index: int = -1
var _transitioning: bool = false

@onready var _backdrop: ColorRect = $Backdrop
@onready var _frame: Panel = $Frame
@onready var _grid: GridContainer = $Frame/Grid
@onready var _detail_panel: PanelContainer = $Frame/DetailPanel
@onready var _detail_margin: MarginContainer = $Frame/DetailPanel/DetailMargin
@onready var _detail_name: Label = $Frame/DetailPanel/DetailMargin/DetailVBox/NameLabel
@onready var _detail_desc: Label = $Frame/DetailPanel/DetailMargin/DetailVBox/DescLabel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # let arena clicks pass through outside Frame

	for i in 9:
		var cell := ToolCell.new()
		cell.slot_index = i
		cell.pad = self
		cell.gui_input.connect(_on_cell_gui_input.bind(i))
		cell.mouse_entered.connect(_on_cell_mouse_entered.bind(i))
		_cells.append(cell)
		_grid.add_child(cell)

	_frame.gui_input.connect(_on_frame_gui_input)
	_backdrop.gui_input.connect(_on_backdrop_gui_input)
	resized.connect(_layout_for_state)

	_detail_margin.add_theme_constant_override("margin_left", 12)
	_detail_margin.add_theme_constant_override("margin_right", 12)
	_detail_margin.add_theme_constant_override("margin_top", 8)
	_detail_margin.add_theme_constant_override("margin_bottom", 8)
	_detail_name.add_theme_font_size_override("font_size", 18)
	_detail_desc.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))

	call_deferred("_layout_for_state")

	Upgrades.purchased.connect(_on_purchased)
	Upgrades.order_changed.connect(_rebuild_cells)
	GameManager.run_reset.connect(_on_run_reset)

	_rebuild_cells()

func _on_purchased(_id: String) -> void:
	_rebuild_cells()

func _on_run_reset(_run: int) -> void:
	_state = State.DOCKED
	_transitioning = false
	_focused_index = -1
	_detail_name.text = ""
	_detail_desc.text = ""
	_rebuild_cells()
	_layout_for_state()

func _rebuild_cells() -> void:
	var order: Array[String] = Upgrades.get_order()
	for i in 9:
		var cell: ToolCell = _cells[i]
		if i < order.size():
			cell.set_tool(order[i])
		else:
			cell.set_tool("")

func _layout_for_state() -> void:
	if _transitioning:
		return  # tween owns _frame.position / size during transitions
	var target: Rect2 = _target_rect(_state)
	_frame.position = target.position
	_frame.size = target.size
	_backdrop.visible = _state == State.EXPANDED
	_detail_panel.visible = _state == State.EXPANDED
	_layout_inside_frame()

func _layout_inside_frame() -> void:
	var inner_margin: float = 8.0
	var frame_w: float = _frame.size.x
	var frame_h: float = _frame.size.y

	# DetailPanel only shows in expanded; reserve space at the bottom if so.
	var detail_h: float = 90.0 if _state == State.EXPANDED else 0.0

	var grid_w: float = frame_w - inner_margin * 2.0
	var grid_h: float = frame_h - inner_margin * 2.0 - detail_h - (inner_margin if detail_h > 0.0 else 0.0)

	var side: float = minf(
		(grid_w - CELL_GUTTER * 2.0) / 3.0,
		(grid_h - CELL_GUTTER * 2.0) / 3.0
	)
	# Recompute the grid's actual square size so we can center it horizontally
	# when height is the constraining dimension (e.g. EXPANDED state where the
	# detail panel reserves vertical space).
	var grid_actual: float = side * 3.0 + CELL_GUTTER * 2.0
	_grid.position = Vector2((frame_w - grid_actual) * 0.5, inner_margin)
	_grid.size = Vector2(grid_actual, grid_actual)
	for cell in _cells:
		(cell as Control).custom_minimum_size = Vector2(side, side)
	_grid.add_theme_constant_override("h_separation", int(CELL_GUTTER))
	_grid.add_theme_constant_override("v_separation", int(CELL_GUTTER))

	if _state == State.EXPANDED:
		_detail_panel.position = Vector2(inner_margin, inner_margin + grid_actual + inner_margin)
		_detail_panel.size = Vector2(grid_w, detail_h)

func _target_rect(state: int) -> Rect2:
	var parent_size: Vector2 = size
	if state == State.DOCKED:
		var pos := Vector2(DOCKED_MARGIN, parent_size.y - DOCKED_MARGIN - DOCKED_SIZE.y)
		return Rect2(pos, DOCKED_SIZE)
	# EXPANDED — centered
	return Rect2((parent_size - EXPANDED_SIZE) * 0.5, EXPANDED_SIZE)

func _process(_delta: float) -> void:
	for cell in _cells:
		if cell.tool_id == "":
			continue
		var progress: float = Upgrades.get_cooldown_progress(cell.tool_id)
		cell.update_cooldown(progress)

func _on_frame_gui_input(event: InputEvent) -> void:
	if _state != State.DOCKED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_expand()

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if _state != State.EXPANDED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_collapse()

func _on_cell_gui_input(event: InputEvent, slot_index: int) -> void:
	if _state == State.DOCKED:
		# Treat any cell click as a pad expand (covered by Frame handler too,
		# but cells consume input first).
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_expand()
		return
	# EXPANDED: clicking an owned cell sets focus.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_focused(slot_index)

func _on_cell_mouse_entered(slot_index: int) -> void:
	if _state == State.EXPANDED:
		_set_focused(slot_index)

func _expand() -> void:
	if _transitioning or _state == State.EXPANDED:
		return
	_state = State.EXPANDED
	_backdrop.visible = true
	_detail_panel.visible = true
	# Default focus to first owned cell, if any.
	var first_owned: int = -1
	for i in _cells.size():
		if (_cells[i] as ToolCell).tool_id != "":
			first_owned = i
			break
	_set_focused(first_owned)
	_tween_to_state()

func _collapse() -> void:
	if _transitioning or _state == State.DOCKED:
		return
	_state = State.DOCKED
	_focused_index = -1
	_tween_to_state()

func _tween_to_state() -> void:
	_transitioning = true
	var target: Rect2 = _target_rect(_state)
	# Cells stay at their previous size during the tween, then reflow once
	# the frame reaches its final size in _on_tween_finished. This avoids
	# the double-jump that would result from reflowing with stale frame size.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_frame, "position", target.position, ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_frame, "size", target.size, ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_on_tween_finished)

func _on_tween_finished() -> void:
	_transitioning = false
	# Recompute frame position+size from the current parent size in case the
	# window was resized during the tween. _layout_for_state also handles the
	# backdrop/detail visibility for the new state.
	_layout_for_state()

func _set_focused(slot_index: int) -> void:
	_focused_index = slot_index
	if slot_index < 0 or slot_index >= _cells.size():
		_detail_name.text = ""
		_detail_desc.text = ""
		return
	var cell: ToolCell = _cells[slot_index]
	if cell.tool_id == "":
		_detail_name.text = ""
		_detail_desc.text = ""
		return
	_detail_name.text = String(Upgrades.CATALOG[cell.tool_id]["name"])
	_detail_desc.text = Upgrades.get_desc(cell.tool_id)

func notify_drop(from_slot: int, to_slot: int) -> void:
	# Both slots are owned (ToolCell._can_drop_data already filtered empty drops).
	Upgrades.swap_slots(from_slot, to_slot)
	# Focus follows the dragged tool to its new slot.
	_set_focused(to_slot)

func is_expanded() -> bool:
	return _state == State.EXPANDED


# ------------------------------------------------------------------
# Inner class — one cell of the pad.
# ------------------------------------------------------------------
class ToolCell extends Control:
	var tool_id: String = ""
	var slot_index: int = -1
	var pad: Control = null   # back-reference to StreamerPad
	var _cooldown_progress: float = 0.0

	var _label: Label

	func _get_drag_data(_at: Vector2) -> Variant:
		if pad == null or tool_id == "":
			return null
		if not pad.is_expanded():
			return null
		# Build a tiny ghost preview so the drag has visible feedback.
		var preview := Label.new()
		preview.text = String(Upgrades.CATALOG[tool_id]["name"])
		preview.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		preview.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		preview.add_theme_constant_override("outline_size", 3)
		set_drag_preview(preview)
		return {"from_slot": slot_index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if tool_id == "":
			return false  # drops on empty cells are no-ops
		if not (data is Dictionary):
			return false
		if not data.has("from_slot"):
			return false
		return int(data["from_slot"]) != slot_index

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if pad == null:
			return
		pad.notify_drop(int(data["from_slot"]), slot_index)

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
		_cooldown_progress = 0.0
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
		var color := Color(0, 0, 0, 0.55)
		# Build the fan as individual triangles so each is convex —
		# draw_colored_polygon is not reliable on concave polygons.
		var step_angle: float = sweep / float(steps)
		var start_angle: float = -PI * 0.5
		var prev: Vector2 = center + Vector2(cos(start_angle), sin(start_angle)) * radius
		for i in range(1, steps + 1):
			var ang: float = start_angle + step_angle * float(i)
			var next: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius
			draw_colored_polygon(PackedVector2Array([center, prev, next]), color)
			prev = next
