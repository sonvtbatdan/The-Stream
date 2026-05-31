extends Control

## Upgrade shelf — displays purchased upgrade items as icon stacks.
##
## Layout per region:
##   Row 0 (bottom): icons fill left → right between start and end markers.
##   Row 1 (above):  same x range, y = row0_y − icon_size − ROW_GAP.
##   Row N wraps upward each time a row fills.
##
## Call define_region() for each upgrade_id once _ready() completes.
## Positions are in this Control's local coordinate space.

const ROW_GAP     := 2.0   # vertical gap between rows (px)
const END_TINT    := Color(1.0, 0.25, 0.25, 0.55)  # red-fade for end marker

# region structure: {
#   "start":      Vector2,   # center of start marker / first slot
#   "end":        Vector2,   # center of end marker  / last possible slot
#   "icon_size":  float,
#   "tex":        Texture2D,
#   "start_node": TextureRect,
#   "end_node":   TextureRect,
#   "item_nodes": Array,
# }
var _regions: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	_build_background()
	UpgradeManager.upgrade_purchased.connect(_on_upgrade_purchased)
	GameManager.game_loaded.connect(_on_game_loaded)

func _on_game_loaded() -> void:
	_setup_regions()
	_refresh_all()

# ---------------------------------------------------------------------------
# Background
# ---------------------------------------------------------------------------

func _build_background() -> void:
	var tex := load("res://assets/stat/Shelf.png") as Texture2D
	if tex == null:
		return
	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -1
	add_child(bg)

# ---------------------------------------------------------------------------
# Region definition — called from _setup_regions()
# ---------------------------------------------------------------------------

## Define one upgrade type's display region.
## start / end: local-space center positions (in px) for the start and end markers.
## icon_size:   size of each icon square in px.
func define_region(upgrade_id: String, start: Vector2, end: Vector2, icon_size: float = 32.0) -> void:
	if not UpgradeManager.UPGRADES.has(upgrade_id):
		return
	if _regions.has(upgrade_id):
		return

	var tex: Texture2D = _load_icon_tex(upgrade_id)

	var start_node := _make_icon(tex, start, icon_size, false)
	var end_node   := _make_icon(tex, end,   icon_size, true)
	add_child(start_node)
	start_node.size = Vector2(icon_size, icon_size)
	start_node.visible = false
	add_child(end_node)
	end_node.size = Vector2(icon_size, icon_size)
	end_node.visible = false

	_regions[upgrade_id] = {
		"start":      start,
		"end":        end,
		"icon_size":  icon_size,
		"tex":        tex,
		"start_node": start_node,
		"end_node":   end_node,
		"item_nodes": [],
	}

# ---------------------------------------------------------------------------
# Region coordinates — fill in after running the game once.
# Positions are relative to the shelf panel's top-left corner (0, 0).
# ---------------------------------------------------------------------------

func _setup_regions() -> void:
	var edit_mode := get_parent().get_node_or_null("EditMode")
	if edit_mode == null or not edit_mode.has_method("get_stat_object_pos"):
		return
	var shelf_origin := position  # matches main.tscn offset_left/top
	for id: String in UpgradeManager.UPGRADES.keys():
		var sg: Vector2 = edit_mode.call("get_stat_object_pos",
				"res://__shelf_start_%s__" % id)
		var eg: Vector2 = edit_mode.call("get_stat_object_pos",
				"res://__shelf_end_%s__" % id)
		if sg == Vector2.ZERO or eg == Vector2.ZERO:
			continue
		define_region(id, sg - shelf_origin, eg - shelf_origin, 25.0)

func set_edit_mode(active: bool) -> void:
	for region in _regions.values():
		var sn: Node = region["start_node"]
		var en: Node = region["end_node"]
		if is_instance_valid(sn):
			sn.visible = active
		if is_instance_valid(en):
			en.visible = active

# ---------------------------------------------------------------------------
# Icon factory
# ---------------------------------------------------------------------------

func _load_icon_tex(upgrade_id: String) -> Texture2D:
	var data: Dictionary = UpgradeManager.UPGRADES[upgrade_id]
	var tab: String = data.get("tab", "view")
	var folder: String = "res://assets/sprites/comments/" if tab == "comment" \
	                     else "res://assets/sprites/upgrades/"
	var tex := load(folder + String(data["icon"])) as Texture2D
	return tex

func _make_icon(tex: Texture2D, center: Vector2, icon_size: float, end_marker: bool) -> TextureRect:
	var half := icon_size * 0.5
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture = tex
	rect.position = center - Vector2(half, half)
	rect.size = Vector2(icon_size, icon_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if end_marker:
		rect.modulate = END_TINT
	return rect

# ---------------------------------------------------------------------------
# Item placement
# ---------------------------------------------------------------------------

func _on_upgrade_purchased(upgrade_id: String) -> void:
	_rebuild_region(upgrade_id)

func _refresh_all() -> void:
	for id: String in _regions:
		_rebuild_region(id)

func _rebuild_region(upgrade_id: String) -> void:
	if not _regions.has(upgrade_id):
		return

	var r: Dictionary  = _regions[upgrade_id]
	var item_nodes: Array = r["item_nodes"]

	for node in item_nodes:
		if is_instance_valid(node):
			node.queue_free()
	item_nodes.clear()

	var n: int = UpgradeManager.get_owned_count(upgrade_id)
	if n == 0:
		return

	var start:     Vector2 = r["start"]
	var end:       Vector2 = r["end"]
	var icon_size: float   = r["icon_size"]
	var tex:       Texture2D = r["tex"]

	var row_w: float = end.x - start.x
	var step: float  = icon_size if n <= 1 else minf(icon_size, row_w / float(n - 1))

	for i: int in n:
		var cx: float = start.x + step * float(i)
		var cy: float = start.y
		var node := _make_icon(tex, Vector2(cx, cy), icon_size, false)
		node.z_index = 1
		add_child(node)
		node.size = Vector2(icon_size, icon_size)
		item_nodes.append(node)
