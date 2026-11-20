extends Area3D

signal card_played(card_node: Node3D)
signal card_hovered(card_node: Node3D)
signal card_unhovered(card_node: Node3D)
signal card_clicked_on_battlefield(card_node: Node3D, button_index: int)
signal card_texture_ready(texture: Texture2D)

const CARD_SHADER = preload("res://card_shader.gdshader")
const LOCAL_CARD_BACK = preload("res://card_back.jpg")
const BELEREN_FONT = preload("res://Beleren.ttf")

@export var card_data: Dictionary = {}

@onready var front_face: MeshInstance3D = $FrontFace
@onready var front_http_request: HTTPRequest = $FrontHTTPRequest
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var is_hovered: bool = false
var is_interactive: bool = true
var is_on_battlefield: bool = false
var is_tapped: bool = false
var is_token: bool = false
var in_library: bool = false
var is_highlighted: bool = false

var front_face_rest_pos: Vector3
var stored_front_texture: Texture2D = null
var stored_back_texture: Texture2D = null
var custom_sleeve_texture: Texture2D = null

# Multi-Face / Split / Adventure / Room State
var active_face_index: int = 0
var is_on_adventure: bool = false
var is_fused_cast: bool = false
var unlocked_rooms: Array[int] = []

var attached_to: Node3D = null
var attachments: Array[Node3D] = []

var counter_amount: int = 0
var plus_counters: int = 0
var custom_counters: Dictionary = {}
var marked_damage: int = 0
var has_deathtouch_damage: bool = false
var dynamic_power: int = 0
var dynamic_toughness: int = 0
var is_attacking: bool = false
var is_blocking: bool = false
var attacking_target_player_id: int = 0
var blocking_target_creature: Node3D = null

var has_summoning_sickness: bool = true
var loyalty_activated_this_turn: bool = false
var goaded_by_player_id: int = 0
var custom_statuses: Array[String] = []
var has_flying: bool = false
var parsed_abilities: Dictionary = {}

# Continuous Layer Modifications (Layer 6 & Layer 7)
var layer_granted_keywords: Array[String] = []
var layer_controller_id: int = -1
var type_overrides: Array[String] = []
var color_overrides: Array[String] = []
var abilities_removed: bool = false
var layer_base_power_override: int = -999
var layer_base_toughness_override: int = -999
var layer_pt_switched: bool = false
var layer_power_modifier: int = 0
var layer_toughness_modifier: int = 0
var temp_power_modifier: int = 0
var temp_toughness_modifier: int = 0

var counter_label: Label3D
var token_label: Label3D
var pt_badge_label: Label3D
var combat_badge_label: Label3D
var status_badge_label: Label3D
var shader_mat: ShaderMaterial
var active_tween: Tween = null
var hover_tween: Tween = null
var damage_flash_mesh: MeshInstance3D = null
var damage_flash_mat: StandardMaterial3D = null
var damage_flash_tween: Tween = null
var damage_shake_tween: Tween = null
var _fly_phase: float = 0.0
var _flair_root: Node3D = null
var _flair_items: Array[Dictionary] = []
var _flair_signature: String = ""

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	front_face_rest_pos = front_face.position

	shader_mat = ShaderMaterial.new()
	shader_mat.shader = CARD_SHADER
	front_face.material_override = shader_mat

	var back_tex_to_use: Texture2D = custom_sleeve_texture if custom_sleeve_texture != null else LOCAL_CARD_BACK
	if back_tex_to_use:
		shader_mat.set_shader_parameter("back_tex", back_tex_to_use)

	if front_http_request:
		front_http_request.request_completed.connect(_on_front_request_completed)

	_setup_counter_label()
	_setup_pt_badge()
	_setup_combat_badge()
	_setup_status_badge()
	_setup_damage_flash()
	_setup_flair_root()
	_fly_phase = randf() * TAU
	reset_dynamic_stats()

	var event_bus = get_node_or_null("/root/EventBus")
	if event_bus:
		event_bus.phase_changed.connect(_on_phase_changed_trigger)

func _setup_counter_label() -> void:
	counter_label = Label3D.new()
	counter_label.name = "CounterLabel"
	counter_label.position = Vector3(0.00, 0.05, -0.05)
	counter_label.rotation_degrees = Vector3(-90, 0, 0)
	counter_label.font_size = 40
	counter_label.outline_size = 20
	counter_label.text = ""
	if BELEREN_FONT:
		counter_label.font = BELEREN_FONT
	front_face.add_child(counter_label)

