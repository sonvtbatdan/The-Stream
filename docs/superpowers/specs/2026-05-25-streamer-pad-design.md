# Streamer Pad — Design

## Summary

Add a persistent HUD component to The Stream: a 3×3 "streamer pad" docked at
the bottom-left of the arena that shows the player's purchased **tools**
(formerly "upgrades" — `auto_lazer`, `nova`, `echo`, and any future entries in
`Upgrades.CATALOG`). Clicking the pad expands it into a centered 500×500 popup
that mirrors the same 3×3 grid at larger scale and shows tool details on
hover/click. Clicking outside the popup collapses it back. Each cell renders a
real-time radial cooldown mask (Dota/LoL-style "clock sweep") driven by the
tool's current cooldown progress. Owned tools fill slots in purchase order; the
player can drag-and-drop to swap slots, but only while the popup is expanded.

The arena stays live while the popup is open — no pause. The pad also stays
visible during the between-round upgrade modal.

## Goals and non-goals

**Goals:**

- Persistent at-a-glance view of which tools the player owns and their
  cooldown state.
- Click-to-expand detail view that shows each tool's full name and
  description.
- Drag-to-reorder within the expanded popup.
- Tool data and cooldown state live in the `Upgrades` autoload; the pad is a
  pure consumer.

**Non-goals (out of scope for this spec):**

- Per-tool icon art. Cells display the tool's display name as text. A future
  change can add an `icon` field to `Upgrades.CATALOG` and have cells prefer
  the texture when present.
- Buying tools from the pad. Purchasing remains exclusively via the
  between-round `upgrade_screen.gd` modal.
- Saving the slot order across runs. `Upgrades.reset()` clears the order
  alongside ownership, which is the desired behavior — a new run starts fresh.
- Pad behavior on touch/mobile. Desktop mouse input only.

## User-facing behavior

**Docked state (default).** A 3×3 grid sitting at the arena's bottom-left
corner. Outer footprint roughly 320×320 (three ~100×100 cells with small
gutters and a thin frame). Empty (unowned) cells render as a faintly outlined
rounded rectangle — a dim silhouette, no text. Owned cells render a darker
rounded background with the tool's display name as centered text, plus the
radial cooldown mask drawn on top.

**Click the pad → expand.** Any click that lands on the pad (any cell or its
frame) while docked transitions to the expanded state. A modal-style
semi-transparent backdrop (`Color(0, 0, 0, 0.55)`) appears behind the popup. A
short tween (~150 ms) animates the pad's `position` and `size` from the
bottom-left rect to a centered 500×500 rect. The 3×3 grid scales up with it;
cells become roughly 130×130 with proportionally larger text. A detail panel
below the grid (~440×80 inside the 500×500 popup) shows the focused tool's
name and full description (from `Upgrades.get_desc(id)`); the focused tool
defaults to the first owned tool, and updates on hover/click of any owned
cell.

