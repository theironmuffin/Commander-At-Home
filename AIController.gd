class_name AIController
extends Node

enum Difficulty { CASUAL, TUNED, CEDH }

var engine: Node = null
var difficulty: int = Difficulty.TUNED
var _is_thinking: bool = false
var _ai_free_actions_this_turn: int = 0
var _ai_last_turn_num: int = -1
var _responded_stack_ids: Dictionary = {}

func setup(main_engine: Node) -> void:
	engine = main_engine

func should_ai_act_on_priority(pid: int) -> bool:
	if not engine:
		return false
	if engine.is_network_multiplayer() and not engine.network_manager.is_hosting:
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
	tree.create_timer(0.65).timeout.connect(func():
		_is_thinking = false
		if not is_instance_valid(engine): return
		var tm: TurnManager = engine.turn_manager
		if tm.priority_player_id != pid: return
		if engine.has_method("is_decision_popup_open") and engine.is_decision_popup_open():
			schedule_ai_action(pid)
			return
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
	var took_free_action := false
	match tm.current_turn_phase:
		TurnManager.TurnPhase.PRECOMBAT_MAIN, TurnManager.TurnPhase.POSTCOMBAT_MAIN:
			took_free_action = _run_ai_main_phase(pid)
		TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS:
			_run_ai_attackers(pid)
	if engine.is_network_multiplayer() and engine.network_manager.is_hosting and engine.has_method("sync_network_state"):
		engine.sync_network_state()
	if tm.turn_number != _ai_last_turn_num:
		_ai_last_turn_num = tm.turn_number
		_ai_free_actions_this_turn = 0
	if took_free_action and engine.active_stack.is_empty() and _ai_free_actions_this_turn < 12:
		_ai_free_actions_this_turn += 1
		schedule_ai_action(pid)
	else:
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

	var top_ol := str(MagicRules.get_card_attribute(top_item.card_data, "oracle_text", "")).to_lower()
	var top_cmc := float(top_item.card_data.get("cmc", 0.0))
	var top_is_cmd: bool = top_item.has_meta("is_commander") and bool(top_item.get_meta("is_commander"))
	var is_high_threat: bool = top_is_cmd or top_cmc >= 4.0 or "destroy all" in top_ol or "exile all" in top_ol or "extra turn" in top_ol or "search your library" in top_ol
	if difficulty == Difficulty.CASUAL and not is_high_threat and randf() > 0.45:
		return
	elif difficulty == Difficulty.TUNED and not is_high_threat and top_cmc < 3.0:
		return
	elif difficulty == Difficulty.CEDH and not is_high_threat and top_cmc < 2.0:
		return

	for card in engine.player_hands.get(pid, []).duplicate():
		if not is_instance_valid(card): continue
		var tl := MagicRules.get_card_type_line(card.card_data).to_lower()
		var ol := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_lower()
		if not ("instant" in tl and "counter target" in ol): continue
		var req := OracleParser.extract_target_requirement(ol)
		if not MagicRules.is_legal_target(top_item, req, pid, card): continue
		if MagicRules.is_spell_uncounterable(top_item, engine): continue
		var mana_cost := str(card.card_data.get("mana_cost", ""))
		if engine.can_pay_and_drain_cost(mana_cost, pid):
			card.set_meta("chosen_target", top_item)
			card.set_meta("target_requirement", req)
			if card.has_method("make_active"): card.make_active(card.card_data)
			engine.zone_manager.move_to_stack(card)
			return

func _run_ai_main_phase(pid: int) -> bool:
	if not engine.turn_manager.can_act_sorcery_speed(pid):
		return false
	var opp_hand: Array = engine.player_hands.get(pid, [])

	# 1. Play 1 land and pause before casting spells so human players can follow each action
	if not engine.land_played_this_turn:
		for card in opp_hand.duplicate():
			if not is_instance_valid(card): continue
			if MagicRules.is_land(card.card_data):
				_play_ai_land(card, pid)
				return true

	# 2. Cast at most 1 sorcery-speed spell per priority window (stack must resolve before casting another!)
	var candidates: Array = []
	for card in engine.player_hands.get(pid, []):
		if is_instance_valid(card) and not MagicRules.is_land(card.card_data):
			candidates.append(card)
	for cmd in engine.player_command_zones.get(pid, []):
		if is_instance_valid(cmd) and not cmd.is_on_battlefield:
			candidates.append(cmd)

	candidates.sort_custom(func(a: Node3D, b: Node3D): return _score_ai_cast_priority(a, pid) > _score_ai_cast_priority(b, pid))
	var my_pow := 0
	var max_opp_pow := 0
	var opp_pows := {}
	for p_c in engine.battlefield_non_lands:
		if not is_instance_valid(p_c) or not p_c.is_on_battlefield or not MagicRules.is_creature(p_c.card_data): continue
		var p_own: int = engine.get_card_owner_id(p_c)
		var pw: int = maxi(0, int(p_c.dynamic_power))
		if p_own == pid: my_pow += pw
		else: opp_pows[p_own] = int(opp_pows.get(p_own, 0)) + pw
	for op_k in opp_pows.keys(): max_opp_pow = maxi(max_opp_pow, int(opp_pows[op_k]))

	for card in candidates:
		var type_line := MagicRules.get_card_type_line(card.card_data).to_lower()
		var oracle_lower := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_lower()
		var is_wipe := "destroy all creatures" in oracle_lower or "exile all creatures" in oracle_lower
		if is_wipe and difficulty != Difficulty.CASUAL and my_pow >= max_opp_pow:
			continue
		if "instant" in type_line and not MagicRules.can_cast_at_instant_speed(card.card_data, 0, pid, engine):
			continue
		if ("sorcery" in type_line or "aura" in type_line) and ("target" in oracle_lower or "aura" in type_line):
			var tgt: Variant = pick_ai_target(pid, oracle_lower, card)
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
			return false

	# 3. Activate Planeswalker loyalty & card-draw/utility abilities, then equip
	if engine.active_stack.is_empty():
		_activate_ai_planeswalkers_and_abilities(pid)
		_equip_ai_equipment(pid)
	return false

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
			var atk_menace: bool = atk.has_method("has_keyword") and bool(atk.has_keyword("menace"))
			var valid_defs: Array[Node3D] = []
			for d in defenders:
				if CombatManager.can_creature_block(atk, d):
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
	var best_score := -99999
	for pid in [1, 2, 3, 4]:
		if pid == my_pid: continue
		if engine.has_method("is_player_eliminated") and engine.is_player_eliminated(pid): continue
		var life_val: int = int(engine.player_life.get(pid, 0))
		if life_val <= 0: continue
		if difficulty == Difficulty.CASUAL:
			if life_val > best_score:
				best_score = life_val
				best_pid = pid
			continue

		var threat := int(life_val * 0.25)
		threat += engine.player_hands.get(pid, []).size() * 2
		if life_val <= 15: threat += 15
		for perm in engine.battlefield_non_lands:
			if not is_instance_valid(perm) or not perm.is_on_battlefield: continue
			if engine.get_card_owner_id(perm) != pid: continue
			if MagicRules.is_creature(perm.card_data):
				threat += maxi(0, int(perm.dynamic_power)) * 3
			var ol := str(MagicRules.get_card_attribute(perm.card_data, "oracle_text", "")).to_lower()
			if "draw " in ol or MagicRules.is_planeswalker(perm.card_data):
				threat += 6
		var my_cmd_dmg: Dictionary = engine.commander_damage.get(my_pid, {})
		for cmd_c in my_cmd_dmg.keys():
			if is_instance_valid(cmd_c) and engine.get_card_owner_id(cmd_c) == pid:
				threat += int(my_cmd_dmg[cmd_c]) * 2
		if threat > best_score:
			best_score = threat
			best_pid = pid
	return best_pid

func _activate_ai_planeswalkers_and_abilities(pid: int) -> void:
	for card in engine.battlefield_non_lands.duplicate():
		if not is_instance_valid(card) or not card.is_on_battlefield: continue
		if engine.get_card_owner_id(card) != pid: continue
		var pa: Dictionary = card.parsed_abilities if "parsed_abilities" in card else {}

		# Planeswalker loyalty abilities (once per turn)
		if MagicRules.is_planeswalker(card.card_data) and "loyalty_activated_this_turn" in card and not bool(card.loyalty_activated_this_turn):
			var l_abs: Array = pa.get("loyalty_abilities", [])
			var cur_loy: int = card.get_named_counter("loyalty") if card.has_method("get_named_counter") else 0
			var chosen_ab: Dictionary = {}
			var chosen_delta := -99
			for lab in l_abs:
				var d_str: String = str(lab.get("delta_str", "0"))
				if "X" in d_str.to_upper(): continue
				var delta: int = d_str.to_int()
				if delta < 0 and cur_loy + delta < 0: continue
				if chosen_ab.is_empty() or (delta < 0 and abs(delta) >= 5 and cur_loy + delta >= 0) or (delta > chosen_delta):
					chosen_ab = lab
					chosen_delta = delta
			if not chosen_ab.is_empty():
				card.modify_named_counter("loyalty", chosen_delta)
				card.loyalty_activated_this_turn = true
				var eff_l := str(chosen_ab.get("effect_raw", "")).to_lower()
				var tgt: Variant = pick_ai_target(pid, eff_l) if "target" in eff_l else null
				engine._finalize_push_ability_to_stack(card, chosen_ab, "Loyalty", tgt)
				return

		# Non-mana utility / card-draw / token abilities
		for ab in pa.get("activated_abilities", []):
			var cost_raw := str(ab.get("cost_raw", ""))
			var eff_raw := str(ab.get("effect_raw", ""))
			var eff_l := eff_raw.to_lower()
			if "add " in eff_l or "sacrifice" in cost_raw.to_lower(): continue
			if "exiled with" in eff_l or "exiled with" in cost_raw.to_lower():
				var linked: Array = card.get_meta("linked_exiled_cards") if card.has_meta("linked_exiled_cards") else []
				if linked.is_empty(): continue
			if not ("draw " in eff_l or "create " in eff_l or "scry " in eff_l): continue
			var needs_tap := "{T}" in cost_raw.to_upper()
			if needs_tap and (card.is_tapped or (MagicRules.is_creature(card.card_data) and card.has_summoning_sickness)): continue
			var m_cost := ""
			for m in engine.MANA_COST_REGEX.search_all(cost_raw):
				var sym: String = str(m.get_string(1)).to_upper()
				if sym != "T" and sym != "Q": m_cost += "{" + sym + "}"
			if not m_cost.is_empty() and not engine.can_pay_and_drain_cost(m_cost, pid, {"is_activated": true}): continue
			if needs_tap: card.toggle_tap()
			var tgt: Variant = pick_ai_target(pid, eff_l) if "target" in eff_l else null
			engine._finalize_push_ability_to_stack(card, ab, "Activated", tgt)
			return

func pick_ai_target(ai_pid: int, effect_lower: String, source_card: Node3D = null) -> Variant:
	var req := OracleParser.extract_target_requirement(effect_lower)
	var tgt_zone := OracleParser.extract_target_zone(req)

	if tgt_zone == "graveyard":
		var best_gy: Node3D = null
		var best_cmc := -1.0
		var gy_pools: Array = []
		if ai_pid == engine.local_player_id:
			gy_pools.append(engine.graveyard_stack)
		for p_key in engine.player_graveyards.keys():
			gy_pools.append(engine.player_graveyards[p_key])
		for pool in gy_pools:
			for c in pool:
				if not is_instance_valid(c): continue
				if not MagicRules.is_legal_target(c, req, ai_pid, source_card): continue
				var cmc_val: float = float(c.card_data.get("cmc", 0.0))
				if cmc_val > best_cmc:
					best_cmc = cmc_val
					best_gy = c
		return best_gy

	if tgt_zone == "exile":
		var ex_pools: Array = [engine.exile_stack]
		for p_key in engine.player_exile.keys():
			ex_pools.append(engine.player_exile[p_key])
		for pool in ex_pools:
			for c in pool:
				if is_instance_valid(c) and MagicRules.is_legal_target(c, req, ai_pid, source_card):
					return c
		return null

	if tgt_zone == "stack":
		return null

	if "creature you control" in effect_lower or "aura" in effect_lower:
		var best_own: Node3D = null
		var best_p := -1
		for c in engine.battlefield_non_lands:
			if is_instance_valid(c) and c.is_on_battlefield and MagicRules.is_creature(c.card_data) and engine.get_card_owner_id(c) == ai_pid:
				if not req.is_empty() and not MagicRules.is_legal_target(c, req, ai_pid, source_card): continue
				if int(c.dynamic_power) > best_p:
					best_p = int(c.dynamic_power)
					best_own = c
		return best_own
	if "creature" in effect_lower or "permanent" in effect_lower or "artifact" in effect_lower or "enchantment" in effect_lower:
		var best_opp: Node3D = null
		var best_threat := -1
		for c in engine.battlefield_non_lands + engine.battlefield_lands:
			if is_instance_valid(c) and c.is_on_battlefield and engine.get_card_owner_id(c) != ai_pid:
				if not req.is_empty() and not MagicRules.is_legal_target(c, req, ai_pid, source_card): continue
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
		var tgt: Variant = pick_ai_target(pid, ol, card)
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
