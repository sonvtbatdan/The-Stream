extends HBoxContainer

@onready var view_label: Label = %ViewLabel
@onready var sub_label:  Label = %SubLabel

func _ready() -> void:
	var font := load("res://assets/fonts/Gameplay.ttf") as FontFile
	for lbl: Label in [view_label, sub_label]:
		if font:
			lbl.add_theme_font_override("font", font)
			lbl.add_theme_font_size_override("font_size", 18)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	view_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	sub_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))

	GameManager.views_changed.connect(_on_views_changed)
	GameManager.subs_changed.connect(_on_subs_changed)
	_on_views_changed(GameManager.views)
	_on_subs_changed(GameManager.subs)

func _on_views_changed(n: int) -> void:
	view_label.text = "VIEWS  " + GameManager.format_views(n)

func _on_subs_changed(n: int) -> void:
	sub_label.text = "SUBS  " + GameManager.format_views(n)
