extends Node2D

signal download_status_changed()

var ffmpeg_path = null
var ffmpeg_can_fork = true
var download_status = 0
var download_failed = false
var download_progress = 0

onready var http = HTTPRequest.new()
onready var http_verifier = HTTPRequest.new()

var binary_release_url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
var binary_sha256_url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256"
var binary_output_path = "user://yomirecord/ffmpeg-release-essentials.zip"
var binary_final_path = "user://yomirecord/ffmpeg.exe"

var BINARY_USER_PATH = ProjectSettings.globalize_path("user://yomirecord/ffmpeg.exe")

func _ready():
	http.use_threads = true
	http.connect("request_completed", self, "_http_request_completed")
	http.set_download_file(binary_output_path)
	add_child(http)

	http_verifier.use_threads = true
	http_verifier.connect("request_completed", self, "_http_verifier_request_completed")
	add_child(http_verifier)

	name = "FFmpeg"
	check_for_binaries()

func get_version(ffmpeg = ffmpeg_path):
	var output = []
	var exit_code = OS.execute(ffmpeg, ["-version"], true, output, false, false)
	if exit_code == ERR_CANT_FORK: return ""
	elif exit_code != 0: return null
	else: return output[0].substr(15).split(" ")[0]
	return null

func get_winget_version():
	var output = []
	var exit_code = OS.execute("winget", ["--version"], true, output, false, false)
	if exit_code != 0: return null
	else: return output[0]
	return null

func unzip_archive(from, to):
	var exit_code = OS.execute("tar", ["-xf", ProjectSettings.globalize_path(from), "-C", ProjectSettings.globalize_path(to)], true, [], false, false)
	print("YOMIRecord: extracted result ", exit_code)
	return exit_code == 0

func list_files_in_directory(path):
	var files = PoolStringArray()
	var dir = Directory.new()
	dir.open(path)
	dir.list_dir_begin()

	while true:
		var file = dir.get_next()
		if file == "":
			break
		elif not file.begins_with("."):
			files.append(file)

	dir.list_dir_end()
	return files

func check_for_binaries():
	var available_paths = PoolStringArray([
		BINARY_USER_PATH,
		"ffmpeg",
		"ffmpeg.exe"
	])
	var file = File.new()

	ffmpeg_path = null
	for binary_path in available_paths:
		if binary_path == BINARY_USER_PATH and not file.file_exists(BINARY_USER_PATH): continue
		var version = get_version(binary_path)
		print("YOMIRecord: tried %s, got " % binary_path, version)
		if version == "":
			print("YOMIRecord: trying to use ffmpeg gave an ERR_CANT_FORK, so we are backing off")
			ffmpeg_can_fork = false
			break
		if version != null:
			ffmpeg_path = binary_path
			break
		ffmpeg_can_fork = true

func using_downloaded_binary():
	return ffmpeg_path == BINARY_USER_PATH

func download():
	if download_status != 0: return

	var winget_ver = get_winget_version()
	if winget_ver != null:
		print("YOMIRecord: Detected winget ", winget_ver)
		
		download_status = 4
		emit_signal("download_status_changed")
		
		var thread = Thread.new()
		thread.start(self, "_winget_download_thread")
	else:
		print("YOMIRecord: winget not found, reverting to legacy download")
		download_binary()

func _winget_download_thread():
	var output = []
	var exit_code = OS.execute("winget", ["install", "ffmpeg"], true, output, false, false)
	print("YOMIRecord: Installed FFmpeg via winget with exit code ", exit_code)
	print(output[0])
	
	download_status = 0
	check_for_binaries()
	emit_signal("download_status_changed")

func download_binary():
	if download_status != 0: return

	# Remove previous binary if there is one
	var file = File.new()
	if file.file_exists(binary_output_path):
		var dir = Directory.new()
		dir.remove(binary_output_path)

	download_failed = false
	download_status = 1
	download_progress = 0
	emit_signal("download_status_changed")

	var request = http.request(binary_release_url)
	if request != OK:
		download_failed = true
		download_status = 0
		emit_signal("download_status_changed")
		push_error("YOMIRecord: HTTP request failed")

func _on_download_fail():
	download_failed = true
	download_status = 0
	emit_signal("download_status_changed")
	_cleanup_download()
	
