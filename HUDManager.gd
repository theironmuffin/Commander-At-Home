class_name HUDManager
extends Node

var engine: Node = null

var life_labels: Dictionary = {}
var life_name_labels: Dictionary = {}
var cmd_dmg_labels: Dictionary = {}
var match_log_canvas: CanvasLayer = null
var settings_canvas: CanvasLayer = null
var lobby_canvas: CanvasLayer = null
var touch_bar_canvas: CanvasLayer = null
var touch_atk_btn: Button = null
var touch_controls_enabled: bool = false
var tracker_canvas: CanvasLayer = null
var life_hud_canvas: CanvasLayer = null

var mana_ui_label: RichTextLabel = null
var mana_canvas: CanvasLayer = null
var mana_panel_container: PanelContainer = null

var phase_ui_label: Label = null
var priority_ui_label: Label = null
var phase_step_buttons: Dictionary = {}
var primary_action_btn: Button = null

var card_preview_canvas: CanvasLayer = null
var card_preview_texture_rect: TextureRect = null
var card_preview_footer_label: Label = null

var loading_canvas: CanvasLayer = null
var loading_progress_bar: ProgressBar = null
var loading_status_label: Label = null

var search_canvas: CanvasLayer = null
var discard_remaining: int = 0
var _preview_card_id: int = 0
var token_canvas: CanvasLayer = null
var controller_help_canvas: CanvasLayer = null
var mulligan_canvas: CanvasLayer = null
var mulligan_status_label: Label = null
var mulligan_keep_btn: Button = null
var mulligan_redraw_btn: Button = null
var targeting_hud_canvas: CanvasLayer = null

var stack_panel_container: PanelContainer = null
var stack_list_vbox: VBoxContainer = null
var stack_header_label: Label = null
var stack_collapse_btn: Button = null
var stack_panel_collapsed: bool = false

var targeting_attachment: Node3D = null
var active_target_callback: Callable = Callable()
var active_target_requirement: String = ""
var active_target_source: Node3D = null

func setup(main_engine: Node) -> void:
	engine = main_engine
	touch_controls_enabled = DisplayServer.is_touchscreen_available() or (OS.get_name() in ["Android", "iOS"])
	setup_mana_ui()
	setup_stack_ui()
	setup_card_preview_ui()
	setup_life_hud()

	EventBus.phase_changed.connect(func(_p): update_phase_ui())
	EventBus.turn_changed.connect(func(pid, t):
		update_phase_ui()
		show_turn_banner(pid, t)
	)
	EventBus.priority_changed.connect(func(_pid, _c): update_phase_ui())
	EventBus.stack_changed.connect(func(_s):
		update_phase_ui()
		update_stack_ui()
	)
	EventBus.mana_pool_changed.connect(func(_pool): update_mana_ui())
	EventBus.life_total_changed.connect(_on_life_total_changed)
	EventBus.damage_dealt.connect(func(_s, _t, _a): refresh_commander_damage_labels())

func apply_custom_font(node: Node) -> void:
	if node is Label or node is Button or node is OptionButton:
		if engine.BELEREN_FONT: node.add_theme_font_override("font", engine.BELEREN_FONT)
	elif node is RichTextLabel:
		if engine.BELEREN_FONT:
			node.add_theme_font_override("normal_font", engine.BELEREN_FONT)
			node.add_theme_font_override("bold_font", engine.BELEREN_FONT)
	elif node is Label3D:
		if engine.BELEREN_FONT: node.font = engine.BELEREN_FONT

	if node is PanelContainer and not node.has_theme_stylebox_override("panel"):
		var ps := StyleBoxFlat.new()
		ps.bg_color = engine.UI_BACKGROUND
		ps.border_color = engine.UI_BORDER
		ps.set_border_width_all(1)
		ps.corner_radius_top_left = 10; ps.corner_radius_top_right = 10
		ps.corner_radius_bottom_left = 10; ps.corner_radius_bottom_right = 10
		ps.content_margin_left = 14; ps.content_margin_right = 14
		ps.content_margin_top = 12; ps.content_margin_bottom = 12
		node.add_theme_stylebox_override("panel", ps)
	elif node is Button and not node.has_theme_stylebox_override("normal"):
		var bn := StyleBoxFlat.new()
		bn.bg_color = Color(0.14, 0.16, 0.21, 0.95)
		bn.border_color = Color(0.75, 0.62, 0.32, 0.85)
		bn.set_border_width_all(1)
		bn.corner_radius_top_left = 7; bn.corner_radius_top_right = 7
		bn.corner_radius_bottom_left = 7; bn.corner_radius_bottom_right = 7
		bn.content_margin_left = 12; bn.content_margin_right = 12
		bn.content_margin_top = 6; bn.content_margin_bottom = 6
		var bh := bn.duplicate()
		bh.bg_color = Color(0.22, 0.25, 0.33, 0.98)
		bh.border_color = Color(0.95, 0.80, 0.40, 1.0)
		var bp := bn.duplicate()
		bp.bg_color = Color(0.10, 0.12, 0.16, 1.0)
		var bd := bn.duplicate()
		bd.bg_color = Color(0.10, 0.10, 0.12, 0.6)
		bd.border_color = Color(0.35, 0.35, 0.40, 0.4)
		node.add_theme_stylebox_override("normal", bn)
		node.add_theme_stylebox_override("hover", bh)
		node.add_theme_stylebox_override("pressed", bp)
		node.add_theme_stylebox_override("disabled", bd)
		node.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88, 1.0))
		node.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.60, 1.0))

	for child in node.get_children():
		apply_custom_font(child)


func refresh_player_names() -> void:
	for pid in life_name_labels.keys():
		var lbl: Label = life_name_labels[pid]
		if is_instance_valid(lbl):
			lbl.text = engine.get_player_display_name(pid)
	if engine.has_method("refresh_command_info_stations"):
		engine.refresh_command_info_stations()
	update_phase_ui()

func setup_touch_action_bar() -> void:
	if touch_bar_canvas and is_instance_valid(touch_bar_canvas):
		touch_bar_canvas.queue_free()
		touch_bar_canvas = null
	if not touch_controls_enabled: return

	touch_bar_canvas = CanvasLayer.new()
	touch_bar_canvas.name = "TouchActionBarHUD"
	touch_bar_canvas.layer = 40
	engine.add_child(touch_bar_canvas)

	var safe := DisplayServer.get_display_safe_area()
	var win_sz := DisplayServer.window_get_size()
	var left_pad := maxi(16, safe.position.x + 8)
	var bot_pad := maxi(16, (win_sz.y - (safe.position.y + safe.size.y)) + 12) if win_sz.y > 0 else 16

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left_pad)
	margin.add_theme_constant_override("margin_bottom", bot_pad)
	margin.anchor_left = 0.0; margin.anchor_right = 0.0; margin.anchor_top = 1.0; margin.anchor_bottom = 1.0
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	touch_bar_canvas.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	touch_atk_btn = Button.new()
	touch_atk_btn.text = "⚔ Attack Mode: OFF"
	touch_atk_btn.custom_minimum_size = Vector2(145, 48)
	touch_atk_btn.pressed.connect(func():
		engine.touch_attack_mode = not engine.touch_attack_mode
		touch_atk_btn.text = "⚔ Attack Mode: ON" if engine.touch_attack_mode else "⚔ Attack Mode: OFF"
	)
	hbox.add_child(touch_atk_btn)

	var cyc_btn := Button.new()
	cyc_btn.text = "🎯 Cycle Target"
	cyc_btn.custom_minimum_size = Vector2(125, 48)
	cyc_btn.pressed.connect(func():
		for c in engine.battlefield_non_lands:
			if is_instance_valid(c) and bool(c.get("is_attacking")) and engine.get_card_owner_id(c) == engine.local_player_id:
				engine.combat_manager.handle_declare_attacker_key(c, true)
	)
	hbox.add_child(cyc_btn)

	var gy_btn := Button.new()
	gy_btn.text = "💀 GY"
	gy_btn.custom_minimum_size = Vector2(74, 48)
	gy_btn.pressed.connect(func():
		open_zone_viewer("%s's Graveyard" % engine.get_player_display_name(engine.local_player_id), engine.graveyard_stack, engine.local_player_id)
	)
	hbox.add_child(gy_btn)

	var ex_btn := Button.new()
	ex_btn.text = "🌀 Exile"
	ex_btn.custom_minimum_size = Vector2(82, 48)
	ex_btn.pressed.connect(func():
		open_zone_viewer("%s's Exile" % engine.get_player_display_name(engine.local_player_id), engine.exile_stack, engine.local_player_id)
	)
	hbox.add_child(ex_btn)

	var lib_btn := Button.new()
	lib_btn.text = "📖 Lib"
	lib_btn.custom_minimum_size = Vector2(78, 48)
	lib_btn.pressed.connect(func():
		open_zone_viewer("Library (Tutor)", engine.library_stack)
	)
	hbox.add_child(lib_btn)

	var untap_btn := Button.new()
	untap_btn.text = "↺ Untap"
	untap_btn.custom_minimum_size = Vector2(88, 48)
	untap_btn.pressed.connect(func():
		if engine.turn_manager.is_local_player_turn():
			engine.zone_manager.untap_all(engine.local_player_id)
	)
	hbox.add_child(untap_btn)

	var trk_btn := Button.new()
	trk_btn.text = "🎲 Track"
	trk_btn.custom_minimum_size = Vector2(88, 48)
	trk_btn.pressed.connect(func(): toggle_table_trackers())
	hbox.add_child(trk_btn)

	var undo_t_btn := Button.new()
	undo_t_btn.text = "↩ Undo"
	undo_t_btn.custom_minimum_size = Vector2(86, 48)
	undo_t_btn.pressed.connect(func():
		if engine.has_method("undo_last_action"): engine.undo_last_action()
	)
	hbox.add_child(undo_t_btn)

	var cam_btn := Button.new()
	cam_btn.text = "📷 Cam"
	cam_btn.custom_minimum_size = Vector2(82, 48)
	cam_btn.pressed.connect(func():
		if engine.camera and engine.camera.has_method("reset_to_home"):
			engine.camera.reset_to_home()
	)
	hbox.add_child(cam_btn)

	apply_custom_font(touch_bar_canvas)

func setup_life_hud() -> void:
	life_hud_canvas = CanvasLayer.new()
	life_hud_canvas.name = "LifeTrackerHUD"
	engine.add_child(life_hud_canvas)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.anchor_left = 1.0; margin.anchor_right = 1.0; margin.anchor_top = 0.0; margin.anchor_bottom = 0.0
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	life_hud_canvas.add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(1)
	style.corner_radius_top_left = 6; style.corner_radius_top_right = 6; style.corner_radius_bottom_left = 6; style.corner_radius_bottom_right = 6
	style.content_margin_left = 15; style.content_margin_right = 15; style.content_margin_top = 10; style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Life totals & Commander damage are displayed on the 3D Command Info Stations around the central stack.

	var settings_btn := Button.new()
	settings_btn.text = "⚙ Settings"
	settings_btn.custom_minimum_size = Vector2(120, 32)
	settings_btn.add_theme_font_size_override("font_size", 13)
	settings_btn.pressed.connect(func(): toggle_settings_menu())
	vbox.add_child(settings_btn)

	apply_custom_font(life_hud_canvas)
	setup_touch_action_bar()

func _on_life_total_changed(player_id: int, new_total: int, _amount: int) -> void:
	if life_labels.has(player_id):
		life_labels[player_id].text = "DEAD" if new_total <= 0 else str(new_total)

func setup_mana_ui() -> void:
	mana_canvas = CanvasLayer.new()
	mana_canvas.name = "GameHUD"
	engine.add_child(mana_canvas)

	var mana_margin := MarginContainer.new()
	mana_margin.name = "ManaMargin"
	mana_margin.add_theme_constant_override("margin_top", 20)
	mana_margin.add_theme_constant_override("margin_left", 20)
	mana_margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mana_canvas.add_child(mana_margin)

	mana_panel_container = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(1)
	style.corner_radius_top_left = 8; style.corner_radius_top_right = 8; style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8
	style.content_margin_left = 15; style.content_margin_right = 15; style.content_margin_top = 10; style.content_margin_bottom = 10
	mana_panel_container.add_theme_stylebox_override("panel", style)
	mana_margin.add_child(mana_panel_container)

	mana_ui_label = RichTextLabel.new()
	mana_ui_label.bbcode_enabled = true
	mana_ui_label.fit_content = true
	mana_ui_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mana_ui_label.custom_minimum_size = Vector2(220, 24)
	mana_ui_label.add_theme_font_size_override("normal_font_size", 16)
	mana_panel_container.add_child(mana_ui_label)

	apply_custom_font(mana_canvas)
	mana_panel_container.visible = false

