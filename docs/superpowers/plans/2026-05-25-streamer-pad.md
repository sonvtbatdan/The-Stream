# Streamer Pad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3×3 streamer pad to The Stream's arena HUD that shows owned tools with real-time radial cooldown masks, expands to a centered 500×500 popup on click, supports drag-and-drop reordering in the popup, and collapses on outside-click.

**Architecture:** Two responsibilities added to the `Upgrades` autoload (per-tool cooldown state, slot ordering) so the pad UI stays a passive consumer. One new scene + script pair (`StreamerPad` with an inner `ToolCell` class). `StreamArena` instances the pad and calls `Upgrades.start_cooldown(...)` when firing tools.

**Tech Stack:** Godot 4.6, GDScript with static typing. No test suite — verification is manual via the Godot editor (F5 to run).

**Spec:** `docs/superpowers/specs/2026-05-25-streamer-pad-design.md`

**Verification note:** This project has no automated tests. Each task ends with a manual verification step that runs the project (`godot --path .` from PowerShell, or open `project.godot` and press F5) and confirms an observable behavior. After each task, commit before moving to the next.

---

## Task 1: Extend `Upgrades` with cooldown tracking and slot ordering

**Files:**
- Modify: `scripts/autoload/upgrades.gd`

This task adds data + signals to the autoload but no UI. After it, the existing between-round upgrade screen still works exactly as before; new APIs are unused.

- [ ] **Step 1: Add new state fields and `order_changed` signal**

Open `scripts/autoload/upgrades.gd`. After the existing `signal purchased(id: String)` line near the top, add:

```gdscript
signal order_changed
```

After the `var _owned: Dictionary = {}` line, add:

```gdscript
# Owned tool ids in slot order. Mutated by try_purchase (append) and
# swap_slots (drag-reorder). The pad reads this to populate cells.
var _order: Array[String] = []

# Per-tool cooldown timers. Keys are tool ids; values are dicts of
# {remaining: float, total: float}. Absent ids are treated as ready (progress 0).
# Populated by start_cooldown, ticked in _process, removed when remaining <= 0.
var _cooldowns: Dictionary = {}
```

- [ ] **Step 2: Append to `_order` on successful purchase**

Find the existing `try_purchase` function. Replace it with:

```gdscript
func try_purchase(id: String) -> bool:
	if not CATALOG.has(id):
		return false
	if is_owned(id):
		return false
	if not GameManager.spend_gold(get_cost(id)):
		return false
	_owned[id] = true
	_order.append(id)
	emit_signal("purchased", id)
	return true
```

- [ ] **Step 3: Add cooldown and order accessor functions**

Append to the bottom of the file (after the existing `reset()`):

```gdscript
func get_order() -> Array[String]:
	return _order.duplicate()

func start_cooldown(id: String, duration: float) -> void:
	if duration <= 0.0:
		_cooldowns.erase(id)
		return
	_cooldowns[id] = {"remaining": duration, "total": duration}

func get_cooldown_progress(id: String) -> float:
	var entry: Dictionary = _cooldowns.get(id, {})
	if entry.is_empty():
		return 0.0
	var total: float = float(entry.get("total", 0.0))
	if total <= 0.0:
		return 0.0
	return clampf(float(entry.get("remaining", 0.0)) / total, 0.0, 1.0)

func swap_slots(i: int, j: int) -> void:
	if i == j:
		return
	if i < 0 or j < 0 or i >= _order.size() or j >= _order.size():
		return
	var tmp: String = _order[i]
	_order[i] = _order[j]
	_order[j] = tmp
	emit_signal("order_changed")

func _process(delta: float) -> void:
	if GameManager.paused:
		return
	if _cooldowns.is_empty():
		return
	# Iterate over a snapshot of keys so we can erase while iterating.
	var ids: Array = _cooldowns.keys()
	for id in ids:
		var entry: Dictionary = _cooldowns[id]
		var remaining: float = float(entry["remaining"]) - delta
		if remaining <= 0.0:
			_cooldowns.erase(id)
		else:
			entry["remaining"] = remaining
```

- [ ] **Step 4: Extend `reset()` to clear new state**