func _setup_pt_badge() -> void:
	pt_badge_label = Label3D.new()
	pt_badge_label.name = "PTBadge"
	pt_badge_label.position = Vector3(0.22, 0.05, 0.35)
	pt_badge_label.rotation_degrees = Vector3(-90, 0, 0)
	pt_badge_label.font_size = 36
	pt_badge_label.outline_size = 18
	pt_badge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pt_badge_label.pixel_size = 0.0025
	pt_badge_label.modulate = Color(1, 1, 0.8, 1)
	if BELEREN_FONT:
		pt_badge_label.font = BELEREN_FONT
	front_face.add_child(pt_badge_label)

func _setup_combat_badge() -> void:
	combat_badge_label = Label3D.new()
	combat_badge_label.name = "CombatBadge"
	combat_badge_label.position = Vector3(-0.22, 0.06, -0.35)
	combat_badge_label.rotation_degrees = Vector3(-90, 0, 0)
	combat_badge_label.font_size = 34
	combat_badge_label.outline_size = 18
	combat_badge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	combat_badge_label.pixel_size = 0.0025
	combat_badge_label.visible = false
	if BELEREN_FONT:
		combat_badge_label.font = BELEREN_FONT
	front_face.add_child(combat_badge_label)


func _setup_status_badge() -> void:
	status_badge_label = Label3D.new()
	status_badge_label.name = "StatusBadge"
	status_badge_label.position = Vector3(-0.20, 0.055, 0.35)
	status_badge_label.rotation_degrees = Vector3(-90, 0, 0)
	status_badge_label.font_size = 24
	status_badge_label.outline_size = 14
	status_badge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_badge_label.pixel_size = 0.0022
	status_badge_label.modulate = Color(0.75, 0.92, 1.0, 1.0)
	status_badge_label.visible = false
	if BELEREN_FONT:
		status_badge_label.font = BELEREN_FONT
	front_face.add_child(status_badge_label)

func set_combat_status(status: String) -> void:
	if not combat_badge_label: return
	if status.is_empty():
		combat_badge_label.visible = false
		combat_badge_label.text = ""
	else:
		combat_badge_label.visible = true
		combat_badge_label.text = status
		combat_badge_label.modulate = Color(1.0, 0.35, 0.3, 1.0) if status.begins_with("ATK") else Color(0.35, 0.75, 1.0, 1.0)

func grant_layer_keyword(kw: String) -> void:
	var lower_kw := kw.to_lower()
	if not lower_kw in layer_granted_keywords:
		layer_granted_keywords.append(lower_kw)

func has_keyword(kw: String) -> bool:
	var lower_kw := kw.to_lower()
	if lower_kw in layer_granted_keywords:
		return true
	if abilities_removed:
		return false
	var keywords: Array = parsed_abilities.get("keywords", [])
	return lower_kw in keywords

func get_active_oracle_text() -> String:
	return str(MagicRules.get_card_attribute(card_data, "oracle_text", "", active_face_index))

func get_active_texture() -> Texture2D:
	if active_face_index == 1 and stored_back_texture != null:
		return stored_back_texture
	return stored_front_texture

func transform_card(target_face: int = -1) -> void:
	if not MagicRules.has_multiple_faces(card_data): return
	active_face_index = (1 - active_face_index) if target_face < 0 else clampi(target_face, 0, 1)
	parsed_abilities = OracleParser.parse_oracle_text(get_active_oracle_text())
	_apply_face_texture()
	refresh_visual_status()

func _apply_face_texture() -> void:
	if in_library: return
	var tex := get_active_texture()
	if tex and shader_mat:
		shader_mat.set_shader_parameter("front_tex", tex)
	elif active_face_index == 1 and stored_back_texture == null:
		_fetch_face_texture(1)

func reset_dynamic_stats() -> void:
	var base_pow: int = layer_base_power_override if layer_base_power_override != -999 else MagicRules.get_base_power(card_data, active_face_index)
	var base_tou: int = layer_base_toughness_override if layer_base_toughness_override != -999 else MagicRules.get_base_toughness(card_data, active_face_index)
	var final_pow: int = base_pow + plus_counters + layer_power_modifier + temp_power_modifier
	var final_tou: int = base_tou + plus_counters + layer_toughness_modifier + temp_toughness_modifier
	if layer_pt_switched or (has_meta("pt_switched") and bool(get_meta("pt_switched"))):
		var swap := final_pow
		final_pow = final_tou
		final_tou = swap
	dynamic_power = final_pow
	dynamic_toughness = final_tou

