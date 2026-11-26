class_name DeckLoader
extends Node

var engine: Node = null
var _prefetch_urls: Array[String] = []
var _prefetch_in_flight: int = 0
var _prefetch_total: int = 0
var _prefetch_done: int = 0
var _pending_deck_loads: int = 0
var _total_deck_loads: int = 0
const MOBILE_DECK_CACHE_PATH = "user://deck_cache.json"

func _load_deck_cache() -> Dictionary:
	var merged := {}
	var cm_cache = CardManager.load_cache_from_disk()
	if cm_cache is Dictionary:
		merged = cm_cache.duplicate(true)
	if FileAccess.file_exists(MOBILE_DECK_CACHE_PATH):
		var f := FileAccess.open(MOBILE_DECK_CACHE_PATH, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.get_data() is Dictionary:
				var u_cache: Dictionary = json.get_data()
				for k in u_cache.keys():
					if not merged.has(k):
						merged[k] = u_cache[k]
	return merged

func _save_deck_cache(cache: Dictionary) -> void:
	CardManager.save_cache_to_disk(cache)
	var f := FileAccess.open(MOBILE_DECK_CACHE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cache))

func setup(main_engine: Node) -> void:
	engine = main_engine

func show_deck_selector_ui() -> void:
	if engine and engine.hud_manager and engine.hud_manager.has_method("set_game_setup_complete"):
		engine.hud_manager.set_game_setup_complete(false)
	var canvas := CanvasLayer.new()
	canvas.name = "DeckSelectorUI"
	engine.add_child(canvas)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0.02, 0.03, 0.06, 0.74)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg_overlay)

	var vp_sz := engine.get_viewport().get_visible_rect().size
	var is_compact := vp_sz.x < 720.0

	var pill_input_style := StyleBoxFlat.new()
	pill_input_style.bg_color = Color(0.05, 0.06, 0.09, 0.96); pill_input_style.border_color = Color(0.32, 0.42, 0.56, 0.9); pill_input_style.set_border_width_all(1)
	pill_input_style.corner_radius_top_left = 12; pill_input_style.corner_radius_top_right = 12; pill_input_style.corner_radius_bottom_left = 12; pill_input_style.corner_radius_bottom_right = 12
	pill_input_style.content_margin_left = 14; pill_input_style.content_margin_right = 14

	var pill_btn_style := StyleBoxFlat.new()
	pill_btn_style.bg_color = Color(0.13, 0.17, 0.26, 0.96); pill_btn_style.border_color = Color(0.45, 0.58, 0.78, 0.85); pill_btn_style.set_border_width_all(1)
	pill_btn_style.corner_radius_top_left = 12; pill_btn_style.corner_radius_top_right = 12; pill_btn_style.corner_radius_bottom_left = 12; pill_btn_style.corner_radius_bottom_right = 12
	pill_btn_style.content_margin_left = 14; pill_btn_style.content_margin_right = 14

	var hover_btn_style := pill_btn_style.duplicate()
	hover_btn_style.bg_color = Color(0.20, 0.26, 0.38, 1.0); hover_btn_style.border_color = Color(0.95, 0.80, 0.42, 1.0)

	var active_tab_style := pill_btn_style.duplicate()
	active_tab_style.bg_color = Color(0.22, 0.30, 0.46, 1.0); active_tab_style.border_color = Color(0.95, 0.80, 0.40, 1.0)
	active_tab_style.set_border_width_all(2)

	var del_style := pill_btn_style.duplicate()
	del_style.bg_color = Color(0.38, 0.13, 0.14, 0.96); del_style.border_color = Color(0.88, 0.35, 0.35, 0.95)

	var start_btn_style := pill_btn_style.duplicate()
	start_btn_style.bg_color = Color(0.14, 0.38, 0.22, 0.98); start_btn_style.border_color = Color(0.42, 0.85, 0.52, 1.0)
	start_btn_style.set_border_width_all(2)

	var hero_btn_style := pill_btn_style.duplicate()
	hero_btn_style.bg_color = Color(0.16, 0.34, 0.24, 0.98); hero_btn_style.border_color = Color(0.95, 0.80, 0.40, 1.0)
	hero_btn_style.set_border_width_all(2)

	# ==========================================================
	# STAGE 1: CINEMATIC SPLASH SCREEN
	# ==========================================================
	var splash_center := CenterContainer.new()
	splash_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(splash_center)

	var splash_card := PanelContainer.new()
	splash_card.custom_minimum_size = Vector2(minf(540.0, vp_sz.x - 28.0), 0)
	var splash_style := StyleBoxFlat.new()
	splash_style.bg_color = Color(0.06, 0.07, 0.11, 0.92)
	splash_style.border_color = Color(0.90, 0.75, 0.38, 0.95)
	splash_style.set_border_width_all(2)
	splash_style.corner_radius_top_left = 20; splash_style.corner_radius_top_right = 20
	splash_style.corner_radius_bottom_left = 20; splash_style.corner_radius_bottom_right = 20
	splash_style.content_margin_left = 34; splash_style.content_margin_right = 34
	splash_style.content_margin_top = 30; splash_style.content_margin_bottom = 26
	splash_card.add_theme_stylebox_override("panel", splash_style)
	splash_center.add_child(splash_card)

	var splash_vbox := VBoxContainer.new()
	splash_vbox.add_theme_constant_override("separation", 14)
	splash_card.add_child(splash_vbox)

	# 5-Mana Pip Crest
	var pip_row := HBoxContainer.new()
	pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pip_row.add_theme_constant_override("separation", 12)
	splash_vbox.add_child(pip_row)
	var pip_defs := [
		["W", Color(0.98, 0.95, 0.78)],
		["U", Color(0.32, 0.68, 0.98)],
		["B", Color(0.62, 0.44, 0.78)],
		["R", Color(0.95, 0.36, 0.28)],
		["G", Color(0.32, 0.80, 0.44)]
	]
	for pd in pip_defs:
		var pip_p := PanelContainer.new()
		pip_p.custom_minimum_size = Vector2(30, 30)
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(pd[1].r * 0.28, pd[1].g * 0.28, pd[1].b * 0.28, 0.95)
		ps.border_color = pd[1]; ps.set_border_width_all(2)
		ps.corner_radius_top_left = 15; ps.corner_radius_top_right = 15; ps.corner_radius_bottom_left = 15; ps.corner_radius_bottom_right = 15
		pip_p.add_theme_stylebox_override("panel", ps)
		var pl := Label.new()
		pl.text = pd[0]
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.add_theme_font_size_override("font_size", 14)
		pl.add_theme_color_override("font_color", pd[1])
		pip_p.add_child(pl)
		pip_row.add_child(pip_p)

	var hero_title := Label.new()
	hero_title.text = "COMMANDER AT HOME"
	hero_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_title.add_theme_font_size_override("font_size", 34 if is_compact else 40)
	hero_title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.50, 1.0))
	splash_vbox.add_child(hero_title)

	var hero_sub := Label.new()
	hero_sub.text = "FOUR-PLAYER 3D TABLETOP SIMULATOR"
	hero_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_sub.add_theme_font_size_override("font_size", 13)
	hero_sub.add_theme_color_override("font_color", Color(0.68, 0.76, 0.88, 0.95))
	splash_vbox.add_child(hero_sub)

	splash_vbox.add_child(HSeparator.new())

	var splash_play_btn := Button.new()
	splash_play_btn.text = "PLAY COMMANDER"
	splash_play_btn.custom_minimum_size = Vector2(0, 52)
	splash_play_btn.add_theme_font_size_override("font_size", 18)
	splash_play_btn.add_theme_stylebox_override("normal", hero_btn_style)
	splash_play_btn.add_theme_stylebox_override("hover", hover_btn_style)
	splash_vbox.add_child(splash_play_btn)

	var has_save: bool = "SAVE_GAME_PATH" in engine and FileAccess.file_exists(engine.SAVE_GAME_PATH)
	var splash_resume_btn: Button = null
	if has_save:
		splash_resume_btn = Button.new()
		splash_resume_btn.text = "RESUME SAVED GAME"
		splash_resume_btn.custom_minimum_size = Vector2(0, 48)
		splash_resume_btn.add_theme_font_size_override("font_size", 16)
		splash_resume_btn.add_theme_stylebox_override("normal", active_tab_style)
		splash_resume_btn.add_theme_stylebox_override("hover", hover_btn_style)
		splash_resume_btn.pressed.connect(func():
			if engine.has_method("load_game_from_disk") and engine.load_game_from_disk():
				canvas.queue_free()
				if engine.has_method("refresh_playable_card_glows"):
					engine.refresh_playable_card_glows()
				if engine.has_method("resume_gameplay_after_decision"):
					engine.resume_gameplay_after_decision()
			elif engine.hud_manager and engine.hud_manager.has_method("show_toast"):
				engine.hud_manager.show_toast("Could not load saved game.", Color(1.0, 0.4, 0.35, 1.0))
		)
		splash_vbox.add_child(splash_resume_btn)

	var splash_lib_btn := Button.new()
	splash_lib_btn.text = "DECK LIBRARY & IMPORTS"
	splash_lib_btn.custom_minimum_size = Vector2(0, 46)
	splash_lib_btn.add_theme_stylebox_override("normal", pill_btn_style)
	splash_lib_btn.add_theme_stylebox_override("hover", hover_btn_style)
	splash_vbox.add_child(splash_lib_btn)

	var splash_mp_btn := Button.new()
	splash_mp_btn.text = "MULTIPLAYER LOBBY"
	splash_mp_btn.custom_minimum_size = Vector2(0, 46)
	splash_mp_btn.add_theme_stylebox_override("normal", pill_btn_style)
	splash_mp_btn.add_theme_stylebox_override("hover", hover_btn_style)
	splash_vbox.add_child(splash_mp_btn)

	var splash_set_btn := Button.new()
	splash_set_btn.text = "TABLE, AUDIO & FONT"
	splash_set_btn.custom_minimum_size = Vector2(0, 46)
	splash_set_btn.add_theme_stylebox_override("normal", pill_btn_style)
	splash_set_btn.add_theme_stylebox_override("hover", hover_btn_style)
	splash_vbox.add_child(splash_set_btn)

	var splash_hint := Label.new()
	splash_hint.text = ("D-Pad / Stick: Navigate  •  A: Select  •  LB/RB: Tabs" if not Input.get_connected_joypads().is_empty() else "Touch, Mouse, Keyboard (Tab/Arrows) & Controller Ready")
	splash_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	splash_hint.add_theme_font_size_override("font_size", 12)
	splash_hint.add_theme_color_override("font_color", Color(0.60, 0.66, 0.76, 0.9))
	splash_vbox.add_child(splash_hint)

	splash_card.modulate.a = 0.0
	var sp_tw := engine.create_tween()
	sp_tw.tween_property(splash_card, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# ==========================================================
	# STAGE 2: REDESIGNED MATCH SETUP CONSOLE
	# ==========================================================
	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_container.visible = false
	canvas.add_child(center_container)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(860.0, vp_sz.x - 24.0), minf(580.0, vp_sz.y - 24.0))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.07, 0.11, 0.95); panel_style.border_color = Color(0.90, 0.75, 0.38, 0.92); panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 18; panel_style.corner_radius_top_right = 18; panel_style.corner_radius_bottom_left = 18; panel_style.corner_radius_bottom_right = 18
	panel_style.content_margin_left = 26; panel_style.content_margin_right = 26; panel_style.content_margin_top = 18; panel_style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	center_container.add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(root_vbox)

	var setup_hdr_hbox := HBoxContainer.new()
	setup_hdr_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(setup_hdr_hbox)

	var back_title_btn := Button.new()
	back_title_btn.text = "← Title"
	back_title_btn.custom_minimum_size = Vector2(96, 38)
	back_title_btn.add_theme_stylebox_override("normal", pill_btn_style)
	back_title_btn.add_theme_stylebox_override("hover", hover_btn_style)
	setup_hdr_hbox.add_child(back_title_btn)

	var title := Label.new()
	title.text = "MATCH SETUP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.50, 1.0))
	setup_hdr_hbox.add_child(title)

	var font_toggle_btn := Button.new()
	var _font_lbl := func() -> String:
		var m_str: String = str(engine.ui_font_mode) if "ui_font_mode" in engine else "mustica"
		return "Font: MusticaPro" if m_str == "mustica" else "Font: Beleren"
	font_toggle_btn.text = _font_lbl.call()
	font_toggle_btn.custom_minimum_size = Vector2(150, 38)
	font_toggle_btn.add_theme_stylebox_override("normal", pill_btn_style)
	font_toggle_btn.add_theme_stylebox_override("hover", hover_btn_style)
	font_toggle_btn.pressed.connect(func():
		if "ui_font_mode" in engine:
			engine.ui_font_mode = "beleren" if engine.ui_font_mode == "mustica" else "mustica"
			font_toggle_btn.text = _font_lbl.call()
			engine.hud_manager.apply_custom_font(canvas)
	)
	setup_hdr_hbox.add_child(font_toggle_btn)

	# --- Top Step / Tab Navigation Bar ---
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 10)
	root_vbox.add_child(tab_bar)

	var tab_library_btn := Button.new()
	tab_library_btn.text = "1. Deck Library"
	tab_library_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_library_btn.custom_minimum_size = Vector2(0, 42)
	tab_bar.add_child(tab_library_btn)

	var tab_table_btn := Button.new()
	tab_table_btn.text = "2. Table & Audio"
	tab_table_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_table_btn.custom_minimum_size = Vector2(0, 42)
	tab_bar.add_child(tab_table_btn)

	var tab_players_btn := Button.new()
	tab_players_btn.text = "3. Seats & Launch"
	tab_players_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_players_btn.custom_minimum_size = Vector2(0, 42)
	tab_bar.add_child(tab_players_btn)

	root_vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var pages_holder := VBoxContainer.new()
	pages_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages_holder)

	# ==========================================================
	# PAGE 1: DECK LIBRARY & MAINTENANCE
	# ==========================================================
	var page_library := VBoxContainer.new()
	page_library.add_theme_constant_override("separation", 14)
	pages_holder.add_child(page_library)

	var lib_hdr := Label.new()
	lib_hdr.text = "Import decks from Moxfield or Archidekt and manage your local library."
	lib_hdr.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88, 1))
	page_library.add_child(lib_hdr)

	var import_hbox := HBoxContainer.new()
	import_hbox.add_theme_constant_override("separation", 10)
	page_library.add_child(import_hbox)

	var url_input := LineEdit.new()
	url_input.placeholder_text = "Paste Moxfield or Archidekt URL..."
	url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_input.custom_minimum_size = Vector2(0, 40)
	url_input.add_theme_stylebox_override("normal", pill_input_style)
	import_hbox.add_child(url_input)

	var import_btn := Button.new()
	import_btn.text = "IMPORT"
	import_btn.custom_minimum_size = Vector2(110, 40)
	import_btn.add_theme_stylebox_override("normal", pill_btn_style)
	import_btn.add_theme_stylebox_override("hover", pill_btn_style)
	import_hbox.add_child(import_btn)

	var manage_hbox := HBoxContainer.new()
	manage_hbox.add_theme_constant_override("separation", 10)
	page_library.add_child(manage_hbox)

	var manage_lbl := Label.new()
	manage_lbl.text = "Saved Decks:"
	manage_lbl.custom_minimum_size = Vector2(110, 0)
	manage_hbox.add_child(manage_lbl)

	var manage_opt := OptionButton.new()
	manage_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manage_opt.custom_minimum_size = Vector2(0, 38)
	manage_opt.add_theme_stylebox_override("normal", pill_input_style)
	manage_hbox.add_child(manage_opt)

	var delete_btn := Button.new()
	delete_btn.text = "DELETE"
	delete_btn.custom_minimum_size = Vector2(110, 38)
	delete_btn.add_theme_stylebox_override("normal", del_style)
	delete_btn.add_theme_stylebox_override("hover", del_style)
	manage_hbox.add_child(delete_btn)

	var deck_info_lbl := Label.new()
	deck_info_lbl.text = ""
	deck_info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deck_info_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 1))
	page_library.add_child(deck_info_lbl)

	var lib_next_btn := Button.new()
	lib_next_btn.text = "Continue to Table Settings →"
	lib_next_btn.custom_minimum_size = Vector2(0, 42)
	lib_next_btn.add_theme_stylebox_override("normal", pill_btn_style)
	lib_next_btn.add_theme_stylebox_override("hover", pill_btn_style)
	page_library.add_child(lib_next_btn)

	# ==========================================================
	# PAGE 2: TABLE SETTINGS
	# ==========================================================
	var page_table := VBoxContainer.new()
	page_table.add_theme_constant_override("separation", 14)
	pages_holder.add_child(page_table)

	var tbl_grid := GridContainer.new()
	tbl_grid.columns = 2
	tbl_grid.add_theme_constant_override("h_separation", 14)
	tbl_grid.add_theme_constant_override("v_separation", 12)
	page_table.add_child(tbl_grid)

	var pm_btn := Button.new()
	var _pm_lbl := func() -> String:
		var t_id: String = str(engine.current_playmat_theme) if "current_playmat_theme" in engine else "classic_felt"
		return "Surface: " + t_id.replace("_", " ").capitalize()
	pm_btn.text = _pm_lbl.call()
	pm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pm_btn.custom_minimum_size = Vector2(0, 40)
	pm_btn.add_theme_stylebox_override("normal", pill_btn_style)
	pm_btn.pressed.connect(func():
		var themes: Array = Array(engine.TABLE_SURFACES)
		var cur_idx: int = themes.find(str(engine.current_playmat_theme))
		engine.apply_playmat_theme(themes[(cur_idx + 1) % themes.size()])
		pm_btn.text = _pm_lbl.call()
	)
	tbl_grid.add_child(pm_btn)

	var diff_btn := Button.new()
	var _diff_lbl := func() -> String:
		var d: int = int(engine.ai_controller.difficulty) if engine.ai_controller else 1
		return "AI Difficulty: Casual" if d == 0 else ("AI Difficulty: cEDH" if d == 2 else "AI Difficulty: Tuned")
	diff_btn.text = _diff_lbl.call()
	diff_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_btn.custom_minimum_size = Vector2(0, 40)
	diff_btn.add_theme_stylebox_override("normal", pill_btn_style)
	diff_btn.pressed.connect(func():
		if engine.ai_controller:
			engine.ai_controller.difficulty = (int(engine.ai_controller.difficulty) + 1) % 3
			diff_btn.text = _diff_lbl.call()
	)
	tbl_grid.add_child(diff_btn)

	var mv_box := HBoxContainer.new()
	mv_box.add_theme_constant_override("separation", 8)
	var mv_lbl := Label.new(); mv_lbl.text = "Master Vol"; mv_lbl.custom_minimum_size = Vector2(85, 0)
	mv_box.add_child(mv_lbl)
	var mv_sl := HSlider.new(); mv_sl.min_value = 0.0; mv_sl.max_value = 1.0; mv_sl.step = 0.05
	mv_sl.value = float(engine.sound_manager.master_volume) if engine.sound_manager else 0.85
	mv_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv_sl.value_changed.connect(func(v: float):
		if engine.sound_manager: engine.sound_manager.set_master_volume(v)
	)
	mv_box.add_child(mv_sl)
	tbl_grid.add_child(mv_box)

	var sv_box := HBoxContainer.new()
	sv_box.add_theme_constant_override("separation", 8)
	var sv_lbl := Label.new(); sv_lbl.text = "SFX Vol"; sv_lbl.custom_minimum_size = Vector2(85, 0)
	sv_box.add_child(sv_lbl)
	var sv_sl := HSlider.new(); sv_sl.min_value = 0.0; sv_sl.max_value = 1.0; sv_sl.step = 0.05
	sv_sl.value = float(engine.sound_manager.sfx_volume) if engine.sound_manager else 0.85
	sv_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv_sl.value_changed.connect(func(v: float):
		if engine.sound_manager: engine.sound_manager.set_sfx_volume(v)
	)
	sv_box.add_child(sv_sl)
	tbl_grid.add_child(sv_box)

	var mp_lobby_btn := Button.new()
	mp_lobby_btn.text = "🌐 P2P MULTIPLAYER LOBBY (HOST / JOIN)"
	mp_lobby_btn.custom_minimum_size = Vector2(0, 42)
	mp_lobby_btn.add_theme_stylebox_override("normal", pill_btn_style)
	mp_lobby_btn.add_theme_stylebox_override("hover", pill_btn_style)
	mp_lobby_btn.pressed.connect(func():
		if engine.hud_manager and engine.hud_manager.has_method("open_multiplayer_lobby"):
			engine.hud_manager.open_multiplayer_lobby()
	)
	page_table.add_child(mp_lobby_btn)

	var tbl_next_btn := Button.new()
	tbl_next_btn.text = "Continue to Player Setup →"
	tbl_next_btn.custom_minimum_size = Vector2(0, 42)
	tbl_next_btn.add_theme_stylebox_override("normal", pill_btn_style)
	tbl_next_btn.add_theme_stylebox_override("hover", pill_btn_style)
	page_table.add_child(tbl_next_btn)

	# ==========================================================
	# PAGE 3: PLAYER SETUP & LAUNCH
	# ==========================================================
	var page_players := VBoxContainer.new()
	page_players.add_theme_constant_override("separation", 12)
	pages_holder.add_child(page_players)

	var player_dropdowns := {}
	var player_active_flags := {1: true, 2: true, 3: true, 4: true}
	var _player_names := {1: "Player 1 (You)", 2: "Player 2 (Left)", 3: "Player 3 (Across)", 4: "Player 4 (Right)"}

	var update_deck_summary := func():
		if manage_opt.get_item_count() == 0 or manage_opt.selected < 0:
			deck_info_lbl.text = "No decks cached yet. Paste a Moxfield or Archidekt URL above to import."
			return
		var key_sel = manage_opt.get_item_metadata(manage_opt.selected)
		var cache := _load_deck_cache()
		if key_sel != null and cache.has(key_sel):
			var d: Dictionary = cache[key_sel]
			var cmd_s: String = str(d.get("commander", "Unknown"))
			var cnt: int = (d.get("cards", []) as Array).size()
			deck_info_lbl.text = "Commander: %s   |   Cards in cache: %d" % [cmd_s, cnt]
		else:
			deck_info_lbl.text = ""

	var populate_all_dropdowns = func():
		var cache := _load_deck_cache()
		var all_opts: Array = [manage_opt]
		for pid in player_dropdowns.keys():
			all_opts.append(player_dropdowns[pid])
		var shuffled_indices: Array[int] = []
		if not cache.is_empty():
			for k_i in range(cache.size()): shuffled_indices.append(k_i)
			shuffled_indices.shuffle()
		var player_slot := 0
		for opt in all_opts:
			var current_sel = opt.get_selected_metadata() if opt.get_item_count() > 0 and opt.selected >= 0 else null
			opt.clear()
			if cache.is_empty():
				opt.add_item("No cached decks found. Import in Tab 1.")
				opt.set_item_disabled(0, true)
			else:
				for key in cache.keys():
					var deck_name: String = cache[key].get("deckName", str(key))
					opt.add_item(deck_name)
					opt.set_item_metadata(opt.get_item_count() - 1, key)
				var restored := false
				if current_sel != null:
					for idx in range(opt.get_item_count()):
						if opt.get_item_metadata(idx) == current_sel:
							opt.select(idx)
							restored = true
							break
				if not restored and opt != manage_opt and opt.get_item_count() > 0:
					var rand_idx: int = shuffled_indices[player_slot % shuffled_indices.size()] if not shuffled_indices.is_empty() else (randi() % opt.get_item_count())
					opt.select(rand_idx)
					player_slot += 1
		delete_btn.disabled = cache.is_empty()
		update_deck_summary.call()

	manage_opt.item_selected.connect(func(_idx: int): update_deck_summary.call())
	delete_btn.pressed.connect(func():
		if manage_opt.get_item_count() == 0 or manage_opt.selected < 0: return
		var key_to_remove = manage_opt.get_item_metadata(manage_opt.selected)
		if key_to_remove == null: return
		var cache := _load_deck_cache()
		if cache.has(key_to_remove):
			cache.erase(key_to_remove)
			_save_deck_cache(cache)
			populate_all_dropdowns.call()
	)

	var _make_sleeve_thumb := func(path: String) -> Texture2D:
		if not path.is_empty() and FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img and not img.is_empty():
				img.resize(32, 42, Image.INTERPOLATE_LANCZOS)
				return ImageTexture.create_from_image(img)
		var def_tex: Texture2D = load("res://card_back.jpg") as Texture2D
		if def_tex != null:
			var def_img: Image = def_tex.get_image()
			if def_img and not def_img.is_empty():
				var dup_img: Image = def_img.duplicate() as Image
				dup_img.resize(32, 42, Image.INTERPOLATE_LANCZOS)
				return ImageTexture.create_from_image(dup_img)
		var fb := Image.create(32, 42, false, Image.FORMAT_RGBA8)
		fb.fill(Color(0.10, 0.17, 0.34, 1.0))
		return ImageTexture.create_from_image(fb)

	var _make_playmat_thumb := func(path: String) -> Texture2D:
		if not path.is_empty() and FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img and not img.is_empty():
				img.resize(58, 34, Image.INTERPOLATE_LANCZOS)
				return ImageTexture.create_from_image(img)
		var def_tex: Texture2D = engine._get_default_player_playmat_texture() if engine.has_method("_get_default_player_playmat_texture") else null
		if def_tex != null:
			var def_img := def_tex.get_image()
			if def_img and not def_img.is_empty():
				var dup_img := def_img.duplicate()
				dup_img.resize(58, 34, Image.INTERPOLATE_LANCZOS)
				return ImageTexture.create_from_image(dup_img)
		var fb := Image.create(58, 34, false, Image.FORMAT_RGBA8)
		fb.fill(Color(0.11, 0.13, 0.17, 1.0))
		return ImageTexture.create_from_image(fb)

	var hdr_hbox := HBoxContainer.new()
	hdr_hbox.add_theme_constant_override("separation", 10)
	page_players.add_child(hdr_hbox)

	var hdr_p := Label.new()
	hdr_p.text = ""
	hdr_p.custom_minimum_size = Vector2(36, 0)
	hdr_hbox.add_child(hdr_p)

	var hdr_on := Label.new()
	hdr_on.text = ""
	hdr_on.custom_minimum_size = Vector2(52, 0)
	hdr_hbox.add_child(hdr_on)

	var hdr_deck := Label.new()
	hdr_deck.text = "Deck"
	hdr_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_deck.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr_deck.add_theme_font_size_override("font_size", 13)
	hdr_deck.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35, 1.0))
	hdr_hbox.add_child(hdr_deck)

	var hdr_slv := Label.new()
	hdr_slv.text = "Sleeves"
	hdr_slv.custom_minimum_size = Vector2(84, 0)
	hdr_slv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr_slv.add_theme_font_size_override("font_size", 13)
	hdr_slv.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35, 1.0))
	hdr_hbox.add_child(hdr_slv)

	var hdr_mat := Label.new()
	hdr_mat.text = "Playmat"
	hdr_mat.custom_minimum_size = Vector2(112, 0)
	hdr_mat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr_mat.add_theme_font_size_override("font_size", 13)
	hdr_mat.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35, 1.0))
	hdr_hbox.add_child(hdr_mat)

	for i in range(1, 5):
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		page_players.add_child(hbox)

		var lbl := Label.new()
		lbl.text = "P%d" % i
		lbl.custom_minimum_size = Vector2(36, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1.0) if i == 1 else Color(0.90, 0.92, 0.96, 1.0))
		hbox.add_child(lbl)

		var active_toggle := Button.new()
		active_toggle.text = "ON"
		active_toggle.custom_minimum_size = Vector2(52, 46)
		active_toggle.disabled = (i == 1)
		hbox.add_child(active_toggle)

		var prev_btn := Button.new()
		prev_btn.text = "◀"
		prev_btn.custom_minimum_size = Vector2(36, 46)
		hbox.add_child(prev_btn)

		var option_btn := OptionButton.new()
		option_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_btn.custom_minimum_size = Vector2(220, 46)
		option_btn.add_theme_stylebox_override("normal", pill_input_style)
		hbox.add_child(option_btn)
		player_dropdowns[i] = option_btn

		var next_btn := Button.new()
		next_btn.text = "▶"
		next_btn.custom_minimum_size = Vector2(36, 46)
		hbox.add_child(next_btn)

		prev_btn.pressed.connect(func():
			var cnt := option_btn.get_item_count()
			if cnt > 0: option_btn.select((option_btn.selected - 1 + cnt) % cnt)
		)
		next_btn.pressed.connect(func():
			var cnt := option_btn.get_item_count()
			if cnt > 0: option_btn.select((option_btn.selected + 1) % cnt)
		)

		var thumb_style := StyleBoxFlat.new()
		thumb_style.bg_color = Color(0.04, 0.06, 0.11, 0.92)
		thumb_style.border_color = Color(0.86, 0.72, 0.34, 0.92)
		thumb_style.set_border_width_all(2)
		thumb_style.set_corner_radius_all(6)
		thumb_style.set_content_margin_all(2)

		var thumb_hover := thumb_style.duplicate() as StyleBoxFlat
		thumb_hover.border_color = Color(0.98, 0.85, 0.45, 1.0)

		var sleeve_btn := Button.new()
		var cur_slv: String = str(engine.player_sleeves.get(i, "")) if "player_sleeves" in engine else ""
		sleeve_btn.text = ""
		sleeve_btn.icon = _make_sleeve_thumb.call(cur_slv)
		sleeve_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sleeve_btn.expand_icon = true
		sleeve_btn.tooltip_text = ("Sleeve: " + cur_slv.get_file()) if not cur_slv.is_empty() else "Select Custom Sleeve"
		sleeve_btn.custom_minimum_size = Vector2(40, 50)
		sleeve_btn.add_theme_stylebox_override("normal", thumb_style)
		sleeve_btn.add_theme_stylebox_override("hover", thumb_hover)
		sleeve_btn.add_theme_stylebox_override("pressed", thumb_hover)
		hbox.add_child(sleeve_btn)

		var sleeve_rst := Button.new()
		sleeve_rst.text = "✕"
		sleeve_rst.tooltip_text = "Reset sleeve to default"
		sleeve_rst.custom_minimum_size = Vector2(34, 46)
		sleeve_rst.add_theme_stylebox_override("normal", del_style)
		sleeve_rst.add_theme_stylebox_override("hover", del_style)
		hbox.add_child(sleeve_rst)

		var pid_cap := i
		sleeve_btn.pressed.connect(func():
			if OS.get_name() == "Android":
				OS.request_permissions()
			var fd := FileDialog.new()
			fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			fd.access = FileDialog.ACCESS_FILESYSTEM
			fd.use_native_dialog = true
			fd.title = "Select Custom Sleeve Image for Player %d" % pid_cap
			fd.add_filter("*.png, *.jpg, *.jpeg, *.webp", "Image Files")
			canvas.add_child(fd)
			fd.file_selected.connect(func(path: String):
				if engine.has_method("set_player_sleeve"):
					var safe_p: String = engine.cache_custom_image_locally(path, "sleeve") if engine.has_method("cache_custom_image_locally") else path
					engine.set_player_sleeve(pid_cap, safe_p)
				sleeve_btn.icon = _make_sleeve_thumb.call(path)
				sleeve_btn.tooltip_text = "Sleeve: " + path.get_file()
				fd.queue_free()
			)
			fd.canceled.connect(func(): fd.queue_free())
			fd.popup_centered(Vector2i(700, 500))
		)
		sleeve_rst.pressed.connect(func():
			if engine.has_method("set_player_sleeve"):
				engine.set_player_sleeve(pid_cap, "")
			sleeve_btn.icon = _make_sleeve_thumb.call("")
			sleeve_btn.tooltip_text = "Select Custom Sleeve"
		)

		var mat_btn := Button.new()
		var cur_pm: String = str(engine.player_playmats.get(i, "")) if "player_playmats" in engine else ""
		mat_btn.text = ""
		mat_btn.icon = _make_playmat_thumb.call(cur_pm)
		mat_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mat_btn.expand_icon = true
		mat_btn.tooltip_text = ("Playmat: " + cur_pm.get_file()) if not cur_pm.is_empty() else "Select Custom Playmat"
		mat_btn.custom_minimum_size = Vector2(68, 44)
		mat_btn.add_theme_stylebox_override("normal", thumb_style)
		mat_btn.add_theme_stylebox_override("hover", thumb_hover)
		mat_btn.add_theme_stylebox_override("pressed", thumb_hover)
		hbox.add_child(mat_btn)

		var mat_rst := Button.new()
		mat_rst.text = "✕"
		mat_rst.tooltip_text = "Reset player playmat to default"
		mat_rst.custom_minimum_size = Vector2(34, 46)
		mat_rst.add_theme_stylebox_override("normal", del_style)
		mat_rst.add_theme_stylebox_override("hover", del_style)
		hbox.add_child(mat_rst)

		mat_btn.pressed.connect(func():
			if OS.get_name() == "Android":
				OS.request_permissions()
			var fd := FileDialog.new()
			fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			fd.access = FileDialog.ACCESS_FILESYSTEM
			fd.use_native_dialog = true
			fd.title = "Select Custom Playmat Image for Player %d" % pid_cap
			fd.add_filter("*.png, *.jpg, *.jpeg, *.webp", "Image Files")
			canvas.add_child(fd)
			fd.file_selected.connect(func(path: String):
				if engine.has_method("set_player_playmat"):
					var safe_p: String = engine.cache_custom_image_locally(path, "playmat") if engine.has_method("cache_custom_image_locally") else path
					engine.set_player_playmat(pid_cap, safe_p)
				mat_btn.icon = _make_playmat_thumb.call(path)
				mat_btn.tooltip_text = "Playmat: " + path.get_file()
				fd.queue_free()
			)
			fd.canceled.connect(func(): fd.queue_free())
			fd.popup_centered(Vector2i(700, 500))
		)
		mat_rst.pressed.connect(func():
			if engine.has_method("set_player_playmat"):
				engine.set_player_playmat(pid_cap, "")
			mat_btn.icon = _make_playmat_thumb.call("")
			mat_btn.tooltip_text = "Select Custom Playmat"
		)
		active_toggle.pressed.connect(func():
			var next_on := not bool(player_active_flags.get(pid_cap, true))
			player_active_flags[pid_cap] = next_on
			active_toggle.text = "ON" if next_on else "OFF"
			prev_btn.disabled = not next_on
			option_btn.disabled = not next_on
			next_btn.disabled = not next_on
			sleeve_btn.disabled = not next_on
			sleeve_rst.disabled = not next_on
			mat_btn.disabled = not next_on
			mat_rst.disabled = not next_on
			lbl.modulate = Color(1, 1, 1, 1) if next_on else Color(0.45, 0.45, 0.5, 0.65)
		)

	populate_all_dropdowns.call()

	import_btn.pressed.connect(func():
		var url := url_input.text.strip_edges()
		if not url.is_empty():
			import_deck_from_url_multi(url, url_input, import_btn, populate_all_dropdowns)
	)

	var load_btn := Button.new()
	load_btn.text = "LOAD ALL DECKS & START GAME"
	load_btn.custom_minimum_size = Vector2(0, 48)
	load_btn.add_theme_stylebox_override("normal", start_btn_style)
	load_btn.add_theme_stylebox_override("hover", start_btn_style)
	page_players.add_child(load_btn)

	load_btn.pressed.connect(func():
		var selections := {}
		var inactive_pids: Array[int] = []
		for i in range(1, 5):
			if not bool(player_active_flags.get(i, true)):
				inactive_pids.append(i)
				continue
			var opt: OptionButton = player_dropdowns[i]
			selections[i] = opt.get_item_metadata(opt.selected) if opt.get_item_count() > 0 and opt.selected >= 0 else opt.get_item_metadata(0)
		if engine.has_method("set_inactive_players"):
			engine.set_inactive_players(inactive_pids)
		canvas.queue_free()
		load_and_spawn_all_decks(selections)
	)

	# --- Tab Switching Logic (Default to Player Setup if decks already cached, else Deck Library) ---
	var _switch_tab := func(tab_idx: int):
		page_library.visible = (tab_idx == 0)
		page_table.visible = (tab_idx == 1)
		page_players.visible = (tab_idx == 2)
		tab_library_btn.add_theme_stylebox_override("normal", active_tab_style if tab_idx == 0 else pill_btn_style)
		tab_table_btn.add_theme_stylebox_override("normal", active_tab_style if tab_idx == 1 else pill_btn_style)
		tab_players_btn.add_theme_stylebox_override("normal", active_tab_style if tab_idx == 2 else pill_btn_style)

	tab_library_btn.pressed.connect(func(): _switch_tab.call(0))
	tab_table_btn.pressed.connect(func(): _switch_tab.call(1))
	tab_players_btn.pressed.connect(func(): _switch_tab.call(2))
	lib_next_btn.pressed.connect(func(): _switch_tab.call(1))
	tbl_next_btn.pressed.connect(func(): _switch_tab.call(2))

	var _current_tab := [0]
	var _open_setup_tab := func(t_idx: int):
		_current_tab[0] = t_idx
		splash_center.visible = false
		center_container.visible = true
		_switch_tab.call(t_idx)
		if t_idx == 0: url_input.grab_focus()
		elif t_idx == 1: pm_btn.grab_focus()
		else: load_btn.grab_focus()

	var _show_splash := func():
		center_container.visible = false
		splash_center.visible = true
		splash_play_btn.grab_focus()

	splash_play_btn.pressed.connect(func():
		_open_setup_tab.call(0 if _load_deck_cache().is_empty() else 2)
	)
	splash_lib_btn.pressed.connect(func(): _open_setup_tab.call(0))
	splash_set_btn.pressed.connect(func(): _open_setup_tab.call(1))
	splash_mp_btn.pressed.connect(func():
		if engine.hud_manager and engine.hud_manager.has_method("open_multiplayer_lobby"):
			engine.hud_manager.open_multiplayer_lobby()
	)
	back_title_btn.pressed.connect(_show_splash)

	# Controller LB/RB tab switching & B/Esc back-to-title
	var nav_node := Node.new()
	var nav_script := GDScript.new()
	nav_script.source_code = """extends Node
var on_prev_tab: Callable
var on_next_tab: Callable
var on_back: Callable
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER and on_prev_tab.is_valid():
			on_prev_tab.call(); get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER and on_next_tab.is_valid():
			on_next_tab.call(); get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_B and on_back.is_valid():
			on_back.call(); get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and on_back.is_valid():
		on_back.call(); get_viewport().set_input_as_handled()
"""
	nav_script.reload()
	nav_node.set_script(nav_script)
	nav_node.set("on_prev_tab", func():
		if center_container.visible: _open_setup_tab.call((int(_current_tab[0]) + 2) % 3)
	)
	nav_node.set("on_next_tab", func():
		if center_container.visible: _open_setup_tab.call((int(_current_tab[0]) + 1) % 3)
	)
	nav_node.set("on_back", func():
		if center_container.visible: _show_splash.call()
	)
	canvas.add_child(nav_node)

	engine.hud_manager.apply_custom_font(canvas)
	if splash_resume_btn != null:
		splash_resume_btn.grab_focus()
	else:
		splash_play_btn.grab_focus()