Find the existing `reset` function. Replace it with:

```gdscript
func reset() -> void:
	_owned.clear()
	_order.clear()
	_cooldowns.clear()
```

- [ ] **Step 5: Run the project and confirm nothing regressed**

Run: `godot --path .` (or open the editor and press F5).
Click white VIEW drifters to bank views, survive to the end of round 1, and confirm the between-round upgrade screen still lists all three tools and lets you buy one. After buying, restart the run (let the eye die) and confirm the upgrade modal shows all tools as buyable again — proves `reset()` still works correctly.

Expected: no visible changes from before this task.

- [ ] **Step 6: Commit**

```powershell
git add scripts/autoload/upgrades.gd
git commit -m "feat(upgrades): add cooldown tracking and slot ordering"
```

---

## Task 2: Report cooldowns from `StreamArena`

**Files:**
- Modify: `scripts/ui/stream/stream_arena.gd`

The arena already tracks `_lazer_cooldown` and `_nova_cooldown` internally. This task forwards the reset value to `Upgrades` so the pad can render the radial mask. `echo` is unchanged (no cooldown).

- [ ] **Step 1: Forward auto_lazer cooldown to Upgrades**

Open `scripts/ui/stream/stream_arena.gd`. Find `_tick_auto_lazer` (around line 328). Replace it with:

```gdscript
func _tick_auto_lazer(delta: float) -> void:
	if not Upgrades.is_owned("auto_lazer"):
		return
	_lazer_cooldown -= delta
	if _lazer_cooldown <= 0.0:
		_lazer_cooldown = float(Upgrades.get_param("auto_lazer", "cooldown", 0.5))
		Upgrades.start_cooldown("auto_lazer", _lazer_cooldown)
		_fire_lazer()
```

- [ ] **Step 2: Forward nova cooldown to Upgrades**

Find `_tick_nova` (around line 384). Replace it with:

```gdscript
func _tick_nova(delta: float) -> void:
	if not Upgrades.is_owned("nova"):
		return
	_nova_cooldown -= delta
	if _nova_cooldown <= 0.0:
		_nova_cooldown = float(Upgrades.get_param("nova", "cooldown", 5.0))
		Upgrades.start_cooldown("nova", _nova_cooldown)
		_fire_nova()
```

- [ ] **Step 3: Run the project and verify cooldown state via a temporary print**

This is throwaway debug code, removed in the next step. At the top of `_process` in `stream_arena.gd` (just inside the function, after the `if _paused: return` line), temporarily add:

```gdscript
	if Engine.get_frames_drawn() % 60 == 0:
		print("lazer cd:", Upgrades.get_cooldown_progress("auto_lazer"),
			" nova cd:", Upgrades.get_cooldown_progress("nova"))
```

Run the project, survive to the upgrade modal, buy `auto_lazer`, continue, and watch the output log. Expected: `lazer cd: 1.0 ...` immediately after the lazer fires, decreasing each second toward 0, then jumping back to 1.0 when it fires again. Nova should stay at 0 until purchased.

- [ ] **Step 4: Remove the debug print**

Delete the three lines added in Step 3.

- [ ] **Step 5: Commit**

```powershell
git add scripts/ui/stream/stream_arena.gd
git commit -m "feat(arena): report tool cooldowns to Upgrades autoload"
```

---

## Task 3: Create `StreamerPad` scene and script with empty docked grid

**Files:**
- Create: `scripts/ui/stream/streamer_pad.gd`
- Create: `scenes/ui/stream/streamer_pad.tscn`
- Modify: `scenes/ui/stream/stream_arena.tscn`

This task creates the visible pad with 9 empty cells anchored to bottom-left. No interactivity yet — no clicks, no expand, no cell content beyond the dim silhouette.

- [ ] **Step 1: Create the script with class structure and empty cells**

Create `scripts/ui/stream/streamer_pad.gd` with this content:

```gdscript
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
```

- [ ] **Step 2: Create the scene file**

Create `scenes/ui/stream/streamer_pad.tscn` with this content (Godot text format):

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/stream/streamer_pad.gd" id="1"]

