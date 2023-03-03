extends Window

onready var yomiRecord = get_tree().get_root().get_node("ModLoader/YOMIRecord")
onready var recorder = get_tree().get_root().get_node("ModLoader/YOMIRecord/YOMIRecorder")
onready var options = get_tree().get_root().get_node("ModLoader/YOMIRecord/YOMIRecordOptions")
onready var ffmpeg = get_tree().get_root().get_node("ModLoader/YOMIRecord/FFmpeg")

var in_replay = false

var refreshing_opts = false

var resolutions = PoolStringArray(["360p", "480p", "720p", "1080p", "1440p"])
var formats = PoolStringArray(["mp4", "webm", "avi"])
var speeds = PoolStringArray(["0.25x", "0.5x", "1x", "2x", "4x"])

func _ready():
	$"%Title".text = "%s (%s)" % [yomiRecord.MOD_NAME, yomiRecord.VERSION]
	$"%Version".text = "v%s" % yomiRecord.VERSION
	$"%FFmpegDescLabel".connect("meta_clicked", self, "_on_meta_clicked")
	$"%AuthorLabel".connect("meta_clicked", self, "_on_meta_clicked")
	$"%DRPRequireLabel".connect("meta_clicked", self, "_on_meta_clicked_overlay")
	$"%ShowButton".connect("pressed", self, "hide")
	$"%RecordButton".connect("pressed", self, "_on_record")
	$"%RefreshButton".connect("pressed", self, "refresh")
	$"%DownloadButton".connect("pressed", self, "_on_download")
	$"%ScreenshotsFolderButton".connect("pressed", self, "_on_open_screenshot_folder")
	$"%RecordingsFolderButton".connect("pressed", self, "_on_open_recording_folder")

	# Hook Options
	$"%Resolution".connect("item_selected", self, "_on_option_select", ["resolution", $"%Resolution"])
	$"%HideHUDToggle".connect("toggled", self, "_on_checkbox_toggle", ["hide_hud"])
	$"%SteamOverlayToggle".connect("toggled", self, "_on_checkbox_toggle", ["use_steam_overlay"])
	$"%Format".connect("item_selected", self, "_on_option_select", ["recording_format", $"%Format"])
	$"%Volume".connect("value_changed", self, "_on_range_change", ["volume", $"%Volume", true])
	$"%Speed".connect("item_selected", self, "_on_option_select", ["speed", $"%Speed"])
	$"%NativeSpeedToggle".connect("toggled", self, "_on_checkbox_toggle", ["native_speed"])
	$"%NormalAudioToggle".connect("toggled", self, "_on_checkbox_toggle", ["normalize_audio"])
	$"%MuteAudioToggle".connect("toggled", self, "_on_checkbox_toggle", ["mute_audio"])
	$"%DRPToggle".connect("toggled", self, "_on_checkbox_toggle", ["drp_record"])
	$"%SkipFilesToggle".connect("toggled", self, "_on_checkbox_toggle", ["skip_files"])
	$"%ExecWindowToggle".connect("toggled", self, "_on_checkbox_toggle", ["exec_console"])
	$"%PauseBetweenFramesToggle".connect("toggled", self, "_on_checkbox_toggle", ["pause_between_frames"])
	$"%HideSupermeterToggle".connect("toggled", self, "_on_checkbox_toggle", ["hide_supermeter"])

	var file = File.new()
	if file.file_exists("res://DiscordRichPresence/ModHook.gd"):
		$"%DRPRequireLabel".hide()
	else: $"%DRPToggle".disabled = true

	for res in resolutions: $"%Resolution".add_item(res)
	for fmt in formats: $"%Format".add_item(fmt)
	for spd in speeds: $"%Speed".add_item(spd)
	refresh_values()
	refresh_ui()

	ffmpeg.connect("download_status_changed", self, "_on_download_status_change")
	hide()

func _on_meta_clicked(meta):
	OS.shell_open(meta)

func _on_meta_clicked_overlay(meta):
	Steam.activateGameOverlayToWebPage(meta)

func _on_download():
	ffmpeg.download_binary()

func _on_record():
	recorder.show_options(false)
	recorder.record()

func refresh():
	refresh_values()
	refresh_ui()
	refresh_options()

func _on_download_status_change():
	refresh_ui()

func _on_open_screenshot_folder():
	var dir = Directory.new()
	if not dir.dir_exists("user://screenshots"):
		dir.make_dir("user://screenshots")
	OS.shell_open(ProjectSettings.globalize_path("user://screenshots"))