func import_deck_from_url_multi(url: String, line_edit: LineEdit, import_btn: Button, refresh_callback: Callable) -> void:
	var clean_url := url.strip_edges()
	import_btn.disabled = true
	import_btn.text = "FETCHING..."

	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = 15.0
	engine.add_child(http)
	var http_id := http.get_instance_id()
	var headers := [
		"User-Agent: MTGBrawlSim/1.0",
		"Accept: application/json"
	]

	if "archidekt.com/decks/" in clean_url:
		var parts := clean_url.split("archidekt.com/decks/")
		if parts.size() > 1:
			var deck_id := parts[1].split("#")[0].split("?")[0].split("/")[0].strip_edges()
			var api_url := "https://archidekt.com/api/decks/%s/" % deck_id
			http.request_completed.connect(func(res, code, _hdr, body):
				_on_archidekt_loaded_multi(res, code, body, deck_id, line_edit, import_btn, refresh_callback, http_id)
			)
			var err := http.request(api_url, headers)
			if err != OK:
				import_btn.text = "ERR %d" % err
				import_btn.disabled = false
				http.queue_free()
			return

	elif "moxfield.com/decks/" in clean_url:
		var parts := clean_url.split("moxfield.com/decks/")
		if parts.size() > 1:
			var deck_id := parts[1].split("#")[0].split("?")[0].split("/")[0].strip_edges()
			var mox_headers := headers.duplicate()
			var api_url := "https://api2.moxfield.com/v2/decks/all/%s" % deck_id
			http.request_completed.connect(func(res, code, _hdr, body):
				if code == 403:
					# Retry v3 endpoint once in case v2 is rate-limited/blocked
					var req2 := HTTPRequest.new()
					req2.use_threads = true
					req2.timeout = 15.0
					engine.add_child(req2)
					var req2_id := req2.get_instance_id()
					var old_req := instance_from_id(http_id)
					if old_req and is_instance_valid(old_req): old_req.queue_free()
					req2.request_completed.connect(func(r2, c2, _h2, b2):
						_on_moxfield_loaded_multi(r2, c2, b2, deck_id, line_edit, import_btn, refresh_callback, req2_id)
					)
					req2.request("https://api2.moxfield.com/v3/decks/all/%s" % deck_id, mox_headers)
					return
				_on_moxfield_loaded_multi(res, code, body, deck_id, line_edit, import_btn, refresh_callback, http_id)
			)
			var err := http.request(api_url, mox_headers)
			if err != OK:
				import_btn.text = "ERR %d" % err
				import_btn.disabled = false
				http.queue_free()
			return

	elif "\n" in clean_url or clean_url.begins_with("1 ") or clean_url.begins_with("1x "):
		http.queue_free()
		_import_plain_text_decklist(clean_url, line_edit, import_btn, refresh_callback)
		return

	line_edit.text = "Invalid URL or Decklist."
	import_btn.disabled = false
	import_btn.text = "IMPORT"
	http.queue_free()

