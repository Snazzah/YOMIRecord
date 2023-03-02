extends "res://SoupModOptions/ModOptions.gd"

func _ready():
	var yomiRecord = get_tree().get_root().get_node("ModLoader/YOMIRecord")
	var my_menu = generate_menu("YOMIRecord", yomiRecord.MOD_NAME)
	my_menu.add_label("lbl1", "Redirecting...")
	my_menu.connect("menu_opened", self, "_yomirecord_menu_opened", [my_menu])
	add_menu(my_menu)
	print("YOMIRecord: Mod options loaded")

func _yomirecord_menu_opened(menu):
	var recorder = get_tree().get_root().get_node("ModLoader/YOMIRecord/YOMIRecorder")
	self.menu.hide()
	menu.hide()
	recorder.show_options()