func update_mana_ui() -> void:
	var total_mana := 0
	for color in engine.mana_pool.keys():
		total_mana += int(engine.mana_pool[color])

	if mana_panel_container:
		if total_mana > 0:
			mana_panel_container.visible = true
			var bbcode_parts: Array[String] = []
			for color in ["W", "U", "B", "R", "G", "C"]:
				var count: int = int(engine.mana_pool[color])
				if count > 0:
					var icon_path: String = engine.MANA_ICONS.get(color, "")
					if not icon_path.is_empty():
						bbcode_parts.append("[img width=20 height=20]%s[/img] %d" % [icon_path, count])
					else:
						bbcode_parts.append("%s:%d" % [color, count])
			mana_ui_label.text = "   ".join(bbcode_parts)
		else:
			mana_panel_container.visible = false


func setup_stack_ui() -> void:
	if not mana_canvas: return

	var stack_margin := MarginContainer.new()
	stack_margin.name = "StackPanelMargin"
	stack_margin.add_theme_constant_override("margin_top", 80)
	stack_margin.add_theme_constant_override("margin_left", 20)
	stack_margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mana_canvas.add_child(stack_margin)

	stack_panel_container = PanelContainer.new()
	stack_panel_container.custom_minimum_size = Vector2(280, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(1)
	style.corner_radius_top_left = 8; style.corner_radius_top_right = 8; style.corner_radius_bottom_left = 8; style.corner_radius_bottom_right = 8
	style.content_margin_left = 12; style.content_margin_right = 12; style.content_margin_top = 8; style.content_margin_bottom = 8
	stack_panel_container.add_theme_stylebox_override("panel", style)
	stack_margin.add_child(stack_panel_container)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 6)
	stack_panel_container.add_child(outer_vbox)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	outer_vbox.add_child(header_hbox)

	stack_header_label = Label.new()
	stack_header_label.text = "THE STACK (0)"
	stack_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_header_label.add_theme_font_size_override("font_size", 13)
	stack_header_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	header_hbox.add_child(stack_header_label)

	var resolve_top_btn := Button.new()
	resolve_top_btn.text = "Resolve Top"
	resolve_top_btn.add_theme_font_size_override("font_size", 11)
	resolve_top_btn.pressed.connect(func(): engine.resolve_top_stack_card())
	header_hbox.add_child(resolve_top_btn)

	stack_collapse_btn = Button.new()
	stack_collapse_btn.text = "▾"
	stack_collapse_btn.custom_minimum_size = Vector2(26, 24)
	stack_collapse_btn.pressed.connect(func():
		stack_panel_collapsed = not stack_panel_collapsed
		stack_collapse_btn.text = "▸" if stack_panel_collapsed else "▾"
		stack_list_vbox.visible = not stack_panel_collapsed
	)
	header_hbox.add_child(stack_collapse_btn)

	stack_list_vbox = VBoxContainer.new()
	stack_list_vbox.add_theme_constant_override("separation", 5)
	outer_vbox.add_child(stack_list_vbox)

	apply_custom_font(stack_margin)
	stack_panel_container.visible = false

func update_stack_ui() -> void:
	if not stack_panel_container or not stack_list_vbox: return

	for child in stack_list_vbox.get_children():
		child.queue_free()

	var count: int = engine.active_stack.size()
	if count == 0:
		stack_panel_container.visible = false
		return

	stack_panel_container.visible = true
	stack_header_label.text = "THE STACK (%d)" % count
	stack_list_vbox.visible = not stack_panel_collapsed

	for i in range(count - 1, -1, -1):
		var item = engine.active_stack[i]
		var row_panel := PanelContainer.new()
		var r_style := StyleBoxFlat.new()
		r_style.bg_color = Color(0.16, 0.18, 0.24, 0.9) if i == count - 1 else Color(0.11, 0.12, 0.16, 0.85)
		r_style.border_color = Color(0.4, 0.75, 1.0, 0.7) if i == count - 1 else Color(0.3, 0.32, 0.4, 0.5)
		r_style.set_border_width_all(1)
		r_style.corner_radius_top_left = 5; r_style.corner_radius_top_right = 5; r_style.corner_radius_bottom_left = 5; r_style.corner_radius_bottom_right = 5
		r_style.content_margin_left = 8; r_style.content_margin_right = 8; r_style.content_margin_top = 4; r_style.content_margin_bottom = 4
		row_panel.add_theme_stylebox_override("panel", r_style)

		var row_hbox := HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 6)
		row_panel.add_child(row_hbox)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_hbox.add_child(info_vbox)

		var item_name: String = ""
		var ctrl_id: int = 1
		var target_val: Variant = null

		if item is Node3D:
			item_name = str(item.card_data.get("name", "Spell"))
			ctrl_id = engine.get_card_owner_id(item)
			if item.has_meta("chosen_target"): target_val = item.get_meta("chosen_target")
		else:
			item_name = str(item.name)
			ctrl_id = int(item.controller_id)
			target_val = item.target_ref

		var name_lbl := Label.new()
		name_lbl.text = "%d. %s" % [i + 1, item_name]
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 1.0))
		info_vbox.add_child(name_lbl)

		var target_str := ""
		if target_val is Node3D and is_instance_valid(target_val):
			target_str = " → %s" % str(target_val.card_data.get("name", "Target"))
		elif target_val is int and int(target_val) > 0:
			target_str = " → %s" % engine.get_player_display_name(int(target_val))

		var sub_lbl := Label.new()
		sub_lbl.text = "%s%s" % [engine.get_player_display_name(ctrl_id), target_str]
		sub_lbl.add_theme_font_size_override("font_size", 10)
		sub_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.95, 1.0))
		info_vbox.add_child(sub_lbl)

		var counter_btn := Button.new()
		counter_btn.text = "Counter"
		counter_btn.add_theme_font_size_override("font_size", 10)
		var stack_idx := i
		counter_btn.pressed.connect(func(): engine.counter_stack_item(stack_idx))
		row_hbox.add_child(counter_btn)

		stack_list_vbox.add_child(row_panel)

	apply_custom_font(stack_list_vbox)

func setup_phase_hud() -> void:
	if phase_ui_label and phase_ui_label.is_inside_tree(): return
	var hud_parent: Node = mana_canvas if mana_canvas else engine

	var phase_margin := MarginContainer.new()
	phase_margin.name = "PhaseHUDContainer"
	phase_margin.add_theme_constant_override("margin_top", 16)
	phase_margin.anchor_left = 0.5; phase_margin.anchor_right = 0.5; phase_margin.anchor_top = 0.0; phase_margin.anchor_bottom = 0.0
	phase_margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_parent.add_child(phase_margin)

	var phase_panel := PanelContainer.new()
	var phase_style := StyleBoxFlat.new()
	phase_style.bg_color = engine.UI_BACKGROUND; phase_style.border_color = engine.UI_BORDER; phase_style.set_border_width_all(1)
	phase_style.corner_radius_top_left = 10; phase_style.corner_radius_top_right = 10; phase_style.corner_radius_bottom_left = 10; phase_style.corner_radius_bottom_right = 10
	phase_style.content_margin_left = 16; phase_style.content_margin_right = 16; phase_style.content_margin_top = 8; phase_style.content_margin_bottom = 8
	phase_panel.add_theme_stylebox_override("panel", phase_style)
	phase_margin.add_child(phase_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	phase_panel.add_child(vbox)

	phase_ui_label = Label.new()
	phase_ui_label.name = "PhaseLabel"
	phase_ui_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_ui_label.add_theme_font_size_override("font_size", 14)
	phase_ui_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	vbox.add_child(phase_ui_label)

	var stepper_hbox := HBoxContainer.new()
	stepper_hbox.name = "PhaseStepperBar"
	stepper_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	stepper_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(stepper_hbox)

	phase_step_buttons.clear()
	var phase_order: Array[TurnManager.TurnPhase] = [
		TurnManager.TurnPhase.UNTAP, TurnManager.TurnPhase.UPKEEP, TurnManager.TurnPhase.DRAW_STEP, TurnManager.TurnPhase.PRECOMBAT_MAIN,
		TurnManager.TurnPhase.COMBAT_BEGIN, TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS, TurnManager.TurnPhase.COMBAT_DECLARE_BLOCKERS, TurnManager.TurnPhase.COMBAT_DAMAGE, TurnManager.TurnPhase.COMBAT_END,
		TurnManager.TurnPhase.POSTCOMBAT_MAIN, TurnManager.TurnPhase.END, TurnManager.TurnPhase.CLEANUP
	]
	for p in phase_order:
		if p == TurnManager.TurnPhase.COMBAT_BEGIN or p == TurnManager.TurnPhase.POSTCOMBAT_MAIN:
			var sep := VSeparator.new()
			sep.custom_minimum_size = Vector2(4, 24)
			stepper_hbox.add_child(sep)

		var step_btn := Button.new()
		step_btn.custom_minimum_size = Vector2(34, 28)
		step_btn.text = TurnManager.PHASE_ICONS.get(p, "?")
		step_btn.tooltip_text = "%s (Click to toggle Auto-Pass Stop)" % TurnManager.PHASE_NAMES.get(p, "")
		step_btn.pressed.connect(func(): engine.turn_manager.toggle_stop(p))
		stepper_hbox.add_child(step_btn)
		phase_step_buttons[p] = step_btn

	priority_ui_label = Label.new()
	priority_ui_label.name = "PriorityLabel"
	priority_ui_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	priority_ui_label.add_theme_font_size_override("font_size", 11)
	priority_ui_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1))
	priority_ui_label.queue_free(); priority_ui_label = null

	# Bottom-right Stacked Action Bar
	var action_margin := MarginContainer.new()
	action_margin.name = "TurnActionHUD"
	action_margin.add_theme_constant_override("margin_right", 24)
	action_margin.add_theme_constant_override("margin_bottom", 24)
	action_margin.anchor_left = 1.0; action_margin.anchor_right = 1.0; action_margin.anchor_top = 1.0; action_margin.anchor_bottom = 1.0
	action_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	action_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_parent.add_child(action_margin)

	var action_vbox := VBoxContainer.new()
	action_vbox.add_theme_constant_override("separation", 8)
	action_margin.add_child(action_vbox)

	primary_action_btn = Button.new()
	primary_action_btn.text = "Next [Space]"
	primary_action_btn.custom_minimum_size = Vector2(210, 44)
	primary_action_btn.add_theme_font_size_override("font_size", 13)
	primary_action_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var prim_style := StyleBoxFlat.new()
	prim_style.bg_color = Color(0.18, 0.34, 0.24, 0.96); prim_style.border_color = engine.UI_BORDER; prim_style.set_border_width_all(2)
	prim_style.corner_radius_top_left = 8; prim_style.corner_radius_top_right = 8; prim_style.corner_radius_bottom_left = 8; prim_style.corner_radius_bottom_right = 8
	prim_style.content_margin_left = 14; prim_style.content_margin_right = 14; prim_style.content_margin_top = 8; prim_style.content_margin_bottom = 8
	primary_action_btn.add_theme_stylebox_override("normal", prim_style)
	primary_action_btn.add_theme_stylebox_override("hover", prim_style)
	primary_action_btn.pressed.connect(func(): engine.turn_manager.request_primary_action())
	action_vbox.add_child(primary_action_btn)

	update_phase_ui()
	apply_custom_font(phase_margin)
	apply_custom_font(action_margin)

