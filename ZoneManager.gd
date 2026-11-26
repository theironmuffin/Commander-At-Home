class_name ZoneManager
extends Node

var engine: Node = null

func setup(main_engine: Node) -> void:
	engine = main_engine

func update_zone_counters() -> void:
	if engine.library_count_label: engine.library_count_label.text = str(engine.library_stack.size())
	if engine.graveyard_count_label: engine.graveyard_count_label.text = str(engine.graveyard_stack.size())
	if engine.exile_count_label: engine.exile_count_label.text = str(engine.exile_stack.size())
	if engine.stack_count_label: engine.stack_count_label.text = str(engine.active_stack.size()) if not engine.active_stack.is_empty() else ""
	for pid in engine.player_zone_labels.keys():
		if pid == engine.local_player_id: continue
		var lbls: Dictionary = engine.player_zone_labels[pid]
		if lbls.get("library"): lbls["library"].text = str(engine.player_libraries.get(pid, []).size())
		if lbls.get("graveyard"): lbls["graveyard"].text = str(engine.player_graveyards.get(pid, []).size())
		if lbls.get("exile"): lbls["exile"].text = str(engine.player_exile.get(pid, []).size())

func update_commander_tax_counter() -> void:
	if engine.commander_count_label:
		var cmd_list: Array = engine.player_command_zones.get(engine.local_player_id, engine.command_zone_cards)
		var parts: Array[String] = []
		for c in cmd_list:
			if is_instance_valid(c):
				parts.append(str(int(engine.commander_cast_counts.get(c, 0)) * 2))
		engine.commander_count_label.text = " / ".join(parts) if not parts.is_empty() else "0"

func untap_single_card(card_node: Node3D) -> void:
	if card_node:
		if card_node.has_method("get_named_counter") and card_node.get_named_counter("stun") > 0:
			card_node.modify_named_counter("stun", -1)
			return
		card_node.is_tapped = false
		engine.event_ledger.log_event(GameEventLedger.EventType.CARD_UNTAPPED, {"card_name": card_node.card_data.get("name", "")})
		update_battlefield_positions(true)

func untap_all(target_player_id: int = 1) -> void:
	for card in engine.battlefield_lands + engine.battlefield_non_lands:
		if is_instance_valid(card) and engine.get_card_owner_id(card) == target_player_id:
			card.has_summoning_sickness = false
			if card.is_tapped and card.has_method("get_named_counter") and card.get_named_counter("stun") > 0:
				card.modify_named_counter("stun", -1)
			else:
				card.is_tapped = false

	engine.event_ledger.log_event(GameEventLedger.EventType.CARD_UNTAPPED, {"target_player_id": target_player_id})
	update_battlefield_positions(true)

func shuffle_library() -> void:
	if engine.library_stack.is_empty(): return
	EventBus.play_sfx("shuffle")
	for c in engine.library_stack:
		if c.has_method("setup_library"): c.setup_library()

	engine.library_stack.shuffle()
	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(engine.library_stack.size()):
		var c: Node3D = engine.library_stack[i]
		tween.tween_property(c, "position", Vector3(0.0, i * engine.card_thickness, 0.0), 0.35)
		tween.tween_property(c, "quaternion", Quaternion.IDENTITY, 0.35)

func draw_card() -> void:
	if engine.library_stack.is_empty():
		if not engine.mulligan_phase_active and engine.turn_manager != null and engine.turn_manager.turn_number >= 1:
			engine.drawn_from_empty_library[engine.local_player_id] = true
			engine.run_state_based_actions()
		return
	EventBus.play_sfx("draw")
	var card_node: Node3D = engine.library_stack.pop_back()
	var global_trans := card_node.global_transform
	card_node.reparent(engine.hand_container, true)
	card_node.global_transform = global_trans

	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	engine.connect_card_signals(card_node)
	card_node.set_meta("arc_draw_anim", true)
	engine.hand_cards.append(card_node)
	if engine.has_method("record_match_stat"): engine.record_match_stat(engine.local_player_id, "cards_drawn", 1)

	engine.event_ledger.log_event(GameEventLedger.EventType.CARD_MOVED, {
		"card_name": card_node.card_data.get("name", ""),
		"from_zone": "Library",
		"to_zone": "Hand",
		"player_id": engine.local_player_id
	})

	update_hand_positions(true)
	update_zone_counters()
	if not engine.mulligan_phase_active and engine.turn_manager != null and engine.turn_manager.turn_number >= 1:
		engine.check_and_queue_triggers("DRAW", null, engine.local_player_id)

