extends HBoxContainer

onready var recorder = get_tree().get_root().get_node("ModLoader/YOMIRecord/YOMIRecorder")
onready var ffmpeg = get_tree().get_root().get_node("ModLoader/YOMIRecord/FFmpeg")

func _ready():
	$"%PlaybackReset".connect("pressed", self, "_on_reset")
	$"%ScreenshotFrame".connect("pressed", self, "_on_screenshot")
	$"%RecordPlayback".connect("pressed", self, "_on_record")
	$"%YOMIRecordOptions".connect("pressed", self, "_on_options")

func _on_reset():
	if is_instance_valid(Global.current_game):
		recorder.reset_playback()

func _on_record():
	if not ffmpeg.ffmpeg_path:
		return recorder.show_options()
	recorder.show_options(false)
	recorder.record()
	
func _on_screenshot():
	recorder.screenshot()
	
func _on_options():
	recorder.show_options(!recorder.options_menu_visible())