func update_phase_ui() -> void:
	if not phase_ui_label: return
	var tm: TurnManager = engine.turn_manager
	var active_name: String = engine.get_player_display_name(tm.active_player_id)
	var prio_name: String = engine.get_player_display_name(tm.priority_player_id)
	var table_tags: Array[String] = []
	if not engine.battlefield_day_night.is_empty():
		table_tags.append("☀ Day" if engine.battlefield_day_night == "Day" else "🌙 Night")
	if engine.monarch_player_id > 0:
		table_tags.append("👑 Monarch: %s" % engine.get_player_display_name(engine.monarch_player_id))
	if engine.initiative_player_id > 0:
		table_tags.append("🗺 Initiative: %s" % engine.get_player_display_name(engine.initiative_player_id))
	var tag_suffix := ("  [" + " | ".join(table_tags) + "]") if not table_tags.is_empty() else ""
	var new_text := "%s | Turn %d — %s%s" % [active_name, tm.turn_number, TurnManager.PHASE_NAMES[tm.current_turn_phase], tag_suffix]
	if phase_ui_label.text != new_text:
		phase_ui_label.text = new_text

	if priority_ui_label:
		var stack_hint := " | Stack: %d [ENTER to Resolve]" % engine.active_stack.size() if not engine.active_stack.is_empty() else ""
		priority_ui_label.text = "Priority: %s (Passes: %d/4) [SPACE: Action, P: Debug Step]%s" % [prio_name, tm.priority_passes_count, stack_hint]

	for p in phase_step_buttons.keys():
		var btn: Button = phase_step_buttons[p]
		var is_current: bool = (p == tm.current_turn_phase)
		var has_stop: bool = bool(tm.phase_stops.get(p, false))
		btn.text = TurnManager.PHASE_ICONS.get(p, "?") + ("●" if has_stop else "")

		var s := StyleBoxFlat.new()
		s.corner_radius_top_left = 5; s.corner_radius_top_right = 5; s.corner_radius_bottom_left = 5; s.corner_radius_bottom_right = 5
		if is_current:
			s.bg_color = Color(0.28, 0.24, 0.12, 1.0); s.border_color = Color(1.0, 0.85, 0.35, 1.0); s.set_border_width_all(2)
			btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
		elif has_stop:
			s.bg_color = Color(0.22, 0.16, 0.08, 0.95); s.border_color = Color(1.0, 0.65, 0.15, 0.95); s.set_border_width_all(1)
			btn.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25, 1.0))
		else:
			s.bg_color = Color(0.12, 0.13, 0.17, 0.85); s.border_color = Color(0.28, 0.3, 0.38, 0.6); s.set_border_width_all(1)
			btn.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 1.0))
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)

	if primary_action_btn:
		if not engine.active_stack.is_empty():
			var top_item = engine.active_stack[-1]
			var top_name: String = str(top_item.name) if not (top_item is Node3D) else str(top_item.card_data.get("name", "Spell"))
			primary_action_btn.text = "Resolve: %s [Space]" % top_name.left(14)
		elif tm.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS:
			var atk_count := 0
			for c in engine.battlefield_non_lands:
				if is_instance_valid(c) and bool(c.get("is_attacking")): atk_count += 1
			primary_action_btn.text = ("Confirm Attackers (%d)" % atk_count if atk_count > 0 else "Skip Combat") + " [Space]"
		elif tm.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_BLOCKERS:
			var blk_count := 0
			for c in engine.battlefield_non_lands:
				if is_instance_valid(c) and bool(c.get("is_blocking")): blk_count += 1
			primary_action_btn.text = ("Confirm Blockers (%d)" % blk_count if blk_count > 0 else "No Blocks") + " [Space]"
		elif tm.current_turn_phase == TurnManager.TurnPhase.PRECOMBAT_MAIN:
			primary_action_btn.text = ("To Combat" if tm._has_eligible_attackers(tm.active_player_id) else "End Turn") + " [Space]"
		elif tm.current_turn_phase == TurnManager.TurnPhase.POSTCOMBAT_MAIN:
			primary_action_btn.text = "End Turn [Space]"
		else:
			primary_action_btn.text = "Next / Pass [Space]"

func setup_card_preview_ui() -> void:
	card_preview_canvas = CanvasLayer.new()
	card_preview_canvas.name = "CardPreviewUI"
	engine.add_child(card_preview_canvas)

	var panel := PanelContainer.new()
	panel.name = "PreviewPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(280, 0)
	panel.offset_left = -300; panel.offset_right = -20; panel.offset_top = -480; panel.offset_bottom = -90

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = engine.UI_BACKGROUND; panel_style.border_color = engine.UI_BORDER; panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 10; panel_style.corner_radius_top_right = 10; panel_style.corner_radius_bottom_left = 10; panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 10; panel_style.content_margin_right = 10; panel_style.content_margin_top = 10; panel_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	card_preview_canvas.add_child(panel)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.name = "PreviewVBox"
	preview_vbox.add_theme_constant_override("separation", 2)
	panel.add_child(preview_vbox)

	card_preview_texture_rect = TextureRect.new()
	card_preview_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_preview_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_preview_texture_rect.custom_minimum_size = Vector2(260, 364)
	card_preview_texture_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var preview_shader := Shader.new()
	preview_shader.code = """shader_type canvas_item;
void fragment() {
	vec2 card_size = vec2(0.635, 0.889);
	float corner_radius = 0.032;
	vec2 p = (UV - 0.5) * card_size;
	vec2 half_size = card_size * 0.5 - vec2(corner_radius);
	vec2 d = abs(p) - half_size;
	float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - corner_radius;
	float alpha_mask = 1.0 - smoothstep(-0.002, 0.002, dist);
	vec4 tex_col = texture(TEXTURE, UV);
	COLOR = vec4(tex_col.rgb, tex_col.a * alpha_mask);
}"""
	var preview_mat := ShaderMaterial.new()
	preview_mat.shader = preview_shader
	card_preview_texture_rect.material = preview_mat
	preview_vbox.add_child(card_preview_texture_rect)

	card_preview_footer_label = Label.new()
	card_preview_footer_label.name = "PreviewFooter"
	card_preview_footer_label.custom_minimum_size = Vector2(256, 0)
	card_preview_footer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_preview_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_preview_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_preview_footer_label.add_theme_font_size_override("font_size", 12)
	card_preview_footer_label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0, 1))
	card_preview_footer_label.visible = false
	preview_vbox.add_child(card_preview_footer_label)

	apply_custom_font(card_preview_canvas)
	panel.visible = false

func show_card_preview(card: Node3D) -> void:
	if card_preview_canvas == null: return
	var panel: Control = card_preview_canvas.get_node_or_null("PreviewPanel")
	if not panel: return
	_preview_card_id = card.get_instance_id()
	var tex: Texture2D = engine._get_card_texture(card)
	if tex == null and card.has_method("_fetch_face_texture"):
		var cid := card.get_instance_id()
		if card.has_signal("card_texture_ready") and not card.card_texture_ready.is_connected(_on_preview_card_texture_ready):
			card.card_texture_ready.connect(_on_preview_card_texture_ready.bind(cid), CONNECT_ONE_SHOT)
		card._fetch_face_texture(int(card.get("active_face_index")) if card.get("active_face_index") != null else 0)
	if tex:
		card_preview_texture_rect.texture = tex
		var status_parts: Array[String] = []
		if MagicRules.is_creature(card.card_data) and card.is_on_battlefield and bool(card.get("has_summoning_sickness")) and not (card.has_method("has_keyword") and bool(card.has_keyword("haste"))):
			status_parts.append("Summoning Sickness")
		for kw in ["flying", "first strike", "double strike", "deathtouch", "lifelink", "trample", "vigilance", "haste", "reach", "menace", "hexproof", "indestructible", "ward", "defender", "flash"]:
			if card.has_method("has_keyword") and bool(card.has_keyword(kw)):
				status_parts.append(kw.capitalize())
		var plus_cnt: int = int(card.get("counter_amount")) if card.get("counter_amount") != null else 0
		if plus_cnt != 0:
			status_parts.append("%+d/%+d Counters" % [plus_cnt, plus_cnt])
		var custom_cnt: Variant = card.get("custom_counters")
		if custom_cnt is Dictionary:
			for k in custom_cnt.keys():
				var v: int = int(custom_cnt[k])
				if v > 0:
					status_parts.append("%s: %d" % [str(k).capitalize(), v])
		if bool(card.get("is_attacking")):
			var tgt_pid: int = int(card.get("attacking_target_player_id")) if card.get("attacking_target_player_id") != null else 0
			status_parts.append("Attacking %s" % engine.get_player_display_name(tgt_pid))
		elif bool(card.get("is_blocking")):
			status_parts.append("Blocking")
		if card.has_meta("unearthed") and bool(card.get_meta("unearthed")):
			status_parts.append("Unearthed")
		if card.get("goaded_by_player_id") != null and int(card.get("goaded_by_player_id")) > 0:
			status_parts.append("Goaded")
		var prot_l: Array = card.parsed_abilities.get("protection_from", [])
		if not prot_l.is_empty():
			status_parts.append("Protection from " + ", ".join(prot_l).capitalize())
		var c_stats: Variant = card.get("custom_statuses")
		if c_stats is Array:
			for cs in c_stats: status_parts.append(str(cs))

		var footer_lines: Array[String] = []
		if not status_parts.is_empty():
			footer_lines.append(" • ".join(status_parts))
		if engine.turn_manager.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_BLOCKERS and engine.combat_manager.selected_blocker != null and is_instance_valid(engine.combat_manager.selected_blocker) and bool(card.get("is_attacking")):
			footer_lines.append("Combat: " + CombatManager.get_combat_math_preview(card, engine.combat_manager.selected_blocker))

		if card_preview_footer_label:
			if footer_lines.is_empty():
				card_preview_footer_label.visible = false
				card_preview_footer_label.text = ""
				panel.custom_minimum_size = Vector2(280, 384)
				panel.offset_top = -474
				panel.offset_bottom = -90
			else:
				card_preview_footer_label.text = "\n".join(footer_lines)
				card_preview_footer_label.visible = true
				panel.custom_minimum_size = Vector2(280, 0)
				panel.offset_top = -510
				panel.offset_bottom = -90
		panel.visible = true
	else:
		panel.visible = false

func _on_preview_card_texture_ready(tex: Texture2D, cid: int) -> void:
	if cid != _preview_card_id or card_preview_canvas == null: return
	var panel: Control = card_preview_canvas.get_node_or_null("PreviewPanel")
	if panel and tex:
		card_preview_texture_rect.texture = tex
		panel.visible = true

func hide_card_preview() -> void:
	_preview_card_id = 0
	if card_preview_canvas == null: return
	var panel: Control = card_preview_canvas.get_node_or_null("PreviewPanel")
	if panel: panel.visible = false


func show_mulligan_ui() -> void:
	hide_mulligan_ui()
	mulligan_canvas = CanvasLayer.new()
	mulligan_canvas.name = "MulliganHUD"
	mulligan_canvas.layer = 90
	engine.add_child(mulligan_canvas)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_bottom", 210)
	margin.anchor_left = 0.5; margin.anchor_right = 0.5; margin.anchor_top = 1.0; margin.anchor_bottom = 1.0
	margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mulligan_canvas.add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 20; style.content_margin_right = 20; style.content_margin_top = 12; style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	mulligan_status_label = Label.new()
	mulligan_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mulligan_status_label.add_theme_font_size_override("font_size", 14)
	mulligan_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(mulligan_status_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	vbox.add_child(hbox)

	mulligan_redraw_btn = Button.new()
	mulligan_redraw_btn.text = "Mulligan (Draw 7)"
	mulligan_redraw_btn.custom_minimum_size = Vector2(160, 38)
	mulligan_redraw_btn.pressed.connect(func(): engine.perform_mulligan())
	hbox.add_child(mulligan_redraw_btn)

	mulligan_keep_btn = Button.new()
	mulligan_keep_btn.text = "Keep Hand"
	mulligan_keep_btn.custom_minimum_size = Vector2(160, 38)
	var keep_style := StyleBoxFlat.new()
	keep_style.bg_color = Color(0.18, 0.36, 0.22, 0.96); keep_style.border_color = engine.UI_BORDER; keep_style.set_border_width_all(1)
	keep_style.corner_radius_top_left = 6; keep_style.corner_radius_top_right = 6; keep_style.corner_radius_bottom_left = 6; keep_style.corner_radius_bottom_right = 6
	mulligan_keep_btn.add_theme_stylebox_override("normal", keep_style)
	mulligan_keep_btn.add_theme_stylebox_override("hover", keep_style)
	mulligan_keep_btn.pressed.connect(func(): engine.confirm_keep_hand())
	hbox.add_child(mulligan_keep_btn)

	update_mulligan_ui()
	apply_custom_font(mulligan_canvas)

func update_mulligan_ui() -> void:
	if not mulligan_status_label or not is_instance_valid(mulligan_status_label): return
	if engine.mulligan_bottom_remaining > 0:
		mulligan_status_label.text = "LONDON MULLIGAN — Click %d card(s) in hand to put on bottom of library" % engine.mulligan_bottom_remaining
		if mulligan_keep_btn: mulligan_keep_btn.visible = false
		if mulligan_redraw_btn: mulligan_redraw_btn.visible = false
	else:
		var count: int = engine.mulligan_count
		if count == 0:
			mulligan_status_label.text = "OPENING HAND — Keep or Mulligan? (First Mulligan is Free)"
		elif count == 1:
			mulligan_status_label.text = "MULLIGAN #1 (Free) — Keep 7 or Mulligan again (Bottom 1)"
		else:
			mulligan_status_label.text = "MULLIGAN #%d — Keep and put %d card(s) on bottom, or Mulligan" % [count, count - 1]
		if mulligan_keep_btn: mulligan_keep_btn.visible = true
		if mulligan_redraw_btn: mulligan_redraw_btn.visible = true

func hide_mulligan_ui() -> void:
	if mulligan_canvas and is_instance_valid(mulligan_canvas):
		mulligan_canvas.queue_free()
		mulligan_canvas = null

func show_loading_screen(initial_text: String) -> void:
	if loading_canvas and loading_canvas.is_inside_tree(): return
	loading_canvas = CanvasLayer.new()
	loading_canvas.name = "LoadingScreenUI"
	loading_canvas.layer = 200
	engine.add_child(loading_canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_canvas.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_canvas.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.95); style.border_color = Color(0.85, 0.7, 0.35, 0.8); style.set_border_width_all(1)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12; style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 30; style.content_margin_right = 30; style.content_margin_top = 25; style.content_margin_bottom = 25
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PREPARING DECK & ARTWORK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	vbox.add_child(title)

	loading_status_label = Label.new()
	loading_status_label.text = initial_text
	loading_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_status_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(loading_status_label)

	loading_progress_bar = ProgressBar.new()
	loading_progress_bar.custom_minimum_size = Vector2(350, 24)
	loading_progress_bar.value = 0; loading_progress_bar.max_value = 100
	vbox.add_child(loading_progress_bar)

	apply_custom_font(loading_canvas)

func update_loading_progress(pct: float, status: String) -> void:
	if loading_progress_bar and is_instance_valid(loading_progress_bar):
		loading_progress_bar.value = pct
	if loading_status_label and is_instance_valid(loading_status_label):
		loading_status_label.text = status

func hide_loading_screen() -> void:
	if loading_canvas and is_instance_valid(loading_canvas):
		loading_canvas.queue_free()
		loading_canvas = null

func start_generic_targeting(prompt: String, callback: Callable, target_req: String = "", source_card: Node3D = null) -> void:
	cancel_attachment_targeting()
	var req_l := target_req.to_lower()
	if "graveyard" in req_l or "exile" in req_l:
		var pool: Array = []
		if "graveyard" in req_l:
			pool.append_array(engine.graveyard_stack)
			for pid in [2, 3, 4]: pool.append_array(engine.player_graveyards.get(pid, []))
		else:
			pool.append_array(engine.exile_stack)
			for pid in [2, 3, 4]: pool.append_array(engine.player_exile.get(pid, []))
		var matches: Array = []
		for c in pool:
			if is_instance_valid(c) and MagicRules.is_legal_target(c, target_req, engine.local_player_id, source_card):
				matches.append(c)
		if not matches.is_empty():
			open_zone_viewer(prompt, matches, engine.local_player_id, func(chosen: Node3D):
				callback.call(chosen)
			)
			return
	active_target_callback = callback
	active_target_requirement = target_req
	active_target_source = source_card

	targeting_hud_canvas = CanvasLayer.new()
	targeting_hud_canvas.name = "GenericTargetingHUD"
	targeting_hud_canvas.layer = 100
	engine.add_child(targeting_hud_canvas)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 70)
	margin.anchor_left = 0.5; margin.anchor_right = 0.5; margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	targeting_hud_canvas.add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)

	var lbl := Label.new()
	lbl.text = "%s (Press ESC to Cancel)" % prompt.to_upper()
	panel.add_child(lbl)
	apply_custom_font(targeting_hud_canvas)