func _on_archidekt_loaded_multi(res: int, code: int, body: PackedByteArray, deck_id: String, line_edit: LineEdit, import_btn: Button, refresh_callback: Callable, http_id: int) -> void:
	var req := instance_from_id(http_id)
	if req and is_instance_valid(req): req.queue_free()
	if res != HTTPRequest.RESULT_SUCCESS or code != 200:
		if is_instance_valid(import_btn):
			import_btn.text = "NO NET/PERM" if code == 0 else ("ERR %d" % code)
			import_btn.disabled = false
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.get_data() is Dictionary:
		var data: Dictionary = json.get_data()
		var deck_name: String = data.get("name", "Archidekt Deck")
		var cards_array := []
		var commander := ""

		for item in data.get("cards", []):
			var qty: int = item.get("quantity", 1)
			var c_data: Dictionary = item.get("card", {})
			var oracle: Dictionary = c_data.get("oracleCard", {})
			var c_name: String = oracle.get("name", c_data.get("name", ""))
			if c_name.is_empty(): continue
			if "Commander" in item.get("categories", []):
				commander = c_name if commander.is_empty() else (commander + " | " + c_name)
			var entry := {"name": c_name, "quantity": qty}
			var s_id: String = str(c_data.get("uid", "")).strip_edges()
			var s_set: String = str(c_data.get("edition", {}).get("editioncode", "")).strip_edges().to_lower()
			var s_cn: String = str(c_data.get("collectorNumber", "")).strip_edges()
			if not s_id.is_empty(): entry["scryfall_id"] = s_id
			if not s_set.is_empty(): entry["set"] = s_set
			if not s_cn.is_empty(): entry["collector_number"] = s_cn
			var mod_str: String = str(item.get("modifier", "")).strip_edges().to_lower()
			if "foil" in mod_str or "etched" in mod_str: entry["is_foil"] = true
			cards_array.append(entry)

		var cache_key := "archidekt_" + deck_id
		var cache := _load_deck_cache()
		cache[cache_key] = {"deckName": deck_name, "commander": commander, "cards": cards_array}
		_save_deck_cache(cache)

		if refresh_callback.is_valid(): refresh_callback.call()
		if is_instance_valid(line_edit): line_edit.text = ""

	else:
		if is_instance_valid(import_btn):
			import_btn.text = "BAD JSON"
			import_btn.disabled = false
		return

	if is_instance_valid(import_btn):
		import_btn.text = "IMPORT"
		import_btn.disabled = false

