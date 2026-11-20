class_name DeckLoader
extends Node

var engine: Node = null
var _prefetch_urls: Array[String] = []
var _prefetch_in_flight: int = 0
var _pending_deck_loads: int = 0
var _total_deck_loads: int = 0

func setup(main_engine: Node) -> void:
	engine = main_engine

func show_deck_selector_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DeckSelectorUI"
	engine.add_child(canvas)

	var bg_overlay := ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.8)
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg_overlay)

	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center_container)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 620)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.11, 0.14, 0.98); panel_style.border_color = Color(0.85, 0.7, 0.35, 0.9); panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 14; panel_style.corner_radius_top_right = 14; panel_style.corner_radius_bottom_left = 14; panel_style.corner_radius_bottom_right = 14
	panel_style.content_margin_left = 30; panel_style.content_margin_right = 30; panel_style.content_margin_top = 25; panel_style.content_margin_bottom = 25
	panel.add_theme_stylebox_override("panel", panel_style)
	center_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SELECT OR IMPORT DECKS (ALL PLAYERS)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	vbox.add_child(title)

	var import_hbox := HBoxContainer.new()
	import_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(import_hbox)

	var url_input := LineEdit.new()
	url_input.placeholder_text = "Paste Moxfield or Archidekt URL..."
	url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_input.custom_minimum_size = Vector2(0, 40)

	var pill_input_style := StyleBoxFlat.new()
	pill_input_style.bg_color = Color(0.06, 0.07, 0.09, 1.0); pill_input_style.border_color = Color(0.2, 0.3, 0.4, 1.0); pill_input_style.set_border_width_all(1)
	pill_input_style.corner_radius_top_left = 20; pill_input_style.corner_radius_top_right = 20; pill_input_style.corner_radius_bottom_left = 20; pill_input_style.corner_radius_bottom_right = 20
	pill_input_style.content_margin_left = 15
	url_input.add_theme_stylebox_override("normal", pill_input_style)
	import_hbox.add_child(url_input)

	var import_btn := Button.new()
	import_btn.text = "IMPORT"
	import_btn.custom_minimum_size = Vector2(100, 40)

	var pill_btn_style := StyleBoxFlat.new()
	pill_btn_style.bg_color = Color(0.15, 0.22, 0.35, 1.0); pill_btn_style.border_color = Color(0.35, 0.55, 0.85, 1.0); pill_btn_style.set_border_width_all(1)
	pill_btn_style.corner_radius_top_left = 20; pill_btn_style.corner_radius_top_right = 20; pill_btn_style.corner_radius_bottom_left = 20; pill_btn_style.corner_radius_bottom_right = 20
	import_btn.add_theme_stylebox_override("normal", pill_btn_style)
	import_btn.add_theme_stylebox_override("hover", pill_btn_style)
	import_hbox.add_child(import_btn)

	vbox.add_child(HSeparator.new())

	var manage_hbox := HBoxContainer.new()
	manage_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(manage_hbox)

	var manage_lbl := Label.new()
	manage_lbl.text = "Saved Decks:"
	manage_lbl.custom_minimum_size = Vector2(105, 0)
	manage_hbox.add_child(manage_lbl)

	var manage_opt := OptionButton.new()
	manage_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manage_opt.custom_minimum_size = Vector2(0, 36)
	manage_opt.add_theme_stylebox_override("normal", pill_input_style)
	manage_hbox.add_child(manage_opt)

	var delete_btn := Button.new()
	delete_btn.text = "DELETE"
	delete_btn.custom_minimum_size = Vector2(100, 36)
	var del_style := pill_btn_style.duplicate()
	del_style.bg_color = Color(0.38, 0.14, 0.14, 1.0); del_style.border_color = Color(0.85, 0.35, 0.35, 1.0)
	delete_btn.add_theme_stylebox_override("normal", del_style)
	delete_btn.add_theme_stylebox_override("hover", del_style)
	manage_hbox.add_child(delete_btn)

	vbox.add_child(HSeparator.new())

	var player_dropdowns := {}
	var player_names := {1: "Player 1 (You)", 2: "Player 2 (Left)", 3: "Player 3 (Across)", 4: "Player 4 (Right)"}

	var populate_all_dropdowns = func():
		var cache := CardManager.load_cache_from_disk()
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
				opt.add_item("No cached decks found. Import above.")
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

	delete_btn.pressed.connect(func():
		if manage_opt.get_item_count() == 0 or manage_opt.selected < 0: return
		var key_to_remove = manage_opt.get_item_metadata(manage_opt.selected)
		if key_to_remove == null: return
		var cache := CardManager.load_cache_from_disk()
		if cache.has(key_to_remove):
			cache.erase(key_to_remove)
			CardManager.save_cache_to_disk(cache)
			populate_all_dropdowns.call()
	)

	for i in range(1, 5):
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 15)
		vbox.add_child(hbox)

		var lbl := Label.new()
		lbl.text = player_names[i]
		lbl.custom_minimum_size = Vector2(140, 0)
		hbox.add_child(lbl)

		var prev_btn := Button.new()
		prev_btn.text = "◀"
		prev_btn.custom_minimum_size = Vector2(38, 40)
		hbox.add_child(prev_btn)

		var option_btn := OptionButton.new()
		option_btn.custom_minimum_size = Vector2(304, 40)
		option_btn.add_theme_stylebox_override("normal", pill_input_style)
		hbox.add_child(option_btn)
		player_dropdowns[i] = option_btn

		var next_btn := Button.new()
		next_btn.text = "▶"
		next_btn.custom_minimum_size = Vector2(38, 40)
		hbox.add_child(next_btn)

		prev_btn.pressed.connect(func():
			var cnt := option_btn.get_item_count()
			if cnt > 0: option_btn.select((option_btn.selected - 1 + cnt) % cnt)
		)
		next_btn.pressed.connect(func():
			var cnt := option_btn.get_item_count()
			if cnt > 0: option_btn.select((option_btn.selected + 1) % cnt)
		)

	populate_all_dropdowns.call()

	import_btn.pressed.connect(func():
		var url := url_input.text.strip_edges()
		if not url.is_empty():
			import_deck_from_url_multi(url, url_input, import_btn, populate_all_dropdowns)
	)

	var first_hbox := HBoxContainer.new()
	first_hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(first_hbox)

	var first_lbl := Label.new()
	first_lbl.text = "First Player:"
	first_lbl.custom_minimum_size = Vector2(140, 0)
	first_hbox.add_child(first_lbl)

	var first_prev := Button.new()
	first_prev.text = "◀"
	first_prev.custom_minimum_size = Vector2(38, 38)
	first_hbox.add_child(first_prev)

	var first_opt := OptionButton.new()
	first_opt.custom_minimum_size = Vector2(304, 38)
	first_opt.add_theme_stylebox_override("normal", pill_input_style)
	first_opt.add_item("Random (Roll)"); first_opt.set_item_metadata(0, 0)
	first_opt.add_item("Player 1 (You)"); first_opt.set_item_metadata(1, 1)
	first_opt.add_item("Player 2 (Left)"); first_opt.set_item_metadata(2, 2)
	first_opt.add_item("Player 3 (Across)"); first_opt.set_item_metadata(3, 3)
	first_opt.add_item("Player 4 (Right)"); first_opt.set_item_metadata(4, 4)
	first_hbox.add_child(first_opt)

	var first_next := Button.new()
	first_next.text = "▶"
	first_next.custom_minimum_size = Vector2(38, 38)
	first_hbox.add_child(first_next)

	first_prev.pressed.connect(func():
		var cnt := first_opt.get_item_count()
		if cnt > 0: first_opt.select((first_opt.selected - 1 + cnt) % cnt)
	)
	first_next.pressed.connect(func():
		var cnt := first_opt.get_item_count()
		if cnt > 0: first_opt.select((first_opt.selected + 1) % cnt)
	)

	var load_btn := Button.new()
	load_btn.text = "LOAD ALL DECKS & START GAME"
	load_btn.custom_minimum_size = Vector2(545, 46)

	var start_btn_style := pill_btn_style.duplicate()
	start_btn_style.bg_color = Color(0.18, 0.35, 0.22, 1.0); start_btn_style.border_color = Color(0.3, 0.55, 0.35, 1.0)
	load_btn.add_theme_stylebox_override("normal", start_btn_style)
	load_btn.add_theme_stylebox_override("hover", start_btn_style)
	vbox.add_child(load_btn)

	load_btn.pressed.connect(func():
		var selections := {}
		for i in range(1, 5):
			var opt: OptionButton = player_dropdowns[i]
			selections[i] = opt.get_item_metadata(opt.selected) if opt.get_item_count() > 0 and opt.selected >= 0 else opt.get_item_metadata(0)
		var chosen_first: int = int(first_opt.get_item_metadata(first_opt.selected))
		if chosen_first == 0:
			chosen_first = TurnManager.CLOCKWISE_ORDER[randi() % TurnManager.CLOCKWISE_ORDER.size()]
		engine.starting_player_id = chosen_first
		canvas.queue_free()
		load_and_spawn_all_decks(selections)
	)

	engine.hud_manager.apply_custom_font(canvas)