func select_target(target_object) -> void:
	if active_target_callback.is_valid():
		if not active_target_requirement.is_empty():
			if not MagicRules.is_legal_target(target_object, active_target_requirement, engine.local_player_id, active_target_source):
				return
		var cb := active_target_callback
		cancel_attachment_targeting()
		cb.call(target_object)
	else:
		cancel_attachment_targeting()

func start_attachment_targeting(attachment_card: Node3D) -> void:
	if not attachment_card: return
	cancel_attachment_targeting()

	targeting_attachment = attachment_card
	if attachment_card.has_method("set_highlight"): attachment_card.set_highlight(true)

	targeting_hud_canvas = CanvasLayer.new()
	targeting_hud_canvas.name = "AttachmentTargetingHUD"
	targeting_hud_canvas.layer = 100
	engine.add_child(targeting_hud_canvas)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 70)
	margin.anchor_left = 0.5; margin.anchor_right = 0.5; margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	targeting_hud_canvas.add_child(margin)

	var panel := PanelContainer.new()
	margin.add_child(panel)

	var lbl := Label.new()
	lbl.text = "TARGET CREATURE TO ATTACH/EQUIP [%s]  (Press A or ESC to Cancel)" % attachment_card.card_data.get("name", "Card").to_upper()
	panel.add_child(lbl)
	apply_custom_font(targeting_hud_canvas)

func cancel_attachment_targeting() -> void:
	if targeting_attachment and is_instance_valid(targeting_attachment) and targeting_attachment.has_method("set_highlight"):
		targeting_attachment.set_highlight(false)
	targeting_attachment = null
	active_target_callback = Callable()
	active_target_requirement = ""
	active_target_source = null
	if targeting_hud_canvas and is_instance_valid(targeting_hud_canvas):
		targeting_hud_canvas.queue_free()
		targeting_hud_canvas = null

func open_discard_choice(amount: int) -> void:
	if amount <= 0 or engine.hand_cards.is_empty(): return
	discard_remaining = mini(amount, engine.hand_cards.size())
	if search_canvas and is_instance_valid(search_canvas):
		search_canvas.queue_free(); search_canvas = null
	open_zone_viewer("CHOOSE %d CARD(S) TO DISCARD" % discard_remaining, engine.hand_cards, engine.local_player_id)

func open_zone_viewer(zone_title: String, zone_cards: Array, zone_owner_id: int = 1, on_card_chosen: Callable = Callable()) -> void:
	if zone_cards.is_empty() or (search_canvas and search_canvas.is_inside_tree()): return

	search_canvas = CanvasLayer.new()
	search_canvas.layer = 100
	engine.add_child(search_canvas)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.75)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	search_canvas.add_child(bg_overlay)
	bg_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			search_canvas.queue_free()
			search_canvas = null
	)

	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	search_canvas.add_child(center_container)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 700)
	center_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = zone_title.to_upper() + " VIEWER"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	var search_input := LineEdit.new()
	search_input.placeholder_text = "Filter by name or text..."
	search_input.custom_minimum_size = Vector2(250, 36)
	search_input.clear_button_enabled = true
	header_hbox.add_child(search_input)

	var close_btn := Button.new()
	close_btn.text = "✕  CLOSE"
	close_btn.custom_minimum_size = Vector2(110, 36)
	close_btn.visible = not ("DISCARD" in zone_title.to_upper())
	close_btn.pressed.connect(func():
		search_canvas.queue_free()
		search_canvas = null
	)
	header_hbox.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 15)
	scroll.add_child(grid)

	var card_button_map := {}

	for i in range(zone_cards.size() - 1, -1, -1):
		var card_node: Node3D = zone_cards[i]
		var btn := TextureButton.new()
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(190, 265)

		if zone_title.begins_with("SCRY ") and zone_owner_id == engine.local_player_id:
			btn.tooltip_text = "Click to put on Bottom of Library"
			btn.pressed.connect(func():
				engine.library_stack.erase(card_node)
				engine.zone_manager.move_to_bottom_library(card_node)
				btn.queue_free()
			)
		elif zone_title.begins_with("SURVEIL ") and zone_owner_id == engine.local_player_id:
			btn.tooltip_text = "Click to put into Graveyard"
			btn.pressed.connect(func():
				engine.library_stack.erase(card_node)
				engine._on_card_to_graveyard(card_node)
				btn.queue_free()
			)
		elif "DISCARD" in zone_title.to_upper() and zone_owner_id == engine.local_player_id:
			btn.tooltip_text = "Click to Discard this card"
			btn.pressed.connect(func():
				engine.hand_cards.erase(card_node)
				engine.player_hands.get(engine.local_player_id, []).erase(card_node)
				engine.zone_manager.update_hand_positions(true)
				engine._on_card_to_graveyard(card_node)
				btn.queue_free()
				discard_remaining = maxi(0, discard_remaining - 1)
				if discard_remaining <= 0 or engine.hand_cards.is_empty():
					if search_canvas and is_instance_valid(search_canvas):
						search_canvas.queue_free(); search_canvas = null
				else:
					title_lbl.text = "CHOOSE %d MORE CARD(S) TO DISCARD" % discard_remaining
			)
		elif on_card_chosen.is_valid():
			btn.tooltip_text = "Click to select this card"
			btn.pressed.connect(func():
				if search_canvas and is_instance_valid(search_canvas):
					search_canvas.queue_free(); search_canvas = null
				on_card_chosen.call(card_node)
			)
		elif zone_title.begins_with("Library"):
			btn.pressed.connect(func(): engine._on_tutor_card_selected(card_node))
		elif "Exile" in zone_title and zone_owner_id == engine.local_player_id and bool(card_node.get("is_on_adventure")):
			btn.tooltip_text = "Click to cast Creature from Adventure (Exile)"
			btn.pressed.connect(func():
				search_canvas.queue_free(); search_canvas = null
				card_node.active_face_index = 0
				engine._cast_card_face(card_node, 0, false)
			)
		elif "Graveyard" in zone_title and zone_owner_id == engine.local_player_id:
			var pa: Dictionary = card_node.parsed_abilities
			var fb_cost := str(pa.get("flashback_cost", ""))
			var esc_cost := str(pa.get("escape_cost", ""))
			var esc_exile := int(pa.get("escape_exile_count", 0))
			var un_cost := str(pa.get("unearth_cost", ""))
			var gy_badge_txt := "FB %s" % fb_cost if not fb_cost.is_empty() else ("ESC %s" % esc_cost if not esc_cost.is_empty() else ("UNR %s" % un_cost if not un_cost.is_empty() else ""))
			if not gy_badge_txt.is_empty():
				var badge_lbl := Label.new()
				badge_lbl.text = gy_badge_txt
				badge_lbl.add_theme_font_size_override("font_size", 11)
				badge_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.85, 1.0))
				badge_lbl.position = Vector2(8, 6)
				btn.add_child(badge_lbl)
			if not fb_cost.is_empty():
				btn.tooltip_text = "Click to Cast with Flashback (%s)" % fb_cost
				btn.pressed.connect(func():
					search_canvas.queue_free(); search_canvas = null
					engine.cast_from_graveyard(card_node, "flashback", fb_cost, 0)
				)
			elif not esc_cost.is_empty():
				btn.tooltip_text = "Click to Escape (%s, Exile %d other cards)" % [esc_cost, esc_exile]
				btn.pressed.connect(func():
					search_canvas.queue_free(); search_canvas = null
					engine.cast_from_graveyard(card_node, "escape", esc_cost, esc_exile)
				)
			elif not un_cost.is_empty():
				btn.tooltip_text = "Click to Unearth (%s)" % un_cost
				btn.pressed.connect(func():
					search_canvas.queue_free(); search_canvas = null
					engine.cast_from_graveyard(card_node, "unearth", un_cost, 0)
				)

		grid.add_child(btn)
		card_button_map[card_node] = btn

		var tex: Texture2D = engine._get_card_texture(card_node)
		if tex:
			btn.texture_normal = tex
		else:
			var front_url: String = card_node.card_data.get("image_url", "")
			if front_url.is_empty() and card_node.card_data.get("card_faces") is Array and not card_node.card_data["card_faces"].is_empty():
				var face: Dictionary = card_node.card_data["card_faces"][0]
				var uris: Dictionary = face.get("image_uris", {})
				front_url = uris.get("normal", uris.get("small", ""))

			if not front_url.is_empty():
				var btn_id := btn.get_instance_id()
				var card_id := card_node.get_instance_id()
				var http := HTTPRequest.new()
				btn.add_child(http)
				var http_id := http.get_instance_id()
				http.request_completed.connect(func(_res, response_code, _hdr, body):
					var req_ref := instance_from_id(http_id)
					if req_ref and is_instance_valid(req_ref): req_ref.queue_free()
					if response_code == 200:
						var fetched_tex: Texture2D = CardManager.store_image_to_cache(front_url, body)
						if fetched_tex:
							var btn_ref := instance_from_id(btn_id) as TextureButton
							if btn_ref and is_instance_valid(btn_ref):
								btn_ref.texture_normal = fetched_tex
							var c_ref := instance_from_id(card_id) as Node3D
							if c_ref and is_instance_valid(c_ref):
								c_ref.stored_front_texture = fetched_tex
				)
				http.request(front_url, ["User-Agent: MTGBrawlSim/1.0", "Accept: */*"])

	search_input.text_changed.connect(func(query: String):
		var filter_text := query.strip_edges().to_lower()
		for card_node in card_button_map.keys():
			var btn: TextureButton = card_button_map[card_node]
			if filter_text.is_empty():
				btn.visible = true
			else:
				var c_name := str(card_node.card_data.get("name", "")).to_lower()
				var o_text := str(card_node.card_data.get("oracle_text", "")).to_lower()
				var type_line := str(card_node.card_data.get("type_line", "")).to_lower()
				btn.visible = filter_text in c_name or filter_text in o_text or filter_text in type_line
	)

	apply_custom_font(search_canvas)
	search_input.grab_focus()