func _on_moxfield_loaded_multi(res: int, code: int, body: PackedByteArray, deck_id: String, line_edit: LineEdit, import_btn: Button, refresh_callback: Callable, http_id: int) -> void:
	var req := instance_from_id(http_id)
	if req and is_instance_valid(req): req.queue_free()
	if res != HTTPRequest.RESULT_SUCCESS or code != 200:
		if is_instance_valid(import_btn):
			import_btn.text = "NO NET/PERM" if code == 0 else ("ERR %d" % code)
			import_btn.disabled = false
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.get_data() is Dictionary:
		var data: Dictionary = json.get_data()
		var deck_name: String = data.get("name", "Moxfield Deck")
		var cards_array := []
		var commander := ""

		for c_name in data.get("commanders", {}).keys():
			commander = c_name if commander.is_empty() else (commander + " | " + c_name)
			var m_entry: Dictionary = data["commanders"][c_name]
			var m_card: Dictionary = m_entry.get("card", {})
			var entry := {"name": c_name, "quantity": m_entry.get("quantity", 1)}
			var s_id: String = str(m_card.get("scryfall_id", "")).strip_edges()
			var s_set: String = str(m_card.get("set", "")).strip_edges().to_lower()
			var s_cn: String = str(m_card.get("cn", "")).strip_edges()
			if not s_id.is_empty(): entry["scryfall_id"] = s_id
			if not s_set.is_empty(): entry["set"] = s_set
			if not s_cn.is_empty(): entry["collector_number"] = s_cn
			var f_str: String = str(m_entry.get("finish", "")).strip_edges().to_lower()
			if f_str == "foil" or f_str == "etched": entry["is_foil"] = true
			cards_array.append(entry)

		for c_name in data.get("mainboard", {}).keys():
			var m_entry: Dictionary = data["mainboard"][c_name]
			var m_card: Dictionary = m_entry.get("card", {})
			var entry := {"name": c_name, "quantity": m_entry.get("quantity", 1)}
			var s_id: String = str(m_card.get("scryfall_id", "")).strip_edges()
			var s_set: String = str(m_card.get("set", "")).strip_edges().to_lower()
			var s_cn: String = str(m_card.get("cn", "")).strip_edges()
			if not s_id.is_empty(): entry["scryfall_id"] = s_id
			if not s_set.is_empty(): entry["set"] = s_set
			if not s_cn.is_empty(): entry["collector_number"] = s_cn
			var f_str: String = str(m_entry.get("finish", "")).strip_edges().to_lower()
			if f_str == "foil" or f_str == "etched": entry["is_foil"] = true
			cards_array.append(entry)

		var cache_key := "moxfield_" + deck_id
		var cache := _load_deck_cache()
		cache[cache_key] = {"deckName": deck_name, "commander": commander, "cards": cards_array}
		_save_deck_cache(cache)

		if refresh_callback.is_valid(): refresh_callback.call()
		if is_instance_valid(line_edit): line_edit.text = ""

	else:
		if is_instance_valid(import_btn):
			import_btn.text = "BAD JSON"
			import_btn.disabled = false
		return

	if is_instance_valid(import_btn):
		import_btn.text = "IMPORT"
		import_btn.disabled = false