[node name="StreamerPad" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("1")

[node name="Frame" type="Panel" parent="."]
mouse_filter = 0

[node name="Grid" type="GridContainer" parent="Frame"]
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = 8.0
offset_right = -8.0
offset_bottom = -8.0
columns = 3
mouse_filter = 2
```

- [ ] **Step 3: Add the pad to the stream arena scene**

Open `scenes/ui/stream/stream_arena.tscn`. Replace the file with:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/ui/stream/stream_arena.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/ui/stream/streamer_pad.tscn" id="2"]

[node name="StreamArena" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 1
script = ExtResource("1")

[node name="DrifterContainer" type="Control" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 1

[node name="Eye" type="TextureRect" parent="."]
mouse_filter = 0

[node name="HPBar" type="ProgressBar" parent="."]
mouse_filter = 2
show_percentage = false

[node name="SpawnTimer" type="Timer" parent="."]
wait_time = 1.5
autostart = true

[node name="StreamerPad" parent="." instance=ExtResource("2")]
```

- [ ] **Step 4: Run the project and confirm the empty pad is visible**

Run the project. Expected: a 320×320 dark panel anchored to the bottom-left of the arena, containing a 3×3 grid of dim outlined squares (the empty silhouettes). Drifters keep spawning and the game runs normally. Clicking the pad does nothing yet (no handler).

- [ ] **Step 5: Commit**

```powershell
git add scripts/ui/stream/streamer_pad.gd scenes/ui/stream/streamer_pad.tscn scenes/ui/stream/stream_arena.tscn
git commit -m "feat(pad): add StreamerPad scene with empty 3x3 grid"
```

---

## Task 4: Populate cells with owned tools from `Upgrades`

**Files:**
- Modify: `scripts/ui/stream/streamer_pad.gd`

This task wires the pad to `Upgrades.purchased`, `Upgrades.order_changed`, and `GameManager.run_reset` so cells fill in with the tool's display name when bought, swap on reorder, and clear on run reset.

- [ ] **Step 1: Connect signals and add `_rebuild_cells`**

In `scripts/ui/stream/streamer_pad.gd`, find `_ready()` and replace its body so the function ends up as:

```gdscript
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	for i in 9:
		var cell := ToolCell.new()
		cell.slot_index = i
		_cells.append(cell)
		_grid.add_child(cell)

	_layout_for_state()

	Upgrades.purchased.connect(_on_purchased)
	Upgrades.order_changed.connect(_rebuild_cells)
	GameManager.run_reset.connect(_on_run_reset)

	_rebuild_cells()
```

Then add these methods anywhere in the outer class (above the `class ToolCell ...` line):

```gdscript
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
```

- [ ] **Step 2: Give `ToolCell` a `set_tool` method and a name Label**

Inside the `class ToolCell extends Control:` block, replace the existing class body with:

```gdscript
class ToolCell extends Control:
	var tool_id: String = ""
	var slot_index: int = -1

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

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if tool_id == "":
			draw_rect(rect, Color(0.12, 0.13, 0.16, 0.55), true)
			draw_rect(rect, Color(0.35, 0.40, 0.50, 0.4), false, 1.0)
			return
		draw_rect(rect, Color(0.18, 0.20, 0.26, 0.85), true)
		draw_rect(rect, Color(0.55, 0.65, 0.85, 0.6), false, 1.0)
```

- [ ] **Step 3: Run and verify**

Run the project, survive round 1, buy `Auto Lazer` from the upgrade modal, click Continue. Expected: the first slot of the pad now shows "Auto Lazer" as a text label on the dark cell background; the other 8 cells remain dim silhouettes.

Buy `Nova` after round 2 and confirm slot 1 fills in. Let the eye die — confirm all cells clear back to empty silhouettes.

- [ ] **Step 4: Commit**

```powershell
git add scripts/ui/stream/streamer_pad.gd
git commit -m "feat(pad): populate cells with owned tools from Upgrades"
```

---

## Task 5: Draw radial cooldown masks

**Files:**
- Modify: `scripts/ui/stream/streamer_pad.gd`

Adds per-frame cooldown polling and the clock-sweep dark mask on top of each owned cell.

- [ ] **Step 1: Add cooldown polling on the outer class**

In `streamer_pad.gd`, add a new method anywhere in the outer class (alongside `_rebuild_cells`):

```gdscript
func _process(_delta: float) -> void:
	for cell in _cells:
		var c: ToolCell = cell
		if c.tool_id == "":
			continue
		var progress: float = Upgrades.get_cooldown_progress(c.tool_id)
		c.update_cooldown(progress)
```

- [ ] **Step 2: Add `update_cooldown` and mask drawing on `ToolCell`**

Inside the `class ToolCell extends Control:` block, add a new field next to `var tool_id`:

```gdscript
	var _cooldown_progress: float = 0.0
```

Then add a new method anywhere inside the class:

```gdscript
	func update_cooldown(progress: float) -> void:
		var clamped: float = clampf(progress, 0.0, 1.0)
		if absf(clamped - _cooldown_progress) < 0.005:
			return
		_cooldown_progress = clamped
		queue_redraw()
```

Finally, extend `_draw()` to render the mask. Replace `_draw()` with:

```gdscript
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
```

- [ ] **Step 3: Run and verify the mask**

Run the project, buy Auto Lazer. Expected: as the auto_lazer fires (every 1 second), the slot 0 cell shows a dark pie-shaped mask that starts as a full circle and sweeps away clockwise over 1 second, then snaps back to full when the lazer fires again. Continue to buy Nova — its 5-second cooldown should be visible as a much slower sweep on slot 1.

Press F8 to open edit mode. Expected: the sweep freezes mid-animation. Close edit mode (F8) — sweep resumes from where it stopped.

Let the eye die. Expected: cells clear and no mask remains drawn.

- [ ] **Step 4: Commit**

```powershell
git add scripts/ui/stream/streamer_pad.gd
git commit -m "feat(pad): draw radial cooldown masks on owned cells"
```

---

## Task 6: Click-to-expand popup with backdrop, tween, and detail panel

**Files:**
- Modify: `scripts/ui/stream/streamer_pad.gd`
- Modify: `scenes/ui/stream/streamer_pad.tscn`

Adds the dark backdrop, the expand/collapse tween, and a detail panel below the grid showing the focused tool's name and full description.

- [ ] **Step 1: Add Backdrop and DetailPanel nodes to the scene**

Replace the contents of `scenes/ui/stream/streamer_pad.tscn` with:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/stream/streamer_pad.gd" id="1"]

[node name="StreamerPad" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("1")

[node name="Backdrop" type="ColorRect" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.55)
visible = false
mouse_filter = 0

[node name="Frame" type="Panel" parent="."]
mouse_filter = 0

[node name="Grid" type="GridContainer" parent="Frame"]
offset_left = 8.0
offset_top = 8.0
columns = 3
mouse_filter = 2

[node name="DetailPanel" type="PanelContainer" parent="Frame"]
visible = false
mouse_filter = 0

[node name="DetailMargin" type="MarginContainer" parent="Frame/DetailPanel"]

[node name="DetailVBox" type="VBoxContainer" parent="Frame/DetailPanel/DetailMargin"]

[node name="NameLabel" type="Label" parent="Frame/DetailPanel/DetailMargin/DetailVBox"]
text = ""

[node name="DescLabel" type="Label" parent="Frame/DetailPanel/DetailMargin/DetailVBox"]
text = ""
autowrap_mode = 3
```

The Grid anchors are now omitted because the script positions Grid and DetailPanel manually in `_layout_for_state` (so they reflow between docked and expanded states without anchor confusion).

- [ ] **Step 2: Add @onready references and state for the new nodes**

In `streamer_pad.gd`, replace the existing `@onready` lines near the top with:

```gdscript
@onready var _backdrop: ColorRect = $Backdrop
@onready var _frame: Panel = $Frame
@onready var _grid: GridContainer = $Frame/Grid
@onready var _detail_panel: PanelContainer = $Frame/DetailPanel
@onready var _detail_name: Label = $Frame/DetailPanel/DetailMargin/DetailVBox/NameLabel
@onready var _detail_desc: Label = $Frame/DetailPanel/DetailMargin/DetailVBox/DescLabel
```

- [ ] **Step 3: Wire up click handlers and layout for both states**

Replace `_ready()` with:

```gdscript
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0

	for i in 9:
		var cell := ToolCell.new()
		cell.slot_index = i
		cell.gui_input.connect(_on_cell_gui_input.bind(i))
		cell.mouse_entered.connect(_on_cell_mouse_entered.bind(i))
		_cells.append(cell)
		_grid.add_child(cell)

	_frame.gui_input.connect(_on_frame_gui_input)
	_backdrop.gui_input.connect(_on_backdrop_gui_input)
	resized.connect(_layout_for_state)

	_detail_panel.add_theme_constant_override("margin_left", 12)
	_detail_panel.add_theme_constant_override("margin_right", 12)
	_detail_panel.add_theme_constant_override("margin_top", 8)
	_detail_panel.add_theme_constant_override("margin_bottom", 8)
	_detail_name.add_theme_font_size_override("font_size", 18)
	_detail_desc.add_theme_color_override("font_color", Color(0.82, 0.88, 0.96))

	_layout_for_state()

	Upgrades.purchased.connect(_on_purchased)
	Upgrades.order_changed.connect(_rebuild_cells)
	GameManager.run_reset.connect(_on_run_reset)

	_rebuild_cells()
```

Replace `_layout_for_state` and `_resize_cells` with:

```gdscript
func _layout_for_state() -> void:
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

	_grid.position = Vector2(inner_margin, inner_margin)
	_grid.size = Vector2(grid_w, grid_h)

	var side: float = (grid_w - CELL_GUTTER * 2.0) / 3.0
	for cell in _cells:
		(cell as Control).custom_minimum_size = Vector2(side, side)
	_grid.add_theme_constant_override("h_separation", int(CELL_GUTTER))
	_grid.add_theme_constant_override("v_separation", int(CELL_GUTTER))

	if _state == State.EXPANDED:
		_detail_panel.position = Vector2(inner_margin, inner_margin + grid_h + inner_margin)
		_detail_panel.size = Vector2(grid_w, detail_h)
```

- [ ] **Step 4: Add expand/collapse methods and click handlers**

Append these methods to the outer class:

```gdscript
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
	# Recompute cell layout immediately so the grid reflows even before the
	# tween finishes (avoids visible reflow at the tail of the animation).
	_layout_inside_frame()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_frame, "position", target.position, ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_frame, "size", target.size, ANIM_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_on_tween_finished)

func _on_tween_finished() -> void:
	_transitioning = false
	if _state == State.DOCKED:
		_backdrop.visible = false
		_detail_panel.visible = false
	_layout_inside_frame()

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
```

- [ ] **Step 5: Run and verify expand/collapse and detail panel**

Run the project, buy at least one tool. Click the pad. Expected:

- The arena dims behind a translucent black backdrop.
- The pad tweens from bottom-left to a centered 500×500 popup (~150 ms).
- The detail panel below the grid shows the first owned tool's name + description.
- Hovering another owned cell updates the detail panel.
- Hovering an empty cell clears the detail panel.

Click the dark backdrop (anywhere outside the popup square). Expected: pad tweens back to bottom-left, backdrop disappears, detail panel disappears.

Click directly on the popup (not the backdrop). Expected: no collapse.

While the popup is open, confirm the arena is still running (drifters spawn, lazer keeps firing, cooldown masks keep sweeping).

- [ ] **Step 6: Commit**

```powershell
git add scripts/ui/stream/streamer_pad.gd scenes/ui/stream/streamer_pad.tscn
git commit -m "feat(pad): click-to-expand popup with backdrop and detail panel"
```

---

## Task 7: Drag-and-drop reordering in the expanded popup

**Files:**
- Modify: `scripts/ui/stream/streamer_pad.gd`

Adds the `_get_drag_data` / `_can_drop_data` / `_drop_data` overrides on `ToolCell` and a `notify_drop` method on `StreamerPad` that calls `Upgrades.swap_slots`.

- [ ] **Step 1: Give cells a back-reference to the pad**

In the outer class's `_ready` loop where cells are created, replace the cell-construction lines with:

```gdscript
	for i in 9:
		var cell := ToolCell.new()
		cell.slot_index = i
		cell.pad = self
		cell.gui_input.connect(_on_cell_gui_input.bind(i))
		cell.mouse_entered.connect(_on_cell_mouse_entered.bind(i))
		_cells.append(cell)
		_grid.add_child(cell)
```

Inside the `class ToolCell extends Control:` block, add a `pad` field next to `tool_id`:

```gdscript
	var pad: Control = null   # back-reference to StreamerPad
```

- [ ] **Step 2: Implement drag-and-drop overrides on `ToolCell`**

Inside `class ToolCell`, add these three methods (anywhere in the class):

```gdscript
	func _get_drag_data(_at: Vector2) -> Variant:
		if pad == null or tool_id == "":
			return null
		if pad.get("_state") != 1:   # 1 == State.EXPANDED; raw int avoids exporting the enum
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
```

The `_state` check uses raw integer `1` because GDScript inner classes can't reference the outer class's enum by name without a fully-qualified path. The brittle alternative is exporting the enum to a global script — not worth it for one comparison.

- [ ] **Step 3: Implement `notify_drop` on `StreamerPad`**

Append to the outer class (alongside `_set_focused`):

```gdscript
func notify_drop(from_slot: int, to_slot: int) -> void:
	# Both slots are owned (ToolCell._can_drop_data already filtered empty drops).
	Upgrades.swap_slots(from_slot, to_slot)
	# Focus follows the dragged tool to its new slot.
	_set_focused(to_slot)
```

(`Upgrades.swap_slots` emits `order_changed`, which the pad already listens to in `_ready` — `_rebuild_cells` runs automatically.)

- [ ] **Step 4: Run and verify drag-and-drop**

Run the project, buy at least two tools (Auto Lazer then Nova). Click the pad to expand. Expected layout:

- Slot 0: Auto Lazer
- Slot 1: Nova
- Slots 2–8: empty

Drag the Auto Lazer cell onto the Nova cell. Expected:

- A small text preview ("Auto Lazer") follows the cursor.
- On release over the Nova cell, the two swap: slot 0 now shows Nova, slot 1 shows Auto Lazer.
- The detail panel updates to Auto Lazer (the dragged tool's new slot).

Try dragging Nova onto an empty cell. Expected: the drag preview appears but `_can_drop_data` rejects it — the cursor shows the "no drop" indicator and releasing does nothing.

Collapse the popup, expand it again. Expected: order persists (Nova in slot 0, Auto Lazer in slot 1).

While docked, try to drag a cell. Expected: nothing happens (drag suppressed by `_state` check). Single click still expands the popup.

Let the eye die (run reset). Expected: cells clear; on the next run, slot order starts fresh in purchase order.

- [ ] **Step 5: Commit**

```powershell
git add scripts/ui/stream/streamer_pad.gd
git commit -m "feat(pad): drag-and-drop reordering in expanded popup"
```

---

## Final verification checklist

After Task 7, run one full integration pass:

1. Start a fresh run. Pad shows 9 empty silhouettes at bottom-left.
2. Click the pad. It expands to a centered 500×500 popup; detail panel below the grid is blank because no tools are owned.
3. Click the backdrop. It collapses back.
4. Survive round 1, buy Auto Lazer. Slot 0 fills with "Auto Lazer" text + a sweeping 1-second cooldown mask.
5. Buy Nova on round 2. Slot 1 fills with "Nova" + a slower 5-second sweep.
6. Buy Echo on round 3. Slot 2 fills with "Echo" but no cooldown mask (echo has no cooldown).
7. Click the pad. Popup opens; hover each cell — detail panel updates to that tool's name and description.
8. Drag Echo onto Auto Lazer. They swap. Reopen — order persists.
9. Press F8 (edit mode). Cooldown sweeps freeze. Close edit mode — sweeps resume.
10. Open the pad popup while a between-round upgrade modal is showing. (You'll need to buy a tool to trigger the modal first.) Confirm the pad is behind the modal and inactive (the modal's dim layer absorbs clicks). Close the modal — pad becomes interactive again.
11. Let the eye die. Pad clears, run resets.

If all 11 steps pass, the feature is done.