func open_token_spawner() -> void:
	if token_canvas and token_canvas.is_inside_tree(): return

	token_canvas = CanvasLayer.new()
	token_canvas.layer = 100
	engine.add_child(token_canvas)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.75)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	token_canvas.add_child(bg_overlay)

	bg_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: token_canvas.queue_free(); token_canvas = null
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	token_canvas.add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = engine.UI_BACKGROUND; panel_style.border_color = engine.UI_BORDER; panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 10; panel_style.corner_radius_top_right = 10; panel_style.corner_radius_bottom_left = 10; panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 24; panel_style.content_margin_right = 24; panel_style.content_margin_top = 20; panel_style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SPAWN TOKEN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	vbox.add_child(title)

	var search_hbox := HBoxContainer.new()
	search_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(search_hbox)

	var custom_input := LineEdit.new()
	custom_input.placeholder_text = "Custom Scryfall token (e.g. Squirrel, Eldrazi Scion)..."
	custom_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_input.custom_minimum_size = Vector2(360, 36)
	search_hbox.add_child(custom_input)

	var custom_btn := Button.new()
	custom_btn.text = "SEARCH & SPAWN"
	custom_btn.custom_minimum_size = Vector2(150, 36)
	var spawn_custom = func():
		var q := custom_input.text.strip_edges()
		if q.is_empty(): return
		engine._spawn_new_token({"name": q.capitalize(), "type_line": "Token", "power": "1", "toughness": "1", "query": "name:%s t:token -is:dfc" % q})
		token_canvas.queue_free(); token_canvas = null
	custom_btn.pressed.connect(spawn_custom)
	custom_input.text_submitted.connect(func(_t): spawn_custom.call())
	search_hbox.add_child(custom_btn)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	for token_data in engine.COMMON_TOKENS:
		var btn := Button.new()
		btn.text = token_data["name"]
		btn.custom_minimum_size = Vector2(140, 46)
		btn.pressed.connect(func(): engine._spawn_new_token(token_data); token_canvas.queue_free(); token_canvas = null)
		grid.add_child(btn)

	apply_custom_font(token_canvas)

func open_activated_abilities_menu(card_node: Node3D) -> void:
	var existing_act := engine.get_node_or_null("ActivatedAbilitiesUI")
	if existing_act: existing_act.queue_free()
	var abilities: Array = card_node.get_activated_abilities()
	var loy_abilities: Array = card_node.parsed_abilities.get("loyalty_abilities", [])
	var can_transform: bool = MagicRules.is_transform(card_node.card_data)
	var is_room: bool = MagicRules.is_room(card_node.card_data)
	var locked_doors: Array[int] = []
	if is_room:
		for d in [0, 1]:
			if not (d in card_node.unlocked_rooms):
				locked_doors.append(d)

	# Always allow opening menu on battlefield permanents so Counter Manager is accessible

	var popup := Control.new()
	popup.name = "ActivatedAbilitiesUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	engine.add_child(popup)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.65)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg_overlay)
	bg_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: popup.queue_free()
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ACTIVATED ABILITIES — %s" % card_node.card_data.get("name", "").to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for loy_ab in loy_abilities:
		var d_str: String = str(loy_ab.get("delta_str", "0"))
		var eff_raw: String = str(loy_ab.get("effect_raw", ""))
		var btn := Button.new()
		btn.text = "[%s]: %s" % [d_str, eff_raw]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(360, 40)
		var cur_loy: int = card_node.get_named_counter("loyalty") if card_node.has_method("get_named_counter") else 0
		var delta_val: int = 0 if "X" in d_str.to_upper() else d_str.to_int()
		var already_used: bool = bool(card_node.get("loyalty_activated_this_turn"))
		var can_act: bool = engine.turn_manager.can_act_sorcery_speed(engine.local_player_id) and not already_used and (delta_val >= 0 or cur_loy >= abs(delta_val))
		btn.disabled = not can_act
		btn.pressed.connect(func():
			popup.queue_free()
			if "X" in d_str.to_upper():
				open_x_stepper_popup(str(card_node.card_data.get("name", "Planeswalker")), "[-X] Loyalty", cur_loy, func(x_val: int):
					card_node.modify_named_counter("loyalty", -x_val)
					card_node.loyalty_activated_this_turn = true
					var sub_ab: Dictionary = loy_ab.duplicate()
					sub_ab["effect_raw"] = OracleParser.substitute_x_in_text(eff_raw, x_val)
					engine._push_ability_to_stack(card_node, sub_ab, "Loyalty [-%d]" % x_val)
				)
			else:
				card_node.modify_named_counter("loyalty", delta_val)
				card_node.loyalty_activated_this_turn = true
				engine._push_ability_to_stack(card_node, loy_ab, "Loyalty [%s]" % d_str)
		)
		vbox.add_child(btn)

	for ab in abilities:
		var cost_raw: String = ab.get("cost_raw", "")
		var effect_raw: String = ab.get("effect_raw", "")
		var sorcery_only: bool = bool(ab.get("sorcery_only", false))
		var target_req: String = str(ab.get("target_requirement", ""))
		var btn := Button.new()
		btn.text = ("Equip %s: %s" % [cost_raw, effect_raw]) if bool(ab.get("is_equip", false)) else ("%s: %s" % [cost_raw, effect_raw])
		if sorcery_only and not engine.turn_manager.can_act_sorcery_speed(engine.local_player_id):
			btn.disabled = true
			btn.text += " [Sorcery Speed]"
		btn.pressed.connect(func():
			var needs_tap := "{T}" in cost_raw or "{t}" in cost_raw
			if needs_tap and card_node.is_tapped:
				popup.queue_free(); return

			var mana_cost := ""
			for m in engine.MANA_COST_REGEX.search_all(cost_raw):
				var sym: String = m.get_string(1).to_upper()
				if sym != "T" and sym != "Q":
					mana_cost += "{" + sym + "}"

			popup.queue_free()

			var execute_activation = func(chosen_tgt: Variant):
				if needs_tap and card_node.is_tapped: return
				var eff_lower := effect_raw.to_lower()
				if "add " in eff_lower:
					var m_abs := OracleParser.parse_mana_abilities(card_node.card_data, card_node)
					if not m_abs.is_empty():
						if m_abs.size() == 1 and m_abs[0].get("colors", []).size() <= 1:
							var cols0: Array = m_abs[0].get("colors", [])
							engine.add_mana_from_ability(card_node, m_abs[0], str(cols0[0]) if not cols0.is_empty() else "")
						else:
							show_mana_ability_popup(card_node, m_abs)
						return
				if not mana_cost.is_empty() and not engine.can_pay_and_drain_cost(mana_cost, engine.local_player_id, {"is_activated": true}): return
				if needs_tap: card_node.toggle_tap()
				var requires_sacrifice := "sacrifice" in cost_raw.to_lower()
				if "add " in eff_lower:
					for m in engine.MANA_SYMBOL_REGEX.search_all(effect_raw.to_upper()):
						var c: String = m.get_string(1)
						if engine.mana_pool.has(c):
							engine.mana_pool[c] += 1
							engine.spawn_mana_produced_animation(card_node, [c])
					update_mana_ui()
				else:
					engine._finalize_push_ability_to_stack(card_node, ab, "Activated", chosen_tgt)
				if requires_sacrifice and is_instance_valid(card_node):
					engine._on_card_to_graveyard(card_node)

			if not target_req.is_empty():
				start_generic_targeting("SELECT %s" % target_req.to_upper(), func(tgt): execute_activation.call(tgt), target_req, card_node)
			else:
				execute_activation.call(null)
		)
		vbox.add_child(btn)

	var crew_n: int = int(card_node.parsed_abilities.get("crew_cost", 0)) if "parsed_abilities" in card_node else 0
	if crew_n > 0:
		var crew_btn := Button.new()
		crew_btn.text = "Crew %d (Animate Vehicle)" % crew_n
		crew_btn.pressed.connect(func():
			popup.queue_free()
			var tot_p := 0
			var tapped_crews: Array[Node3D] = []
			for cr in engine.battlefield_non_lands:
				if is_instance_valid(cr) and cr != card_node and not cr.is_tapped and engine.get_card_owner_id(cr) == engine.local_player_id and MagicRules.is_creature(cr.card_data):
					cr.toggle_tap()
					tapped_crews.append(cr)
					tot_p += maxi(0, int(cr.dynamic_power))
					if tot_p >= crew_n: break
			if tot_p >= crew_n:
				card_node.set_meta("crewed_until_eot", true)
				if "type_overrides" in card_node and not ("Creature" in card_node.type_overrides):
					card_node.type_overrides.append("Creature")
				engine.run_state_based_actions()
			else:
				for cr in tapped_crews:
					if is_instance_valid(cr) and cr.is_tapped: cr.toggle_tap()
		)
		vbox.add_child(crew_btn)

	if can_transform:
		var tr_btn := Button.new()
		var next_face: int = 1 - card_node.active_face_index
		var next_name := str(MagicRules.get_face_data(card_node.card_data, next_face).get("name", "Other Side"))
		tr_btn.text = "Transform → %s" % next_name
		tr_btn.pressed.connect(func():
			popup.queue_free()
			card_node.transform_card()
			engine.run_state_based_actions()
		)
		vbox.add_child(tr_btn)

	for door_idx in locked_doors:
		var door_face := MagicRules.get_face_data(card_node.card_data, door_idx)
		var door_name := str(door_face.get("name", "Door %d" % (door_idx + 1)))
		var door_cost := str(door_face.get("mana_cost", ""))
		var door_btn := Button.new()
		door_btn.text = "Unlock Door: %s (%s)" % [door_name, door_cost]
		door_btn.pressed.connect(func():
			if not engine.turn_manager.can_act_sorcery_speed(engine.local_player_id):
				popup.queue_free(); return
			if not door_cost.is_empty() and not engine.can_pay_and_drain_cost(door_cost):
				popup.queue_free(); return
			popup.queue_free()
			card_node.unlocked_rooms.append(door_idx)
			var door_oracle := str(door_face.get("oracle_text", ""))
			AbilityResolver.execute_effect_text(door_oracle, card_node, null, engine)
			engine.run_state_based_actions()
		)
		vbox.add_child(door_btn)

	var cnt_btn := Button.new()
	cnt_btn.text = "Manage Counters (Oil, Charge, Time, +1/+1...)"
	cnt_btn.pressed.connect(func():
		popup.queue_free()
		open_counter_manager(card_node)
	)
	vbox.add_child(cnt_btn)

	var st_lbl := Label.new()
	st_lbl.text = "CREATURE STATUSES"
	st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st_lbl.add_theme_font_size_override("font_size", 12)
	st_lbl.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0, 1.0))
	vbox.add_child(st_lbl)

	var st_row := HBoxContainer.new()
	st_row.alignment = BoxContainer.ALIGNMENT_CENTER
	st_row.add_theme_constant_override("separation", 6)
	vbox.add_child(st_row)
	for s_name in ["Ring-bearer", "Renowned", "Monstrous", "Suspected", "Saddled"]:
		var s_str: String = s_name
		var sb := Button.new()
		var active_s: bool = card_node.has_method("has_custom_status") and bool(card_node.has_custom_status(s_str))
		sb.text = ("✓ " + s_str) if active_s else s_str
		sb.add_theme_font_size_override("font_size", 11)
		sb.pressed.connect(func():
			if card_node.has_method("toggle_custom_status"):
				card_node.toggle_custom_status(s_str)
				var now_on := bool(card_node.has_custom_status(s_str))
				sb.text = ("✓ " + s_str) if now_on else s_str
		)
		st_row.add_child(sb)

	apply_custom_font(popup)

