class_name AIController
extends Node

var engine: Node = null
var _is_thinking: bool = false
var _responded_stack_ids: Dictionary = {}

func setup(main_engine: Node) -> void:
	engine = main_engine

func should_ai_act_on_priority(pid: int) -> bool:
	if not engine or not engine.turn_manager.auto_pass_opponents:
		return false
	if engine.is_human_seat(pid):
		return false
	var tm: TurnManager = engine.turn_manager
	if not engine.active_stack.is_empty():
		return _can_ai_respond_to_stack(pid)
	if tm.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_BLOCKERS and tm.active_player_id != pid:
		return _can_ai_cast_combat_instant(pid)
	if tm.active_player_id != pid:
		return false
	return (
		tm.current_turn_phase == TurnManager.TurnPhase.PRECOMBAT_MAIN
		or tm.current_turn_phase == TurnManager.TurnPhase.POSTCOMBAT_MAIN
		or tm.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS
	)

func schedule_ai_action(pid: int) -> void:
	if _is_thinking:
		return
	_is_thinking = true
	var tree := get_tree()
	if tree == null:
		_is_thinking = false
		return
	tree.create_timer(0.4).timeout.connect(func():
		_is_thinking = false
		if not is_instance_valid(engine): return
		var tm: TurnManager = engine.turn_manager
		if not tm.auto_pass_opponents or tm.priority_player_id != pid: return
		_execute_ai_step(pid)
	)

func _execute_ai_step(pid: int) -> void:
	var tm: TurnManager = engine.turn_manager
	if not engine.active_stack.is_empty():
		_run_ai_stack_response(pid)
		tm.pass_priority()
		return
	if tm.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_BLOCKERS and tm.active_player_id != pid:
		_run_ai_combat_instant(pid)
		tm.pass_priority()
		return
	match tm.current_turn_phase:
		TurnManager.TurnPhase.PRECOMBAT_MAIN, TurnManager.TurnPhase.POSTCOMBAT_MAIN:
			_run_ai_main_phase(pid)
		TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS:
			_run_ai_attackers(pid)
	tm.pass_priority()

func _can_ai_respond_to_stack(pid: int) -> bool:
	if engine.active_stack.is_empty(): return false
	var top_item = engine.active_stack[-1]
	if not (top_item is Node3D) or not is_instance_valid(top_item): return false
	if engine.get_card_owner_id(top_item) == pid: return false
	var item_id: int = top_item.get_instance_id()
	if _responded_stack_ids.has(item_id): return false
	for card in engine.player_hands.get(pid, []):
		if not is_instance_valid(card): continue
		var tl := MagicRules.get_card_type_line(card.card_data).to_lower()
		var ol := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_lower()
		if "instant" in tl and "counter target" in ol:
			return true
	return false

func _run_ai_stack_response(pid: int) -> void:
	if engine.active_stack.is_empty(): return
	var top_item = engine.active_stack[-1]
	if not (top_item is Node3D) or not is_instance_valid(top_item): return
	var item_id: int = top_item.get_instance_id()
	_responded_stack_ids[item_id] = true
	if engine.get_card_owner_id(top_item) == pid: return

	for card in engine.player_hands.get(pid, []).duplicate():
		if not is_instance_valid(card): continue
		var tl := MagicRules.get_card_type_line(card.card_data).to_lower()
		var ol := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_lower()
		if not ("instant" in tl and "counter target" in ol): continue
		var req := OracleParser.extract_target_requirement(ol)
		if not MagicRules.is_legal_target(top_item, req, pid, card): continue
		var mana_cost := str(card.card_data.get("mana_cost", ""))
		if engine.can_pay_and_drain_cost(mana_cost, pid):
			card.set_meta("chosen_target", top_item)
			card.set_meta("target_requirement", req)
			if card.has_method("make_active"): card.make_active(card.card_data)
			engine.zone_manager.move_to_stack(card)
			return

