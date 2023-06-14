extends Node

signal recording_starting()
signal recording_started()
signal recording_ending()
signal recording_ended()

var recording = false
var record_effect: AudioEffectRecord
var recording_id = -1
var recording_bus_volume = 0
var recording_frame_skip = 10
var recording_frames = []
var recording_end_buffer = 115
var recording_show_playback_controls = false

var thread_counter_current:int = 0
var thread_counter_final:int = 0
var writer_thread:Thread
var writer_thread_semaphore:Semaphore = Semaphore.new()

var default_recording_bus_volume = -0.130497

onready var options = get_tree().get_root().get_node("ModLoader/YOMIRecord/YOMIRecordOptions")
onready var ffmpeg = get_tree().get_root().get_node("ModLoader/YOMIRecord/FFmpeg")

# NOTE: This recorder sets FX audio volume to a constant value to ensure the recording works well
# For compatibility for https://steamcommunity.com/sharedfiles/filedetails/?id=2939891318

# TODO
# - option menu
#  - gif format?
#       gif quality sucks, I might skip this honestly, maybe limit frames
#       https://superuser.com/questions/1049606/reduce-generated-gif-size-using-ffmpeg
#  - quality slider (https://superuser.com/questions/677576/what-is-crf-used-for-in-ffmpeg)
#       gonna skip this for now, avg recordings are 3MB and wouldnt make sense to have
#       quality slider for 1MB instead
# BUGS
#  - fix resetting in between the P1 WIN screen (and not making tt stay there for the whole recording)

func _ready():
	name = "YOMIRecorder"
	print("YOMIRecord: Recorder spawned")

func generate_timed_name():
	var time = Time.get_datetime_dict_from_system()
	var strings = [str(time.year), str(time.month), str(time.day), str(time.hour), str(time.minute)]
	var string = ""
	for s in strings:
		string += s
		string += "-"
	string += str(time.second)
	return string

# Instead of setting visibility (because UILayer sets it every frame)
# I can use self_modulate to make it invisible
func set_ui_visibility(visible = false):
	var uilayer = get_tree().get_root().get_node("Main/UILayer")
	var to_self_modulate = [
		uilayer.get_node("GameUI/TopInfo"),
		uilayer.get_node("GameUI/TopInfoMP"),
		uilayer.get_node("GameUI/TopInfoReplay"),
		uilayer.get_node("GameUI/HelpButton"),
		uilayer.get_node("GameUI/AdvantageLabel"),
		uilayer.get_node("GameUI/PredictionSettingsOpenButton"),
		uilayer.get_node("P1TurnTimerBar"),
		uilayer.get_node("P1TurnTimerLabel"),
		uilayer.get_node("P2TurnTimerBar"),
		uilayer.get_node("P2TurnTimerLabel"),
		uilayer.get_node("OpponentDisconnectedLabel")
	]
	var to_modulate = [
		uilayer.get_node("GameUI/PausePanel"),
		uilayer.get_node("GameUI/HelpScreen"),
		uilayer.get_node("GameUI/ResetZoomButton"),
		uilayer.get_node("YOMIRecordOptionsWindow"),
		uilayer.get_node("ResimRequestScreen"),
		uilayer.get_node("PostGameButtons"),
		uilayer.get_node("NagWindow"),
		uilayer.get_node("ReplayControls"),
		get_tree().get_root().get_node("Main/HudLayer/HudLayer/HboxContainer"), # Show style buttons
		uilayer.get_node("DiscordRichPresenceLayer") # Discord Rich Presence
	]

	if options.get_option("hide_supermeter"):
		to_modulate.append(uilayer.get_node("GameUI/BottomBar/ActionButtons/VBoxContainer/P1InfoContainer"))
		to_modulate.append(uilayer.get_node("GameUI/BottomBar/ActionButtons/VBoxContainer2/P2InfoContainer"))

	if options.get_option("hide_chat"):
		to_modulate.append(uilayer.get_node("ChatWindow"))

	if not visible:
		for node in to_modulate:
			if node: node.modulate.a = 0
		for node in to_self_modulate:
			if node: node.self_modulate.a = 0
	else:
		for node in to_modulate:
			if node: node.modulate.a = 1
		for node in to_self_modulate:
			if node: node.self_modulate.a = 1

