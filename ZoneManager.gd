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
		var total_casts := 0
		for c in engine.command_zone_cards:
			total_casts += int(engine.commander_cast_counts.get(c, 0))
		engine.commander_count_label.text = str(total_casts) if total_casts > 0 else "0"

func untap_single_card(card_node: Node3D) -> void:
	if card_node:
		card_node.is_tapped = false
		engine.event_ledger.log_event(GameEventLedger.EventType.CARD_UNTAPPED, {"card_name": card_node.card_data.get("name", "")})
		update_battlefield_positions(true)

func untap_all(target_player_id: int = 1) -> void:
	for card in engine.battlefield_lands:
		if is_instance_valid(card) and engine.get_card_owner_id(card) == target_player_id:
			card.is_tapped = false
			card.has_summoning_sickness = false
	for card in engine.battlefield_non_lands:
		if is_instance_valid(card) and engine.get_card_owner_id(card) == target_player_id:
			card.is_tapped = false
			card.has_summoning_sickness = false

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
	if engine.library_stack.is_empty(): return
	EventBus.play_sfx("draw")
	var card_node: Node3D = engine.library_stack.pop_back()
	var global_trans := card_node.global_transform
	card_node.reparent(engine.hand_container, true)
	card_node.global_transform = global_trans

	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	engine.connect_card_signals(card_node)
	engine.hand_cards.append(card_node)

	engine.event_ledger.log_event(GameEventLedger.EventType.CARD_MOVED, {
		"card_name": card_node.card_data.get("name", ""),
		"from_zone": "Library",
		"to_zone": "Hand",
		"player_id": engine.local_player_id
	})

	update_hand_positions(true)
	update_zone_counters()

func draw_opponent_card(player_id: int) -> void:
	var opp_lib: Array = engine.player_libraries.get(player_id, [])
	var opp_hand: Array = engine.player_hands.get(player_id, [])
	var opp_hand_cont: Node3D = engine.player_hand_containers.get(player_id, null)

	if opp_lib.is_empty(): return
	EventBus.play_sfx("draw")

	var card_node: Node3D = opp_lib.pop_back()
	if is_instance_valid(card_node):
		if opp_hand_cont:
			var global_trans := card_node.global_transform
			card_node.reparent(opp_hand_cont, true)
			card_node.global_transform = global_trans

		opp_hand.append(card_node)
		update_opponent_hand_positions(player_id, true)
		update_zone_counters()
		engine.event_ledger.log_event(GameEventLedger.EventType.CARD_MOVED, {
			"card_name": card_node.card_data.get("name", ""),
			"from_zone": "Library",
			"to_zone": "Hand",
			"player_id": player_id
		})


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

	# Player 1 (Local) — untouched
	var p1_lands: Array[Node3D] = []
	var p1_non_lands: Array[Node3D] = []
	for c in engine.battlefield_lands:
		if is_instance_valid(c) and engine.get_card_owner_id(c) == engine.local_player_id: p1_lands.append(c)
	for c in engine.battlefield_non_lands:
		if is_instance_valid(c) and engine.get_card_owner_id(c) == engine.local_player_id: p1_non_lands.append(c)

	_arrange_cards_in_row(p1_lands, engine.battlefield_lands_spacing_x, engine.battlefield_lands_y, engine.battlefield_lands_z, animated, tween)
	_arrange_cards_in_row(p1_non_lands, engine.battlefield_non_lands_spacing_x, engine.battlefield_non_lands_y, engine.battlefield_non_lands_z, animated, tween)

	# Players 2-4 — arranged in their station anchors
	for pid in [2, 3, 4]:
		if not engine.player_stations.has(pid): continue
		var st: Dictionary = engine.player_stations[pid]
		var lands_anc: Node3D = st["lands_anchor"]
		var non_lands_anc: Node3D = st["non_lands_anchor"]
		var opp_lands: Array[Node3D] = []
		var opp_non_lands: Array[Node3D] = []
		for c in engine.battlefield_lands:
			if is_instance_valid(c) and engine.get_card_owner_id(c) == pid: opp_lands.append(c)
		for c in engine.battlefield_non_lands:
			if is_instance_valid(c) and engine.get_card_owner_id(c) == pid: opp_non_lands.append(c)
		if not opp_lands.is_empty() and lands_anc:
			_arrange_cards_in_row(opp_lands, engine.battlefield_lands_spacing_x, 0.0, 0.0, animated, tween, lands_anc)
		if not opp_non_lands.is_empty() and non_lands_anc:
			_arrange_cards_in_row(opp_non_lands, engine.battlefield_non_lands_spacing_x, 0.0, 0.0, animated, tween, non_lands_anc)

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
			var target_pos := Vector3(base_x, y_pos, z_pos) + cascade_offset + atk_offset
			var target_rot := Vector3(0.0, deg_to_rad(-90.0) if card.is_tapped else 0.0, 0.0)
			if animated:
				tween.tween_property(card, "position", target_pos, 0.35)
				tween.tween_property(card, "rotation", target_rot, 0.35)
			else:
				card.position = target_pos
				card.rotation = target_rot

func remove_from_battlefield(card_node: Node3D) -> void:
	engine.battlefield_lands.erase(card_node)
	engine.battlefield_non_lands.erase(card_node)
	if "attachments" in card_node and not card_node.attachments.is_empty():
		for att in card_node.attachments.duplicate():
			if is_instance_valid(att):
				detach_card(att)
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

