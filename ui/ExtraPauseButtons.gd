extends VBoxContainer

onready var recorder = get_tree().get_root().get_node("ModLoader/YOMIRecord/YOMIRecorder")
onready var ffmpeg = get_tree().get_root().get_node("ModLoader/YOMIRecord/FFmpeg")

func _ready():
	$"%RecordButton".connect("pressed", self, "_on_record")
	$"%ScreenshotButton".connect("pressed", self, "_on_screenshot")
	$"%OptionsButton".connect("pressed", self, "_on_options")

func _on_record():
	if not ffmpeg.ffmpeg_path:
		return recorder.show_options()
	recorder.record()
	
func _on_screenshot():
	recorder.screenshot()
	
func _on_options():
	recorder.show_options(!recorder.options_menu_visible())
