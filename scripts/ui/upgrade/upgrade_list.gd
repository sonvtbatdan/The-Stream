extends Panel

const UpgradeItem := preload("res://scenes/ui/upgrade/upgrade_item.tscn")

@onready var vbox: VBoxContainer = $UpgradeVBox

func _ready() -> void:
	for child in vbox.get_children():
		child.free()
	for id in UpgradeManager.UPGRADES:
		var item: Control = UpgradeItem.instantiate()
		vbox.add_child(item)
		item.setup(id)
