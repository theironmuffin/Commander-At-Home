class_name GameSerializer
extends RefCounted

static func _serialize_card(card: Node3D, zone_name: String, zone_idx: int, engine: Node) -> Dictionary:
	var owner_id: int = engine.get_card_owner_id(card)
	var ctrl_id: int = engine.get_card_controller_id(card) if engine.has_method("get_card_controller_id") else owner_id
	var d := {
		"uid": card.get_instance_id(),
		"card_data": card.card_data.duplicate(true),
		"owner_id": owner_id,
		"controller_id": ctrl_id,
		"zone": zone_name,
		"zone_index": zone_idx,
		"is_tapped": bool(card.is_tapped),
		"has_summoning_sickness": bool(card.has_summoning_sickness),
		"is_attacking": bool(card.get("is_attacking")),
		"attacking_target_player_id": int(card.get("attacking_target_player_id")),
		"counter_amount": int(card.get("counter_amount")),
		"custom_counters": (card.get("custom_counters") as Dictionary).duplicate(true) if card.get("custom_counters") is Dictionary else {},
		"custom_statuses": (card.get("custom_statuses") as Array).duplicate(true) if card.get("custom_statuses") is Array else [],
		"type_overrides": (card.get("type_overrides") as Array).duplicate(true) if card.get("type_overrides") is Array else [],
		"unlocked_rooms": (card.get("unlocked_rooms") as Array).duplicate(true) if card.get("unlocked_rooms") is Array else [],
		"temp_power_modifier": int(card.get("temp_power_modifier")),
		"temp_toughness_modifier": int(card.get("temp_toughness_modifier")),
		"marked_damage": int(card.get("marked_damage")),
		"has_deathtouch_damage": bool(card.get("has_deathtouch_damage")),
		"loyalty_activated_this_turn": bool(card.get("loyalty_activated_this_turn")),
		"active_face_index": int(card.get("active_face_index")),
		"is_commander": card.has_meta("is_commander") and bool(card.get_meta("is_commander")),
		"commander_cast_count": int(engine.commander_cast_counts.get(card, 0)),
		"is_token": bool(card.get("is_token"))
	}
	var host_n: Variant = card.get("attached_to")
	if host_n is Node3D and is_instance_valid(host_n):
		d["attached_to_uid"] = (host_n as Node3D).get_instance_id()
	for meta_k in ["foretold", "foretold_turn", "plotted", "plotted_turn", "suspended", "crewed_until_eot", "saddled_until_eot", "animated_until_eot", "base_pt_until_eot", "temp_granted_keywords", "perm_granted_keywords", "pt_switched", "chosen_creature_type", "chosen_color"]:
		if card.has_meta(meta_k):
			d["meta_" + meta_k] = card.get_meta(meta_k)
	if card.has_meta("base_pt_override"):
		var bpt: Variant = card.get_meta("base_pt_override")
		if bpt is Vector2i:
			d["meta_base_pt_override"] = [bpt.x, bpt.y]
	return d