func _run_ai_main_phase(pid: int) -> void:
	if not engine.turn_manager.can_act_sorcery_speed(pid):
		return
	var opp_hand: Array = engine.player_hands.get(pid, [])

	# 1. Play up to 1 land if not played this turn
	if not engine.land_played_this_turn:
		for card in opp_hand.duplicate():
			if not is_instance_valid(card): continue
			if MagicRules.is_land(card.card_data):
				_play_ai_land(card, pid)
				break

	# 2. Cast at most 1 sorcery-speed spell per priority window (stack must resolve before casting another!)
	var candidates: Array = []
	for card in engine.player_hands.get(pid, []):
		if is_instance_valid(card) and not MagicRules.is_land(card.card_data):
			candidates.append(card)
	for cmd in engine.player_command_zones.get(pid, []):
		if is_instance_valid(cmd) and not cmd.is_on_battlefield:
			candidates.append(cmd)

	candidates.sort_custom(func(a: Node3D, b: Node3D): return _score_ai_cast_priority(a, pid) > _score_ai_cast_priority(b, pid))
	for card in candidates:
		var type_line := MagicRules.get_card_type_line(card.card_data).to_lower()
		var oracle_lower := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_lower()
		if "instant" in type_line and not MagicRules.can_cast_at_instant_speed(card.card_data, 0, pid, engine):
			continue
		if ("sorcery" in type_line or "aura" in type_line) and ("target" in oracle_lower or "aura" in type_line):
			var tgt: Variant = pick_ai_target(pid, oracle_lower)
			if tgt == null: continue
			card.set_meta("chosen_target", tgt)
			if "target" in oracle_lower:
				card.set_meta("target_requirement", OracleParser.extract_target_requirement(oracle_lower))
		elif not ("sorcery" in type_line or "creature" in type_line or "artifact" in type_line or "enchantment" in type_line or "planeswalker" in type_line):
			continue

		var raw_cost: String = engine.get_taxed_mana_cost(card) if (card in engine.player_command_zones.get(pid, [])) else str(card.card_data.get("mana_cost", ""))
		var red := ContinuousEffectsEngine.get_cost_reduction(card.card_data, pid, engine.battlefield_lands, engine.battlefield_non_lands)
		var mana_cost := ContinuousEffectsEngine.apply_cost_reduction(raw_cost, red)
		var x_count := OracleParser.count_x_in_mana_cost(mana_cost)
		if x_count > 0:
			var max_x: int = engine.get_max_available_x(mana_cost, pid)
			if max_x <= 0:
				continue
			card.set_meta("chosen_x", max_x)
			mana_cost = mana_cost.replace("{X}", "").replace("{x}", "")
			if max_x * x_count > 0:
				mana_cost = "{%d}%s" % [max_x * x_count, mana_cost]
		if engine.can_pay_and_drain_cost(mana_cost, pid, {"type_line": type_line, "is_commander": card in engine.player_command_zones.get(pid, []), "is_activated": false}):
			if card.has_method("make_active"):
				card.make_active(card.card_data)
			if card in engine.player_command_zones.get(pid, []):
				engine.commander_cast_counts[card] = int(engine.commander_cast_counts.get(card, 0)) + 1
			engine.zone_manager.move_to_stack(card)
			return

	# 3. Equip unattached Equipment onto best AI creature (only if stack is still empty)
	if engine.active_stack.is_empty():
		_equip_ai_equipment(pid)

func _score_ai_cast_priority(card: Node3D, pid: int) -> int:
	var tl := MagicRules.get_card_type_line(card.card_data).to_lower()
	var score := 10
	if card in engine.player_command_zones.get(pid, []): score += 35
	if "artifact" in tl and ("add " in str(card.card_data.get("oracle_text", "")).to_lower() or "equipment" in tl): score += 25
	if "creature" in tl: score += 20
	if "planeswalker" in tl: score += 18
	if "sorcery" in tl: score += 12
	return score

func _equip_ai_equipment(pid: int) -> void:
	var my_creatures: Array[Node3D] = []
	var unattached_equip: Array[Node3D] = []
	for c in engine.battlefield_non_lands:
		if not is_instance_valid(c) or not c.is_on_battlefield: continue
		if engine.get_card_owner_id(c) != pid: continue
		var tl := MagicRules.get_card_type_line(c.card_data).to_lower()
		if MagicRules.is_creature(c.card_data):
			my_creatures.append(c)
		elif "equipment" in tl and c.get("attached_to") == null:
			unattached_equip.append(c)
	if my_creatures.is_empty() or unattached_equip.is_empty(): return
	my_creatures.sort_custom(func(a: Node3D, b: Node3D): return int(a.dynamic_power) > int(b.dynamic_power))
	var host := my_creatures[0]
	for eq in unattached_equip:
		var equip_cost: String = engine.parse_equip_cost(str(eq.card_data.get("oracle_text", "")))
		if equip_cost.is_empty(): equip_cost = "{1}"
		if engine.can_pay_and_drain_cost(equip_cost, pid):
			engine.zone_manager.attach_card_to_creature(eq, host, false)

