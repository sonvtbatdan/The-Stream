extends Panel

signal transform_changed(pos: Vector2, sz: Vector2)
signal apply_requested
signal all_icon_size_changed(size: float)

@onready var x_spin: SpinBox = $VBox/PosRow/XSpin
@onready var y_spin: SpinBox = $VBox/PosRow/YSpin
@onready var w_spin: SpinBox = $VBox/SizeRow/WSpin
@onready var h_spin: SpinBox = $VBox/SizeRow/HSpin

var _aspect_ratio := 1.0
var _syncing := false
# In All_icon mode the panel binds to a master width (single scalar), so X/Y/H are
# disabled and W edits emit all_icon_size_changed instead of transform_changed.
var _all_icon_mode := false

func _ready() -> void:
	x_spin.value_changed.connect(_on_pos_changed)
	y_spin.value_changed.connect(_on_pos_changed)
	w_spin.value_changed.connect(_on_w_changed)
	h_spin.value_changed.connect(_on_h_changed)

func refresh(obj: EditableObjectNode) -> void:
	_all_icon_mode = false
	_set_all_editable(true)
	if obj == null or not is_instance_valid(obj):
		_syncing = true
		x_spin.value = 0
		y_spin.value = 0
		w_spin.value = 0
		h_spin.value = 0
		_syncing = false
		return
	_aspect_ratio = obj._aspect_ratio
	_syncing = true
	x_spin.value = snappedf(obj.position.x, 1.0)
	y_spin.value = snappedf(obj.position.y, 1.0)
	w_spin.value = snappedf(obj.size.x, 1.0)
	h_spin.value = snappedf(obj.size.y, 1.0)
	_syncing = false

func refresh_all_icon(size: float) -> void:
	_all_icon_mode = true
	_set_all_editable(false)
	w_spin.editable = true
	_aspect_ratio = 1.0
	_syncing = true
	x_spin.value = 0
	y_spin.value = 0
	w_spin.value = snappedf(size, 1.0)
	h_spin.value = snappedf(size, 1.0)
	_syncing = false

func _set_all_editable(v: bool) -> void:
	x_spin.editable = v
	y_spin.editable = v
	w_spin.editable = v
	h_spin.editable = v

func _on_pos_changed(_value: float) -> void:
	if _syncing or _all_icon_mode:
		return
	_emit_live()

func _on_w_changed(value: float) -> void:
	if _syncing:
		return
	if _all_icon_mode:
		_syncing = true
		h_spin.value = snappedf(value, 1.0)  # mirror W for display only
		_syncing = false
		all_icon_size_changed.emit(value)
		return
	if _aspect_ratio <= 0.0:
		return
	_syncing = true
	h_spin.value = snappedf(value / _aspect_ratio, 1.0)
	_syncing = false
	_emit_live()

func _on_h_changed(value: float) -> void:
	if _syncing or _all_icon_mode or _aspect_ratio <= 0.0:
		return
	_syncing = true
	w_spin.value = snappedf(value * _aspect_ratio, 1.0)
	_syncing = false
	_emit_live()

func _emit_live() -> void:
	transform_changed.emit(
		Vector2(x_spin.value, y_spin.value),
		Vector2(w_spin.value, h_spin.value)
	)

func _on_apply_pressed() -> void:
	apply_requested.emit()