func draw_opponent_card(player_id: int) -> void:
	var opp_lib: Array = engine.player_libraries.get(player_id, [])
	var opp_hand: Array = engine.player_hands.get(player_id, [])
	var opp_hand_cont: Node3D = engine.player_hand_containers.get(player_id, null)

	if opp_lib.is_empty():
		if not engine.mulligan_phase_active and engine.turn_manager != null and engine.turn_manager.turn_number >= 1:
			engine.drawn_from_empty_library[player_id] = true
			engine.run_state_based_actions()
		return
	EventBus.play_sfx("draw")

	var card_node: Node3D = opp_lib.pop_back()
	if is_instance_valid(card_node):
		if opp_hand_cont:
			var global_trans := card_node.global_transform
			card_node.reparent(opp_hand_cont, true)
			card_node.global_transform = global_trans

		card_node.set_meta("arc_draw_anim", true)
		opp_hand.append(card_node)
		if engine.has_method("record_match_stat"): engine.record_match_stat(player_id, "cards_drawn", 1)
		update_opponent_hand_positions(player_id, true)
		update_zone_counters()
		engine.event_ledger.log_event(GameEventLedger.EventType.CARD_MOVED, {
			"card_name": card_node.card_data.get("name", ""),
			"from_zone": "Library",
			"to_zone": "Hand",
			"player_id": player_id
		})
		if not engine.mulligan_phase_active and engine.turn_manager != null and engine.turn_manager.turn_number >= 1:
			engine.check_and_queue_triggers("DRAW", null, player_id)


func update_opponent_hand_positions(pid: int, animated: bool = false) -> void:
	var opp_hand: Array = engine.player_hands.get(pid, [])
	var hand_size: int = opp_hand.size()
	if animated and hand_size == 0: return
	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) if animated else null
	var total_width := minf(max(0, hand_size - 1) * engine.card_spacing_x, engine.max_hand_width)
	var current_spacing: float = total_width / float(max(1, hand_size - 1)) if hand_size > 1 else engine.card_spacing_x
	var start_x := -total_width / 2.0
	for i in range(hand_size):
		var card_instance: Node3D = opp_hand[i]
		if not is_instance_valid(card_instance): continue
		var target_pos := Vector3(start_x + (i * current_spacing), 0.0, float(i) * 0.002)
		var target_rot := Vector3(deg_to_rad(80.0), 0.0, PI)
		if animated:
			if card_instance.has_meta("arc_draw_anim"):
				card_instance.remove_meta("arc_draw_anim")
				_tween_bezier_arc(card_instance, target_pos, target_rot, 0.48, 0.36)
			else:
				tween.tween_property(card_instance, "position", target_pos, 0.35)
				tween.tween_property(card_instance, "rotation", target_rot, 0.35)
		else:
			card_instance.position = target_pos
			card_instance.rotation = target_rot

func update_hand_positions(animated: bool = false) -> void:
	var hand_size: int = engine.hand_cards.size()
	if animated and hand_size == 0: return

	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) if animated else null
	var total_width := minf(max(0, hand_size - 1) * engine.card_spacing_x, engine.max_hand_width)
	var current_spacing: float = total_width / float(max(1, hand_size - 1)) if hand_size > 1 else engine.card_spacing_x
	var start_x := -total_width / 2.0

	for i in range(hand_size):
		var card_instance: Node3D = engine.hand_cards[i]
		var target_pos := Vector3(start_x + (i * current_spacing), 0.0, float(i) * 0.002)
		var target_rot := Vector3(deg_to_rad(80.0), 0.0, 0.0)

		if animated:
			tween.tween_property(card_instance, "position", target_pos, 0.35)
			tween.tween_property(card_instance, "rotation", target_rot, 0.35)
		else:
			card_instance.position = target_pos
			card_instance.rotation = target_rot