func _play_ai_land(card_node: Node3D, pid: int) -> void:
	engine.land_played_this_turn = true
	var opp_hand: Array = engine.player_hands.get(pid, [])
	opp_hand.erase(card_node)
	engine.zone_manager.update_opponent_hand_positions(pid, true)

	if card_node.has_method("make_active"):
		card_node.make_active(card_node.card_data)
	card_node.rotation = Vector3.ZERO
	engine.connect_card_signals(card_node)

	var lands_anc: Node3D = engine.player_stations[pid]["lands_anchor"]
	var gt := card_node.global_transform
	card_node.reparent(lands_anc, true)
	card_node.global_transform = gt

	card_node.is_on_battlefield = true
	if card_node.collision_shape: card_node.collision_shape.disabled = false
	engine._apply_etb_tapped_replacement(card_node, 0)

	engine.battlefield_lands.append(card_node)
	EventBus.notify_etb(card_node, "Hand")
	engine.check_and_queue_triggers("ETB", card_node)
	engine.zone_manager.update_battlefield_positions(true)
	engine.run_state_based_actions()

func _run_ai_attackers(pid: int) -> void:
	var target_pid := _pick_target_opponent(pid)
	if target_pid <= 0 or target_pid == pid: return

	var opp_blockers: Array[Node3D] = []
	for c in engine.battlefield_non_lands:
		if is_instance_valid(c) and c.is_on_battlefield and engine.get_card_owner_id(c) == target_pid and MagicRules.is_creature(c.card_data) and not c.is_tapped:
			opp_blockers.append(c)

	var declared_any := false
	for card in engine.battlefield_non_lands:
		if not is_instance_valid(card) or not card.is_on_battlefield: continue
		if engine.get_card_owner_id(card) != pid: continue
		if not MagicRules.is_creature(card.card_data): continue
		if card.is_tapped: continue
		var has_haste: bool = card.has_method("has_keyword") and bool(card.has_keyword("haste"))
		if card.has_summoning_sickness and not has_haste: continue
		if card.has_method("has_keyword") and bool(card.has_keyword("defender")): continue
		if int(card.dynamic_power) <= 0: continue

		# Evaluate whether attack is favorable
		var is_evasive: bool = card.has_method("has_keyword") and (bool(card.has_keyword("flying")) or bool(card.has_keyword("menace")) or bool(card.has_keyword("indestructible")) or bool(card.has_keyword("deathtouch")))
		var can_be_eaten_free := false
		if not is_evasive:
			for blk in opp_blockers:
				var outcome := CombatManager._compute_combat_outcome(card, blk)
				if bool(outcome["atk_dies"]) and not bool(outcome["blk_dies"]):
					can_be_eaten_free = true
					break
		if can_be_eaten_free: continue

		card.set("is_attacking", true)
		card.set("attacking_target_player_id", target_pid)
		if card.has_method("set_combat_status"):
			card.set_combat_status("ATK -> %s" % engine.get_player_display_name(target_pid))
		var has_vigilance: bool = card.has_method("has_keyword") and bool(card.has_keyword("vigilance"))
		if not has_vigilance and not card.is_tapped:
			card.toggle_tap()
		EventBus.combat_declared.emit(card, target_pid)
		declared_any = true

	if declared_any:
		engine.zone_manager.update_battlefield_positions(true)

func assign_ai_blockers() -> void:
	var active_pid: int = engine.turn_manager.active_player_id
	for pid in [1, 2, 3, 4]:
		if pid == active_pid or engine.is_human_seat(pid): continue

		var incoming: Array[Node3D] = []
		for card in engine.battlefield_non_lands:
			if is_instance_valid(card) and bool(card.get("is_attacking")) and int(card.get("attacking_target_player_id")) == pid:
				incoming.append(card)
		if incoming.is_empty(): continue
		incoming.sort_custom(func(a: Node3D, b: Node3D): return int(a.dynamic_power) > int(b.dynamic_power))

		var defenders: Array[Node3D] = []
		for card in engine.battlefield_non_lands:
			if not is_instance_valid(card) or not card.is_on_battlefield: continue
			if engine.get_card_owner_id(card) != pid: continue
			if not MagicRules.is_creature(card.card_data) or card.is_tapped or bool(card.get("is_blocking")): continue
			defenders.append(card)

		var my_life: int = int(engine.player_life.get(pid, 40))
		for atk in incoming:
			var atk_flying: bool = atk.has_method("has_keyword") and bool(atk.has_keyword("flying"))
			var atk_menace: bool = atk.has_method("has_keyword") and bool(atk.has_keyword("menace"))
			var valid_defs: Array[Node3D] = []
			for d in defenders:
				var can_reach: bool = d.has_method("has_keyword") and (bool(d.has_keyword("flying")) or bool(d.has_keyword("reach")))
				if not atk_flying or can_reach:
					valid_defs.append(d)

			var needed := 2 if atk_menace else 1
			if valid_defs.size() < needed: continue

			# Score candidate blockers using CombatManager._compute_combat_outcome
			valid_defs.sort_custom(func(a: Node3D, b: Node3D):
				return _score_blocker(atk, a, my_life) > _score_blocker(atk, b, my_life)
			)
			if _score_blocker(atk, valid_defs[0], my_life) <= 0:
				continue

			for i in range(needed):
				var blk: Node3D = valid_defs[i]
				defenders.erase(blk)
				blk.set("is_blocking", true)
				blk.set("blocking_target_creature", atk)
				if blk.has_method("set_combat_status"):
					blk.set_combat_status(CombatManager.get_combat_badge_tag(atk, blk))
				EventBus.blocker_declared.emit(blk, atk)