func refresh_visual_status() -> void:
	_apply_parsed_keywords()
	_refresh_keyword_flairs()
	reset_dynamic_stats()
	var is_creat := MagicRules.is_creature(card_data, active_face_index)
	if is_creat and is_on_battlefield:
		pt_badge_label.visible = true
		pt_badge_label.text = "%d/%d" % [dynamic_power, dynamic_toughness]
		if marked_damage > 0:
			pt_badge_label.text += " (-%d)" % marked_damage
	else:
		pt_badge_label.visible = false

	if status_badge_label:
		status_badge_label.visible = false

func _input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not is_interactive: return
	if event is InputEventMouseButton and event.pressed:
		if is_on_battlefield:
			if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed):
				card_clicked_on_battlefield.emit(self, MOUSE_BUTTON_RIGHT)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				card_clicked_on_battlefield.emit(self, MOUSE_BUTTON_LEFT)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			card_played.emit(self)

func set_highlight(active: bool) -> void:
	is_highlighted = active
	if shader_mat:
		shader_mat.set_shader_parameter("outline_active", active)

func toggle_tap() -> void:
	is_tapped = not is_tapped
	var eb := get_node_or_null("/root/EventBus")
	if eb and eb.has_method("play_sfx"):
		eb.play_sfx("tap")
	var target_y_rot := deg_to_rad(-90.0) if is_tapped else 0.0
	if active_tween and active_tween.is_running(): active_tween.kill()
	active_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(self, "rotation:y", target_y_rot, 0.25)

func make_active(data: Dictionary) -> void:
	in_library = false
	setup(data)
	if collision_shape: collision_shape.disabled = false

func set_sleeve_texture(tex: Texture2D) -> void:
	custom_sleeve_texture = tex
	var back_tex_to_use: Texture2D = custom_sleeve_texture if custom_sleeve_texture != null else LOCAL_CARD_BACK
	if shader_mat and back_tex_to_use:
		shader_mat.set_shader_parameter("back_tex", back_tex_to_use)
		if in_library:
			shader_mat.set_shader_parameter("front_tex", back_tex_to_use)

func _update_foil_shader() -> void:
	if shader_mat:
		var is_foil: bool = (not in_library) and bool(card_data.get("is_foil", false))
		shader_mat.set_shader_parameter("foil_amount", 1.0 if is_foil else 0.0)

func setup(data: Dictionary) -> void:
	card_data = data
	is_interactive = true
	parsed_abilities = OracleParser.parse_oracle_text(get_active_oracle_text())
	refresh_visual_status()
	_update_foil_shader()

	var cur_tex := get_active_texture()
	if cur_tex != null:
		shader_mat.set_shader_parameter("front_tex", cur_tex)
		return

	_fetch_face_texture(active_face_index)
	# Pre-cache back face texture for DFCs
	if MagicRules.has_multiple_faces(card_data) and (MagicRules.is_transform(card_data) or MagicRules.is_modal_dfc(card_data)):
		_fetch_face_texture(1)

func _get_face_image_url(face_idx: int) -> String:
	if MagicRules.has_multiple_faces(card_data):
		var f := MagicRules.get_face_data(card_data, face_idx)
		var f_url := str(f.get("image_url", ""))
		if not f_url.is_empty(): return f_url
		var uris: Dictionary = f.get("image_uris", {})
		var u := str(uris.get("normal", uris.get("small", "")))
		if not u.is_empty(): return u
	return str(card_data.get("image_url", ""))