func load_and_spawn_all_decks(selections: Dictionary) -> void:
	engine.hud_manager.show_loading_screen("Loading all player decks...")
	engine.hud_manager.setup_phase_hud()

	var cache := _load_deck_cache()
	_pending_deck_loads = 0
	for pid in selections.keys():
		if cache.has(selections[pid]):
			_pending_deck_loads += 1
	_total_deck_loads = _pending_deck_loads

	if _pending_deck_loads == 0:
		engine.hud_manager.hide_loading_screen()
		return

	for pid in selections.keys():
		var chosen_key: String = selections[pid]
		if not cache.has(chosen_key): continue

		var deck_info: Dictionary = cache[chosen_key]
		var live_deck_data := {}
		if deck_info.has("cards"):
			live_deck_data = deck_info
		else:
			var json_path: String = deck_info.get("json_path", "")
			if not json_path.is_empty() and FileAccess.file_exists(json_path):
				var file := FileAccess.open(json_path, FileAccess.READ)
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					live_deck_data = json.get_data()

		var cards_array: Array = live_deck_data.get("cards", [])
		var designated_commander := str(deck_info.get("commander", live_deck_data.get("commander", ""))).strip_edges()

		var raw_card_reqs: Array = []
		for item in cards_array:
			var c_name := ""
			var qty := 1
			var s_id := ""
			var s_set := ""
			var s_cn := ""
			var is_foil := false
			if item is Dictionary:
				if item.has("card"):
					var c_node: Dictionary = item.get("card", {})
					var o_node: Dictionary = c_node.get("oracleCard", {})
					c_name = o_node.get("name", c_node.get("name", ""))
					s_id = str(c_node.get("uid", c_node.get("scryfall_id", ""))).strip_edges()
					s_set = str(c_node.get("edition", {}).get("editioncode", c_node.get("set", ""))).strip_edges().to_lower()
					s_cn = str(c_node.get("collectorNumber", c_node.get("cn", ""))).strip_edges()
					var mod_s: String = str(item.get("modifier", item.get("finish", ""))).strip_edges().to_lower()
					is_foil = bool(item.get("is_foil", false)) or ("foil" in mod_s) or ("etched" in mod_s)
				else:
					c_name = str(item.get("name", ""))
					s_id = str(item.get("scryfall_id", "")).strip_edges()
					s_set = str(item.get("set", "")).strip_edges().to_lower()
					s_cn = str(item.get("collector_number", "")).strip_edges()
					is_foil = bool(item.get("is_foil", false))
				qty = int(item.get("quantity", 1))

			if not c_name.is_empty():
				var req_obj := {"name": c_name, "scryfall_id": s_id, "set": s_set, "collector_number": s_cn, "is_foil": is_foil}
				for q in range(qty): raw_card_reqs.append(req_obj)

		var scryfall_service := ScryfallService.new()
		engine.add_child(scryfall_service)
		var svc_id := scryfall_service.get_instance_id()

		scryfall_service.fetch_batch_metadata(raw_card_reqs, func(metadata_map: Dictionary):
			var svc := instance_from_id(svc_id)
			if svc and is_instance_valid(svc): svc.queue_free()
			var built_cards := []
			for req_obj in raw_card_reqs:
				var c_name: String = str(req_obj.get("name", ""))
				var s_id: String = str(req_obj.get("scryfall_id", ""))
				var s_set: String = str(req_obj.get("set", ""))
				var s_cn: String = str(req_obj.get("collector_number", ""))
				var matched: Variant = null
				if not s_id.is_empty() and metadata_map.has("id:" + s_id):
					matched = metadata_map["id:" + s_id]
				elif not s_set.is_empty() and not s_cn.is_empty() and metadata_map.has("set:" + s_set + "|" + s_cn):
					matched = metadata_map["set:" + s_set + "|" + s_cn]
				elif metadata_map.has(c_name):
					matched = metadata_map[c_name]
				var card_d: Dictionary = matched.duplicate() if matched is Dictionary else {"name": c_name, "type_line": "Card", "image_url": ""}
				if bool(req_obj.get("is_foil", false)):
					card_d["is_foil"] = true
				built_cards.append(card_d)

			process_player_deck(pid, deck_info, built_cards, designated_commander)
			_pending_deck_loads -= 1
			var progress := float(_total_deck_loads - _pending_deck_loads) / float(max(1, _total_deck_loads)) * 100.0
			engine.hud_manager.update_loading_progress(progress, "Loaded Player %d deck..." % pid)
			if _pending_deck_loads <= 0:
				engine.hud_manager.hide_loading_screen()
				if engine.has_method("start_first_player_decision"):
					engine.start_first_player_decision()
				else:
					engine.start_mulligan_phase()
		)