func update_battlefield_positions(animated: bool = false) -> void:
	if animated and engine.battlefield_lands.is_empty() and engine.battlefield_non_lands.is_empty(): return
	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) if animated else null

	# Arrange all 4 seats in their respective station anchors so every player sees every board in its true seat
	for pid in [1, 2, 3, 4]:
		if not engine.player_stations.has(pid): continue
		var st: Dictionary = engine.player_stations[pid]
		var lands_anc: Node3D = st["lands_anchor"]
		var non_lands_anc: Node3D = st["non_lands_anchor"]
		var opp_lands: Array[Node3D] = []
		var opp_non_lands: Array[Node3D] = []
		for c in engine.battlefield_lands:
			if is_instance_valid(c) and engine.get_card_controller_id(c) == pid:
				if c.get_parent() != lands_anc:
					var gt_l: Transform3D = c.global_transform
					c.reparent(lands_anc, true)
					c.global_transform = gt_l
				opp_lands.append(c)
		for c in engine.battlefield_non_lands:
			if is_instance_valid(c) and engine.get_card_controller_id(c) == pid:
				if c.get_parent() != non_lands_anc:
					var gt_n: Transform3D = c.global_transform
					c.reparent(non_lands_anc, true)
					c.global_transform = gt_n
				opp_non_lands.append(c)
		if not opp_lands.is_empty() and lands_anc:
			_arrange_cards_in_row(opp_lands, engine.battlefield_lands_spacing_x, 0.0, 0.0, animated, tween, lands_anc)
		if not opp_non_lands.is_empty() and non_lands_anc:
			_arrange_cards_in_row(opp_non_lands, engine.battlefield_non_lands_spacing_x, 0.0, 0.0, animated, tween, non_lands_anc)

func _get_card_jitter(card: Node3D) -> Dictionary:
	if not is_instance_valid(card):
		return {"dx": 0.0, "dz": 0.0, "dyaw": 0.0}
	if card.has_meta("board_jitter"):
		var cached = card.get_meta("board_jitter")
		if cached is Dictionary: return cached
	var jit := {
		"dx": randf_range(-0.022, 0.022),
		"dz": randf_range(-0.022, 0.022),
		"dyaw": deg_to_rad(randf_range(-2.2, 2.2))
	}
	card.set_meta("board_jitter", jit)
	return jit

func _arrange_cards_in_row(cards: Array[Node3D], spacing: float, y_pos: float, z_pos: float, animated: bool, tween: Tween, parent_anchor: Node3D = null) -> void:
	# Group same-named cards (separated by tapped state) into stacks of up to max_stack_group_size (5)
	var max_per_stack: int = max(1, engine.max_stack_group_size)
	var stacks: Array[Array] = []
	var group_lookup: Dictionary = {} # key -> index of current non-full stack in `stacks`

	for card in cards:
		if not is_instance_valid(card): continue
		var c_name: String = str(card.card_data.get("name", "Card"))
		var key: String = "%s|%s" % [c_name, "T" if card.is_tapped else "U"]

		var placed := false
		if group_lookup.has(key):
			var stack_idx: int = int(group_lookup[key])
			if stacks[stack_idx].size() < max_per_stack:
				stacks[stack_idx].append(card)
				placed = true

		if not placed:
			stacks.append([card])
			group_lookup[key] = stacks.size() - 1

	if stacks.is_empty(): return

	var max_w: float = engine.max_battlefield_width
	var num_stacks: int = stacks.size()
	var row_width: float = minf(float(max(0, num_stacks - 1)) * spacing, max_w)
	var actual_spacing: float = row_width / float(max(1, num_stacks - 1)) if num_stacks > 1 else spacing
	var start_x: float = -row_width / 2.0

	for s_idx in range(num_stacks):
		var stack_cards: Array = stacks[s_idx]
		var base_x: float = start_x + (s_idx * actual_spacing)
		for j in range(stack_cards.size()):
			var card: Node3D = stack_cards[j]
			if parent_anchor != null and card.get_parent() != parent_anchor:
				var gt := card.global_transform
				card.reparent(parent_anchor, true)
				card.global_transform = gt
			var cascade_offset := Vector3(j * 0.04, j * 0.004, j * 0.06)
			var atk_offset := Vector3.ZERO
			if card.is_on_battlefield and bool(card.get("is_attacking")):
				if parent_anchor == null:
					atk_offset = Vector3(0.0, 0.06, -0.65)
				else:
					var dir_local: Vector3 = parent_anchor.to_local(Vector3.ZERO) - parent_anchor.to_local(parent_anchor.global_position)
					dir_local.y = 0.0
					if dir_local.length() > 0.01:
						atk_offset = dir_local.normalized() * 0.65 + Vector3(0.0, 0.06, 0.0)
			var jit := _get_card_jitter(card)
			var target_pos := Vector3(base_x + float(jit["dx"]), y_pos, z_pos + float(jit["dz"])) + cascade_offset + atk_offset
			var target_rot := Vector3(0.0, (deg_to_rad(-90.0) if card.is_tapped else 0.0) + float(jit["dyaw"]), 0.0)
			if animated:
				tween.tween_property(card, "position", target_pos, 0.35)
				tween.tween_property(card, "rotation", target_rot, 0.35)
			else:
				card.position = target_pos
				card.rotation = target_rot
			if "attachments" in card and not card.attachments.is_empty():
				for a_idx in range(card.attachments.size()):
					var att: Node3D = card.attachments[a_idx]
					if not is_instance_valid(att): continue
					if parent_anchor != null and att.get_parent() != parent_anchor:
						var gt_att := att.global_transform
						att.reparent(parent_anchor, true)
						att.global_transform = gt_att
					att.is_tapped = false
					var att_pos := target_pos + Vector3(-0.08 * float(a_idx + 1), -0.004 * float(a_idx + 1), -0.14 * float(a_idx + 1))
					var att_rot := Vector3.ZERO
					if animated and tween:
						tween.tween_property(att, "position", att_pos, 0.35)
						tween.tween_property(att, "rotation", att_rot, 0.35)
					else:
						att.position = att_pos
						att.rotation = att_rot