func _fetch_face_texture(face_idx: int) -> void:
	var url := _get_face_image_url(face_idx)
	if url.is_empty(): return
	var cached_tex := CardManager.get_cached_image_texture(url)
	if cached_tex:
		if face_idx == 1 and (MagicRules.is_transform(card_data) or MagicRules.is_modal_dfc(card_data)):
			stored_back_texture = cached_tex
		else:
			stored_front_texture = cached_tex
		if face_idx == active_face_index and not in_library:
			shader_mat.set_shader_parameter("front_tex", cached_tex)
			card_texture_ready.emit(cached_tex)
		return

	if face_idx == 0 and front_http_request and front_http_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED and is_inside_tree():
		front_http_request.request(url, ["User-Agent: MTGBrawlSim/1.0", "Accept: */*"])
	else:
		var tmp_http := HTTPRequest.new()
		add_child(tmp_http)
		var req_id := tmp_http.get_instance_id()
		var card_id := get_instance_id()
		tmp_http.request_completed.connect(func(_res, code, _hdr, body):
			var r := instance_from_id(req_id)
			if r and is_instance_valid(r): r.queue_free()
			var self_ref := instance_from_id(card_id)
			if not (self_ref and is_instance_valid(self_ref)): return
			if code == 200:
				var tex := CardManager.store_image_to_cache(url, body)
				if tex:
					if face_idx == 1 and (MagicRules.is_transform(card_data) or MagicRules.is_modal_dfc(card_data)):
						stored_back_texture = tex
					else:
						stored_front_texture = tex
					if active_face_index == face_idx and not in_library and shader_mat:
						shader_mat.set_shader_parameter("front_tex", tex)
					card_texture_ready.emit(tex)
		)
		if is_inside_tree():
			tmp_http.request(url, ["User-Agent: MTGBrawlSim/1.0", "Accept: */*"])

func _apply_parsed_keywords() -> void:
	if has_keyword("haste"): has_summoning_sickness = false
	has_flying = has_keyword("flying")

func get_activated_abilities() -> Array:
	return parsed_abilities.get("activated_abilities", [])

func get_triggered_abilities() -> Array:
	return parsed_abilities.get("triggered_abilities", [])

func _on_front_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var front_url := _get_face_image_url(0)
		var texture := CardManager.store_image_to_cache(front_url, body)
		if texture:
			stored_front_texture = texture
			card_texture_ready.emit(texture)
			if not in_library and active_face_index == 0:
				shader_mat.set_shader_parameter("front_tex", texture)

func setup_library() -> void:
	is_interactive = false; in_library = true; is_on_battlefield = false; is_tapped = false
	rotation = Vector3(0, 0, PI)
	force_unhover()
	if collision_shape: collision_shape.disabled = true
	_update_foil_shader()
	var back_tex_to_use: Texture2D = custom_sleeve_texture if custom_sleeve_texture != null else LOCAL_CARD_BACK
	if back_tex_to_use and shader_mat:
		shader_mat.set_shader_parameter("front_tex", back_tex_to_use)
		shader_mat.set_shader_parameter("back_tex", back_tex_to_use)

func _on_mouse_entered() -> void:
	if not is_interactive: return
	is_hovered = true
	card_hovered.emit(self)
	var parent := get_parent()
	if parent: parent.move_child(self, parent.get_child_count() - 1)
	var hover_target_pos := front_face_rest_pos
	if is_on_battlefield:
		hover_target_pos += Vector3(-0.15, 0.05, 0.0) if is_tapped else Vector3(0.0, 0.05, -0.15)
	else:
		hover_target_pos += Vector3(0.0, 0.05, -0.15)
	_tween_front_face_position(hover_target_pos, 0.15)

func _on_mouse_exited() -> void:
	if not is_interactive: return
	is_hovered = false
	card_unhovered.emit(self)
	_tween_front_face_position(front_face_rest_pos, 0.15)

func force_unhover() -> void:
	if is_hovered:
		is_hovered = false
		_tween_front_face_position(front_face_rest_pos, 0.15)

func _tween_front_face_position(target_pos: Vector3, duration: float) -> void:
	if hover_tween and hover_tween.is_running(): hover_tween.kill()
	hover_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hover_tween.tween_property(front_face, "position", target_pos, duration)

func modify_counters(amount: int) -> void:
	counter_amount += amount
	var eb := get_node_or_null("/root/EventBus")
	if eb and eb.has_method("play_sfx") and amount != 0:
		eb.play_sfx("counter_up" if amount > 0 else "counter_down")
	plus_counters = counter_amount
	_refresh_counter_label()
	refresh_visual_status()

func modify_named_counter(counter_type: String, delta: int) -> void:
	var eb := get_node_or_null("/root/EventBus")
	if eb and eb.has_method("play_sfx") and delta != 0:
		eb.play_sfx("counter_up" if delta > 0 else "counter_down")
	var key := counter_type.strip_edges().to_lower()
	if key.is_empty(): return
	var next_val: int = max(0, int(custom_counters.get(key, 0)) + delta)
	if next_val == 0:
		custom_counters.erase(key)
	else:
		custom_counters[key] = next_val
	_refresh_counter_label()