func process_player_deck(pid: int, _deck_info: Dictionary, cards_array: Array, raw_commander_str: String) -> void:
	var target_commanders: Array[String] = []
	for part in raw_commander_str.split("|"):
		var clean_p := part.strip_edges().to_lower()
		if not clean_p.is_empty(): target_commanders.append(clean_p)

	var extracted_commanders := []
	var matched_cmd_names: Array[String] = []
	var remaining_cards := []

	for card_data in cards_array:
		var c_name_check := str(card_data.get("name", "")).strip_edges().to_lower()
		if c_name_check in target_commanders and not (c_name_check in matched_cmd_names):
			extracted_commanders.append(card_data)
			matched_cmd_names.append(c_name_check)
		else:
			remaining_cards.append(card_data)

	if extracted_commanders.is_empty() and not cards_array.is_empty():
		extracted_commanders.append(cards_array[0])
		remaining_cards = cards_array.slice(1)

	var first_names: Array[String] = []
	for cmd_d in extracted_commanders:
		var full_n := str(cmd_d.get("name", "")).split(" // ")[0].strip_edges()
		var words := full_n.split(" ")
		if words.size() > 0:
			var fn := words[0].trim_suffix(",")
			if fn.to_lower() == "the" and words.size() > 1:
				fn = "The " + words[1].trim_suffix(",")
			first_names.append(fn)
	if not first_names.is_empty():
		engine.player_display_names[pid] = " & ".join(first_names)
		engine.hud_manager.refresh_player_names()

	var sleeve_tex: Texture2D = engine.get_player_sleeve_texture(pid) if engine.has_method("get_player_sleeve_texture") else null
	var station_data: Dictionary = engine.player_stations[pid]
	var cmd_anchor: Node3D = engine.command_zone_anchor if pid == engine.local_player_id else station_data["command_zone"]
	var lib_anchor: Node3D = engine.library_anchor if pid == engine.local_player_id else station_data["library"]
	var hand_cont: Node3D = engine.hand_container if pid == engine.local_player_id else station_data["hand_container"]

	for i in range(extracted_commanders.size()):
		var cmd_data: Dictionary = extracted_commanders[i]
		var cmd_card: Node3D = engine._instantiate_card()
		cmd_card.card_data = cmd_data
		cmd_card.set_meta("owner_id", pid)
		cmd_card.set_meta("is_commander", true)
		if sleeve_tex and cmd_card.has_method("set_sleeve_texture"): cmd_card.set_sleeve_texture(sleeve_tex)
		engine.connect_card_signals(cmd_card)
		cmd_anchor.add_child(cmd_card)
		cmd_card.position = Vector3(i * 0.7, 0.0, 0.0)
		cmd_card.rotation = Vector3.ZERO

		if cmd_card.has_method("make_active"): cmd_card.make_active(cmd_data)
		if pid == engine.local_player_id:
			engine.command_zone_cards.append(cmd_card)
			engine.commander_cast_counts[cmd_card] = 0

		engine.player_command_zones[pid].append(cmd_card)

	if pid == engine.local_player_id:
		engine.zone_manager.update_commander_tax_counter()

	var shuffled := remaining_cards.duplicate()
	shuffled.shuffle()
	var hand_size: int = min(7, shuffled.size())

	for i in range(hand_size):
		var card_inst: Node3D = engine._instantiate_card()
		card_inst.card_data = shuffled[i]
		card_inst.set_meta("owner_id", pid)
		if sleeve_tex and card_inst.has_method("set_sleeve_texture"): card_inst.set_sleeve_texture(sleeve_tex)
		engine.connect_card_signals(card_inst)
		hand_cont.add_child(card_inst)
		if pid == engine.local_player_id:
			card_inst.setup(shuffled[i])
			engine.hand_cards.append(card_inst)
		else:
			card_inst.setup_library()
		engine.player_hands[pid].append(card_inst)

	if pid == engine.local_player_id:
		engine.zone_manager.update_hand_positions(false)
	else:
		var ai_lands := 0
		for hc in engine.player_hands[pid]:
			if is_instance_valid(hc) and MagicRules.is_land(hc.card_data): ai_lands += 1
		var ai_diff: int = int(engine.ai_controller.difficulty) if engine.ai_controller else 1
		var bad_hand: bool = (ai_lands <= 1 or ai_lands >= 6) if ai_diff < 2 else (ai_lands < 2 or ai_lands > 4)
		if bad_hand and shuffled.size() >= 14:
			for hc in engine.player_hands[pid]:
				if is_instance_valid(hc): hc.queue_free()
			engine.player_hands[pid].clear()
			shuffled.shuffle()
			for i in range(hand_size):
				var mc: Node3D = engine._instantiate_card()
				mc.card_data = shuffled[i]
				mc.set_meta("owner_id", pid)
				if sleeve_tex and mc.has_method("set_sleeve_texture"): mc.set_sleeve_texture(sleeve_tex)
				engine.connect_card_signals(mc)
				hand_cont.add_child(mc)
				mc.setup_library()
				engine.player_hands[pid].append(mc)
		engine.zone_manager.update_opponent_hand_positions(pid, false)

	var lib_cards := shuffled.slice(hand_size)
	for i in range(lib_cards.size()):
		var card_inst: Node3D = engine._instantiate_card()
		card_inst.card_data = lib_cards[i]
		card_inst.set_meta("owner_id", pid)
		if sleeve_tex and card_inst.has_method("set_sleeve_texture"): card_inst.set_sleeve_texture(sleeve_tex)
		engine.connect_card_signals(card_inst)
		lib_anchor.add_child(card_inst)
		card_inst.position = Vector3(0.0, i * engine.card_thickness, 0.0)
		card_inst.rotation = Vector3.ZERO
		card_inst.setup_library()

		if pid == engine.local_player_id: engine.library_stack.append(card_inst)
		engine.player_libraries[pid].append(card_inst)

	engine.zone_manager.update_zone_counters()
	_enqueue_deck_prefetch(cards_array)

