# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4 GDScript — "The Stream", a Twitch-streamer idle/clicker game. Entry scene: `scenes/main.tscn`. Toggle edit mode with the `toggle_edit_mode` input action (mapped in `project.godot`).

## Commands

- **Run:** `godot --path .`
- **Parse check (no window):** `godot --headless --check-only --path . --quit` — exit 0 = parse clean
- **No test suite.** Verification is manual (F5 in editor). Say so explicitly rather than asserting success from a parse check alone.
- **Shell:** Windows / PowerShell. Use PowerShell syntax (`$null`, `$env:VAR`, backtick for line continuation). Bash tool is available for POSIX scripts.

---

## Architecture

### Autoloads (load order in project.godot)

| Name | File | Role |
|------|------|------|
| `GameManager` | `scripts/autoload/game_manager.gd` | Economy: views, subs, cash, click_power, vps, auto_click_rate, comment_auto_click_rate, donations |
| `UpgradeManager` | `scripts/autoload/upgrade_manager.gd` | UPGRADES catalog, owned counts, factory accumulator, save/load |
| `AudioManager` | `scripts/autoload/audio_manager.gd` | Music/SFX, volume control |
| `EquipmentManager` | `scripts/autoload/equipment_manager.gd` | Auto-scans `assets/upgrades/equipment/*.png`, cost = 20 × 1.6^index |

### Main Scene (`scenes/main.tscn`)

Root `Control` with these direct children:

- `EditMode` — `CanvasLayer` layer=10 (`scripts/ui/edit_mode/edit_mode.gd`): drag/resize for "screen", "equipment", "stat" groups, persisted to `user://layout.cfg`
- `UserPanel` — `CanvasLayer` layer=5 (`scripts/ui/user_panel/user_panel.gd`): PANEL_SCALE=0.5, contains TodoList, MusicPlayer, WeatherClock
- `ToolsColumn` — `Panel` with `scripts/ui/upgrade/upgrade_list.gd`: two tabs (VIEW / COMMENT)
- `StatPanel` — `Panel` with `scripts/ui/hud/stat_panel.gd`: stat display + action bar (SETTING, QUIT)
- `ChatbotPanel` — `scripts/ui/chatbot/chatbot_panel.gd`: Chat display panel (AI backend disconnected; Whisper STT mic input active)
- `EquipmentColumn` — equipment shop UI

### CanvasLayer conventions

| Layer | Used for |
|-------|----------|
| 5 | UserPanel |
| 10 | EditMode overlay |
| 100 | Settings panel (always on top, even above screen group) |

---

## GameManager

### Key fields

```gdscript
var cash: float                       # earned from Poisson donation events
var click_power: float = 1.0          # views per player click
var vps: float = 0.0                  # views/sec from VPS upgrade tools
var auto_click_rate: float = 0.0      # auto-clicks/sec (each × click_power views)
var comment_auto_click_rate: float = 0.0  # auto comment dismissals/sec
var parasocial: float = 1.0           # multiplier (future: wired to sub growth)
var stat_template: String             # editable display template

# Read-only computed getters
var views: int        # int(_subs + _passive_views)
var subs: int         # int(_subs)
var stable_views: int
var displayed_views: int
```

### Signals

`views_changed(int)`, `subs_changed(int)`, `cash_changed(float)`, `stable_views_changed(int)`, `stat_template_changed(String)`, `game_loaded`

`game_loaded` is emitted from `main.gd` after both `UpgradeManager.load_game()` and `GameManager.load_game()` complete — connect to it for late-initialising nodes that need loaded data.

### Formatting

```gdscript
format_views(n: int) -> String   # plain integer up to 999,999; then "1.28 Million" / "Billion" etc.
format_count(n: int) -> String   # plain below 1000; then "1 thousand" / "1 million" etc.
render_stat_template() -> String # replaces all {tokens} in stat_template
```

**VPS display rule:** always use `format_views()` for VPS — both in StatPanel template and in the screen overlay label in `editable_object.gd`.

### Stat template tokens

`{views}`, `{subs}`, `{cash}`, `{click_power}`, `{parasocial}`, `{goal}`, `{run}`, `{time}`, `{vps}`

---

## UpgradeManager

### UPGRADES const structure

