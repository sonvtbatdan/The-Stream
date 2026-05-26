# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.6 GDScript project — "The Stream", a Twitch-streamer idle/clicker game. Entry scene `scenes/main.tscn`. F4 toggles an in-game editor (input action `toggle_edit_mode` in `project.godot`).

## Commands

- **Run the game (headless or windowed):** `godot --path .`
- **Parse / load check (catches GDScript errors and missing autoload refs without opening a window):** `godot --headless --check-only --path . --quit` — exit 0 means parse clean. Runtime warnings (e.g. the pre-existing missing `res://fonts/GoodOldDOS.ttf`) still print but don't affect exit code.
- **No test suite exists.** Verification is manual via the editor (F5). When asked to verify behavior, say so explicitly rather than asserting success from a parse check alone.
- **Shell:** Windows / PowerShell — use PowerShell syntax in shell-only flows (`$null`, `$env:VAR`, backtick continuation). Bash via the Bash tool is available for POSIX scripts.

## Architecture

**Two autoloads drive game state** (`project.godot` `[autoload]`):

- `GameManager` — owns views/subs. Internal storage is `_views: float` / `_subs: float`; public `views` / `subs` are int getters. Signals `views_changed(int)` and `subs_changed(int)` fire only when the integer floor changes (debounced via `_emit_if_changed`). The active click loop is `on_view_clicked()` (adds `click_power`). Passive sub growth runs in `_process` at a log-scaled rate of views, multiplied by `parasocial`.
- `UpgradeManager` — legacy upgrade catalog (`fanreact`, `botreact`, `algorimth`, etc.) keyed by filename basename of images in `assets/upgrade/`. Calls back into `GameManager` for cash/VPS effects.
- `AudioManager` — sound effects.

**`GameManager` has a "Legacy compatibility shims" block** at the bottom — inert `signal cash_changed`, `var cash`, `func spend_cash`, `func apply_view_multiplier`, etc. These exist *only* to keep the still-instanced old HUD scripts (`stat_panel.gd`, `comment_panel.gd`, `upgrade_item.gd`) and `upgrade_manager.gd` from crashing at load. Delete the whole shim block when those scripts/scenes are removed or ported.

**`EditableObjectNode` (`scripts/ui/edit_mode/editable_object.gd`, `class_name`) is the central placeable Control.** Every in-canvas sprite — characters, screens, upgrades, decoration — is one of these. It carries:
- `group_id: String` — one of `"screen" | "upgrade" | "visual" | "stat"`, matching the asset subfolder it came from
- `source_path: String` — `res://assets/<group>/<file>.png`, also the persistence key
- `_gameplay_mode: bool` — toggled by `set_gameplay_mode(v)`. False = edit handles visible, mouse-resize/drag enabled; True = handles hidden, clicks emit `object_clicked` for the gameplay router

**Asset → behavior mapping is by filename basename**, not by class hierarchy. Special cases in `_handle_gameplay_input` and `_handle_gameplay_click`:
- `group_id == "screen" && basename == "view"` → `GameManager.on_view_clicked()` + `animate_screen_click()` (this is the main click loop)
- Other screen objects → only the surrounding-pop animation (`_animate_screen_objects`)
- Any name containing `"frame"` → skipped from animation and made `mouse_filter = IGNORE` in gameplay mode
- `source_path == "res://__all_upgrades__"` → synthetic control object pinned at top of upgrade-group list; resizing it propagates to every other upgrade via `_propagate_all_upgrades_size`. Texture is generated procedurally by `_make_all_upgrades_texture`; hidden in gameplay mode

**Edit mode (`scripts/ui/edit_mode/edit_mode.gd`, CanvasLayer at layer 10)** is the layout/spawn system. At startup:
1. `_load_layout()` reads `user://layout.cfg` and rebuilds all placed objects
2. `_auto_load_all_groups()` walks `assets/{screen,upgrade,visual,stat}/` and instantiates an `EditableObjectNode` for every new image not already in the layout — so dropping a PNG into an asset folder is enough to add a placeable object

**Z-index / input-order pitfall:** Godot 4 routes Control GUI input by **tree order** (later sibling wins), but renders by **`z_index`**. Without keeping them in sync, a visually-on-top object can be unclickable because an earlier sibling absorbs the click. The system handles this:
- `object_list_panel.gd` sets `z_index` based on row position (row 0 = highest z) and emits `z_indices_changed`
- `edit_mode._sort_canvas_z_order()` listens and calls `move_child` on every `EditableObjectNode` in `ObjectsContainer` so tree order matches `z_index` globally across all groups
- This is also called explicitly after `_load_layout` and `_auto_load_all_groups` so initial state is correct before any user interaction

**Layout persistence (`user://layout.cfg`)** stores per-group arrays of `{path, group, pos, size, z_index}`. The synthetic `res://__all_upgrades__` is persisted like any other entry; `_load_tex` recognizes the sentinel and substitutes the procedural texture on reload.

## Conventions

- **Static typing throughout** (`var x: int`, `func f() -> void:`). Type loop variables too: `for id: String in dict.keys():`.
- **Tabs for indentation** (matches all existing files).
- **GameManager signal contract**: `views_changed` / `subs_changed` carry `int`, never `float`. Internal accumulators are `_views: float` / `_subs: float` — call `_emit_if_changed()` after any mutation so the int signal only fires when the floor changes.
- **`add_views(int)` and `add_bonus_subs(int)` are public bulk-grant APIs** for non-click sources (e.g. arena rewards). The view-image click goes through `on_view_clicked()` instead so `click_power` applies. Don't call `add_views(1)` from the screen-click middleman — that path was removed to avoid double-counting.
- **Inner classes are common in GDScript here.** They can't reference the outer enum by qualified name, so cross-reference via a public helper method (e.g. `pad.is_expanded() -> bool`) rather than `pad.get("_state") != 1`.
- **Don't auto-fix the dead HUD scripts** (`stat_panel.gd`, `comment_panel.gd`, `view_sub_bar.gd`, `upgrade_item.gd`) unless explicitly asked — they're known broken-against-clean-slate state held alive by the shims. Touching them invites scope creep into the broader pending HUD-replacement work.
- **`.uid` files** sit next to every `.gd` and `.tscn`. Godot regenerates them on first editor load; if the implementer creates new scripts headlessly, the `.uid` may be missing and should be added in a follow-up editor session.

## Risky areas

- `scripts/main.gd` references `UpgradeManager.upgrade_purchased` — if `UpgradeManager` is removed without porting `main.gd`, the project fails at load.
- `scenes/main.tscn` still instances the legacy HUD nodes (`ViewSubBar`, `CommentPanel`, `StatPanel`, plus the per-row upgrade list). Those scripts read the shimmed APIs and display zeros; if the shims are removed, those scenes crash.
- Adding new groups beyond `["screen", "upgrade", "visual", "stat"]` requires updating `edit_mode.gd`'s `GROUPS` const, the four toggle buttons in `edit_mode.tscn`, and the matching `assets/<group>/` folder.