func _enqueue_deck_prefetch(cards_array: Array) -> void:
	for c in cards_array:
		if not (c is Dictionary): continue
		var urls: Array[String] = []
		var u0 := str(c.get("image_url", ""))
		if not u0.is_empty(): urls.append(u0)
		if c.get("card_faces") is Array:
			for f in c["card_faces"]:
				if f is Dictionary:
					var fu := str(f.get("image_url", ""))
					if fu.is_empty() and f.get("image_uris") is Dictionary:
						fu = str(f["image_uris"].get("normal", f["image_uris"].get("small", "")))
					if not fu.is_empty(): urls.append(fu)
		for u in urls:
			if CardManager.get_cached_image_texture(u) == null and not (u in _prefetch_urls):
				_prefetch_urls.append(u)
				_prefetch_total += 1
	if engine and engine.hud_manager and engine.hud_manager.has_method("update_prefetch_progress"):
		engine.hud_manager.update_prefetch_progress(_prefetch_done, _prefetch_total)
	_pump_prefetch_queue()

func _pump_prefetch_queue() -> void:
	while _prefetch_in_flight < 4 and not _prefetch_urls.is_empty():
		var url: String = _prefetch_urls.pop_front()
		if CardManager.get_cached_image_texture(url) != null:
			continue
		_prefetch_in_flight += 1
		var http := HTTPRequest.new()
		add_child(http)
		var req_id := http.get_instance_id()
		http.request_completed.connect(func(_res, code, _hdr, body):
			var r := instance_from_id(req_id)
			if r and is_instance_valid(r): r.queue_free()
			_prefetch_in_flight = maxi(0, _prefetch_in_flight - 1)
			_prefetch_done += 1
			if code == 200:
				CardManager.store_image_to_cache(url, body)
			if engine and engine.hud_manager and engine.hud_manager.has_method("update_prefetch_progress"):
				engine.hud_manager.update_prefetch_progress(_prefetch_done, _prefetch_total)
			if _prefetch_urls.is_empty() and _prefetch_in_flight == 0:
				_prefetch_total = 0; _prefetch_done = 0
			_pump_prefetch_queue()
		)
		http.request(url, ["User-Agent: MTGBrawlSim/1.0", "Accept: */*"])