```gdscript
const UPGRADES = {
    "id": {
        "name": "Display Name",
        "icon": "filename.png",           # in assets/upgrades/active/
        "cost": 100.0,                    # cash cost
        "tab": "view",                    # "view" or "comment"
        # one or more effect fields:
        "vps": 1.0,                       # adds to GameManager.vps
        "click_power": 1.0,               # adds to GameManager.click_power
        "auto_click_rate": 1.0,           # adds to GameManager.auto_click_rate
        "comment_click_rate": 1.0,        # adds to GameManager.comment_auto_click_rate
        "factory": true,                  # special: see factory mechanic below
        "desc": "Tooltip text",
    },
}
```

### View tab upgrades
`fanclub`, `collaborators`, `publishers`, `agency`, `streaming_agency`, `broadcast_network`, `media_conglomerate`, `streaming_empire`, `auto_clicker` (+ more)

### Comment tab upgrades
`comment_react` ($100, +1/s), `reaction_bot` ($500, +5/s), `reaction_machine` ($10k, +50/s), `reaction_farm` ($50k, +200/s), `reaction_factory` ($500k, factory), `reaction_industry` ($2M, +1000/s), `reaction_economic_zone` ($5M, +3000/s)

### Factory mechanic

`reaction_factory` spawns a virtual `reaction_machine` (+50 comment_click_rate) every 5 seconds per owned factory, via `_factory_acc` float accumulator in `UpgradeManager._process()`. Persisted as `_virtual_machines: int` in `upgrades_save.cfg`.

---

## UI Scripts

### `scripts/ui/hud/stat_panel.gd`

- Displays `GameManager.render_stat_template()` in TemplateLabel
- `_build_action_bar()`: adds HSeparator + styled mini Panel + HBox (SETTING, QUIT) below StatVBox
- Settings overlay: CanvasLayer(layer=100, PROCESS_MODE_ALWAYS) added to `get_tree().root`
  - ColorRect (0,0,0,0.6) with MOUSE_FILTER_STOP blocks all input to scene below
  - Panel 310×320 with: Resolution section (720p/1080p/2K buttons), Volume section (Music/SFX sliders)
- `_open_settings()`: show overlay + `get_tree().paused = true`
- `_close_settings()`: hide overlay + `get_tree().paused = false`
- Escape key closes settings via `_input()`
- StatPanel has `process_mode = PROCESS_MODE_ALWAYS` so it updates while paused
- Saves to `user://settings.cfg` on every change

### `scripts/ui/hud/comment_panel.gd`

- Comment buttons in VBoxContainer, font_size=13
- `_comment_acc: float` accumulates fractional auto-dismiss ticks from `GameManager.comment_auto_click_rate`
- `_auto_dismiss_n(n: int)`: collects available buttons in one pass
  - If `n >= available.size()`: instant (no tween), O(N) single pass
  - Otherwise: animate each via `_on_comment_pressed()`
- Every 5 positive dismissals → `GameManager.add_bonus_subs(1)`

### `scripts/ui/upgrade/upgrade_list.gd`

- Tab bar (VIEW / COMMENT) built at top; ScrollContainer offset_top=50 to clear it
- `_current_tab: String` filters by `UPGRADES[id].get("tab", "view")`
- `_switch_tab(tab)` rebuilds item list and updates button highlight colors

### `scripts/ui/chatbot/chatbot_panel.gd`

- Chat display panel — AI backend currently disconnected
- Whisper STT mic input still active (`godot_whisper` addon)
- `UserTodoList` integration: `add_task()`, `set_task()`, `clear_task()` via `[CMD:todo_*]` tags
- `_set_reminder()`: timer-based reminders via `[REMINDER:N:msg]` tags
- `_build_context()`: builds game-state string (time, stats, upgrades, todo list) — ready to inject into future AI system prompt
- `login_panel.gd` repurposed as API key entry panel (not spawned at startup)

### `scripts/ui/edit_mode/editable_object.gd`

- `EditableObjectNode` (`class_name`) — every in-canvas placed sprite
- `group_id: String` — one of `"screen" | "equipment" | "stat"`
- `_gameplay_mode: bool` — edit handles vs gameplay click routing
- VPS label uses `GameManager.format_views(total_vps)` (NOT format_count)
- `group_id == "screen" && basename == "view"` → `GameManager.on_view_clicked()`

---

## Assets