func import_deck_from_url_multi(url: String, line_edit: LineEdit, import_btn: Button, refresh_callback: Callable) -> void:
	import_btn.disabled = true
	import_btn.text = "FETCHING..."

	var http := HTTPRequest.new()
	engine.add_child(http)
	var http_id := http.get_instance_id()

	if "archidekt.com/decks/" in url:
		var parts := url.split("archidekt.com/decks/")
		if parts.size() > 1:
			var deck_id := parts[1].split("/")[0].split("?")[0]
			var api_url := "https://archidekt.com/api/decks/%s/" % deck_id
			http.request_completed.connect(func(_res, code, _hdr, body):
				_on_archidekt_loaded_multi(code, body, deck_id, line_edit, import_btn, refresh_callback, http_id)
			)
			http.request(api_url, ["User-Agent: MTGBrawlSim/1.0", "Accept: application/json"])
			return

	elif "moxfield.com/decks/" in url:
		var parts := url.split("moxfield.com/decks/")
		if parts.size() > 1:
			var deck_id := parts[1].split("/")[0].split("?")[0]
			var api_url := "https://api2.moxfield.com/v2/decks/all/%s" % deck_id
			http.request_completed.connect(func(_res, code, _hdr, body):
				_on_moxfield_loaded_multi(code, body, deck_id, line_edit, import_btn, refresh_callback, http_id)
			)
			http.request(api_url, ["User-Agent: MTGBrawlSim/1.0", "Accept: application/json"])
			return

	line_edit.text = "Invalid URL."
	import_btn.disabled = false
	import_btn.text = "IMPORT"
	http.queue_free()

