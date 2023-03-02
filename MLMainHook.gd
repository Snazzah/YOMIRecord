extends "res://modloader/MLMainHook.gd"


func _ready():
	call_deferred("_yomirecord_init")

func _yomirecord_init():
	_yomirecord_add_to_playback_controls()
	_yomirecord_add_to_main()

func _yomirecord_add_to_playback_controls():
	var replay_controls = get_tree().get_root().get_node("Main/UILayer/ReplayControls")
	var controls = load("res://YOMIRecord/ui/ExtraReplayOptions.tscn").instance()
	var option_list = replay_controls.get_node("VBoxContainer/Contents/VBoxContainer")
	var above_node = option_list.get_node("HBoxContainer")
	option_list.add_child_below_node(above_node, controls, true)
	controls.set_owner(replay_controls)
	print("YOMIRecord: Injected into playback controls")

func _yomirecord_add_to_main():
	var main = get_tree().get_root().get_node("Main")
	
	# Record Options
	ModLoader.appendNodeInScene(main, "YOMIRecordOptionsWindow", "UILayer", "res://YOMIRecord/RecordOptions.tscn")
	
	# Overlay Layer
	var overlay = load("res://YOMIRecord/ui/overlay/OverlayLayer.tscn").instance()
	var uilayer = main.get_node("UILayer")
	main.add_child(overlay)
	overlay.set_owner(main)

	# Pause Buttons
	var yomirecord_pause_btns = load("res://YOMIRecord/ui/ExtraPauseButtons.tscn").instance()
	var pause_buttons: VBoxContainer = uilayer.get_node("GameUI/PausePanel/VBoxContainer")
	var save_replay_btn = pause_buttons.get_node("SaveReplayButton")
	pause_buttons.add_child_below_node(save_replay_btn, yomirecord_pause_btns, true)
	yomirecord_pause_btns.set_owner(main)

	print("YOMIRecord: Injected into main")