func load_and_spawn_network_decks(seat_decks: Dictionary) -> void:
	var cache := _load_deck_cache()
	var temp_key_map := {}
	for pid in seat_decks.keys():
		var k := "net_seat_%d" % int(pid)
		cache[k] = seat_decks[pid]
		temp_key_map[int(pid)] = k
	_save_deck_cache(cache)
	load_and_spawn_all_decks(temp_key_map)


func _import_plain_text_decklist(raw_text: String, line_edit: LineEdit, import_btn: Button, refresh_callback: Callable) -> void:
	var cards_array := []
	var commander := ""
	var in_cmd_section := false
	var line_rx := RegEx.new()
	line_rx.compile("^(\\d+)x?\\s+([^(\\r\\n]+?)(?:\\s+\\(([A-Za-z0-9]+)\\)\\s+(\\S+))?(?:\\s+\\*([FE])\\*)?$")
	for raw_line in raw_text.split("\n"):
		var l := raw_line.strip_edges()
		if l.is_empty(): continue
		var lower := l.to_lower()
		if lower.begins_with("commander"):
			in_cmd_section = true
			continue
		if lower.begins_with("deck") or lower.begins_with("mainboard") or lower.begins_with("sideboard"):
			in_cmd_section = false
			continue
		var m := line_rx.search(l)
		if m:
			var qty := m.get_string(1).to_int()
			var c_name := m.get_string(2).strip_edges()
			var s_set := m.get_string(3).strip_edges().to_lower()
			var s_cn := m.get_string(4).strip_edges()
			var foil_tag := m.get_string(5).strip_edges().to_upper()
			var entry := {"name": c_name, "quantity": qty}
			if not s_set.is_empty(): entry["set"] = s_set
			if not s_cn.is_empty(): entry["collector_number"] = s_cn
			if foil_tag == "F" or foil_tag == "E": entry["is_foil"] = true
			cards_array.append(entry)
			if in_cmd_section:
				commander = c_name if commander.is_empty() else (commander + " | " + c_name)
	if cards_array.is_empty():
		if is_instance_valid(import_btn):
			import_btn.text = "EMPTY LIST"
			import_btn.disabled = false
		return
	if commander.is_empty():
		commander = str(cards_array[0].get("name", ""))
	var deck_name := "Imported (%s)" % commander.split(" | ")[0]
	var cache_key := "text_" + str(Time.get_unix_time_from_system())
	var cache := _load_deck_cache()
	cache[cache_key] = {"deckName": deck_name, "commander": commander, "cards": cards_array}
	_save_deck_cache(cache)
	if refresh_callback.is_valid(): refresh_callback.call()
	if is_instance_valid(line_edit): line_edit.text = ""
	if is_instance_valid(import_btn):
		import_btn.text = "IMPORT"
		import_btn.disabled = false
