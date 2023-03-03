extends Node

var file_path = "user://yomirecord/options.json"

var default_options = {
	"resolution": 720,
	"hide_hud": false,
	"hide_supermeter": false,
	"use_steam_overlay": false,
	"recording_format": "mp4",
	"speed": 1.0,
	"native_speed": true,
	"volume": 100,
	"normalize_audio": false,
	"mute_audio": false,
	"skip_files": false,
	"exec_console": false,
	"pause_between_frames": false,
	"drp_record": true
}

var options = {}


func _ready():
	load_options()
	name = "YOMIRecordOptions"

func load_file():
	var file = File.new()
	var err = file.open(file_path, File.READ)
	if err: return null
	return parse_json(file.get_as_text())

func load_options():
	var loaded_options = load_file()
	if loaded_options == null: loaded_options = default_options.duplicate()
	options = loaded_options

	var file = File.new()
	if not file.file_exists(file_path):
		save_options()
	print("YOMIRecord: Loaded options")

func save_options():
	var dir = Directory.new()
	if not dir.dir_exists("user://yomirecord"):
		dir.make_dir("user://yomirecord")

	var file = File.new()
	file.open(file_path, File.WRITE)
	file.store_line(to_json(options))
	file.close()
	print("YOMIRecord: Saved options")

func get_option(path: String):
	if options.has(path):
		return options.get(path)
	return default_options.get(path)

func set_option(path: String, value):
	if not default_options.has(path): return
	options[path] = value
	return