func screenshot():
	var dir = Directory.new()
	if not dir.dir_exists("user://screenshots"):
		dir.make_dir("user://screenshots")

	var hudlayer = get_tree().get_root().get_node("Main/HudLayer/HudLayer")
	var uilayer = get_tree().get_root().get_node("Main/UILayer")
	var ghostlayer = get_tree().get_root().get_node("Main/GhostLayer")
	var p1_action_btns = uilayer.get_node("GameUI/BottomBar/ActionButtons/VBoxContainer/P1ActionButtons")
	var p2_action_btns = uilayer.get_node("GameUI/BottomBar/ActionButtons/VBoxContainer2/P2ActionButtons")
	var replay_controls = uilayer.get_node("ReplayControls")
	var prevHudVis = hudlayer.visible
	var prevGhostVis = ghostlayer.visible
	var prevP1ActionBtnsVis = p1_action_btns.visible
	var prevP2ActionBtnsVis = p2_action_btns.visible
	var showPlaybackControls = not Network.multiplayer_active and Global.show_playback_controls

	hudlayer.visible = not options.get_option("hide_hud")
	ghostlayer.visible = false
	p1_action_btns.visible = false
	p2_action_btns.visible = false
	Global.show_playback_controls = false
	set_ui_visibility(false)
	set_yomirecord_overlay_visible(false)

	var file_name = generate_timed_name() + ".png"
	var filepath = "user://screenshots/" + file_name
	print("YOMIRecord: Saving screenshot to " + filepath)
	yield(VisualServer, "frame_post_draw")

	if options.get_option("use_steam_overlay") and Steam.isOverlayEnabled():
		Steam.triggerScreenshot()
		yield (get_tree(), "idle_frame")
		yield (get_tree(), "idle_frame")
		yield (get_tree(), "idle_frame")
		yield (get_tree(), "idle_frame")
	else:
		var viewport: Viewport = Global.current_game.get_viewport()
		viewport.set_clear_mode(Viewport.CLEAR_MODE_ONLY_NEXT_FRAME)

		var image = viewport.get_texture().get_data()
		image.flip_y()
		
		var resolution = int(options.get_option("resolution"))
		if resolution < get_viewport().size.y:
			image.generate_mipmaps()
		if resolution != get_viewport().size.y:
			var resolution_scale = float(resolution) / float(get_viewport().size.y)
			image.resize(
				int(get_viewport().size.x * resolution_scale),
				int(get_viewport().size.y * resolution_scale),
				Image.INTERPOLATE_NEAREST
			)
		image.save_png(filepath)
		spawn_file_toast("screenshot", file_name)

	hudlayer.visible = prevHudVis
	ghostlayer.visible = prevGhostVis
	p1_action_btns.visible = prevP1ActionBtnsVis
	p2_action_btns.visible =  prevP2ActionBtnsVis
	Global.show_playback_controls = showPlaybackControls
	set_ui_visibility(true)
	set_yomirecord_overlay_visible(true)

func parse_char_name(char_name: String):
	# Fix modded character names
	if char_name.find("F-") == 0 and char_name.find("__") != -1:
		var name_split: PoolStringArray = char_name.split("__")
		if name_split[0].length() == 34 and name_split[1]:
			return name_split[1]

	return char_name

func get_player_names():
	var p1name = Global.current_game.match_data.selected_characters[1].name
	var p2name = Global.current_game.match_data.selected_characters[2].name
	if Global.current_game.match_data.has("user_data"):
		if Global.current_game.match_data.user_data.has("p1") and Global.current_game.match_data.user_data.p1 != "":
			p1name = Global.current_game.match_data.user_data.p1
		if Global.current_game.match_data.user_data.has("p2") and Global.current_game.match_data.user_data.p2 != "":
			p2name = Global.current_game.match_data.user_data.p2
	return [parse_char_name(p1name), parse_char_name(p2name)]

func get_native_speed():
	if not options.get_option("native_speed"): return null
	var speed = options.get_option("speed")
	if speed == 1: return 1
	elif speed == 0.5: return 2
	elif speed == 0.25: return 4
	return null