func open_counter_manager(card_node: Node3D) -> void:
	var existing := engine.get_node_or_null("CounterManagerUI")
	if existing: existing.queue_free()

	var popup := Control.new()
	popup.name = "CounterManagerUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	engine.add_child(popup)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.7)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg_overlay)
	bg_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: popup.queue_free()
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 20; style.content_margin_right = 20; style.content_margin_top = 16; style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "COUNTERS — %s" % str(card_node.card_data.get("name", "Card")).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12); grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	var counter_types := ["+1/+1", "Oil", "Charge", "Time", "Loyalty", "Stun", "Shield", "Lore"]
	for ct in counter_types:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := Label.new()
		lbl.text = ct
		lbl.custom_minimum_size = Vector2(75, 0)
		row.add_child(lbl)

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(30, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.text = str(card_node.counter_amount if ct == "+1/+1" else card_node.get_named_counter(ct))

		var minus_btn := Button.new()
		minus_btn.text = "-"
		minus_btn.custom_minimum_size = Vector2(28, 28)
		minus_btn.pressed.connect(func():
			if ct == "+1/+1": card_node.modify_counters(-1)
			else: card_node.modify_named_counter(ct, -1)
			val_lbl.text = str(card_node.counter_amount if ct == "+1/+1" else card_node.get_named_counter(ct))
			engine.run_state_based_actions()
		)
		row.add_child(minus_btn)
		row.add_child(val_lbl)

		var plus_btn := Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(28, 28)
		plus_btn.pressed.connect(func():
			if ct == "+1/+1": card_node.modify_counters(1)
			else: card_node.modify_named_counter(ct, 1)
			val_lbl.text = str(card_node.counter_amount if ct == "+1/+1" else card_node.get_named_counter(ct))
			engine.run_state_based_actions()
		)
		row.add_child(plus_btn)
		grid.add_child(row)

	var close_btn := Button.new()
	close_btn.text = "Done"
	close_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close_btn)

	apply_custom_font(popup)


func open_choice_popup(title_text: String, choice_labels: Array, on_chosen: Callable) -> void:
	var existing := engine.get_node_or_null("GenericChoiceUI")
	if existing: existing.queue_free()

	var popup := Control.new()
	popup.name = "GenericChoiceUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_to_group("dismissible_popup")
	engine.add_child(popup)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.7)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 22; style.content_margin_right = 22; style.content_margin_top = 18; style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	for i in range(choice_labels.size()):
		var idx := i
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 42)
		btn.text = str(choice_labels[i])
		btn.pressed.connect(func():
			popup.queue_free()
			on_chosen.call(idx)
		)
		vbox.add_child(btn)

	apply_custom_font(popup)

func open_face_choice_popup(card_node: Node3D, title_text: String, options: Array, on_selected: Callable) -> void:
	var existing := engine.get_node_or_null("FaceChoiceUI")
	if existing: existing.queue_free()

	var popup := Control.new()
	popup.name = "FaceChoiceUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	engine.add_child(popup)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.7)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg_overlay)
	bg_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: popup.queue_free()
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 22; style.content_margin_right = 22; style.content_margin_top = 18; style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	for opt in options:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(360, 44)
		btn.text = opt["label"]
		btn.pressed.connect(func():
			popup.queue_free()
			on_selected.call(opt)
		)
		vbox.add_child(btn)

	apply_custom_font(popup)

func show_mana_choice_popup(card_node: Node3D, colors: Array) -> void:
	var existing_popup := engine.get_node_or_null("ManaPopupUI")
	if existing_popup: existing_popup.queue_free()

	var spawn_pos: Vector3 = card_node.global_position if (card_node and is_instance_valid(card_node)) else engine.central_stack_anchor.global_position
	var card_id: int = card_node.get_instance_id() if (card_node and is_instance_valid(card_node)) else 0

	var popup := Control.new()
	popup.name = "ManaPopupUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	engine.add_child(popup)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.65)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg_overlay)

	bg_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			var c_ref := instance_from_id(card_id) as Node3D if card_id != 0 else null
			if c_ref and is_instance_valid(c_ref) and c_ref.is_tapped: c_ref.toggle_tap()
			popup.queue_free()
	)

	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center_container)

	var panel := PanelContainer.new()
	center_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	var label := Label.new()
	label.text = "ADD MANA"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)

	for color in colors:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(50, 50)
		if engine.MANA_ICONS.has(color):
			var tex: Texture2D = load(engine.MANA_ICONS[color])
			if tex: btn.icon = tex; btn.expand_icon = true
		if btn.icon == null: btn.text = "{" + color + "}"

		btn.pressed.connect(func():
			engine.mana_pool[color] += 1
			engine.event_ledger.log_event(GameEventLedger.EventType.MANA_ADDED, {"color": color, "amount": 1})
			var c_ref := instance_from_id(card_id) as Node3D if card_id != 0 else null
			engine.spawn_mana_produced_animation(c_ref if (c_ref and is_instance_valid(c_ref)) else spawn_pos, [color])
			update_mana_ui()
			popup.queue_free()
		)
		hbox.add_child(btn)

	apply_custom_font(popup)

func show_mana_ability_popup(card_node: Node3D, abilities: Array[Dictionary]) -> void:
	var popup := CanvasLayer.new()
	popup.layer = 100
	popup.add_to_group("dismissible_popup")
	engine.add_child(popup)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 20; style.content_margin_right = 20; style.content_margin_top = 16; style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var c_name: String = str(card_node.card_data.get("name", "Mana Source")) if is_instance_valid(card_node) else "Mana Source"
	var title := Label.new()
	title.text = "TAP %s FOR MANA" % c_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
	vbox.add_child(title)

	var card_id := card_node.get_instance_id() if is_instance_valid(card_node) else 0

	for ab in abilities:
		var colors: Array = ab.get("colors", [])
		var fixed_combo: Array = ab.get("fixed_combo", [])
		var mana_cost: String = str(ab.get("mana_cost", ""))
		var life_cost: int = int(ab.get("life_cost", 0))
		var sac_cost: bool = bool(ab.get("sac_cost", false))
		var rest_text: String = str(ab.get("restriction_text", ""))
		var amt: int = int(ab.get("amount", 1))

		var cost_tags: Array[String] = []
		if not mana_cost.is_empty(): cost_tags.append(mana_cost)
		if life_cost > 0: cost_tags.append("Pay %d life" % life_cost)
		if sac_cost: cost_tags.append("Sacrifice")
		if not rest_text.is_empty(): cost_tags.append(rest_text)
		var note_str := (" [" + ", ".join(cost_tags) + "]") if not cost_tags.is_empty() else ""

		if not fixed_combo.is_empty() or colors.size() <= 1:
			var btn := Button.new()
			var sym_str := ""
			if not fixed_combo.is_empty():
				for fc in fixed_combo: sym_str += "{" + str(fc) + "}"
			else:
				var c0: String = str(colors[0]) if not colors.is_empty() else "C"
				sym_str = ("%dx {%s}" % [amt, c0]) if amt > 1 else ("{" + c0 + "}")
				if engine.MANA_ICONS.has(c0):
					var tex: Texture2D = load(engine.MANA_ICONS[c0])
					if tex: btn.icon = tex; btn.expand_icon = true
			btn.text = "Add %s%s" % [sym_str, note_str]
			btn.custom_minimum_size = Vector2(300, 42)
			var ab_cap := ab.duplicate(true)
			btn.pressed.connect(func():
				var c_ref := instance_from_id(card_id) as Node3D if card_id != 0 else null
				if c_ref and is_instance_valid(c_ref):
					engine.add_mana_from_ability(c_ref, ab_cap, "")
				popup.queue_free()
			)
			vbox.add_child(btn)
		else:
			if not note_str.is_empty():
				var note_lbl := Label.new()
				note_lbl.text = note_str.strip_edges()
				note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				note_lbl.add_theme_font_size_override("font_size", 12)
				note_lbl.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45, 1.0))
				vbox.add_child(note_lbl)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 10)
			vbox.add_child(row)
			for col in colors:
				var c_str := str(col)
				var btn := Button.new()
				btn.custom_minimum_size = Vector2(52, 52)
				if engine.MANA_ICONS.has(c_str):
					var tex: Texture2D = load(engine.MANA_ICONS[c_str])
					if tex: btn.icon = tex; btn.expand_icon = true
				if btn.icon == null: btn.text = "{" + c_str + "}"
				var ab_cap := ab.duplicate(true)
				btn.pressed.connect(func():
					var c_ref := instance_from_id(card_id) as Node3D if card_id != 0 else null
					if c_ref and is_instance_valid(c_ref):
						engine.add_mana_from_ability(c_ref, ab_cap, c_str)
					popup.queue_free()
				)
				row.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 34)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(cancel_btn)

	apply_custom_font(popup)

func open_etb_creature_type_popup(card_node: Node3D, candidate_types: Array[String], callback: Callable) -> void:
	var popup := CanvasLayer.new()
	popup.layer = 105
	popup.add_to_group("dismissible_popup")
	engine.add_child(popup)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 360)
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 20; style.content_margin_right = 20; style.content_margin_top = 16; style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var c_name: String = str(card_node.card_data.get("name", "Card")) if is_instance_valid(card_node) else "Card"
	var title := Label.new()
	title.text = "CHOOSE CREATURE TYPE (%s)" % c_name.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	for ct in candidate_types:
		var btn := Button.new()
		btn.text = ct
		btn.custom_minimum_size = Vector2(175, 36)
		btn.pressed.connect(func():
			popup.queue_free()
			if callback.is_valid(): callback.call(ct)
		)
		grid.add_child(btn)

	apply_custom_font(popup)

func toggle_controller_help() -> void:
	if controller_help_canvas and is_instance_valid(controller_help_canvas):
		controller_help_canvas.queue_free()
		controller_help_canvas = null
		return

	controller_help_canvas = CanvasLayer.new()
	controller_help_canvas.name = "ControllerHelpUI"
	controller_help_canvas.layer = 120
	engine.add_child(controller_help_canvas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	controller_help_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND
	style.border_color = engine.UI_BORDER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 12; style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	style.content_margin_left = 24; style.content_margin_right = 24
	style.content_margin_top = 20; style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "XBOX CONTROLLER CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	vbox.add_child(title)

	var body := Label.new()
	body.text = """Left Stick: Move Virtual Cursor
Right Stick: Pan Camera
LT + Right Stick (Up/Down): Zoom In / Out
RT + Right Stick: Free Look (Turn / Tilt)
R3 (Right Stick Click): Reset Camera Home
A: Play / Tap / Select / Click UI
B: Cancel / Close Menu / Clear Blocker
X: Declare Attacker (Combat) / Abilities Menu
RB (Combat) / Tab: Cycle Next Attacker
LB (Combat) / Shift+A (Key): Cycle Attack Target
Y: Confirm / Pass Priority / Next Phase
LB / RB: Open Graveyard / Open Exile
L3 (Left Stick Click): Untap Card or All
Back / View: Toggle Help"""
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 1))
	vbox.add_child(body)

	var close_btn := Button.new()
	close_btn.text = "Close (B / View)"
	close_btn.pressed.connect(func(): toggle_controller_help())
	vbox.add_child(close_btn)

	apply_custom_font(controller_help_canvas)