func remove_from_battlefield(card_node: Node3D) -> void:
	engine.battlefield_lands.erase(card_node)
	engine.battlefield_non_lands.erase(card_node)
	if card_node and is_instance_valid(card_node) and card_node.has_meta("ltb_return_cards"):
		var ltb_arr: Array = card_node.get_meta("ltb_return_cards")
		card_node.remove_meta("ltb_return_cards")
		for ret_c in ltb_arr:
			if is_instance_valid(ret_c):
				move_to_battlefield_from_zone(ret_c, engine.get_card_owner_id(ret_c), false)
	if "attachments" in card_node and not card_node.attachments.is_empty():
		for att in card_node.attachments.duplicate():
			if is_instance_valid(att):
				detach_card(att)
	if card_node.has_meta("control_override_player_id"): card_node.remove_meta("control_override_player_id")
	if "layer_controller_id" in card_node: card_node.layer_controller_id = 0
	if card_node.has_method("clear_counters"): card_node.clear_counters()
	update_battlefield_positions(true)
	engine.run_state_based_actions()

func _destroy_if_token(card_node: Node3D) -> bool:
	if card_node.get("is_token"):
		remove_from_battlefield(card_node)
		engine.active_stack.erase(card_node)
		card_node.queue_free()
		EventBus.notify_stack(engine.active_stack.size())
		return true
	return false

func _erase_from_non_battlefield_zones(card_node: Node3D) -> void:
	engine.graveyard_stack.erase(card_node)
	engine.exile_stack.erase(card_node)
	engine.library_stack.erase(card_node)
	engine.command_zone_cards.erase(card_node)
	engine.active_stack.erase(card_node)
	if card_node in engine.hand_cards:
		engine.hand_cards.erase(card_node)
		update_hand_positions(true)
	for pid in [2, 3, 4]:
		engine.player_graveyards.get(pid, []).erase(card_node)
		engine.player_exile.get(pid, []).erase(card_node)
		engine.player_libraries.get(pid, []).erase(card_node)
		engine.player_command_zones.get(pid, []).erase(card_node)
		var p_hand: Array = engine.player_hands.get(pid, [])
		if card_node in p_hand:
			p_hand.erase(card_node)
			update_opponent_hand_positions(pid, true)

