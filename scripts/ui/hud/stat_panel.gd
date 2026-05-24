extends PanelContainer

@onready var goal_label: Label = %GoalLabel
@onready var cash_label: Label = %CashLabel
@onready var run_label: Label = %RunLabel
@onready var time_label: Label = %TimeLabel

func _ready() -> void:
	var font := load("res://fonts/GoodOldDOS.ttf") as FontFile
	if font:
		for lbl: Label in [goal_label, cash_label, run_label, time_label]:
			lbl.add_theme_font_override("font", font)
	GameManager.views_changed.connect(_on_views_changed)
	GameManager.cash_changed.connect(_on_cash_changed)
	_refresh()

func _process(_delta: float) -> void:
	time_label.text = "Time: " + GameManager.get_time_string()

func _refresh() -> void:
	goal_label.text = "Goal: %d Views" % GameManager.current_goal
	cash_label.text = "Cash: $%.2f" % GameManager.cash
	run_label.text = "Run: %d" % GameManager.run

func _on_views_changed(new_views: int) -> void:
	goal_label.text = "Goal: %d / %d Views" % [new_views, GameManager.current_goal]

func _on_cash_changed(new_cash: float) -> void:
	cash_label.text = "Cash: $%.2f" % new_cash