func _delete_directory_recursively(dir_path):
	var dir = Directory.new()
	if dir.open(dir_path) != OK: return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if !file_name.begins_with("."):
			if dir.current_is_dir(): _delete_directory_recursively(dir_path + "/" + file_name)
			else: dir.remove(dir_path + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	dir.remove(dir_path)

func _cleanup_download():
	var file = File.new()
	if file.file_exists(binary_output_path):
		var dir = Directory.new()
		dir.remove(binary_output_path)

	var files = list_files_in_directory("user://yomirecord")
	print(files)
	for file_name in files:
		if file_name.begins_with("ffmpeg-") and file_name.ends_with("-essentials_build"):
			_delete_directory_recursively("user://yomirecord/" + file_name)
			break

#### This locks up the game, so we are just gonna use powershell
#### gdunzip would be better if I could just straight up write to files but whatever
#func extract_download():
#	var gdunzip = load("res://modloader/gdunzip/gdunzip.gd").new()
#	gdunzip.load(binary_output_path)
#	for zipFilePath in gdunzip.files:
#		if zipFilePath.ends_with("/bin/ffmpeg.exe"):
#			var uncompressed = gdunzip.uncompress(zipFilePath)
#			if !uncompressed:
#				_on_download_fail()
#				push_error("YOMIRecord: Decompression Failed")
#				return
#
#			print("Writing file ", gdunzip.files[zipFilePath])
#			var tmp_file = File.new()
#			tmp_file.open(binary_final_path, File.WRITE)
#			tmp_file.store_buffer(uncompressed)
#			tmp_file.close()

func extract_download():
	print("starting to extract")
	unzip_archive(binary_output_path, "user://yomirecord")
	
	var dir = Directory.new()
	dir.open("user://yomirecord")
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var ffmpeg_folder = ""
	while file_name != "":
		if file_name.begins_with("ffmpeg-") and file_name.ends_with("-essentials_build"):
			ffmpeg_folder = file_name
			break
		file_name = dir.get_next()
	if ffmpeg_folder != "":
		var err = dir.rename("user://yomirecord/%s/bin/ffmpeg.exe" % ffmpeg_folder, "user://yomirecord/ffmpeg.exe")
		if err == OK:
			download_status = 0
			_cleanup_download()
			check_for_binaries()
			emit_signal("download_status_changed")
			return
	_on_download_fail()
	push_error("YOMIRecord: Failed to find binary in archive")

func request_hash_verification():
	var verifier_request = http_verifier.request(binary_sha256_url)
	if verifier_request != OK:
		_on_download_fail()
		push_error("YOMIRecord: Verifier HTTP request failed")
		return

func verify_sha256(download_sha256):
	var file = File.new()
	var our_sha256 = file.get_sha256(binary_output_path)
	var matches = our_sha256 == download_sha256

	if matches:
		download_status = 3
		emit_signal("download_status_changed")
		yield (get_tree(), "idle_frame")
		yield (get_tree(), "idle_frame")
		extract_download()
		return

	_on_download_fail()
	push_error("YOMIRecord: SHA verification failed")

func _http_request_completed(result, response_code: int, headers: PoolStringArray, _body: PoolByteArray):
	print("YOMIRecord: Request finished with %d (%d) " % [response_code, result])
	if download_status == 0: return
	if result != OK or response_code > 399:
		_on_download_fail()
		push_error("YOMIRecord: Download Failed")
		return

	# Follow redirects
	if response_code in [301, 302, 303]:
		var next_url = null
		for header in headers:
			if header.begins_with("Location: https://"):
				next_url = header.substr(10)

		if next_url != null:
			print("YOMIRecord: Download redirecting to %s" % next_url)

			var request = http.request(next_url)
			if request != OK:
				_on_download_fail()
				push_error("YOMIRecord: Subsequent HTTP request failed")
		else:
			_on_download_fail()
			push_error("YOMIRecord: Redirect failed")
		return

	download_status = 2
	emit_signal("download_status_changed")
	request_hash_verification()

func _process(delta):
	if download_status == 1:
		var content_length = http.get_body_size()
		var content_downloaded = http.get_downloaded_bytes()
		if content_length == -1 and content_downloaded > 2000: return
		var new_percent = int((float(content_downloaded) / float(content_length)) * 100)
		if download_progress != new_percent:
			download_progress = new_percent
			emit_signal("download_status_changed")

func _http_verifier_request_completed(result, response_code: int, headers: PoolStringArray, body: PoolByteArray):
	print("YOMIRecord: Verifier request finished with %d " % response_code)
	if download_status == 0: return
	if result != OK or response_code > 399:
		_on_download_fail()
		push_error("YOMIRecord: Verification request failed")
		return

	# Follow redirects
	if response_code in [301, 302, 303]:
		var next_url = null
		for header in headers:
			if header.begins_with("Location: https://"):
				next_url = header.substr(10)

		if next_url != null:
			print("YOMIRecord: Verification location redirecting to %s" % next_url)

			var request = http_verifier.request(next_url)
			if request != OK:
				_on_download_fail()
				push_error("YOMIRecord: Subsequent Verifier HTTP request failed")
		else:
			_on_download_fail()
			push_error("YOMIRecord: Redirect failed")
		return

	verify_sha256(body.get_string_from_ascii())