static func serialize_state(engine: Node) -> Dictionary:
	var tm: Node = engine.turn_manager
	var cards_out: Array = []

	for pid in [1, 2, 3, 4]:
		var lib_arr: Array = engine.library_stack if pid == engine.local_player_id else engine.player_libraries.get(pid, [])
		for i in range(lib_arr.size()):
			if is_instance_valid(lib_arr[i]):
				cards_out.append(_serialize_card(lib_arr[i], "library", i, engine))
		var hand_arr: Array = engine.hand_cards if pid == engine.local_player_id else engine.player_hands.get(pid, [])
		for i in range(hand_arr.size()):
			if is_instance_valid(hand_arr[i]):
				cards_out.append(_serialize_card(hand_arr[i], "hand", i, engine))
		var gy_arr: Array = engine.graveyard_stack if pid == engine.local_player_id else engine.player_graveyards.get(pid, [])
		for i in range(gy_arr.size()):
			if is_instance_valid(gy_arr[i]):
				cards_out.append(_serialize_card(gy_arr[i], "graveyard", i, engine))
		var ex_arr: Array = engine.exile_stack if pid == engine.local_player_id else engine.player_exile.get(pid, [])
		for i in range(ex_arr.size()):
			if is_instance_valid(ex_arr[i]):
				cards_out.append(_serialize_card(ex_arr[i], "exile", i, engine))
		var cmd_arr: Array = engine.command_zone_cards if pid == engine.local_player_id else engine.player_command_zones.get(pid, [])
		for i in range(cmd_arr.size()):
			if is_instance_valid(cmd_arr[i]):
				cards_out.append(_serialize_card(cmd_arr[i], "command_zone", i, engine))

	for i in range(engine.battlefield_lands.size()):
		if is_instance_valid(engine.battlefield_lands[i]):
			cards_out.append(_serialize_card(engine.battlefield_lands[i], "battlefield_land", i, engine))
	for i in range(engine.battlefield_non_lands.size()):
		var b_card: Node3D = engine.battlefield_non_lands[i]
		if is_instance_valid(b_card):
			cards_out.append(_serialize_card(b_card, "battlefield_non_land", i, engine))
			if "attachments" in b_card:
				for a_idx in range(b_card.attachments.size()):
					var att_c: Node3D = b_card.attachments[a_idx]
					if is_instance_valid(att_c):
						cards_out.append(_serialize_card(att_c, "attachment", a_idx, engine))
	for i in range(engine.battlefield_lands.size()):
		var bl_card: Node3D = engine.battlefield_lands[i]
		if is_instance_valid(bl_card) and "attachments" in bl_card:
			for a_idx in range(bl_card.attachments.size()):
				var att_c: Node3D = bl_card.attachments[a_idx]
				if is_instance_valid(att_c):
					cards_out.append(_serialize_card(att_c, "attachment", a_idx, engine))
	for i in range(engine.active_stack.size()):
		var s_it = engine.active_stack[i]
		if s_it is Node3D and is_instance_valid(s_it):
			cards_out.append(_serialize_card(s_it, "stack", i, engine))

	return {
		"version": 1,
		"local_player_id": engine.local_player_id,
		"starting_player_id": engine.starting_player_id,
		"turn_number": tm.turn_number,
		"active_player_id": tm.active_player_id,
		"priority_player_id": tm.priority_player_id,
		"current_turn_phase": tm.current_turn_phase,
		"priority_passes_count": tm.priority_passes_count,
		"land_played_this_turn": engine.land_played_this_turn,
		"spells_cast_this_turn": engine.spells_cast_this_turn,
		"player_life": engine.player_life.duplicate(true),
		"eliminated_players": engine.eliminated_players.duplicate(true),
		"player_display_names": engine.player_display_names.duplicate(true),
		"player_counters": engine.player_counters.duplicate(true),
		"player_statuses": engine.player_statuses.duplicate(true),
		"monarch_player_id": engine.monarch_player_id,
		"initiative_player_id": engine.initiative_player_id,
		"battlefield_day_night": engine.battlefield_day_night,
		"player_dungeons": engine.player_dungeons.duplicate(true),
		"commander_damage": engine.commander_damage.duplicate(true),
		"mana_pool": engine.mana_pool.duplicate(true),
		"restricted_mana": engine.restricted_mana.duplicate(true),
		"cards": cards_out
	}

static func _clear_all_cards(engine: Node) -> void:
	var to_free: Array[Node3D] = []
	for arr in [engine.hand_cards, engine.library_stack, engine.graveyard_stack, engine.exile_stack, engine.command_zone_cards, engine.battlefield_lands, engine.battlefield_non_lands]:
		for c in arr:
			if c is Node3D and is_instance_valid(c) and not (c in to_free):
				to_free.append(c)
		arr.clear()
	for s_item in engine.active_stack:
		if s_item is Node3D and is_instance_valid(s_item) and not (s_item in to_free):
			to_free.append(s_item)
	engine.active_stack.clear()
	for pid in [1, 2, 3, 4]:
		for dict_ref in [engine.player_libraries, engine.player_hands, engine.player_graveyards, engine.player_exile, engine.player_command_zones]:
			var a: Array = dict_ref.get(pid, [])
			for c in a:
				if c is Node3D and is_instance_valid(c) and not (c in to_free):
					to_free.append(c)
			a.clear()
	engine.commander_cast_counts.clear()
	engine.commander_damage.clear()
	for c in to_free:
		c.queue_free()