func _on_archidekt_loaded_multi(code: int, body: PackedByteArray, deck_id: String, line_edit: LineEdit, import_btn: Button, refresh_callback: Callable, http_id: int) -> void:
	var req := instance_from_id(http_id)
	if req and is_instance_valid(req): req.queue_free()
	if code != 200:
		if is_instance_valid(import_btn):
			import_btn.text = "ERROR"
			import_btn.disabled = false
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK:
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
			cards_array.append({"name": c_name, "quantity": qty})

		var cache_key := "archidekt_" + deck_id
		var cache := CardManager.load_cache_from_disk()
		cache[cache_key] = {"deckName": deck_name, "commander": commander, "cards": cards_array}
		CardManager.save_cache_to_disk(cache)

		if refresh_callback.is_valid(): refresh_callback.call()
		if is_instance_valid(line_edit): line_edit.text = ""

	if is_instance_valid(import_btn):
		import_btn.text = "IMPORT"
		import_btn.disabled = false

func _on_moxfield_loaded_multi(code: int, body: PackedByteArray, deck_id: String, line_edit: LineEdit, import_btn: Button, refresh_callback: Callable, http_id: int) -> void:
	var req := instance_from_id(http_id)
	if req and is_instance_valid(req): req.queue_free()
	if code != 200:
		if is_instance_valid(import_btn):
			import_btn.text = "ERROR"
			import_btn.disabled = false
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK:
		var data: Dictionary = json.get_data()
		var deck_name: String = data.get("name", "Moxfield Deck")
		var cards_array := []
		var commander := ""

		for c_name in data.get("commanders", {}).keys():
			commander = c_name if commander.is_empty() else (commander + " | " + c_name)
			cards_array.append({"name": c_name, "quantity": data["commanders"][c_name].get("quantity", 1)})

		for c_name in data.get("mainboard", {}).keys():
			cards_array.append({"name": c_name, "quantity": data["mainboard"][c_name].get("quantity", 1)})

		var cache_key := "moxfield_" + deck_id
		var cache := CardManager.load_cache_from_disk()
		cache[cache_key] = {"deckName": deck_name, "commander": commander, "cards": cards_array}
		CardManager.save_cache_to_disk(cache)

		if refresh_callback.is_valid(): refresh_callback.call()
		if is_instance_valid(line_edit): line_edit.text = ""

	if is_instance_valid(import_btn):
		import_btn.text = "IMPORT"
		import_btn.disabled = false

