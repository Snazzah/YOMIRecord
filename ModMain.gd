extends Node2D

var recorder: Node
var options: Node
var ffmpeg: Node

var MOD_NAME = "Your Only Move Is Record"
onready var VERSION = ModLoader._readMetadata("res://YOMIRecord/_metadata")["version"]

func _init(modLoader = ModLoader):
	options = load("res://YOMIRecord/Options.gd").new()
	add_child(options)
	ffmpeg = load("res://YOMIRecord/FFmpeg.gd").new()
	add_child(ffmpeg)
	recorder = load("res://YOMIRecord/Recorder.gd").new()
	add_child(recorder)

	modLoader.installScriptExtension("res://YOMIRecord/MLMainHook.gd")
	var file = File.new()
	if file.file_exists("res://SoupModOptions/ModOptions.gd"):
		modLoader.installScriptExtension("res://YOMIRecord/ModOptionsAddon.gd")
	if file.file_exists("res://DiscordRichPresence/ModHook.gd"):
		modLoader.installScriptExtension("res://YOMIRecord/DRPAddon.gd")

	name = "YOMIRecord"