func move_to_hand(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	engine.graveyard_stack.erase(card_node)
	engine.exile_stack.erase(card_node)
	for pid in [2, 3, 4]:
		engine.player_graveyards.get(pid, []).erase(card_node)
		engine.player_exile.get(pid, []).erase(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false

	var global_trans := card_node.global_transform
	card_node.reparent(engine.hand_container, true)
	card_node.global_transform = global_trans

	engine.hand_cards.append(card_node)
	update_hand_positions(true)
	update_zone_counters()

func move_to_top_library(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	engine.graveyard_stack.erase(card_node); engine.hand_cards.erase(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.has_method("setup_library"): card_node.setup_library()

	engine.library_stack.append(card_node)
	_animate_to_pile(card_node, engine.library_anchor, (engine.library_stack.size() - 1) * engine.card_thickness)
	update_hand_positions(true); update_zone_counters()

func move_to_bottom_library(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	engine.graveyard_stack.erase(card_node); engine.hand_cards.erase(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.has_method("setup_library"): card_node.setup_library()

	engine.library_stack.insert(0, card_node)
	var global_trans := card_node.global_transform
	card_node.reparent(engine.library_anchor, true)
	card_node.global_transform = global_trans

	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in range(engine.library_stack.size()):
		var c: Node3D = engine.library_stack[i]
		tween.tween_property(c, "position", Vector3(0.0, i * engine.card_thickness, 0.0), 0.35)
		tween.tween_property(c, "quaternion", Quaternion.IDENTITY, 0.35)
	update_hand_positions(true); update_zone_counters()

func move_to_command_zone(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	remove_from_battlefield(card_node)
	engine.graveyard_stack.erase(card_node); engine.active_stack.erase(card_node)
	if card_node in engine.hand_cards: engine.hand_cards.erase(card_node); update_hand_positions(true)

	if not card_node in engine.command_zone_cards: engine.command_zone_cards.append(card_node)

	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false

	var global_trans := card_node.global_transform
	card_node.reparent(engine.command_zone_anchor, true)
	card_node.global_transform = global_trans

	var idx: int = engine.command_zone_cards.find(card_node)
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
	engine.check_and_queue_triggers("CAST", card_node)

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
		)
		return true
	return false

func move_to_graveyard(card_node: Node3D) -> void:
	if _destroy_if_token(card_node): return
	if _check_commander_redirect(card_node, "Graveyard", func(c): move_to_graveyard(c)): return
	remove_from_battlefield(card_node)
	card_node.is_on_battlefield = false; card_node.is_tapped = false
	if card_node.collision_shape: card_node.collision_shape.disabled = false

	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
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
	engine.graveyard_stack.erase(card_node); engine.library_stack.erase(card_node)
	if card_node in engine.hand_cards: engine.hand_cards.erase(card_node); update_hand_positions(true)

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

func _animate_to_pile(card_node: Node3D, anchor: Node3D, y_offset: float, stack_index: int = 0) -> void:
	var global_trans := card_node.global_transform
	card_node.reparent(anchor, true)
	card_node.global_transform = global_trans

	var fan_idx: int = stack_index % 8
	var fan_pos := Vector3(fan_idx * 0.014, y_offset, fan_idx * 0.016)
	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_node, "position", fan_pos, 0.35)
	tween.tween_property(card_node, "quaternion", Quaternion.IDENTITY, 0.35)

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

	if is_land_card: engine.battlefield_lands.append(card_node)
	else: engine.battlefield_non_lands.append(card_node)
	EventBus.notify_etb(card_node, "Graveyard")
	engine.check_and_queue_triggers("ETB", card_node)
	update_battlefield_positions(true)
	update_zone_counters()
	engine.run_state_based_actions()

func attach_card_to_creature(attachment: Node3D, target_creature: Node3D, pay_equip_cost: bool = false) -> void:
	if not attachment or not target_creature: return

	var type_line := MagicRules.get_card_type_line(attachment.card_data).to_lower()
	if pay_equip_cost and "equipment" in type_line and attachment.is_on_battlefield:
		var equip_cost: String = engine.parse_equip_cost(attachment.card_data.get("oracle_text", ""))
		if not equip_cost.is_empty() and not engine.can_pay_and_drain_cost(equip_cost): return

	if attachment.get("attached_to") != null: detach_card(attachment)

	engine.battlefield_non_lands.erase(attachment); engine.active_stack.erase(attachment)
	if attachment in engine.hand_cards: engine.hand_cards.erase(attachment); update_hand_positions(true)

	attachment.attached_to = target_creature
	if not attachment in target_creature.attachments: target_creature.attachments.append(attachment)

	attachment.is_on_battlefield = true; attachment.is_tapped = false
	if attachment.collision_shape: attachment.collision_shape.disabled = false

	attachment.reparent(target_creature, true)
	var attach_idx: int = target_creature.attachments.find(attachment)
	var target_local_pos := Vector3(-0.11 - (attach_idx * 0.05), -0.003 * (attach_idx + 1), -0.14 - (attach_idx * 0.05))

	var tween := engine.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(attachment, "position", target_local_pos, 0.3)
	tween.tween_property(attachment, "quaternion", Quaternion.IDENTITY, 0.3)

	engine.hud_manager.cancel_attachment_targeting()
	update_battlefield_positions(true)
	engine.run_state_based_actions()

func detach_card(attachment: Node3D) -> void:
	if not attachment: return
	var host_creature: Node3D = attachment.get("attached_to")
	if host_creature and "attachments" in host_creature:
		host_creature.attachments.erase(attachment)
	attachment.attached_to = null

	var type_line := MagicRules.get_card_type_line(attachment.card_data).to_lower()
	if "aura" in type_line:
		move_to_graveyard(attachment)
	else:
		var global_trans := attachment.global_transform
		attachment.reparent(engine, true)
		attachment.global_transform = global_trans
		if not attachment in engine.battlefield_non_lands: engine.battlefield_non_lands.append(attachment)
		update_battlefield_positions(true)