func load_and_spawn_all_decks(selections: Dictionary) -> void:
	engine.hud_manager.show_loading_screen("Loading all player decks...")
	engine.hud_manager.setup_phase_hud()

	var cache := CardManager.load_cache_from_disk()
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

		var raw_card_names: Array[String] = []
		for item in cards_array:
			var c_name := ""
			var qty := 1
			if item is Dictionary:
				if item.has("card"):
					var c_node: Dictionary = item.get("card", {})
					var o_node: Dictionary = c_node.get("oracleCard", {})
					c_name = o_node.get("name", c_node.get("name", ""))
				else:
					c_name = item.get("name", "")
				qty = item.get("quantity", 1)

			if not c_name.is_empty():
				for q in range(qty): raw_card_names.append(c_name)

		var scryfall_service := ScryfallService.new()
		engine.add_child(scryfall_service)
		var svc_id := scryfall_service.get_instance_id()

		scryfall_service.fetch_batch_metadata(raw_card_names, func(metadata_map: Dictionary):
			var svc := instance_from_id(svc_id)
			if svc and is_instance_valid(svc): svc.queue_free()
			var built_cards := []
			for card_name in raw_card_names:
				if metadata_map.has(card_name):
					built_cards.append(metadata_map[card_name].duplicate())
				else:
					built_cards.append({"name": card_name, "type_line": "Card", "image_url": ""})

			process_player_deck(pid, deck_info, built_cards, designated_commander)
			_pending_deck_loads -= 1
			var progress := float(_total_deck_loads - _pending_deck_loads) / float(max(1, _total_deck_loads)) * 100.0
			engine.hud_manager.update_loading_progress(progress, "Loaded Player %d deck..." % pid)
			if _pending_deck_loads <= 0:
				engine.hud_manager.hide_loading_screen()
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
		engine.zone_manager.update_opponent_hand_positions(pid, false)

	var lib_cards := shuffled.slice(hand_size)
	for i in range(lib_cards.size()):
		var card_inst: Node3D = engine._instantiate_card()
		card_inst.card_data = lib_cards[i]
		card_inst.set_meta("owner_id", pid)
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
			if code == 200:
				CardManager.store_image_to_cache(url, body)
			_pump_prefetch_queue()
		)
		http.request(url, ["User-Agent: MTGBrawlSim/1.0", "Accept: */*"])
