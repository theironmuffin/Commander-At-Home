class_name CameraControls
extends Camera3D

@export_category("Movement Settings")
@export var move_speed: float = 12.0
@export var fast_multiplier: float = 2.5
@export var mouse_sensitivity: float = 0.003

@export_category("Zoom Settings")
@export var zoom_speed: float = 1.2
@export var zoom_smoothness: float = 10.0
@export var min_zoom: float = 3.0
@export var max_zoom: float = 25.0
@export var stick_deadzone: float = 0.18
@export var trigger_zoom_speed: float = 12.0
@export var stick_look_speed: float = 1.8

@export_category("Home Settings")
@export var home_position: Vector3 = Vector3(0.0, 3.0, 7.0)
@export var home_rotation: Vector3 = Vector3(deg_to_rad(-51.0), 0.0, 0.0)

@onready var target_y: float = home_position.y

var is_rotating: bool = false
var is_resetting: bool = false
var active_tween: Tween = null

func _ready() -> void:
	position = home_position
	rotation = home_rotation
	target_y = home_position.y

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_rotating = event.pressed
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if is_rotating else Input.MOUSE_MODE_VISIBLE)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_y = clampf(target_y - zoom_speed, min_zoom, max_zoom)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_y = clampf(target_y + zoom_speed, min_zoom, max_zoom)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and is_rotating:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		rotation.x = clampf(rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	elif event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		reset_to_home()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_STICK:
		reset_to_home()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if is_resetting:
		return
	# Smooth zoom target lerp
	if not is_equal_approx(position.y, target_y):
		position.y = lerpf(position.y, target_y, zoom_smoothness * delta)

	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_DOWN): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1.0

	var parent_modal: bool = get_parent() != null and get_parent().has_method("is_modal_ui_open") and bool(get_parent().is_modal_ui_open())
	if not parent_modal and not Input.get_connected_joypads().is_empty():
		var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
		var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
		var r_vec := Vector2(rx, ry)
		var lt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
		var rt: float = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
		if rt > 0.1:
			if r_vec.length() > stick_deadzone:
				rotate_y(-r_vec.x * stick_look_speed * delta)
				rotate_object_local(Vector3.RIGHT, -r_vec.y * stick_look_speed * delta)
				rotation.x = clampf(rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))
		elif lt > 0.1:
			if absf(ry) > stick_deadzone:
				target_y = clampf(target_y + ry * trigger_zoom_speed * delta, min_zoom, max_zoom)
		elif r_vec.length() > stick_deadzone:
			input_dir.x += r_vec.x
			input_dir.y -= r_vec.y

	if input_dir != Vector3.ZERO:
		var current_speed := move_speed * (fast_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		translate(input_dir.normalized() * current_speed * delta)

func reset_to_home() -> void:
	target_y = home_position.y
	is_resetting = true
	if active_tween and active_tween.is_running():
		active_tween.kill()

	var target_quat := Quaternion.from_euler(home_rotation)
	active_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(self, "position", home_position, 0.45)
	active_tween.tween_property(self, "quaternion", target_quat, 0.45)
	active_tween.chain().tween_callback(func():
		is_resetting = false
		rotation = home_rotation
		target_y = home_position.y
	)
