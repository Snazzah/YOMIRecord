extends PanelContainer

var max_time = 10.0
var ttl = max_time
var active = false
var leaving = false
var hovering = false

func _ready():
	hide()

func _process(delta):
	if hovering or leaving or not active: return
	ttl -= delta
	if ttl <= 0: _on_close()
	$LifetimeBar.rect_scale[0] = ttl / max_time

func _input(event):
	if event.get_class() == "InputEventMouseMotion":
		hovering = Rect2(Vector2(), rect_size).has_point(get_local_mouse_position())

func set_text(text: String):
	$Label.bbcode_text = text

func pop(alert = false):
	var sound: AudioStreamPlayer2D
	if alert: sound = $"../../ToastAlertSound"
	else: sound = $"../../ToastSound"
	if sound: sound.play()
	active = true
	show()

func _on_close():
	leaving = true
	queue_free()
	return