func _on_open_recording_folder():
	var dir = Directory.new()
	if not dir.dir_exists("user://recordings"):
		dir.make_dir("user://recordings")
	OS.shell_open(ProjectSettings.globalize_path("user://recordings"))

func refresh_values():
	in_replay = is_instance_valid(Global.current_game) and ReplayManager.frames[1].size() != 0 and ReplayManager.frames[2].size() != 0

func refresh_ffmpeg_ui():
	$"%DownloadButton".disabled = ffmpeg.download_status != 0 or ffmpeg.ffmpeg_path != null and not ffmpeg.using_downloaded_binary() or OS.get_name() != "Windows"
	$"%FFmpegWarnLabel".visible = ffmpeg.download_status == 0 and ffmpeg.ffmpeg_path == null

	if ffmpeg.download_status != 0:
		$"%FFmpegStatusLabel".add_color_override("font_color", Color(0, 0, 1))
		if ffmpeg.download_status == 1:
			$"%FFmpegStatusLabel".text = "Downloading... %d%%" % ffmpeg.download_progress
		elif ffmpeg.download_status == 2:
			$"%FFmpegStatusLabel".text = "Verifying..."
		elif ffmpeg.download_status == 3:
			$"%FFmpegStatusLabel".text = "Extracting..."
	else:
		if ffmpeg.using_downloaded_binary():
			$"%DownloadButton".text = "Update"
		else:
			$"%DownloadButton".text = "Download"

		if ffmpeg.ffmpeg_path:
			var version = ffmpeg.get_version()
			if version == null:
				ffmpeg.check_for_binaries()
				return refresh_ui()
			$"%FFmpegStatusLabel".text = "Installed v%s" % version.split("-")[0]
			$"%FFmpegStatusLabel".add_color_override("font_color", Color(0, 1, 0))
		else:
			$"%FFmpegStatusLabel".add_color_override("font_color", Color(1, 0, 0))
			if ffmpeg.download_failed:
				$"%FFmpegStatusLabel".text = "Download failed!"
			else: $"%FFmpegStatusLabel".text = "Not installed!"
			
	pass

func refresh_options():
	if refreshing_opts: return
	refreshing_opts = true
	$"%HideHUDToggle".set_pressed_no_signal(options.get_option("hide_hud"))

	var resolution = "%dp" % options.get_option("resolution")
	$"%Resolution".selected = -1
	for i in resolutions.size():
		if resolutions[i] == resolution: $"%Resolution".selected = i

	$"%SteamOverlayToggle".set_pressed_no_signal(options.get_option("use_steam_overlay"))

	var format = options.get_option("recording_format")
	$"%Format".selected = -1
	for i in formats.size():
		if formats[i] == format: $"%Format".selected = i

	var speed = "%sx" % str(options.get_option("speed"))
	$"%Speed".selected = -1
	for i in speeds.size():
		if speeds[i] == speed: $"%Speed".selected = i

	$"%NativeSpeedToggle".set_pressed_no_signal(options.get_option("native_speed"))
	$"%Volume".value = options.get_option("volume")
	$"%NormalAudioToggle".set_pressed_no_signal(options.get_option("normalize_audio"))
	$"%MuteAudioToggle".set_pressed_no_signal(options.get_option("mute_audio"))
	$"%DRPToggle".set_pressed_no_signal(options.get_option("drp_record"))
	$"%SkipFilesToggle".set_pressed_no_signal(options.get_option("skip_files"))
	$"%ExecWindowToggle".set_pressed_no_signal(options.get_option("exec_console"))
	$"%PauseBetweenFramesToggle".set_pressed_no_signal(options.get_option("pause_between_frames"))
	$"%HideSupermeterToggle".set_pressed_no_signal(options.get_option("hide_supermeter"))
	refreshing_opts = false

func _on_checkbox_toggle(value: bool, setting: String):
	options.set_option(setting, value)
	options.save_options()

func _on_option_select(idx: int, setting: String, option_button: OptionButton):
	var option = option_button.get_item_text(idx)
	var value = option
	if setting == "resolution":
		value = int(option.left(option.length() - 1))
	elif setting == "speed":
		value = float(option.left(option.length() - 1))
	options.set_option(setting, value)
	options.save_options()

func _on_range_change(_value, setting: String, range_opt: Range, use_int = false):
	if refreshing_opts: return
	# NOTE: _value returned a boolean for some reason?
	var value = range_opt.value
	if use_int: options.set_option(setting, int(value))
	else: options.set_option(setting, value)
	options.save_options()

func refresh_ui():
	$"%RecordButton".disabled = not in_replay or not ffmpeg.ffmpeg_path
	refresh_ffmpeg_ui()