func _score_blocker(atk: Node3D, blk: Node3D, my_life: int) -> int:
	var res := CombatManager._compute_combat_outcome(atk, blk)
	var atk_dies := bool(res["atk_dies"])
	var blk_dies := bool(res["blk_dies"])
	var is_cmd := blk.has_meta("is_commander") and bool(blk.get_meta("is_commander"))
	var atk_pow: int = int(res["atk_pow"])
	if atk_dies and not blk_dies: return 100
	if atk_dies and blk_dies:
		return 60 if not is_cmd else (40 if atk_pow >= 4 else 10)
	if atk_pow >= my_life or atk_pow >= int(my_life * 0.25):
		return 25 if not is_cmd else 5
	return -10

func _pick_target_opponent(my_pid: int) -> int:
	var best_pid := -1
	var best_life := -9999
	for pid in [1, 2, 3, 4]:
		if pid == my_pid: continue
		var life_val: int = int(engine.player_life.get(pid, 0))
		if life_val > 0 and life_val > best_life:
			best_life = life_val
			best_pid = pid
	return best_pid

func pick_ai_target(ai_pid: int, effect_lower: String) -> Variant:
	if "creature you control" in effect_lower:
		var best_own: Node3D = null
		var best_p := -1
		for c in engine.battlefield_non_lands:
			if is_instance_valid(c) and c.is_on_battlefield and MagicRules.is_creature(c.card_data) and engine.get_card_owner_id(c) == ai_pid:
				if int(c.dynamic_power) > best_p:
					best_p = int(c.dynamic_power)
					best_own = c
		return best_own
	if "creature" in effect_lower or "permanent" in effect_lower:
		var best_opp: Node3D = null
		var best_threat := -1
		for c in engine.battlefield_non_lands:
			if is_instance_valid(c) and c.is_on_battlefield and MagicRules.is_creature(c.card_data) and engine.get_card_owner_id(c) != ai_pid:
				var threat: int = int(c.dynamic_power) + int(c.dynamic_toughness) + (5 if (c.has_meta("is_commander") and bool(c.get_meta("is_commander"))) else 0)
				if threat > best_threat:
					best_threat = threat
					best_opp = c
		return best_opp
	return _pick_target_opponent(ai_pid)

func _can_ai_cast_combat_instant(pid: int) -> bool:
	for card in engine.player_hands.get(pid, []):
		if not is_instance_valid(card): continue
		if not MagicRules.can_cast_at_instant_speed(card.card_data, 0, pid, engine): continue
		var ol := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_lower()
		if "destroy target" in ol or "exile target" in ol or "deals " in ol:
			return true
	return false

func _run_ai_combat_instant(pid: int) -> void:
	for card in engine.player_hands.get(pid, []).duplicate():
		if not is_instance_valid(card): continue
		if not MagicRules.can_cast_at_instant_speed(card.card_data, 0, pid, engine): continue
		var ol := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_lower()
		if not ("destroy target" in ol or "exile target" in ol or "deals " in ol): continue
		var tgt: Variant = pick_ai_target(pid, ol)
		if tgt == null: continue
		var raw_cost := str(card.card_data.get("mana_cost", ""))
		var red := ContinuousEffectsEngine.get_cost_reduction(card.card_data, pid, engine.battlefield_lands, engine.battlefield_non_lands)
		var mana_cost := ContinuousEffectsEngine.apply_cost_reduction(raw_cost, red)
		if engine.can_pay_and_drain_cost(mana_cost, pid):
			card.set_meta("chosen_target", tgt)
			card.set_meta("target_requirement", OracleParser.extract_target_requirement(ol))
			if card.has_method("make_active"): card.make_active(card.card_data)
			engine.zone_manager.move_to_stack(card)
			return