func get_named_counter(counter_type: String) -> int:
	return int(custom_counters.get(counter_type.strip_edges().to_lower(), 0))

func _refresh_counter_label() -> void:
	if not counter_label: return
	var lines: Array[String] = []
	if counter_amount != 0:
		lines.append("%+d/%+d" % [counter_amount, counter_amount])
	for k in custom_counters.keys():
		lines.append("%s: %d" % [str(k).capitalize(), int(custom_counters[k])])
	counter_label.text = "\n".join(lines)
	if counter_amount > 0:
		counter_label.modulate = Color(0.4, 0.9, 0.4, 1)
	elif counter_amount < 0:
		counter_label.modulate = Color(0.9, 0.4, 0.4, 1)
	else:
		counter_label.modulate = Color(0.95, 0.85, 0.4, 1)

func clear_counters() -> void:
	counter_amount = 0; plus_counters = 0; marked_damage = 0; has_deathtouch_damage = false
	temp_power_modifier = 0; temp_toughness_modifier = 0
	custom_counters.clear()
	_refresh_counter_label()
	set_combat_status("")
	refresh_visual_status()

func mark_as_token() -> void:
	is_token = true
	if token_label == null:
		token_label = Label3D.new()
		token_label.name = "TokenLabel"
		token_label.position = Vector3(0.0, 0.05, -0.35)
		token_label.rotation_degrees = Vector3(-90, 0, 0)
		token_label.font_size = 40; token_label.outline_size = 20
		token_label.text = "TOKEN"; token_label.modulate = Color(0.4, 0.7, 1.0, 1)
		if BELEREN_FONT: token_label.font = BELEREN_FONT
		front_face.add_child(token_label)

func _on_phase_changed_trigger(new_phase: int) -> void:
	if not is_on_battlefield: return
	var oracle_text: String = get_active_oracle_text().to_lower()
	if new_phase == 1 and "at the beginning of your upkeep" in oracle_text:
		set_highlight(true)
		var t := create_tween()
		t.tween_property(self, "scale", Vector3(1.1, 1.1, 1.1), 0.3)
		t.chain().tween_property(self, "scale", Vector3.ONE, 0.3)
		t.chain().tween_callback(func(): set_highlight(false))

func _setup_damage_flash() -> void:
	if not front_face: return
	damage_flash_mesh = MeshInstance3D.new()
	damage_flash_mesh.name = "DamageFlashOverlay"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.64, 0.89)
	damage_flash_mesh.mesh = qm
	damage_flash_mesh.position = Vector3(0.0, 0.025, 0.0)
	damage_flash_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	damage_flash_mat = StandardMaterial3D.new()
	damage_flash_mat.albedo_color = Color(1.0, 0.12, 0.12, 0.0)
	damage_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	damage_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	damage_flash_mesh.material_override = damage_flash_mat
	damage_flash_mesh.visible = false
	front_face.add_child(damage_flash_mesh)