static func restore_state(engine: Node, state: Dictionary) -> void:
	if state.is_empty() or not state.has("cards"): return
	_clear_all_cards(engine)

	engine.starting_player_id = int(state.get("starting_player_id", 1))
	engine.land_played_this_turn = bool(state.get("land_played_this_turn", false))
	engine.spells_cast_this_turn = int(state.get("spells_cast_this_turn", 0))
	engine.monarch_player_id = int(state.get("monarch_player_id", 0))
	engine.initiative_player_id = int(state.get("initiative_player_id", 0))
	engine.battlefield_day_night = str(state.get("battlefield_day_night", ""))

	for k_raw in state.get("player_life", {}).keys():
		engine.player_life[int(k_raw)] = int(state["player_life"][k_raw])
	engine.eliminated_players.clear()
	for k_raw in state.get("eliminated_players", {}).keys():
		engine.eliminated_players[int(k_raw)] = bool(state["eliminated_players"][k_raw])
	for k_raw in state.get("player_display_names", {}).keys():
		engine.player_display_names[int(k_raw)] = str(state["player_display_names"][k_raw])
	for k_raw in state.get("player_counters", {}).keys():
		engine.player_counters[int(k_raw)] = state["player_counters"][k_raw].duplicate(true)
	for k_raw in state.get("player_statuses", {}).keys():
		engine.player_statuses[int(k_raw)] = state["player_statuses"][k_raw].duplicate(true)
	for k_raw in state.get("player_dungeons", {}).keys():
		engine.player_dungeons[int(k_raw)] = state["player_dungeons"][k_raw].duplicate(true)
	for k_raw in state.get("commander_damage", {}).keys():
		var sub_d: Dictionary = {}
		for s_k in state["commander_damage"][k_raw].keys():
			sub_d[int(s_k)] = int(state["commander_damage"][k_raw][s_k])
		engine.commander_damage[int(k_raw)] = sub_d
	var uid_to_card: Dictionary = {}
	var pending_attachments: Array = []

	if int(state.get("local_player_id", engine.local_player_id)) == engine.local_player_id:
		var mp: Dictionary = state.get("mana_pool", {})
		for c_k in engine.mana_pool.keys():
			engine.mana_pool[c_k] = int(mp.get(c_k, 0))
		engine.restricted_mana.clear()
		for rm in state.get("restricted_mana", []):
			if rm is Dictionary: engine.restricted_mana.append(rm.duplicate(true))

	var tm: Node = engine.turn_manager
	tm.turn_number = int(state.get("turn_number", 1))
	tm.active_player_id = int(state.get("active_player_id", 1))
	tm.priority_player_id = int(state.get("priority_player_id", 1))
	tm.current_turn_phase = int(state.get("current_turn_phase", TurnManager.TurnPhase.PRECOMBAT_MAIN))
	tm.priority_passes_count = int(state.get("priority_passes_count", 0))

	for cd in state.get("cards", []):
		if not (cd is Dictionary): continue
		var owner_id: int = int(cd.get("owner_id", 1))
		var ctrl_id: int = int(cd.get("controller_id", owner_id))
		var zone: String = str(cd.get("zone", "library"))
		var card: Node3D = engine._instantiate_card()
		card.card_data = cd.get("card_data", {}).duplicate(true)
		card.set_meta("owner_id", owner_id)
		if ctrl_id != owner_id and zone.begins_with("battlefield"):
			card.set_meta("control_override_player_id", ctrl_id)
		if bool(cd.get("is_commander", false)):
			card.set_meta("is_commander", true)
			engine.commander_cast_counts[card] = int(cd.get("commander_cast_count", 0))

		var orig_uid: int = int(cd.get("uid", 0))
		if orig_uid != 0:
			uid_to_card[orig_uid] = card
		var f_idx: int = int(cd.get("active_face_index", 0))
		if "active_face_index" in card:
			card.active_face_index = f_idx
		if "type_overrides" in card and cd.get("type_overrides") is Array:
			card.type_overrides.clear()
			for ov in cd["type_overrides"]: card.type_overrides.append(str(ov))
		if "unlocked_rooms" in card and cd.get("unlocked_rooms") is Array:
			card.unlocked_rooms.clear()
			for rm_i in cd["unlocked_rooms"]: card.unlocked_rooms.append(int(rm_i))
		for meta_k in ["foretold", "foretold_turn", "plotted", "plotted_turn", "suspended", "crewed_until_eot", "saddled_until_eot", "animated_until_eot", "base_pt_until_eot", "temp_granted_keywords", "perm_granted_keywords", "pt_switched", "chosen_creature_type", "chosen_color"]:
			if cd.has("meta_" + meta_k):
				card.set_meta(meta_k, cd["meta_" + meta_k])
		if cd.has("meta_base_pt_override") and cd["meta_base_pt_override"] is Array and cd["meta_base_pt_override"].size() >= 2:
			var b_arr: Array = cd["meta_base_pt_override"]
			card.set_meta("base_pt_override", Vector2i(int(b_arr[0]), int(b_arr[1])))
		if engine.has_method("get_player_sleeve_texture"):
			var slv: Texture2D = engine.get_player_sleeve_texture(owner_id)
			if slv and card.has_method("set_sleeve_texture"): card.set_sleeve_texture(slv)
		engine.connect_card_signals(card)

		var st_d: Dictionary = engine.player_stations.get(owner_id, {})
		var is_local: bool = (owner_id == engine.local_player_id)
		match zone:
			"library":
				var anc: Node3D = engine.library_anchor if is_local else st_d["library"]
				anc.add_child(card)
				card.setup_library()
				if is_local: engine.library_stack.append(card)
				engine.player_libraries[owner_id].append(card)
				card.position = Vector3(0.0, (engine.player_libraries[owner_id].size() - 1) * engine.card_thickness, 0.0)
			"hand":
				var cont: Node3D = engine.hand_container if is_local else st_d["hand_container"]
				cont.add_child(card)
				if is_local:
					card.setup(card.card_data)
					engine.hand_cards.append(card)
				else:
					card.setup_library()
				engine.player_hands[owner_id].append(card)
			"graveyard":
				var anc: Node3D = engine.graveyard_anchor if is_local else st_d["graveyard"]
				anc.add_child(card)
				if card.has_method("make_active"): card.make_active(card.card_data)
				if is_local: engine.graveyard_stack.append(card)
				else: engine.player_graveyards[owner_id].append(card)
			"exile":
				var anc: Node3D = engine.exile_anchor if is_local else st_d["exile"]
				anc.add_child(card)
				if card.has_method("make_active"): card.make_active(card.card_data)
				if is_local: engine.exile_stack.append(card)
				else: engine.player_exile[owner_id].append(card)
			"command_zone":
				var anc: Node3D = engine.command_zone_anchor if is_local else st_d["command_zone"]
				anc.add_child(card)
				if card.has_method("make_active"): card.make_active(card.card_data)
				if is_local: engine.command_zone_cards.append(card)
				engine.player_command_zones[owner_id].append(card)
			"stack":
				engine.central_stack_anchor.add_child(card)
				if card.has_method("make_active"): card.make_active(card.card_data)
				engine.active_stack.append(card)
			"battlefield_land", "battlefield_non_land", "attachment":
				var is_land := (zone == "battlefield_land")
				var p_anc: Node3D = engine.player_stations[ctrl_id]["lands_anchor" if is_land else "non_lands_anchor"] if engine.player_stations.has(ctrl_id) else engine
				p_anc.add_child(card)
				if card.has_method("make_active"): card.make_active(card.card_data)
				card.is_on_battlefield = true
				if zone == "attachment":
					pending_attachments.append({"card": card, "host_uid": int(cd.get("attached_to_uid", 0))})
				elif is_land: engine.battlefield_lands.append(card)
				else: engine.battlefield_non_lands.append(card)

		card.is_tapped = bool(cd.get("is_tapped", false))
		card.has_summoning_sickness = bool(cd.get("has_summoning_sickness", false))
		card.set("is_attacking", bool(cd.get("is_attacking", false)))
		card.set("attacking_target_player_id", int(cd.get("attacking_target_player_id", 0)))
		card.set("counter_amount", int(cd.get("counter_amount", 0)))
		card.set("plus_counters", int(cd.get("counter_amount", 0)))
		card.set("custom_counters", cd.get("custom_counters", {}).duplicate(true))
		card.set("custom_statuses", cd.get("custom_statuses", []).duplicate(true))
		card.set("temp_power_modifier", int(cd.get("temp_power_modifier", 0)))
		card.set("temp_toughness_modifier", int(cd.get("temp_toughness_modifier", 0)))
		card.set("marked_damage", int(cd.get("marked_damage", 0)))
		card.set("has_deathtouch_damage", bool(cd.get("has_deathtouch_damage", false)))
		card.set("loyalty_activated_this_turn", bool(cd.get("loyalty_activated_this_turn", false)))
		if bool(cd.get("is_token", false)) and card.has_method("mark_as_token"):
			card.mark_as_token()
		if card.has_method("refresh_visual_status"): card.refresh_visual_status()

	for pa_item in pending_attachments:
		var att_node: Node3D = pa_item["card"]
		var host_node: Node3D = uid_to_card.get(int(pa_item["host_uid"]), null) as Node3D
		if host_node != null and is_instance_valid(host_node):
			att_node.attached_to = host_node
			if not (att_node in host_node.attachments):
				host_node.attachments.append(att_node)
		else:
			engine.battlefield_non_lands.append(att_node)

	engine.zone_manager.update_hand_positions(false)
	for pid in [1, 2, 3, 4]:
		if pid != engine.local_player_id:
			engine.zone_manager.update_opponent_hand_positions(pid, false)
	engine.zone_manager.update_battlefield_positions(false)
	engine.zone_manager.update_zone_counters()
	engine.zone_manager.update_commander_tax_counter()
	engine.refresh_command_info_stations()
	engine.run_state_based_actions()
	EventBus.notify_phase(tm.current_turn_phase)
	EventBus.notify_priority(tm.priority_player_id, tm.priority_passes_count)
	EventBus.notify_stack(engine.active_stack.size())
	if engine.has_method("refresh_playable_card_glows"):
		engine.refresh_playable_card_glows()
	EventBus.notify_mana(engine.mana_pool)
	EventBus.notify_phase(tm.current_turn_phase)
	EventBus.notify_stack(engine.active_stack.size())