func move_to_hand(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	_erase_from_non_battlefield_zones(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false

	var owner_id: int = engine.get_card_owner_id(card_node)
	var global_trans := card_node.global_transform
	if owner_id == engine.local_player_id:
		card_node.reparent(engine.hand_container, true)
		card_node.global_transform = global_trans
		engine.hand_cards.append(card_node)
		update_hand_positions(true)
	else:
		var opp_cont: Node3D = engine.player_hand_containers.get(owner_id, null)
		if opp_cont:
			card_node.reparent(opp_cont, true)
			card_node.global_transform = global_trans
		engine.player_hands.get(owner_id, []).append(card_node)
		update_opponent_hand_positions(owner_id, true)
	update_zone_counters()

func move_to_top_library(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	_erase_from_non_battlefield_zones(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.has_method("setup_library"): card_node.setup_library()

	var owner_id: int = engine.get_card_owner_id(card_node)
	if owner_id == engine.local_player_id:
		engine.library_stack.append(card_node)
		_animate_to_pile(card_node, engine.library_anchor, (engine.library_stack.size() - 1) * engine.card_thickness)
	else:
		var lib_list: Array = engine.player_libraries.get(owner_id, [])
		lib_list.append(card_node)
		var lib_anc: Node3D = engine.player_stations[owner_id]["library"]
		_animate_to_pile(card_node, lib_anc, (lib_list.size() - 1) * engine.card_thickness)
	update_zone_counters()

func move_to_bottom_library(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	_erase_from_non_battlefield_zones(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.has_method("setup_library"): card_node.setup_library()

	var owner_id: int = engine.get_card_owner_id(card_node)
	var lib_list: Array = engine.library_stack if owner_id == engine.local_player_id else engine.player_libraries.get(owner_id, [])
	var lib_anc: Node3D = engine.library_anchor if owner_id == engine.local_player_id else engine.player_stations[owner_id]["library"]
	lib_list.insert(0, card_node)
	var global_trans := card_node.global_transform
	card_node.reparent(lib_anc, true)
	card_node.global_transform = global_trans

	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(lib_list.size()):
		var c: Node3D = lib_list[i]
		tween.tween_property(c, "position", Vector3(0.0, i * engine.card_thickness, 0.0), 0.35)
		tween.tween_property(c, "quaternion", Quaternion.IDENTITY, 0.35)
	update_zone_counters()

func move_to_command_zone(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	_erase_from_non_battlefield_zones(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false
	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)

	var owner_id: int = engine.get_card_owner_id(card_node)
	var cmd_list: Array = engine.command_zone_cards if owner_id == engine.local_player_id else engine.player_command_zones.get(owner_id, [])
	var cmd_anc: Node3D = engine.command_zone_anchor if owner_id == engine.local_player_id else engine.player_stations[owner_id]["command_zone"]
	if not card_node in cmd_list: cmd_list.append(card_node)

	var global_trans := card_node.global_transform
	card_node.reparent(cmd_anc, true)
	card_node.global_transform = global_trans

	var idx: int = cmd_list.find(card_node)
	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_node, "position", Vector3(idx * 0.7, 0.0, 0.0), 0.35)
	tween.tween_property(card_node, "quaternion", Quaternion.IDENTITY, 0.35)

	update_zone_counters(); update_commander_tax_counter()
	EventBus.notify_stack(engine.active_stack.size())

func move_to_stack(card_node: Node3D) -> void:
	remove_from_battlefield(card_node)
	engine.graveyard_stack.erase(card_node); engine.hand_cards.erase(card_node); engine.command_zone_cards.erase(card_node)
	var owner_id: int = engine.get_card_owner_id(card_node)
	if owner_id != engine.local_player_id:
		engine.player_hands.get(owner_id, []).erase(card_node)
		engine.player_command_zones.get(owner_id, []).erase(card_node)
		update_opponent_hand_positions(owner_id, true)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false
	if card_node.has_method("set_highlight"): card_node.set_highlight(true)

	engine.active_stack.append(card_node)
	engine.turn_manager.priority_passes_count = 0

	var global_trans := card_node.global_transform
	card_node.reparent(engine.central_stack_anchor, true)
	card_node.global_transform = global_trans

	engine.event_ledger.log_event(GameEventLedger.EventType.STACK_PUSHED, {"card_name": card_node.card_data.get("name", "")})
	update_hand_positions(true)

	var idx: int = engine.active_stack.size() - 1
	var target_pos := Vector3(idx * 0.2, idx * 0.03, idx * 0.2)
	var target_rot := Vector3(0, deg_to_rad(idx * 5.0), 0)

	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_node, "position", target_pos, 0.35)
	tween.tween_property(card_node, "rotation", target_rot, 0.35)

	update_zone_counters()
	EventBus.notify_stack(engine.active_stack.size())
	if engine.has_method("record_match_stat"): engine.record_match_stat(engine.get_card_owner_id(card_node), "spells_cast", 1)
	engine.check_and_queue_triggers("CAST", card_node)
	if engine.has_method("on_spell_cast_mechanics"): engine.on_spell_cast_mechanics(card_node)

func _check_commander_redirect(card_node: Node3D, dest_name: String, leave_fn: Callable) -> bool:
	if not card_node or not is_instance_valid(card_node): return false
	if not (card_node.has_meta("is_commander") and bool(card_node.get_meta("is_commander"))): return false
	if card_node.has_meta("cmd_redirect_resolved"):
		card_node.remove_meta("cmd_redirect_resolved")
		return false
	var owner_id: int = engine.get_card_owner_id(card_node)
	if owner_id != engine.local_player_id:
		move_to_command_zone(card_node)
		return true
	if engine.hud_manager and engine.hud_manager.has_method("open_choice_popup"):
		var c_name := str(card_node.card_data.get("name", "Commander"))
		engine.hud_manager.open_choice_popup(
			"COMMANDER ZONE REDIRECT (%s)" % c_name.to_upper(),
			["Return to Command Zone", "Leave in %s" % dest_name],
			func(idx: int):
				if not is_instance_valid(card_node): return
				if idx == 0:
					move_to_command_zone(card_node)
				else:
					card_node.set_meta("cmd_redirect_resolved", true)
					leave_fn.call(card_node)
				engine.sync_network_state()
		)
		return true
	return false

func move_to_graveyard(card_node: Node3D) -> void:
	if card_node and is_instance_valid(card_node):
		var c_owner: int = engine.get_card_owner_id(card_node)
		for p in engine.battlefield_lands + engine.battlefield_non_lands:
			if not is_instance_valid(p) or p == card_node: continue
			var p_ol := str(MagicRules.get_card_attribute(p.card_data, "oracle_text", "")).to_lower()
			if ("would be put into a graveyard" in p_ol or "would be put into an opponent's graveyard" in p_ol or "would die" in p_ol) and "exile it instead" in p_ol:
				var p_ctrl: int = engine.get_card_controller_id(p)
				if "opponent's graveyard" in p_ol and c_owner == p_ctrl: continue
				move_to_exile(card_node)
				return
	if card_node and is_instance_valid(card_node) and card_node.is_on_battlefield and card_node.has_method("get_named_counter") and card_node.get_named_counter("finality") > 0:
		move_to_exile(card_node)
		return
	var was_bf_creature: bool = card_node != null and is_instance_valid(card_node) and card_node.is_on_battlefield and MagicRules.is_creature(card_node.card_data, 0, card_node)
	var pre_ctr: int = int(card_node.get("counter_amount")) if (card_node and "counter_amount" in card_node) else 0
	var pre_ol: String = str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "")).to_lower() if card_node else ""
	if _destroy_if_token(card_node): return
	if _check_commander_redirect(card_node, "Graveyard", func(c): move_to_graveyard(c)): return
	remove_from_battlefield(card_node)
	_erase_from_non_battlefield_zones(card_node)
	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false

	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	if was_bf_creature and not bool(card_node.get("is_token")):
		var has_undying: bool = (card_node.has_method("has_keyword") and bool(card_node.has_keyword("undying"))) or ("undying" in pre_ol)
		var has_persist: bool = (card_node.has_method("has_keyword") and bool(card_node.has_keyword("persist"))) or ("persist" in pre_ol)
		if has_undying and pre_ctr <= 0:
			move_to_battlefield_from_zone(card_node, engine.get_card_owner_id(card_node), false)
			if card_node.has_method("modify_counters"): card_node.modify_counters(1)
			return
		elif has_persist and pre_ctr >= 0:
			move_to_battlefield_from_zone(card_node, engine.get_card_owner_id(card_node), false)
			if card_node.has_method("modify_counters"): card_node.modify_counters(-1)
			return
	var owner_id: int = engine.get_card_owner_id(card_node)
	if owner_id == engine.local_player_id:
		engine.graveyard_stack.append(card_node)
		_animate_to_pile(card_node, engine.graveyard_anchor, (engine.graveyard_stack.size() - 1) * engine.card_thickness, engine.graveyard_stack.size() - 1)
	else:
		var gy_list: Array = engine.player_graveyards.get(owner_id, [])
		gy_list.append(card_node)
		var gy_anc: Node3D = engine.player_stations[owner_id]["graveyard"]
		_animate_to_pile(card_node, gy_anc, (gy_list.size() - 1) * engine.card_thickness, gy_list.size() - 1)
	if card_node.has_method("refresh_visual_status"): card_node.refresh_visual_status()
	update_zone_counters()

func move_to_exile(card_node: Node3D) -> void:
	EventBus.play_sfx("exile")
	if _destroy_if_token(card_node): return
	if _check_commander_redirect(card_node, "Exile", func(c): move_to_exile(c)): return
	remove_from_battlefield(card_node)
	_erase_from_non_battlefield_zones(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false

	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	var owner_id: int = engine.get_card_owner_id(card_node)
	if owner_id == engine.local_player_id:
		engine.exile_stack.append(card_node)
		_animate_to_pile(card_node, engine.exile_anchor, (engine.exile_stack.size() - 1) * engine.card_thickness, engine.exile_stack.size() - 1)
	else:
		var ex_list: Array = engine.player_exile.get(owner_id, [])
		ex_list.append(card_node)
		var ex_anc: Node3D = engine.player_stations[owner_id]["exile"]
		_animate_to_pile(card_node, ex_anc, (ex_list.size() - 1) * engine.card_thickness, ex_list.size() - 1)
	if card_node.has_method("refresh_visual_status"): card_node.refresh_visual_status()
	update_zone_counters()

func _tween_bezier_arc(card_node: Node3D, target_pos: Vector3, target_rot: Vector3, arc_height: float = 0.45, duration: float = 0.34) -> void:
	if not is_instance_valid(card_node) or not is_instance_valid(engine):
		return
	var start_pos: Vector3 = card_node.position
	var start_rot: Vector3 = card_node.rotation
	var ctrl_pos: Vector3 = start_pos.lerp(target_pos, 0.5) + Vector3(0.0, arc_height, 0.0)
	var tw := engine.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float):
		if not is_instance_valid(card_node): return
		var p1 := start_pos.lerp(ctrl_pos, t)
		var p2 := ctrl_pos.lerp(target_pos, t)
		card_node.position = p1.lerp(p2, t)
		card_node.rotation = start_rot.lerp(target_rot, t)
	, 0.0, 1.0, duration)

func _animate_to_pile(card_node: Node3D, anchor: Node3D, y_offset: float, stack_index: int = 0) -> void:
	var global_trans := card_node.global_transform
	card_node.reparent(anchor, true)
	card_node.global_transform = global_trans

	var fan_idx: int = stack_index % 8
	var depth_y: float = maxf(y_offset, float(mini(stack_index, 24)) * 0.0055)
	var yaw_j: float = float(((stack_index * 37) % 9) - 4) * 0.014
	var p_jit := _get_card_jitter(card_node)
	var fan_pos := Vector3(fan_idx * 0.012 + float(p_jit["dx"]) * 0.85, depth_y, fan_idx * 0.014 + float(p_jit["dz"]) * 0.85)
	var target_q := Quaternion(Vector3.UP, yaw_j + float(p_jit["dyaw"]) * 1.35)
	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_node, "position", fan_pos, 0.35)
	tween.tween_property(card_node, "quaternion", target_q, 0.35)

func move_to_battlefield_from_zone(card_node: Node3D, controller_id: int, enter_tapped: bool = false) -> void:
	if not card_node or not is_instance_valid(card_node): return
	engine.graveyard_stack.erase(card_node)
	engine.exile_stack.erase(card_node)
	engine.hand_cards.erase(card_node)
	for pid in [1, 2, 3, 4]:
		engine.player_graveyards.get(pid, []).erase(card_node)
		engine.player_exile.get(pid, []).erase(card_node)
		engine.player_hands.get(pid, []).erase(card_node)
	card_node.set_meta("owner_id", controller_id)

	var is_land_card := MagicRules.is_land(card_node.card_data)
	var target_parent: Node3D = engine
	if controller_id != engine.local_player_id and engine.player_stations.has(controller_id):
		target_parent = engine.player_stations[controller_id]["lands_anchor"] if is_land_card else engine.player_stations[controller_id]["non_lands_anchor"]

	var gt := card_node.global_transform
	card_node.reparent(target_parent, true)
	card_node.global_transform = gt
	card_node.rotation = Vector3.ZERO
	engine.connect_card_signals(card_node)
	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	card_node.is_on_battlefield = true
	if card_node.collision_shape: card_node.collision_shape.disabled = false
	if enter_tapped and not card_node.is_tapped: card_node.toggle_tap()
	elif is_land_card: engine._apply_etb_tapped_replacement(card_node, 0)

	if MagicRules.is_planeswalker(card_node.card_data) and card_node.has_method("modify_named_counter"):
		var start_loy: int = str(MagicRules.get_card_attribute(card_node.card_data, "loyalty", "0")).to_int()
		if start_loy > 0:
			card_node.modify_named_counter("loyalty", start_loy)
	if is_land_card: engine.battlefield_lands.append(card_node)
	else: engine.battlefield_non_lands.append(card_node)
	EventBus.notify_etb(card_node, "Graveyard")
	engine.check_and_queue_triggers("ETB", card_node)
	update_battlefield_positions(true)
	update_zone_counters()
	engine.run_state_based_actions()

func attach_card_to_creature(attachment: Node3D, target_creature: Node3D, pay_equip_cost: bool = false) -> void:
	if not attachment or not target_creature or attachment == target_creature: return

	var type_line := MagicRules.get_card_type_line(attachment.card_data).to_lower()
	if pay_equip_cost and "equipment" in type_line and attachment.is_on_battlefield:
		var equip_cost: String = engine.parse_equip_cost(attachment.card_data.get("oracle_text", ""))
		if not equip_cost.is_empty() and not engine.can_pay_and_drain_cost(equip_cost): return

	if attachment.get("attached_to") != null:
		detach_card(attachment, true)

	if attachment.has_meta("_attach_tween"):
		var old_tw: Variant = attachment.get_meta("_attach_tween")
		if old_tw is Tween and (old_tw as Tween).is_valid():
			(old_tw as Tween).kill()

	engine.battlefield_non_lands.erase(attachment); engine.active_stack.erase(attachment)
	if attachment in engine.hand_cards: engine.hand_cards.erase(attachment); update_hand_positions(true)

	attachment.attached_to = target_creature
	if not attachment in target_creature.attachments: target_creature.attachments.append(attachment)

	attachment.is_on_battlefield = true; attachment.is_tapped = false
	attachment.visible = true
	if attachment.collision_shape: attachment.collision_shape.disabled = false

	var host_parent: Node = target_creature.get_parent() if target_creature.get_parent() != null else engine
	if attachment.get_parent() != host_parent:
		var gt_att := attachment.global_transform
		attachment.reparent(host_parent, true)
		attachment.global_transform = gt_att

	engine.hud_manager.cancel_attachment_targeting()
	update_battlefield_positions(true)
	engine.run_state_based_actions()

func detach_card(attachment: Node3D, skip_layout: bool = false) -> void:
	if not attachment: return
	var host_creature: Node3D = attachment.get("attached_to")
	if host_creature and is_instance_valid(host_creature) and "attachments" in host_creature:
		host_creature.attachments.erase(attachment)
	attachment.attached_to = null

	var type_line := MagicRules.get_card_type_line(attachment.card_data).to_lower()
	if "aura" in type_line and not skip_layout:
		move_to_graveyard(attachment)
	elif not skip_layout:
		var global_trans := attachment.global_transform
		attachment.reparent(engine, true)
		attachment.global_transform = global_trans
		if not attachment in engine.battlefield_non_lands: engine.battlefield_non_lands.append(attachment)
		update_battlefield_positions(true)