**Click outside the popup → collapse.** Clicking the dark backdrop (anywhere
outside the popup's 500×500 rect) tweens the pad back to its docked
rect/position and removes the backdrop. Clicks on the popup itself do not
dismiss.

**Cooldowns.** Each owned cell draws a darkening radial mask whose "missing
slice" corresponds to elapsed-cooldown progress. Just-fired = full dark mask
(slice covers the whole cell); fully cooled down = no mask visible. The mask
is driven by `Upgrades.get_cooldown_progress(id)`. Tools without a cooldown
(currently `echo`) never show a mask. Cooldowns freeze when
`GameManager.paused` is true (edit mode, between-round modal) and resume on
unpause.

**Drag-and-drop reordering.** Only available while the popup is expanded.
Pressing on an owned cell and moving past Godot's drag threshold starts a
drag; releasing over another **owned** cell calls
`Upgrades.swap_slots(from, to)`. Dropping on an empty cell, or outside any
cell, cancels the drag with no state change. Releasing without moving past
the threshold counts as a normal click (sets the focused tool in the detail
panel). After a swap, focus follows the tool the player just moved (now at
its new slot).

**During the between-round modal.** Pad stays visible. It does NOT become a
backdrop for the modal; `upgrade_screen.gd` already covers the full viewport
with its own dim layer, so the pad is visually behind it. Cooldowns freeze
because `GameManager.paused` is true. Players can't interact with the pad
during the modal because the modal's dim layer captures all input.

## Architecture

### `Upgrades` autoload additions (`scripts/autoload/upgrades.gd`)

The autoload gains two responsibilities so the pad UI can stay simple:

**Cooldown tracking.**

- `var _cooldowns: Dictionary = {}` — maps `tool_id: String` → `{remaining:
  float, total: float}`. Only contains entries for tools with active
  cooldowns; absence means "no cooldown / ready".
- `func start_cooldown(id: String, duration: float) -> void` — called by
  `StreamArena` immediately after firing a tool. Overwrites any existing
  entry: `_cooldowns[id] = {"remaining": duration, "total": duration}`.
- `func get_cooldown_progress(id: String) -> float` — returns
  `remaining / total` ∈ [0, 1]. Returns 0.0 if the tool has no entry (ready
  or never fired).
- `_process(delta)` ticks remaining downward, bailing immediately when
  `GameManager.paused` is true so the entire game pause behavior carries
  through. Entries with `remaining <= 0` are removed (keeps the dict small
  and means `get_cooldown_progress` returns 0 for ready tools).

**Slot ordering.**

- `var _order: Array[String] = []` — owned tool ids in display order. Used
  by the pad as the source of truth for "which tool is in which slot".
- `try_purchase(id)` appends `id` to `_order` after a successful buy
  (purchase order).
- `func swap_slots(i: int, j: int) -> void` — swaps two indices, then emits
  a new `order_changed` signal so the pad can rebuild. Both indices must be
  in range `[0, _order.size())`; out-of-range calls are a no-op (matches
  the user-facing rule that drops onto empty cells do nothing).
- `reset()` clears `_order` and `_cooldowns` in addition to `_owned`.

**New signals:**

- `signal order_changed` — emitted when `swap_slots` runs.

The existing `purchased(id)` signal is enough for "tool added to a new slot"
since the pad knows to append in that case.

### `StreamArena` changes (`scripts/ui/stream/stream_arena.gd`)

Two surgical changes:

1. **Instance the pad.** Add a `StreamerPad` child node in
   `scenes/ui/stream/stream_arena.tscn` anchored to bottom-left. The arena
   doesn't need a reference to it after construction — the pad subscribes
   to `Upgrades` signals on its own.
2. **Report cooldowns.** In `_tick_auto_lazer`, immediately after
   `_lazer_cooldown = float(Upgrades.get_param("auto_lazer", "cooldown",
   0.5))`, call `Upgrades.start_cooldown("auto_lazer", _lazer_cooldown)`.
   Same pattern for `_tick_nova` and the `nova` cooldown.

`echo` does not call `start_cooldown` — it has no cooldown to display.

### `StreamerPad` scene/script

**Files:**

- `scenes/ui/stream/streamer_pad.tscn`
- `scripts/ui/stream/streamer_pad.gd`

**Node tree:**

```
StreamerPad (Control)
├─ Backdrop (ColorRect, hidden by default, mouse_filter = STOP)
├─ Frame (Panel) — the actual pad/popup background
│   └─ Grid (GridContainer, columns = 3)
│       └─ 9 × ToolCell (Control) — created in code at _ready
└─ DetailPanel (PanelContainer, visible only in EXPANDED state)
    ├─ NameLabel (Label)
    └─ DescLabel (Label, autowrap)
```

**Why Backdrop is a child of `StreamerPad`, not `StreamArena`:** keeping the
pad and its modal layer in one subtree means a single script owns the
expand/collapse state and no cross-node ordering hacks are needed. The
backdrop sits behind `Frame` in the tree but is anchored full-rect so it
covers the viewport when visible — the arena keeps processing because
nothing called `set_paused`.

**State:**

```gdscript
enum State { DOCKED, EXPANDED }

const DOCKED_SIZE := Vector2(320, 320)
const DOCKED_MARGIN := 16.0           # gap from arena's left and bottom edges
const EXPANDED_SIZE := Vector2(500, 500)
const ANIM_DURATION := 0.15

var _state: State = State.DOCKED
var _cells: Array = []                # 9 ToolCell controls in slot order
var _focused_index: int = -1          # which cell drives DetailPanel
var _transitioning: bool = false      # guards re-entrant clicks during tween
```

**Layout math.** `StreamerPad` itself is full-rect (anchors 0/0/1/1) on the
StreamArena so it can host both the bottom-left pad position and the
centered expanded position without re-anchoring. `Frame` (the pad/popup
panel) is positioned via `Frame.position` and `Frame.size` set in code each
transition:

- DOCKED: `position = Vector2(DOCKED_MARGIN, parent.size.y - DOCKED_MARGIN
  - DOCKED_SIZE.y)`, `size = DOCKED_SIZE`.
- EXPANDED: `position = (parent.size - EXPANDED_SIZE) * 0.5`,
  `size = EXPANDED_SIZE`.

The tween animates `Frame.position` and `Frame.size` over `ANIM_DURATION`.
Target positions are recomputed at the start of every transition (so window
resizes are respected). A single `_target_rect(state)` helper centralizes
the math.

**Initialization.** On `_ready`:

1. Build 9 `ToolCell`s and add to `Grid`. Empty by default.
2. Connect `Upgrades.purchased`, `Upgrades.order_changed`,
   `GameManager.run_reset` → `_rebuild_cells()`.
3. `_rebuild_cells()` walks `Upgrades._order` (need an accessor — add
   `func get_order() -> Array: return _order.duplicate()`), assigns
   `tool_id` to the first N cells, clears the rest.
4. Hide `Backdrop` and `DetailPanel`. Set state to DOCKED.

**Per-frame work** (`_process`): for each owned cell, set the cooldown
progress from `Upgrades.get_cooldown_progress(cell.tool_id)` and call
`queue_redraw()`. Cells only repaint when progress actually changed since
last frame to keep redraws cheap.

**Click handling.**

- DOCKED state: any `gui_input` on the pad (`InputEventMouseButton`,
  `BUTTON_LEFT`, pressed) → call `_expand()`.
- EXPANDED state: backdrop's `gui_input` (left click pressed) →
  `_collapse()`. Clicks on `Frame` are absorbed by `Frame`'s mouse_filter
  STOP so they don't reach the backdrop.

**Tween.** A single `create_tween()` per transition tweening `offset_left`,
`offset_top`, `offset_right`, `offset_bottom` to the target state's values
over `ANIM_DURATION` with `Tween.EASE_OUT`. While the tween is running,
clicks are ignored (`_transitioning: bool` guard).

### `ToolCell` inner class

Defined in the same file as `StreamerPad` (it's small and only used here).
Subclass of `Control` with:

```gdscript
var tool_id: String = ""    # "" means empty slot
var slot_index: int = -1    # which grid position
var _cooldown_progress: float = 0.0
var _hovered: bool = false
```

**Drawing.** Override `_draw()`:

1. Background rounded rect: `draw_rect` with rounded corners (or use a
   `StyleBoxFlat` via theme override on a child `Panel` if simpler).
   Dimmer color when `tool_id == ""`, normal when owned, slightly
   brighter when `_hovered`.
2. Centered label is a `Label` child node, not drawn in `_draw()` — easier
   to manage font sizing across docked vs. expanded scale.
3. If `tool_id != ""` and `_cooldown_progress > 0.0`: draw the radial mask.
   Build a polygon starting at the cell center, sweeping clockwise from 12
   o'clock through `_cooldown_progress * TAU` radians, using ~32 vertices
   for smoothness. Fill with `Color(0, 0, 0, 0.6)`. The vertex math:

   ```gdscript
   var center := size * 0.5
   var radius := size.length() * 0.6   # past the corners so mask covers fully
   var pts := PackedVector2Array([center])
   var steps := 32
   var sweep := _cooldown_progress * TAU
   for i in steps + 1:
       var t := float(i) / steps
       var ang := -PI * 0.5 + sweep * t   # start at top
       pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
   draw_colored_polygon(pts, Color(0, 0, 0, 0.6))
   ```

**Drag-and-drop.** Override the three standard Control methods:

- `_get_drag_data(at_pos: Vector2) -> Variant`: returns
  `{from_slot = slot_index}` only when the pad is EXPANDED and the cell is
  owned. Returns `null` otherwise (suppresses drag).
- `_can_drop_data(at_pos: Vector2, data: Variant) -> bool`: returns true
  when `data is Dictionary and data.has("from_slot") and data.from_slot !=
  slot_index` **and this cell is owned** (drops on empty cells are
  rejected per the user-facing rule).
- `_drop_data(at_pos: Vector2, data: Variant) -> void`: calls
  `_pad.notify_drop(data.from_slot, slot_index)`. The pad then calls
  `Upgrades.swap_slots(...)`.

Godot's built-in drag system handles the 8-pixel threshold automatically
(it won't start a drag for tiny mouse movements), so no manual click-vs-drag
disambiguation is needed.

**Hover focus.** `mouse_entered` signal → notify pad → pad sets
`_focused_index` and updates DetailPanel. Only fires in EXPANDED state
(docked state, DetailPanel is hidden).

## Data flow

```
[Player clicks upgrade in upgrade_screen]
    → Upgrades.try_purchase(id)
        → spend gold, _owned[id] = true, _order.append(id)
        → emit purchased(id)
            → StreamerPad._rebuild_cells()  [cell appears in next free slot]

[Per frame, while !GameManager.paused]
    → Upgrades._process: tick _cooldowns
    → StreamArena._tick_auto_lazer: if fired, Upgrades.start_cooldown("auto_lazer", D)
    → StreamerPad._process: for each owned cell, read progress, queue_redraw

[Player clicks pad while docked]
    → StreamerPad._on_gui_input → _expand()
        → show backdrop, tween rect to centered 500×500
        → reveal DetailPanel, default focus = slot 0

[Player drags cell A onto cell B while expanded]
    → Godot drag system: A._get_drag_data → drag preview floats
    → release on B: B._can_drop_data → true; B._drop_data → pad.notify_drop(i, j)
        → Upgrades.swap_slots(i, j)
            → emit order_changed
                → StreamerPad._rebuild_cells() reflects new order

[Player clicks backdrop]
    → Backdrop._on_gui_input → pad._collapse()
        → tween rect back to bottom-left, hide backdrop, hide DetailPanel
```

## Edge cases and error handling

- **Owning > 9 tools.** Out of scope today (the catalog has 3 entries) but
  the pad clamps: only the first 9 entries in `Upgrades._order` are shown.
  When/if a 10th tool ships, this spec needs revisiting — log a one-line
  TODO in the pad script.
- **Cooldown set on an unowned tool.** `start_cooldown` does not check
  ownership; the dict entry simply exists with no visible UI consumer
  (since no cell is bound to that id). Harmless. Removed naturally when
  remaining hits 0.
- **Run reset while popup is expanded.** `GameManager.run_reset` →
  `_rebuild_cells` clears all owned cells. The popup stays open but shows
  9 empty cells; the DetailPanel hides itself because there's nothing to
  focus. Acceptable — the player can still click the backdrop to dismiss.
- **Drag aborted (release off-cell).** Godot's drag system handles this:
  no `_drop_data` is called, no state changes.
- **Window resize during popup.** Both states use anchor + offset math so
  resizing while docked keeps the pad anchored to bottom-left, and
  resizing while expanded keeps it centered. The tween targets are
  recomputed at the moment a transition starts, not cached.

## Testing

The project has no test suite. Verification is manual via Godot editor F5:

- Buy a tool from the between-round modal — cell appears in the pad's
  first empty slot.
- Watch the auto_lazer cell's radial mask sweep clockwise as the cooldown
  ticks. Verify it freezes when entering edit mode.
- Click the pad — it expands. Click outside — it collapses.
- Buy a second and third tool. Drag the third cell over the first while
  expanded — they swap. Reopen the popup — order persists.
- Trigger a run reset (eye HP to 0). Pad clears to 9 empty cells.

## Open questions / explicitly deferred

- **Tool icons.** Spec uses text labels. Adding `icon: String` (path) to
  catalog entries and preferring it over the name label is a one-line
  change in `ToolCell` once art exists.
- **Pad position customization.** Edit-mode-style drag-to-reposition the
  whole pad isn't requested. If we ever want it, it'd live as a new
  edit-mode object group.
- **Visual polish.** Rounded corner radii, shadows, hover/click feedback
  beyond a brightness shift, animated sweep easing — all left as
  follow-ups once the core behavior is in.