func open_x_stepper_popup(card_name: String, mana_cost: String, max_x: int, on_confirmed: Callable) -> void:
	var existing := engine.get_node_or_null("XStepperUI")
	if existing: existing.queue_free()

	var popup := Control.new()
	popup.name = "XStepperUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_to_group("dismissible_popup")
	engine.add_child(popup)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 24; style.content_margin_right = 24; style.content_margin_top = 18; style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE X FOR %s (%s)" % [card_name.to_upper(), mana_cost]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var state := {"x": mini(1, max_x)}
	var step_row := HBoxContainer.new()
	step_row.alignment = BoxContainer.ALIGNMENT_CENTER
	step_row.add_theme_constant_override("separation", 12)
	vbox.add_child(step_row)

	var val_lbl := Label.new()
	val_lbl.text = "X = %d" % state["x"]
	val_lbl.custom_minimum_size = Vector2(90, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 20)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(44, 40)
	minus_btn.pressed.connect(func():
		state["x"] = maxi(0, int(state["x"]) - 1)
		val_lbl.text = "X = %d" % state["x"]
	)
	step_row.add_child(minus_btn)
	step_row.add_child(val_lbl)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(44, 40)
	plus_btn.pressed.connect(func():
		state["x"] = mini(max_x, int(state["x"]) + 1)
		val_lbl.text = "X = %d" % state["x"]
	)
	step_row.add_child(plus_btn)

	var max_btn := Button.new()
	max_btn.text = "Max (%d)" % max_x
	max_btn.custom_minimum_size = Vector2(90, 40)
	max_btn.pressed.connect(func():
		state["x"] = max_x
		val_lbl.text = "X = %d" % state["x"]
	)
	step_row.add_child(max_btn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(110, 38)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	btn_row.add_child(cancel_btn)

	var cast_btn := Button.new()
	cast_btn.text = "Confirm X"
	cast_btn.custom_minimum_size = Vector2(140, 38)
	cast_btn.pressed.connect(func():
		var chosen := int(state["x"])
		popup.queue_free()
		on_confirmed.call(chosen)
	)
	btn_row.add_child(cast_btn)

	apply_custom_font(popup)

func open_modal_choice_popup(card_name: String, choose_count: int, allow_repeat: bool, modes: Array, on_confirmed: Callable) -> void:
	var existing := engine.get_node_or_null("ModalChoiceUI")
	if existing: existing.queue_free()

	var popup := Control.new()
	popup.name = "ModalChoiceUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_to_group("dismissible_popup")
	engine.add_child(popup)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 22; style.content_margin_right = 22; style.content_margin_top = 18; style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE %d MODE(S) — %s" % [choose_count, card_name.to_upper()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var selected_modes: Array[String] = []
	var confirm_btn: Button = null
	var mode_buttons: Array[Button] = []

	for i in range(modes.size()):
		var m_txt := str(modes[i])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(440, 42)
		btn.text = m_txt
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.pressed.connect(func():
			if choose_count == 1:
				popup.queue_free()
				on_confirmed.call(m_txt)
				return
			if not allow_repeat and (m_txt in selected_modes):
				selected_modes.erase(m_txt)
			elif selected_modes.size() < choose_count:
				selected_modes.append(m_txt)
			for j in range(mode_buttons.size()):
				var base_t := str(modes[j])
				var cnt := selected_modes.count(base_t)
				mode_buttons[j].text = ("[%dx] " % cnt + base_t) if cnt > 0 else base_t
			if confirm_btn:
				confirm_btn.disabled = (selected_modes.size() != choose_count)
				confirm_btn.text = "Confirm (%d/%d)" % [selected_modes.size(), choose_count]
		)
		vbox.add_child(btn)
		mode_buttons.append(btn)

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 12)
	vbox.add_child(action_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(110, 36)
	cancel_btn.pressed.connect(func(): popup.queue_free())
	action_row.add_child(cancel_btn)

	if choose_count > 1:
		confirm_btn = Button.new()
		confirm_btn.text = "Confirm (0/%d)" % choose_count
		confirm_btn.disabled = true
		confirm_btn.custom_minimum_size = Vector2(150, 36)
		confirm_btn.pressed.connect(func():
			var joined := "\n".join(selected_modes)
			popup.queue_free()
			on_confirmed.call(joined)
		)
		action_row.add_child(confirm_btn)

	apply_custom_font(popup)

func refresh_commander_damage_labels() -> void:
	for pid in cmd_dmg_labels.keys():
		var lbl: Label = cmd_dmg_labels[pid]
		if not is_instance_valid(lbl): continue
		var cmd_map: Dictionary = engine.commander_damage.get(pid, {})
		var parts: Array[String] = []
		for cmd_card in cmd_map.keys():
			var amt := int(cmd_map[cmd_card])
			if amt > 0 and is_instance_valid(cmd_card):
				parts.append("%s: %d" % [str(cmd_card.card_data.get("name", "Cmd")).split(" ")[0], amt])
		if parts.is_empty():
			lbl.visible = false
		else:
			lbl.text = "Cmd Dmg — " + ", ".join(parts)
			lbl.visible = true

func toggle_match_log() -> void:
	if match_log_canvas and is_instance_valid(match_log_canvas):
		match_log_canvas.queue_free()
		match_log_canvas = null
		return
	match_log_canvas = CanvasLayer.new()
	match_log_canvas.name = "MatchLogUI"
	match_log_canvas.layer = 115
	engine.add_child(match_log_canvas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	match_log_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 480)
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 20; style.content_margin_right = 20; style.content_margin_top = 16; style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var title := Label.new()
	title.text = "MATCH EVENT LOG"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	hdr.add_child(title)
	var close_b := Button.new()
	close_b.text = "Close"
	close_b.pressed.connect(func(): toggle_match_log())
	hdr.add_child(close_b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var log_lbl := Label.new()
	log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lines: Array[String] = []
	if engine.event_ledger and "event_history" in engine.event_ledger:
		for ev in engine.event_ledger.event_history:
			lines.append(str(ev))
	log_lbl.text = "\n".join(lines) if not lines.is_empty() else "No events recorded yet."
	scroll.add_child(log_lbl)
	apply_custom_font(match_log_canvas)

func open_scry_surveil_popup(is_surveil: bool, top_cards: Array) -> void:
	if top_cards.is_empty(): return
	var existing := engine.get_node_or_null("ScrySurveilUI")
	if existing: existing.queue_free()

	var popup := Control.new()
	popup.name = "ScrySurveilUI"
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	engine.add_child(popup)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = engine.UI_BACKGROUND; style.border_color = engine.UI_BORDER; style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10; style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 22; style.content_margin_right = 22; style.content_margin_top = 18; style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var mode_name := "SURVEIL" if is_surveil else "SCRY"
	var dest_name := "Graveyard" if is_surveil else "Bottom"
	var title := Label.new()
	title.text = "%s %d — Click cards to toggle Top vs. %s" % [mode_name, top_cards.size(), dest_name]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vbox.add_child(row)

	var decisions := {}
	for c in top_cards:
		decisions[c] = "top"
		var card_col := VBoxContainer.new()
		card_col.add_theme_constant_override("separation", 6)
		row.add_child(card_col)

		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.custom_minimum_size = Vector2(180, 250)
		var tex: Texture2D = engine._get_card_texture(c)
		if tex: tex_rect.texture = tex
		card_col.add_child(tex_rect)

		var toggle_btn := Button.new()
		toggle_btn.text = "Keep on Top"
		toggle_btn.custom_minimum_size = Vector2(180, 34)
		toggle_btn.pressed.connect(func():
			if decisions[c] == "top":
				decisions[c] = "away"
				toggle_btn.text = "Put in %s" % dest_name
			else:
				decisions[c] = "top"
				toggle_btn.text = "Keep on Top"
		)
		card_col.add_child(toggle_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm %s" % mode_name.capitalize()
	confirm_btn.custom_minimum_size = Vector2(200, 38)
	confirm_btn.pressed.connect(func():
		popup.queue_free()
		for c in top_cards:
			if not is_instance_valid(c): continue
			if decisions[c] == "away":
				engine.library_stack.erase(c)
				if is_surveil:
					engine._on_card_to_graveyard(c)
				else:
					engine.zone_manager.move_to_bottom_library(c)
			else:
				if c.has_method("setup_library"): c.setup_library()
		engine.zone_manager.update_zone_counters()
	)
	vbox.add_child(confirm_btn)
	apply_custom_font(popup)

func toggle_settings_menu() -> void:
	if settings_canvas and is_instance_valid(settings_canvas):
		settings_canvas.queue_free()
		settings_canvas = null
		return

	settings_canvas = CanvasLayer.new()
	settings_canvas.name = "SettingsMenuUI"
	settings_canvas.layer = 115
	engine.add_child(settings_canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_canvas.add_child(bg)
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed: toggle_settings_menu()
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_canvas.add_child(center)

	var panel := PanelContainer.new()
	var vp_sz := engine.get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(minf(600.0, vp_sz.x - 24.0), 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "GAME SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	var sfx_btn := Button.new()
	var is_muted: bool = engine.sound_manager != null and bool(engine.sound_manager._muted)
	sfx_btn.text = "Sound Effects: OFF" if is_muted else "Sound Effects: ON"
	sfx_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_btn.custom_minimum_size = Vector2(0, 38)
	sfx_btn.pressed.connect(func():
		if engine.sound_manager:
			var next_m := not bool(engine.sound_manager._muted)
			engine.sound_manager.set_muted(next_m)
			sfx_btn.text = "Sound Effects: OFF" if next_m else "Sound Effects: ON"
	)
	grid.add_child(sfx_btn)

	var auto_btn := Button.new()
	auto_btn.text = "Auto-Pass Opponents: ON" if engine.turn_manager.auto_pass_opponents else "Auto-Pass Opponents: OFF"
	auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_btn.custom_minimum_size = Vector2(0, 38)
	auto_btn.pressed.connect(func():
		engine.turn_manager.auto_pass_opponents = not engine.turn_manager.auto_pass_opponents
		auto_btn.text = "Auto-Pass Opponents: ON" if engine.turn_manager.auto_pass_opponents else "Auto-Pass Opponents: OFF"
	)
	grid.add_child(auto_btn)

	var diff_btn := Button.new()
	var _diff_lbl := func() -> String:
		var d: int = int(engine.ai_controller.difficulty) if engine.ai_controller else 1
		return "AI Difficulty: Casual" if d == 0 else ("AI Difficulty: cEDH" if d == 2 else "AI Difficulty: Tuned")
	diff_btn.text = _diff_lbl.call()
	diff_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_btn.custom_minimum_size = Vector2(0, 38)
	diff_btn.pressed.connect(func():
		if engine.ai_controller:
			engine.ai_controller.difficulty = (int(engine.ai_controller.difficulty) + 1) % 3
			diff_btn.text = _diff_lbl.call()
	)
	grid.add_child(diff_btn)

	var touch_btn := Button.new()
	touch_btn.text = "Touch Action Bar: ON" if touch_controls_enabled else "Touch Action Bar: OFF"
	touch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	touch_btn.custom_minimum_size = Vector2(0, 42)
	touch_btn.pressed.connect(func():
		touch_controls_enabled = not touch_controls_enabled
		touch_btn.text = "Touch Action Bar: ON" if touch_controls_enabled else "Touch Action Bar: OFF"
		setup_touch_action_bar()
	)
	grid.add_child(touch_btn)

	var mp_btn := Button.new()
	mp_btn.text = "🌐 P2P Multiplayer Lobby"
	mp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_btn.custom_minimum_size = Vector2(0, 42)
	mp_btn.pressed.connect(func():
		toggle_settings_menu()
		open_multiplayer_lobby()
	)
	grid.add_child(mp_btn)

	var undo_btn := Button.new()
	undo_btn.text = "↩ Undo Last Action"
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_btn.custom_minimum_size = Vector2(0, 40)
	undo_btn.disabled = engine.is_network_multiplayer() or engine.undo_stack.is_empty()
	undo_btn.pressed.connect(func():
		toggle_settings_menu()
		if engine.has_method("undo_last_action"): engine.undo_last_action()
	)
	grid.add_child(undo_btn)

	var save_btn := Button.new()
	save_btn.text = "💾 Save Game"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 40)
	save_btn.pressed.connect(func():
		if engine.has_method("save_game_to_disk") and engine.save_game_to_disk():
			save_btn.text = "💾 Saved!"
	)
	grid.add_child(save_btn)

	var load_g_btn := Button.new()
	load_g_btn.text = "📂 Load Saved Game"
	load_g_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_g_btn.custom_minimum_size = Vector2(0, 40)
	load_g_btn.disabled = not FileAccess.file_exists("user://savegame.json")
	load_g_btn.pressed.connect(func():
		toggle_settings_menu()
		if engine.has_method("load_game_from_disk"): engine.load_game_from_disk()
	)
	grid.add_child(load_g_btn)

	var spd_btn := Button.new()
	var _spd_label := func() -> String:
		if engine.controller_cursor_speed < 750.0: return "Controller Cursor Speed: Slow"
		elif engine.controller_cursor_speed > 1150.0: return "Controller Cursor Speed: Fast"
		return "Controller Cursor Speed: Normal"
	spd_btn.text = _spd_label.call()
	spd_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spd_btn.custom_minimum_size = Vector2(0, 38)
	spd_btn.pressed.connect(func():
		if engine.controller_cursor_speed < 750.0: engine.controller_cursor_speed = 950.0
		elif engine.controller_cursor_speed < 1150.0: engine.controller_cursor_speed = 1350.0
		else: engine.controller_cursor_speed = 650.0
		spd_btn.text = _spd_label.call()
	)
	grid.add_child(spd_btn)

	var trk_btn := Button.new()
	trk_btn.text = "Table & Player Trackers"
	trk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trk_btn.custom_minimum_size = Vector2(0, 38)
	trk_btn.pressed.connect(func():
		toggle_settings_menu()
		toggle_table_trackers()
	)
	grid.add_child(trk_btn)

	var log_btn := Button.new()
	log_btn.text = "Match Event Log"
	log_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_btn.custom_minimum_size = Vector2(0, 38)
	log_btn.pressed.connect(func():
		toggle_settings_menu()
		toggle_match_log()
	)
	grid.add_child(log_btn)

	var ctrl_btn := Button.new()
	ctrl_btn.text = "Xbox Controller Guide"
	ctrl_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl_btn.custom_minimum_size = Vector2(0, 38)
	ctrl_btn.pressed.connect(func():
		toggle_settings_menu()
		toggle_controller_help()
	)
	grid.add_child(ctrl_btn)

	var reset_btn := Button.new()
	reset_btn.text = "New Game / Reselect Decks"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.custom_minimum_size = Vector2(0, 38)
	reset_btn.pressed.connect(func():
		toggle_settings_menu()
		engine.reset_game_and_reselect_decks()
	)
	grid.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(func(): toggle_settings_menu())
	vbox.add_child(close_btn)

	apply_custom_font(settings_canvas)

func show_game_over_banner(winner_pid: int) -> void:
	var existing := engine.get_node_or_null("GameOverUI")
	if existing: existing.queue_free()

	var canvas := CanvasLayer.new()
	canvas.name = "GameOverUI"
	canvas.layer = 130
	engine.add_child(canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MATCH COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var sub := Label.new()
	var w_name: String = str(engine.get_player_display_name(winner_pid)) if winner_pid > 0 else "Draw"
	sub.text = "%s wins on Turn %d!" % [w_name, engine.turn_manager.turn_number] if winner_pid > 0 else "All players eliminated!"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	vbox.add_child(sub)

	var restart_btn := Button.new()
	restart_btn.text = "New Game / Reselect Decks"
	restart_btn.custom_minimum_size = Vector2(0, 42)
	restart_btn.pressed.connect(func():
		canvas.queue_free()
		engine.reset_game_and_reselect_decks()
	)
	vbox.add_child(restart_btn)
	apply_custom_font(canvas)

func open_damage_order_popup(attacker: Node3D, blockers: Array, on_confirmed: Callable) -> void:
	var existing := engine.get_node_or_null("DamageOrderUI")
	if existing: existing.queue_free()

	var canvas := CanvasLayer.new()
	canvas.name = "DamageOrderUI"
	canvas.layer = 112
	engine.add_child(canvas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "DAMAGE ORDER FOR %s" % str(attacker.card_data.get("name", "ATTACKER")).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var ordered: Array = []
	for b in blockers:
		var blk_ref: Node3D = b
		var btn := Button.new()
		btn.text = "%s (%d/%d)" % [str(blk_ref.card_data.get("name", "Blocker")), int(blk_ref.dynamic_power), int(blk_ref.dynamic_toughness)]
		btn.custom_minimum_size = Vector2(0, 38)
		btn.pressed.connect(func():
			if not (blk_ref in ordered):
				ordered.append(blk_ref)
				btn.text = "#%d: %s (%d/%d)" % [ordered.size(), str(blk_ref.card_data.get("name", "Blocker")), int(blk_ref.dynamic_power), int(blk_ref.dynamic_toughness)]
				btn.disabled = true
			if ordered.size() >= blockers.size():
				canvas.queue_free()
				on_confirmed.call(ordered)
		)
		vbox.add_child(btn)
	apply_custom_font(canvas)

func toggle_table_trackers() -> void:
	if tracker_canvas and is_instance_valid(tracker_canvas):
		tracker_canvas.queue_free()
		tracker_canvas = null
		return

	tracker_canvas = CanvasLayer.new()
	tracker_canvas.name = "TableTrackersUI"
	tracker_canvas.layer = 115
	engine.add_child(tracker_canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	tracker_canvas.add_child(bg)
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed: toggle_table_trackers()
	)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	tracker_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 520)
	center.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(main_vbox)

	var hdr := HBoxContainer.new()
	main_vbox.add_child(hdr)
	var title := Label.new()
	title.text = "TABLE & PLAYER TRACKERS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	hdr.add_child(title)
	var close_b := Button.new()
	close_b.text = "Close"
	close_b.pressed.connect(func(): toggle_table_trackers())
	hdr.add_child(close_b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var dn_row := HBoxContainer.new()
	dn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(dn_row)
	var dn_lbl := Label.new()
	dn_lbl.text = "Battlefield Time:"
	dn_lbl.custom_minimum_size = Vector2(140, 0)
	dn_row.add_child(dn_lbl)
	for dn_val in ["", "Day", "Night"]:
		var dv: String = dn_val
		var db := Button.new()
		db.text = "None" if dv.is_empty() else dv
		db.pressed.connect(func(): engine.set_day_night(dv))
		dn_row.add_child(db)

	vbox.add_child(HSeparator.new())

	for pid in [1, 2, 3, 4]:
		var p_id: int = pid
		var p_hdr := Label.new()
		p_hdr.text = engine.get_player_display_name(p_id)
		p_hdr.add_theme_color_override("font_color", Color(0.45, 0.95, 0.45, 1.0) if p_id == 1 else Color(1.0, 0.85, 0.4, 1.0))
		vbox.add_child(p_hdr)

		var cnt_row := HBoxContainer.new()
		cnt_row.add_theme_constant_override("separation", 6)
		vbox.add_child(cnt_row)
		for cname in ["poison", "experience", "energy", "rad"]:
			var ck: String = cname
			var cur_v: int = int(engine.player_counters.get(p_id, {}).get(ck, 0))
			var b_minus := Button.new()
			b_minus.text = "-%s" % ck.left(3).capitalize()
			var b_plus := Button.new()
			b_plus.text = "+%s (%d)" % [ck.left(3).capitalize(), cur_v]
			b_minus.pressed.connect(func():
				engine.modify_player_counter(p_id, ck, -1)
				b_plus.text = "+%s (%d)" % [ck.left(3).capitalize(), int(engine.player_counters.get(p_id, {}).get(ck, 0))]
			)
			b_plus.pressed.connect(func():
				engine.modify_player_counter(p_id, ck, 1)
				b_plus.text = "+%s (%d)" % [ck.left(3).capitalize(), int(engine.player_counters.get(p_id, {}).get(ck, 0))]
			)
			cnt_row.add_child(b_minus)
			cnt_row.add_child(b_plus)

		var st_row := HBoxContainer.new()
		st_row.add_theme_constant_override("separation", 6)
		vbox.add_child(st_row)
		var mon_b := Button.new()
		mon_b.text = "Monarch"
		mon_b.pressed.connect(func(): engine.set_monarch(0 if engine.monarch_player_id == p_id else p_id))
		st_row.add_child(mon_b)

		var init_b := Button.new()
		init_b.text = "Initiative"
		init_b.pressed.connect(func(): engine.set_initiative(0 if engine.initiative_player_id == p_id else p_id))
		st_row.add_child(init_b)

		for ps_name in ["City's Blessing", "Storied"]:
			var ps_str: String = ps_name
			var ps_b := Button.new()
			ps_b.text = ps_str
			ps_b.pressed.connect(func(): engine.toggle_player_status(p_id, ps_str))
			st_row.add_child(ps_b)

		var dng_b := Button.new()
		dng_b.text = "Advance Dungeon"
		dng_b.pressed.connect(func():
			var cur_d: Dictionary = engine.player_dungeons.get(p_id, {})
			var next_rm: int = (int(cur_d.get("room", 0)) % 4) + 1
			engine.set_player_dungeon(p_id, "Dungeon", next_rm)
		)
		st_row.add_child(dng_b)

	apply_custom_font(tracker_canvas)


var _turn_banner_canvas: CanvasLayer = null

func show_turn_banner(pid: int, turn_num: int) -> void:
	if _turn_banner_canvas and is_instance_valid(_turn_banner_canvas):
		_turn_banner_canvas.queue_free()
	_turn_banner_canvas = CanvasLayer.new()
	_turn_banner_canvas.layer = 95
	engine.add_child(_turn_banner_canvas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 86
	center.offset_bottom = 146
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_banner_canvas.add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	var is_local: bool = (pid == engine.local_player_id)
	style.bg_color = Color(0.08, 0.11, 0.14, 0.92)
	style.border_color = Color(0.40, 0.92, 0.50, 0.95) if is_local else Color(0.95, 0.78, 0.32, 0.95)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 10; style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10; style.corner_radius_bottom_right = 10
	style.content_margin_left = 26; style.content_margin_right = 26
	style.content_margin_top = 8; style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var lbl := Label.new()
	var p_name: String = engine.get_player_display_name(pid).to_upper()
	lbl.text = ("YOUR TURN  •  TURN %d" % turn_num) if is_local else ("%s'S TURN  •  TURN %d" % [p_name, turn_num])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.65) if is_local else Color(1.0, 0.88, 0.50))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	apply_custom_font(_turn_banner_canvas)
	panel.modulate.a = 0.0
	var c_id := _turn_banner_canvas.get_instance_id()
	var tw := engine.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.05)
	tw.tween_property(panel, "modulate:a", 0.0, 0.32)
	tw.tween_callback(func():
		var c := instance_from_id(c_id)
		if c and is_instance_valid(c): c.queue_free()
	)


func open_multiplayer_lobby() -> void:
	if lobby_canvas and is_instance_valid(lobby_canvas):
		lobby_canvas.queue_free()
		lobby_canvas = null
		return

	lobby_canvas = CanvasLayer.new()
	lobby_canvas.name = "MultiplayerLobbyUI"
	lobby_canvas.layer = 125
	engine.add_child(lobby_canvas)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_canvas.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby_canvas.add_child(center)

	var panel := PanelContainer.new()
	var vp_sz := engine.get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(minf(540.0, vp_sz.x - 24.0), 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "P2P 4-PLAYER LOBBY (ENET)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var nm: NetworkManager = engine.network_manager
	var status_lbl := Label.new()
	status_lbl.text = "Status: %s" % ("Host / Connected" if (nm and nm.is_network_active()) else "Offline (Solo / AI Mode)")
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0, 1.0))
	vbox.add_child(status_lbl)

	var seats_lbl := Label.new()
	seats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seats_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(seats_lbl)

	var refresh_seats := func():
		if not is_instance_valid(seats_lbl) or not nm: return
		var parts: Array[String] = []
		for s in [1, 2, 3, 4]:
			if nm.seat_to_peer.has(s):
				parts.append("Seat %d: %s" % [s, str(nm.seat_names.get(s, "Human"))])
			else:
				parts.append("Seat %d: AI Bot" % s)
		seats_lbl.text = "\n".join(parts)
	refresh_seats.call()

	if nm:
		nm.lobby_updated.connect(refresh_seats)
		nm.connection_status_changed.connect(func(txt: String, _ok: bool):
			if is_instance_valid(status_lbl): status_lbl.text = "Status: " + txt
		)

	vbox.add_child(HSeparator.new())

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 8)
	vbox.add_child(host_row)
	var port_in := LineEdit.new()
	port_in.text = str(NetworkManager.DEFAULT_PORT)
	port_in.placeholder_text = "Port (7777)"
	port_in.custom_minimum_size = Vector2(110, 40)
	host_row.add_child(port_in)
	var host_btn := Button.new()
	host_btn.text = "Host Game"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.custom_minimum_size = Vector2(0, 40)
	host_btn.pressed.connect(func():
		if nm: nm.host_game(int(port_in.text) if port_in.text.is_valid_int() else NetworkManager.DEFAULT_PORT)
	)
	host_row.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	vbox.add_child(join_row)
	var ip_in := LineEdit.new()
	ip_in.placeholder_text = "Host IP (e.g. 192.168.1.50)"
	ip_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_in.custom_minimum_size = Vector2(0, 40)
	join_row.add_child(ip_in)
	var join_btn := Button.new()
	join_btn.text = "Join Game"
	join_btn.custom_minimum_size = Vector2(120, 40)
	join_btn.pressed.connect(func():
		if nm: nm.join_game(ip_in.text, int(port_in.text) if port_in.text.is_valid_int() else NetworkManager.DEFAULT_PORT)
	)
	join_row.add_child(join_btn)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var disc_btn := Button.new()
	disc_btn.text = "Disconnect / Solo"
	disc_btn.custom_minimum_size = Vector2(160, 40)
	disc_btn.pressed.connect(func():
		if nm: nm.disconnect_game()
	)
	btn_row.add_child(disc_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.pressed.connect(func(): open_multiplayer_lobby())
	btn_row.add_child(close_btn)

	apply_custom_font(lobby_canvas)


func open_trigger_order_popup(trigs: Array, callback: Callable) -> void:
	var popup := CanvasLayer.new()
	popup.layer = 110
	engine.add_child(popup)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ORDER SIMULTANEOUS TRIGGERS (1ST = RESOLVES LAST)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	vbox.add_child(title)

	var ordered := []
	var remaining := trigs.duplicate()

	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 6)
	vbox.add_child(list_box)

	var rebuild := [Callable()]
	rebuild[0] = func():
		for ch in list_box.get_children(): ch.queue_free()
		for idx in range(remaining.size()):
			var item: Dictionary = remaining[idx]
			var p_name := str(item["perm"].card_data.get("name", "Card")) if is_instance_valid(item["perm"]) else "Card"
			var eff := str(item["trig"].get("effect_raw", "")).left(42)
			var b := Button.new()
			b.text = "Stack Next: %s — %s" % [p_name, eff]
			b.pressed.connect(func():
				ordered.append(item)
				remaining.remove_at(idx)
				if remaining.is_empty():
					popup.queue_free()
					if callback.is_valid(): callback.call(ordered)
				else:
					rebuild[0].call()
			)
			list_box.add_child(b)
	rebuild[0].call()

	var auto_b := Button.new()
	auto_b.text = "Auto-Order Remaining"
	auto_b.pressed.connect(func():
		ordered.append_array(remaining)
		popup.queue_free()
		if callback.is_valid(): callback.call(ordered)
	)
	vbox.add_child(auto_b)
	apply_custom_font(popup)