func spawn_file_toast(type, file_name: String, time_elapsed_msec = -1, frames_taken = -1):
	var toast_container = get_tree().get_root().get_node("Main/YOMIRecordLayer/Overlay/Toasts/ToastContainer")
	var toast = load("res://YOMIRecord/ui/overlay/FileToast.tscn").instance()
	toast_container.add_child(toast)
	toast.file_path = "user://%ss/%s" % [type, file_name]
	toast.folder_path = "user://%ss" % type

	var truncated_filename: String = file_name
	if file_name.length() > 30:
		truncated_filename = truncated_filename.substr(0, 27) + "..."

	if time_elapsed_msec != -1 and frames_taken != -1:
		var time_elapsed = float(time_elapsed_msec) / 1000
		var fps = float(frames_taken) / time_elapsed
		toast.set_text("Saved %s to [color=#fff][u]%s[/u][/color] [color=#555](took %.2fs, %.2f fps)[/color]" % [type, truncated_filename, time_elapsed, fps])
	else:
		toast.set_text("Saved %s to [color=#fff][u]%s[/u][/color]" % [type, file_name])

	toast.pop()

func spawn_text_toast(text, alert = false):
	var toast_container = get_tree().get_root().get_node("Main/YOMIRecordLayer/Overlay/Toasts/ToastContainer")
	var toast = load("res://YOMIRecord/ui/overlay/TextToast.tscn").instance()
	toast_container.add_child(toast)
	toast.set_text(text)
	toast.pop(alert)

func set_rendering_overlay(visible = true, frames = -1):
	var overlay: MarginContainer = get_tree().get_root().get_node("Main/YOMIRecordLayer/Overlay/RenderingOverlay")
	overlay.visible = visible
	var frames_label: Label = overlay.get_node("HContainer/Detail")
	var eta = float(frames) / 40
	var eta2 = float(frames) / 20
	frames_label.text = "Rendering %d frames... ETA: %.2f-%.2f seconds" % [frames, eta, eta2]
	var warn_label: Label = overlay.get_node("HContainer/FrameWarn")
	warn_label.visible = not options.get_option("pause_between_frames")
	yield(VisualServer, "frame_post_draw")

func set_yomirecord_overlay_visible(visible = true):
	var layer: CanvasLayer = get_tree().get_root().get_node("Main/YOMIRecordLayer")
	layer.visible = visible

func change_window_icon(icon: String):
	if OS.get_name() == "Windows":
		OS.set_native_icon("res://YOMIRecord/icon/icon_%s.ico" % icon)

func reset_playback():
	Global.current_game.game_started = false
	Global.current_game.start_playback()

func show_options(visible = true):
	var option_menu = get_tree().get_root().get_node("Main/UILayer/YOMIRecordOptionsWindow")
	if visible:
		option_menu.refresh()
		option_menu.show()
	else: option_menu.hide()

func options_menu_visible():
	var option_menu: PanelContainer = get_tree().get_root().get_node("Main/UILayer/YOMIRecordOptionsWindow")
	return option_menu.visible

func pre_recording():
	emit_signal("recording_starting")

	# Hide Layers
	var hudlayer = get_tree().get_root().get_node("Main/HudLayer/HudLayer")
	hudlayer.visible = not options.get_option("hide_hud")
	recording_show_playback_controls = Global.show_playback_controls
	if not Network.multiplayer_active: Global.show_playback_controls = false
	set_ui_visibility(false)
	set_yomirecord_overlay_visible(false)
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")

	# Reset and Start Playback
	var playback_speed = get_native_speed()
	if playback_speed == null: playback_speed = 1
	Global.playback_speed_mod = playback_speed
	reset_playback()
	Global.frame_advance = true
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	Global.current_game.advance_frame_input = true
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	Global.frame_advance = false

	# Handle Audio and Record Audio Effect
	recording_bus_volume = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Fx"))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Fx"), default_recording_bus_volume)
	if typeof(record_effect) == 0:
		var idx = AudioServer.get_bus_index("Fx")
		record_effect = AudioEffectRecord.new()
		print("YOMIRecord: Created record audio effect")
		AudioServer.add_bus_effect(idx, record_effect)

	# Prepare Directory
	recording_id = randi() % 10000000
	var local_path = "user://yomirecord/_recording_%d" % recording_id
	Directory.new().make_dir(local_path)

	# Start writer thread
	writer_thread = Thread.new()
	writer_thread.start(self, "_thread_write", local_path, 0)
	
	# Window Stuff
	OS.set_window_title("Your Only Move Is HUSTLE (Recording)")
	change_window_icon("recording")

	# Start recording
	record_effect.set_recording_active(true)
	emit_signal("recording_started")

