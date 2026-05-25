# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"The Stream" — a Godot 4.6 idle/clicker game about a Twitch streamer. Forward+ renderer, Jolt physics, D3D12 on Windows. Main scene: [scenes/main.tscn](scenes/main.tscn). There is no test suite, no build script, and no linter — this is a pure Godot editor project. Run it by opening [project.godot](project.godot) in the Godot 4.6 editor and pressing F5, or from the CLI: `godot --path .` (use `--headless` only for non-rendering tasks; the game requires a window).

## Architecture

### Autoload singletons drive all gameplay state

Three autoloads are registered in [project.godot](project.godot:18-21) and are the single source of truth for game state. Nodes never own gameplay data directly — they connect to autoload signals and react.

- **[GameManager](scripts/autoload/game_manager.gd)** — views, subs, cash, elapsed time, and the passive view-per-second pipeline. `views_per_second` is a *computed* getter built from four separately-tracked components (`_non_bot_vps`, `_bot_base_vps`, `_bot_efficiency`, `_view_mult`, `_boost_mult`). When adding a new upgrade effect, decide which bucket it feeds — the bot-vs-non-bot split exists specifically so that `botupgrade` can multiply only the bot contribution. Cash is derived from views at `cash_per_view = 0.01`; subs are derived as `views / 5` plus `add_bonus_subs` from chat interaction. Fractional view accumulation lives in `_fractional_views` — don't bypass `_tick_passive_views`.
- **[UpgradeManager](scripts/autoload/upgrade_manager.gd)** — the `UPGRADES` constant dictionary is the catalog. Each entry's *key* (e.g. `"botreact"`) must match a PNG basename in [assets/upgrade/](assets/upgrade/) (lowercased) — that's how edit-mode binds clickable upgrade sprites to purchase logic in [edit_mode.gd:212-215](scripts/ui/edit_mode/edit_mode.gd#L212-L215). Effects are applied by `_apply_upgrade` checking which optional keys are present (`non_bot_vps`, `bot_vps`, `view_mult_bonus`, `boost_pct`+`boost_duration`, `bot_efficiency_bonus`). To add an upgrade: add the dictionary entry, drop a matching PNG into `assets/upgrade/`, and extend `_apply_upgrade` if the effect type is new.
- **[AudioManager](scripts/autoload/audio_manager.gd)** — two `AudioStreamPlayer`s (music + sfx) with linear-to-dB volume controls.

### Two-mode UI: gameplay vs. edit mode

The entire HUD is reskinnable at runtime. [EditMode](scripts/ui/edit_mode/edit_mode.gd) is a `CanvasLayer` at layer 10 toggled by the `toggle_edit_mode` input action (F8 by default, mapped in [project.godot:32-36](project.godot#L32-L36)). It manages four object groups — `screen`, `upgrade`, `visual`, `stat` — each corresponding to a folder under [assets/](assets/).

Key invariants when touching edit mode:
- **Auto-loading**: on startup, every PNG/JPG/JPEG/WEBP in `assets/<group>/` that isn't already placed gets auto-positioned into the layout. New artwork dropped into those folders just appears.
- **Layout persistence**: positions/sizes/z-indices are saved to `user://layout.cfg` via `ConfigFile`, not to a `.tres`. Don't try to commit layout state to the repo.
- **Mouse filter toggling**: `_update_object_interactivity` flips `mouse_filter` between `STOP` and `IGNORE` depending on whether edit mode is open and which group is active. If clicks stop working on a placed sprite, this is the first place to check.
- **Gameplay click routing**: when *not* in edit mode, clicking a `screen`-group sprite calls `GameManager.add_views(1)` and animates all screen objects (except files containing "frame" or named view/sub/screen). Clicking an `upgrade`-group sprite looks up `UPGRADES[basename]` and calls `try_purchase`.
- **Special sprite names**: sprites in the `screen` group named `view.png` or `sub.png` auto-attach a live counter label fed by `GameManager.views_changed`/`subs_changed` ([editable_object.gd:59-85](scripts/ui/edit_mode/editable_object.gd#L59-L85)). Files containing "frame" are decorative and non-interactive.

### Comment panel uses Pollinations.ai for live chat

[CommentPanel](scripts/ui/hud/comment_panel.gd) fetches batches of 10 Twitch-style chat lines from `https://text.pollinations.ai/openai` (no API key) and falls back to hard-coded `POSITIVE_COMMENTS`/`NEGATIVE_COMMENTS` arrays if the request fails or the queue runs dry. Buttons are pooled (`_pool`) and reused — the `_gen` metadata counter on each button exists so that timer/tween callbacks from a *previous* use don't fire on a recycled instance. Negative comments auto-dismiss after `NEGATIVE_LIFETIME` (10s) and cost 1 sub if not clicked. Spawn rate scales with view count via `_on_views_changed`.

### Signal flow

State changes flow one way: `GameManager` (and `UpgradeManager`) emit; UI listens. Examples:
- `GameManager.views_changed` → `stat_panel.gd`, `comment_panel.gd`, view counter labels on `view.png` screen sprite
- `GameManager.cash_changed` → `stat_panel.gd`, every `upgrade_item.gd` (to disable/enable buy buttons)
- `UpgradeManager.upgrade_purchased` → [main.gd:14-24](scripts/main.gd#L14-L24) (adds a thumbnail to the `VisualContainer` HBox)

If a UI element looks stale, the fix is almost always "connect to the right signal in `_ready`", not polling in `_process`.

## Conventions

- GDScript with static typing (`var x: int`, `func f() -> void`). Match the existing style.
- The `%NodeName` unique-name selector is used heavily — check the relevant `.tscn` for `unique_name_in_owner = true` before assuming a node path.
- `.uid` files next to `.gd` files are Godot's resource UID tracking — commit them, don't edit them.
- The `class_name EditableObjectNode` declaration in [editable_object.gd](scripts/ui/edit_mode/editable_object.gd:1) is the only global class registration; reference it by that name, not by path.

## Platform notes

The shell is PowerShell on Windows 11. The repo uses D3D12 explicitly ([project.godot:44](project.godot#L44)) — don't change the rendering driver without reason.