| Folder | Contents |
|--------|----------|
| `assets/upgrades/active/` | 48×48 PNG icons, one per upgrade id |
| `assets/upgrades/equipment/` | Equipment icons, auto-scanned by EquipmentManager (sorted order = cost order) |
| `assets/fonts/Gameplay.ttf` | Pixel/retro font for main UI |
| `assets/audio/music/` | OGG Vorbis music files streamed by AudioManager |

EquipmentManager cost formula: `20 * pow(1.6, sorted_index)`

---

## Persistence Files (`user://`)

| File | Contents |
|------|----------|
| `game_save.cfg` | passive_views, subs, cash |
| `upgrades_save.cfg` | owned counts per upgrade id + `factory/virtual_machines` |
| `settings.cfg` | resolution (w, h), music_vol, sfx_vol; `[ai]` section: groq_api_key, tavily_api_key |
| `layout.cfg` | positions/sizes of draggable groups |
| `equipment.cfg` | owned equipment items |
| `user_panel.cfg` | UserPanel widget states |
| `session.cfg` | Chatbot conversation history |
| `audio_config.cfg` | AudioManager internal state |

---

## Key Patterns & Conventions

### Static typing throughout
```gdscript
var x: int
func f() -> void:
for id: String in dict.keys():
```

### GDScript type inference gotcha
Dictionary access returns `Variant`. Annotate explicitly when comparing to a typed value:
```gdscript
# WRONG — GDScript can't infer bool from Variant:
var active := voices[i]["id"] == _selected_voice_id
# CORRECT:
var active: bool = voices[i]["id"] == _selected_voice_id
```

### Fractional accumulator (sub-integer tick rates)
```gdscript
_acc += rate * delta
if _acc >= 1.0:
    var n := int(_acc)
    _acc = fmod(_acc, 1.0)
    _process_n_times(n)
```

### Pause-safe UI nodes
Any node that must remain interactive while `get_tree().paused = true`:
```gdscript
process_mode = Node.PROCESS_MODE_ALWAYS
```
Apply to: the Panel, its CanvasLayer, and all interactive children (buttons, sliders).

### Settings overlay (guaranteed top layer)
```gdscript
# Build in _ready() deferred:
_overlay_layer = CanvasLayer.new()
_overlay_layer.layer = 100
_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
get_tree().root.add_child(_overlay_layer)
_overlay_layer.hide()

# Open:
_overlay_layer.show()
get_tree().paused = true

# Close:
_overlay_layer.hide()
get_tree().paused = false
```
CanvasLayer with high `layer` value beats any Control node's `z_index` — use layer=100 for overlays that must appear above the "screen" group.

### Tabs for indentation (matches all existing files)

---

## LOCKED MODULES — DO NOT MODIFY WITHOUT EXPLICIT USER PERMISSION

The following files are considered **stable and complete**. Claude must **not edit them** in any session unless the user explicitly says "bạn được phép sửa [tên file]" hoặc tương đương rõ ràng. Nếu có bug liên quan, hãy **báo cáo** thay vì tự ý sửa.

| File | Lý do khoá |
|------|-----------|
| `scripts/ui/user/music_player.gd` | Music player widget — đã ổn định sau nhiều lần debug |
| `scripts/ui/user/music_server.gd` | YouTube IPC client — logic kết nối mpv dễ vỡ |
| `scripts/autoload/audio_manager.gd` | Game music manager — đã có prev/next/shuffle/loop |
| `scripts/ui/user/user_panel.gd` | UserPanel layout — z-order và position đã được căn chỉnh |
| `tools/mpv-bridge.ps1` | PowerShell bridge — bidirectional async pipe, cực kỳ nhạy cảm |

Nếu một tác vụ yêu cầu đọc những file này để **hiểu context** thì được phép đọc. Chỉ không được **sửa** mà không có lệnh rõ ràng.

---

## Risky Areas

- Removing autoloads without updating `main.gd` references causes load failure
- Edit mode groups are hardcoded: `["screen", "equipment", "stat"]` — adding a new group requires updating `edit_mode.gd` GROUPS const, `edit_mode.tscn` toggle buttons, and `assets/<group>/` folder
- `.uid` files sit next to every `.gd` and `.tscn` — Godot regenerates them on first editor open; scripts created headlessly may be missing UIDs
- `UpgradeManager.load_game()` must run before `GameManager.load_game()` (UpgradeManager resets GameManager rate fields to 0 then re-applies owned upgrades)