func post_recording():
	recording = false
	emit_signal("recording_ending")
	var local_path = "user://yomirecord/_recording_%d" % recording_id
	
	# Show Layers
	var hudlayer = get_tree().get_root().get_node("Main/HudLayer/HudLayer")
	var frames_length = recording_frames.size()
	set_yomirecord_overlay_visible(true)
	set_ui_visibility(true)
	if not Network.multiplayer_active: Global.show_playback_controls = recording_show_playback_controls

	# Save Audio Recording
	record_effect.set_recording_active(false)
	var recording_stream = record_effect.get_recording()
	recording_stream.save_to_wav("%s/audio.wav" % local_path)

	print("YOMIRecord: Writing frames...")
	OS.set_window_title("Your Only Move Is HUSTLE (Rendering)")
	change_window_icon("rendering")
	set_rendering_overlay(true, frames_length)
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	var start_time = Time.get_ticks_msec()
	Global.frame_advance = true
#	var pause_btwn = options.get_option("pause_between_frames")
#	for frame_num in frames_length:
#		var frame: Image = recording_frames[frame_num]
#		frame.save_png("%s/%d.png" % [local_path, frame_num])
#		if pause_btwn: yield (get_tree(), "idle_frame")
#	recording_frames.clear()
	thread_counter_final = frames_length
	writer_thread_semaphore.post()
	writer_thread.wait_to_finish()
	recording_frames.clear()
	thread_counter_current = 0
	thread_counter_final = 0
	Global.frame_advance = false

	var dir = Directory.new()
	if not dir.dir_exists("user://recordings"):
		dir.make_dir("user://recordings")

	print("YOMIRecord: Rendering...")
	var global_path = ProjectSettings.globalize_path(local_path)
	var usernames = get_player_names()
	var video_name = Utils.filter_filename(ReplayManager.generate_mp_replay_name(usernames[0], usernames[1]))
	var audio_muted = options.get_option("mute_audio")

	# Apply Resolution
	var resolution = int(options.get_option("resolution"))
	var res_size = "640x360"
	if resolution != 360:
		var resolution_scale = float(resolution) / float(get_viewport().size.y)
		res_size = "%dx%d" % [int(ceil(get_viewport().size.x * resolution_scale)), int(get_viewport().size.y * resolution_scale)]
		if resolution == 480: res_size = "854x480"

	# Apply Format
	var ffmpegExtraArgs = PoolStringArray()
	var format = options.get_option("recording_format")
	if format == "webm":
		video_name += ".webm"
		ffmpegExtraArgs.append_array([
			"-c:v", "libvpx-vp9"
		])
	if format == "avi":
		video_name += ".avi"
		ffmpegExtraArgs.append_array([
			"-c:v", "mpeg4"
		])
		ffmpegExtraArgs.append("-c:v mpeg4")
	else:
		video_name += ".mp4"
		ffmpegExtraArgs.append_array([
			"-c:v", "libx264",
			"-preset", "veryslow"
		])

	# Apply Audio Effects
	if not audio_muted:
		var volume = float(options.get_option("volume")) / 100
		if volume != 1:
			ffmpegExtraArgs.append_array([
				"-filter:a", "volume=%.2f" % volume
			])
		if options.get_option("normalize_audio"):
			ffmpegExtraArgs.append_array([
				"-filter:a", "dynaudnorm"
			])
	
	# Change Video Speed
	var native_speed = get_native_speed()
	var framerate = 60
	if get_native_speed()  == null:
		framerate = int(float(60) * options.get_option("speed"))
		if framerate <= 0: framerate = 1
		# https://superuser.com/a/1667260
		if not audio_muted and framerate != 60:
			ffmpegExtraArgs.append_array([
				"-af", "asetrate=44100*%s,aresample=44100" % str(float(framerate) / 60)
			])

	if audio_muted: ffmpegExtraArgs.append("-an")

	# Run FFmpeg
	var final_path = ProjectSettings.globalize_path("user://recordings/" + video_name)
	var ffmpegArgs = PoolStringArray([
		"-framerate", str(framerate),
		"-i", "%s/%%d.png" % global_path,
		"-i", "%s/audio.wav" % global_path,
		"-map", "0:v",
		"-map", "1:a",
#		"-crf", "17", # 17-37 (37 is worst)
		"-pix_fmt", "yuv420p",
		"-vf", "vflip",
		"-s", res_size,
		"-sws_flags", "neighbor",
		"-metadata", "title=" + usernames[0].replace('"', '\\"') + " vs " + usernames[1].replace('"', '\\"'),
		"-metadata", "comment=Recording of Your Only Move Is Hustle [%s], created using Y.O.M.I Record" % Global.VERSION.replace('"', '\\"')
	]);
	print(ffmpegArgs)
	var ffmpegCommand = PoolStringArray([ffmpegArgs.join(" "), ffmpegExtraArgs.join(" "), '"%s"' % final_path]).join(" ");
	print("YOMIRecord: running command: %s " % ffmpegCommand, PoolStringArray([ffmpegArgs.join(" "), ffmpegExtraArgs.join(" "), '"%s"' % final_path]).join(" "))
	var output = []
	var exit_code = OS.execute(ffmpeg.ffmpeg_path, ffmpegArgs + ffmpegExtraArgs + PoolStringArray([final_path]), true, output, true, options.get_option("exec_console"))
	print("YOMIRecord: ", output[0])
	print("YOMIRecord: Finished rendering with exit code %d" % exit_code)

	if exit_code != 0:
		spawn_text_toast("[color=#ff0000]Error![/color] FFmpeg failed to render that capture, Check with your settings or try again later!", true)
	var time_elapsed = Time.get_ticks_msec() - start_time

	# File Cleanup
	if not options.get_option("skip_files"):
		if dir.open(local_path) == OK:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name != "." and file_name != ".." and not dir.current_is_dir():
					dir.remove(local_path + "/" + file_name)
				file_name = dir.get_next()
		dir.remove(local_path)
	
	# Variable Cleanup
	recording_frame_skip = 10
	recording_end_buffer = 115
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Fx"), recording_bus_volume)
	
	# Update playback controls slider
	var playback_controls = get_tree().get_root().get_node("Main/UILayer/ReplayControls")
	var playback_hslider: HSlider = get_tree().get_root().get_node("Main/UILayer/ReplayControls/VBoxContainer/Contents/VBoxContainer/PlaybackSpeed")
	playback_hslider.value = 2

	OS.set_window_title("Your Only Move Is HUSTLE")
	change_window_icon("normal")
	OS.request_attention()
	print("YOMIRecord: Cleanup finished, output file in ", final_path)

	hudlayer.visible = true
	set_rendering_overlay(false)
	emit_signal("recording_ended")
	if exit_code == 0: spawn_file_toast("recording", video_name, time_elapsed, frames_length)