func play_damage_flash() -> void:
	if damage_flash_mesh and damage_flash_mat:
		if damage_flash_tween and damage_flash_tween.is_running():
			damage_flash_tween.kill()
		damage_flash_mesh.visible = true
		damage_flash_mat.albedo_color = Color(1.0, 0.12, 0.12, 0.68)
		damage_flash_tween = create_tween()
		damage_flash_tween.tween_property(damage_flash_mat, "albedo_color:a", 0.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		damage_flash_tween.tween_callback(func():
			if damage_flash_mesh and is_instance_valid(damage_flash_mesh):
				damage_flash_mesh.visible = false
		)

	if front_face:
		if damage_shake_tween and damage_shake_tween.is_running():
			damage_shake_tween.kill()
		front_face.position = front_face_rest_pos
		damage_shake_tween = create_tween()
		damage_shake_tween.tween_property(front_face, "position:x", front_face_rest_pos.x + 0.045, 0.045)
		damage_shake_tween.tween_property(front_face, "position:x", front_face_rest_pos.x - 0.045, 0.055)
		damage_shake_tween.tween_property(front_face, "position:x", front_face_rest_pos.x + 0.025, 0.045)
		damage_shake_tween.tween_property(front_face, "position:x", front_face_rest_pos.x, 0.05)

func _process(delta: float) -> void:
	if not front_face: return
	_fly_phase += delta * 2.4
	if not (is_on_battlefield and has_custom_status("Monstrous")) and not front_face.scale.is_equal_approx(Vector3.ONE):
		front_face.scale = front_face.scale.lerp(Vector3.ONE, minf(1.0, delta * 10.0))
	if is_on_battlefield and has_flying and not is_hovered and not in_library:
		var bob_y: float = front_face_rest_pos.y + 0.14 + sin(_fly_phase) * 0.032
		if not (hover_tween and hover_tween.is_running()):
			front_face.position.y = lerpf(front_face.position.y, bob_y, minf(1.0, delta * 8.0))
		front_face.rotation.z = sin(_fly_phase * 0.72) * deg_to_rad(3.5)
		front_face.rotation.x = cos(_fly_phase * 0.55) * deg_to_rad(2.2)
	else:
		if not front_face.rotation.is_zero_approx():
			front_face.rotation = front_face.rotation.lerp(Vector3.ZERO, minf(1.0, delta * 10.0))
		if not is_hovered and not (hover_tween and hover_tween.is_running()) and not is_equal_approx(front_face.position.y, front_face_rest_pos.y):
			front_face.position.y = lerpf(front_face.position.y, front_face_rest_pos.y, minf(1.0, delta * 10.0))

	if _flair_root and _flair_root.visible and not _flair_items.is_empty():
		for item in _flair_items:
			var node: Node3D = item["node"]
			if not is_instance_valid(node): continue
			var mode: String = item["mode"]
			var speed: float = item["speed"]
			var phase: float = _fly_phase * speed + float(item["offset"])
			if mode == "orbit":
				node.position = Vector3(cos(phase) * float(item["rx"]), float(item["y"]) + sin(phase * 1.7) * 0.02, sin(phase) * float(item["rz"]))
			elif mode == "pulse":
				var s: float = 1.0 + sin(phase) * float(item["amp"])
				node.scale = Vector3(s, 1.0, s)
			elif mode == "slash":
				node.position.x = sin(phase) * 0.28
				node.rotation.y = phase * 1.5
			elif mode == "glint":
				var g: float = maxf(0.0, sin(phase))
				node.scale = Vector3.ONE * (0.4 + g * 0.9)
			elif mode == "spin":
				node.rotation.y = phase * 0.85
				node.position.y = float(item["y"]) + sin(phase * 1.4) * 0.018
			elif mode == "breathe":
				var b: float = 1.0 + sin(phase) * 0.035
				front_face.scale = Vector3(b, 1.0, b)

func _setup_flair_root() -> void:
	if not front_face: return
	_flair_root = Node3D.new()
	_flair_root.name = "KeywordFlairs"
	front_face.add_child(_flair_root)

func _add_flair_mote(col: Color, radius: float, mode: String, speed: float, offset: float, rx: float = 0.34, rz: float = 0.46, y: float = 0.04) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(rx, y, 0.0)
	_flair_root.add_child(mi)
	_flair_items.append({"node": mi, "mode": mode, "speed": speed, "offset": offset, "rx": rx, "rz": rz, "y": y, "amp": 0.15})

func _add_flair_ring(col: Color, size: Vector2, y: float, mode: String, speed: float, amp: float = 0.06) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.position = Vector3(0.0, y, 0.0)
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	_flair_root.add_child(mi)
	_flair_items.append({"node": mi, "mode": mode, "speed": speed, "offset": 0.0, "rx": 0.0, "rz": 0.0, "y": y, "amp": amp})

func _add_flair_blade(col: Color, offset: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.11, 0.015, 0.03)
	mi.mesh = bm
	mi.position = Vector3(0.0, 0.045, -0.44)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	_flair_root.add_child(mi)
	_flair_items.append({"node": mi, "mode": "slash", "speed": 1.6, "offset": offset, "rx": 0.0, "rz": 0.0, "y": 0.045, "amp": 0.0})

func _add_flair_torus(col: Color, inner_r: float, outer_r: float, y: float, speed: float) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = outer_r
	tm.rings = 16
	tm.ring_segments = 8
	mi.mesh = tm
	mi.position = Vector3(0.0, y, -0.25)
	mi.rotation_degrees = Vector3(65.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	_flair_root.add_child(mi)
	_flair_items.append({"node": mi, "mode": "spin", "speed": speed, "offset": 0.0, "rx": 0.0, "rz": 0.0, "y": y, "amp": 0.0})

func _refresh_keyword_flairs() -> void:
	if not _flair_root: return
	var has_gy_play := (not is_on_battlefield and not in_library) and (
		not str(parsed_abilities.get("flashback_cost", "")).is_empty()
		or not str(parsed_abilities.get("escape_cost", "")).is_empty()
		or not str(parsed_abilities.get("unearth_cost", "")).is_empty()
	)
	var active := (is_on_battlefield and not in_library) or has_gy_play
	_flair_root.visible = active
	if not active: return

	var kws: Array[String] = []
	for kw in ["flying", "first strike", "double strike", "deathtouch", "trample", "vigilance", "lifelink", "haste", "reach", "indestructible", "hexproof", "shroud", "ward", "menace", "flash", "defender"]:
		if has_keyword(kw):
			kws.append(kw)
	var is_creat := MagicRules.is_creature(card_data, active_face_index)
	var is_sick := is_on_battlefield and is_creat and has_summoning_sickness and not has_keyword("haste")
	var is_goaded := is_on_battlefield and goaded_by_player_id > 0
	var prot_arr: Array = parsed_abilities.get("protection_from", [])
	var has_prot := is_on_battlefield and not prot_arr.is_empty()
	var c_stats := custom_statuses.duplicate()

	var sig := "%s|sick:%s|goad:%s|prot:%s|gy:%s|cs:%s" % [",".join(kws), str(is_sick), str(is_goaded), str(has_prot), str(has_gy_play), ",".join(c_stats)]
	if sig == _flair_signature: return
	_flair_signature = sig

	for ch in _flair_root.get_children():
		ch.queue_free()
	_flair_items.clear()

	if has_gy_play and not is_on_battlefield:
		_add_flair_ring(Color(0.30, 0.95, 0.85, 0.25), Vector2(0.71, 0.96), -0.004, "pulse", 1.6, 0.04)
		return

	# Keyword Auras & Accents
	if "indestructible" in kws:
		_add_flair_ring(Color(1.0, 0.84, 0.25, 0.28), Vector2(0.73, 0.98), -0.008, "pulse", 1.1, 0.03)
	if "hexproof" in kws or "shroud" in kws or "ward" in kws:
		_add_flair_ring(Color(0.35, 0.85, 1.0, 0.22), Vector2(0.74, 0.99), -0.006, "pulse", 1.4, 0.05)
	if "vigilance" in kws:
		_add_flair_ring(Color(0.95, 0.96, 1.0, 0.20), Vector2(0.71, 0.96), -0.005, "pulse", 0.9, 0.025)
	if "defender" in kws:
		_add_flair_ring(Color(0.55, 0.65, 0.78, 0.24), Vector2(0.72, 0.97), -0.005, "pulse", 0.6, 0.015)
	if "flying" in kws:
		_add_flair_ring(Color(0.55, 0.85, 1.0, 0.16), Vector2(0.68, 0.92), -0.03, "pulse", 1.8, 0.06)
	if "trample" in kws:
		_add_flair_ring(Color(0.95, 0.35, 0.15, 0.22), Vector2(0.75, 1.00), -0.01, "pulse", 2.0, 0.08)

	if "haste" in kws:
		_add_flair_mote(Color(1.0, 0.38, 0.12, 0.92), 0.028, "orbit", 2.8, 0.0, 0.36, 0.48, 0.04)
		_add_flair_mote(Color(1.0, 0.65, 0.20, 0.85), 0.022, "orbit", 2.8, PI, 0.36, 0.48, 0.04)
	if "deathtouch" in kws:
		_add_flair_mote(Color(0.25, 0.95, 0.38, 0.90), 0.026, "orbit", 1.1, 0.5, 0.34, 0.46, 0.03)
		_add_flair_mote(Color(0.65, 0.25, 0.95, 0.85), 0.022, "orbit", 1.1, 0.5 + PI, 0.34, 0.46, 0.03)
	if "lifelink" in kws:
		_add_flair_mote(Color(1.0, 0.72, 0.85, 0.92), 0.024, "orbit", 1.3, 1.0, 0.32, 0.44, 0.06)
		_add_flair_mote(Color(1.0, 0.92, 0.55, 0.88), 0.020, "orbit", 1.3, 1.0 + PI, 0.32, 0.44, 0.06)
	if "double strike" in kws:
		_add_flair_blade(Color(1.0, 0.85, 0.25, 0.95), 0.0)
		_add_flair_blade(Color(1.0, 0.96, 0.65, 0.95), PI)
	elif "first strike" in kws:
		_add_flair_blade(Color(1.0, 0.82, 0.25, 0.92), 0.0)
	if "menace" in kws:
		_add_flair_mote(Color(0.95, 0.12, 0.18, 0.90), 0.030, "glint", 1.9, 0.0, 0.31, 0.43, 0.05)
		_add_flair_mote(Color(0.95, 0.12, 0.18, 0.90), 0.030, "glint", 1.9, PI, -0.31, 0.43, 0.05)
	if "reach" in kws:
		_add_flair_mote(Color(0.25, 0.90, 0.65, 0.85), 0.022, "glint", 1.5, 0.7, 0.0, -0.46, 0.08)
	if "flash" in kws:
		_add_flair_mote(Color(0.35, 0.92, 1.0, 0.95), 0.025, "glint", 3.2, 0.0, 0.28, -0.42, 0.06)

	# Creature Status Animations (replacing 3D text badges)
	if is_sick:
		_add_flair_mote(Color(0.68, 0.75, 1.0, 0.55), 0.024, "orbit", 0.65, 0.0, 0.22, 0.32, 0.08)
		_add_flair_mote(Color(0.55, 0.62, 0.95, 0.45), 0.018, "orbit", 0.65, PI, 0.22, 0.32, 0.11)
	if is_goaded:
		_add_flair_ring(Color(1.0, 0.18, 0.12, 0.30), Vector2(0.76, 1.01), -0.004, "pulse", 3.2, 0.09)
	if has_prot:
		_add_flair_ring(Color(0.85, 0.95, 1.0, 0.28), Vector2(0.75, 1.00), -0.003, "pulse", 1.5, 0.04)
	if has_custom_status("Ring-bearer"):
		_add_flair_torus(Color(1.0, 0.84, 0.22, 0.95), 0.08, 0.12, 0.14, 1.4)
	if has_custom_status("Renowned"):
		_add_flair_mote(Color(1.0, 0.92, 0.45, 0.95), 0.024, "orbit", 1.2, 0.0, 0.26, 0.38, 0.10)
		_add_flair_mote(Color(1.0, 0.98, 0.85, 0.90), 0.020, "orbit", 1.2, PI, 0.26, 0.38, 0.10)
	if has_custom_status("Monstrous"):
		_add_flair_ring(Color(0.65, 0.12, 0.55, 0.28), Vector2(0.78, 1.03), -0.006, "pulse", 1.8, 0.07)
		_flair_items.append({"node": front_face, "mode": "breathe", "speed": 1.3, "offset": 0.0, "rx": 0.0, "rz": 0.0, "y": 0.0, "amp": 0.035})
	if has_custom_status("Suspected"):
		_add_flair_ring(Color(1.0, 0.72, 0.15, 0.24), Vector2(0.72, 0.97), -0.004, "pulse", 2.1, 0.05)
		_add_flair_mote(Color(1.0, 0.80, 0.20, 0.92), 0.026, "glint", 2.4, 0.0, 0.0, -0.35, 0.10)
	if has_custom_status("Saddled"):
		_add_flair_mote(Color(0.35, 0.88, 0.48, 0.88), 0.022, "glint", 1.4, 0.0, -0.30, 0.0, 0.05)
		_add_flair_mote(Color(0.35, 0.88, 0.48, 0.88), 0.022, "glint", 1.4, 0.0, 0.30, 0.0, 0.05)

func toggle_custom_status(status_name: String) -> void:
	var key := status_name.strip_edges()
	if key.is_empty(): return
	var found_idx := -1
	for i in range(custom_statuses.size()):
		if custom_statuses[i].to_lower() == key.to_lower():
			found_idx = i; break
	if found_idx >= 0:
		custom_statuses.remove_at(found_idx)
	else:
		custom_statuses.append(key)
	refresh_visual_status()

func has_custom_status(status_name: String) -> bool:
	var low := status_name.strip_edges().to_lower()
	for s in custom_statuses:
		if s.to_lower() == low: return true
	return false