func record():
	if recording: return false

	if is_instance_valid(Global.current_game):
		if Network.multiplayer_active:
			spawn_text_toast("[color=#ff0000]Error![/color] Can't record while in multiplayer!", true)
			return false
		if ReplayManager.frames[1].size() == 0 or ReplayManager.frames[2].size() == 0:
			spawn_text_toast("[color=#ff0000]Error![/color] There aren't any frames to record!", true)
			return false
		pre_recording()
		recording = true
		return true
	return false

func _thread_write(local_path):
	while true:
		writer_thread_semaphore.wait()
		if thread_counter_final > 0 && thread_counter_final == thread_counter_current:
			return
		var frame: Image = recording_frames[thread_counter_current]
		frame.save_png("%s/%d.png" % [local_path, thread_counter_current])
		recording_frames[thread_counter_current] = null
		thread_counter_current += 1

func _physics_process(delta):
	if not recording: return

	# Skip leading frames, seems to solve the offset issue and frames bleeding into the editor
	if recording_frame_skip > 0:
		recording_frame_skip -= 1
		return
	
	# Replay stopped playback? End recording early
	if not ReplayManager.playback and Global.current_game.is_waiting_on_player() and not Global.current_game.game_finished:
		return post_recording()

	# Snapshot and Store Image
	var viewport: Viewport = Global.current_game.get_viewport()
	viewport.set_clear_mode(Viewport.CLEAR_MODE_ONLY_NEXT_FRAME)
	var image = viewport.get_texture().get_data()
#	image.flip_y()

	# Save Frame
	recording_frames.append(image)
	writer_thread_semaphore.post()

	# Pad ending frames, to show player win UI
	if Global.current_game.game_finished:
		if recording_end_buffer > 0:
			recording_end_buffer -= 1
			return
		return post_recording()
