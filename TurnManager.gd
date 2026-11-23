class_name TurnManager
extends Node

enum TurnPhase {
	UNTAP, UPKEEP, DRAW_STEP, PRECOMBAT_MAIN,
	COMBAT_BEGIN, COMBAT_DECLARE_ATTACKERS, COMBAT_DECLARE_BLOCKERS, COMBAT_DAMAGE, COMBAT_END,
	POSTCOMBAT_MAIN, END, CLEANUP
}

const PHASE_ICONS := {
	TurnPhase.UNTAP: "↻",
	TurnPhase.UPKEEP: "⏳",
	TurnPhase.DRAW_STEP: "🃏",
	TurnPhase.PRECOMBAT_MAIN: "Ⅰ",
	TurnPhase.COMBAT_BEGIN: "⚔",
	TurnPhase.COMBAT_DECLARE_ATTACKERS: "🗡",
	TurnPhase.COMBAT_DECLARE_BLOCKERS: "🛡",
	TurnPhase.COMBAT_DAMAGE: "💥",
	TurnPhase.COMBAT_END: "⚑",
	TurnPhase.POSTCOMBAT_MAIN: "Ⅱ",
	TurnPhase.END: "🌙",
	TurnPhase.CLEANUP: "🧹"
}

const PHASE_NAMES := {
	TurnPhase.UNTAP: "Beginning — Untap",
	TurnPhase.UPKEEP: "Beginning — Upkeep",
	TurnPhase.DRAW_STEP: "Beginning — Draw",
	TurnPhase.PRECOMBAT_MAIN: "Pre-combat Main Phase",
	TurnPhase.COMBAT_BEGIN: "Combat — Beginning",
	TurnPhase.COMBAT_DECLARE_ATTACKERS: "Combat — Declare Attackers",
	TurnPhase.COMBAT_DECLARE_BLOCKERS: "Combat — Declare Blockers",
	TurnPhase.COMBAT_DAMAGE: "Combat — Damage Step",
	TurnPhase.COMBAT_END: "Combat — End of Combat",
	TurnPhase.POSTCOMBAT_MAIN: "Post-combat Main Phase",
	TurnPhase.END: "Ending — End Step",
	TurnPhase.CLEANUP: "Ending — Cleanup"
}

const CLOCKWISE_ORDER: Array[int] = [1, 2, 3, 4]

var engine: Node = null

var active_player_id: int = 1
var priority_player_id: int = 1
var priority_passes_count: int = 0
var auto_pass_opponents: bool = true
var current_turn_phase: TurnPhase = TurnPhase.UNTAP
var turn_number: int = 1

var phase_stops: Dictionary = {}
var pass_until_end_step: bool = false
var hold_priority_in_response: bool = false
var _auto_pass_timer_active: bool = false

func setup(main_engine: Node) -> void:
	engine = main_engine


func get_next_player_id(current_pid: int) -> int:
	var idx := CLOCKWISE_ORDER.find(current_pid)
	if idx == -1: idx = 0
	for step in range(1, CLOCKWISE_ORDER.size() + 1):
		var cand: int = CLOCKWISE_ORDER[(idx + step) % CLOCKWISE_ORDER.size()]
		if not engine.has_method("is_player_eliminated") or not engine.is_player_eliminated(cand):
			return cand
	return CLOCKWISE_ORDER[(idx + 1) % CLOCKWISE_ORDER.size()]

func set_starting_player(pid: int) -> void:
	active_player_id = pid
	priority_player_id = pid
	priority_passes_count = 0
	current_turn_phase = TurnPhase.UNTAP
	turn_number = 1
	EventBus.notify_turn(active_player_id, turn_number)
	EventBus.notify_phase(current_turn_phase)


func has_local_player_interaction() -> bool:
	if hold_priority_in_response:
		return true
	if bool(phase_stops.get(current_turn_phase, false)):
		return true
	if current_turn_phase == TurnPhase.COMBAT_DECLARE_BLOCKERS and engine.combat_manager.has_attackers_declared():
		for c in engine.battlefield_non_lands:
			if is_instance_valid(c) and bool(c.get("is_attacking")) and int(c.get("attacking_target_player_id")) == engine.local_player_id:
				for blk in engine.battlefield_non_lands:
					if is_instance_valid(blk) and engine.get_card_controller_id(blk) == engine.local_player_id and MagicRules.is_creature(blk.card_data) and not blk.is_tapped:
						return true
	if active_player_id == engine.local_player_id and current_turn_phase == TurnPhase.COMBAT_DECLARE_ATTACKERS and not pass_until_end_step:
		if _has_eligible_attackers(engine.local_player_id):
			return true
	if engine.has_method("has_any_playable_card") and engine.has_any_playable_card():
		return true
	return false

func _schedule_paced_auto_pass() -> void:
	if _auto_pass_timer_active:
		return
	_auto_pass_timer_active = true
	var tree := get_tree()
	if tree == null:
		_auto_pass_timer_active = false
		return
	tree.create_timer(0.48).timeout.connect(func():
		_auto_pass_timer_active = false
		if not is_instance_valid(engine): return
		if engine.mulligan_phase_active: return
		if priority_player_id == engine.local_player_id and not has_local_player_interaction():
			pass_priority()
		elif auto_pass_opponents and not engine.is_human_seat(priority_player_id) and not (engine.ai_controller and engine.ai_controller.should_ai_act_on_priority(priority_player_id)):
			pass_priority()
	)

func is_local_player_turn() -> bool:
	return active_player_id == engine.local_player_id

func holds_priority(player_id: int = -1) -> bool:
	var pid: int = player_id if player_id > 0 else engine.local_player_id
	return priority_player_id == pid

func can_act_sorcery_speed(player_id: int = -1) -> bool:
	var pid: int = player_id if player_id > 0 else engine.local_player_id
	var is_main := (current_turn_phase == TurnPhase.PRECOMBAT_MAIN or current_turn_phase == TurnPhase.POSTCOMBAT_MAIN)
	return active_player_id == pid and priority_player_id == pid and engine.active_stack.is_empty() and is_main

func toggle_stop(phase: TurnPhase) -> void:
	phase_stops[phase] = not bool(phase_stops.get(phase, false))
	EventBus.notify_phase(current_turn_phase)

func request_primary_action() -> void:
	pass_priority()

func request_pass_turn() -> void:
	pass_until_end_step = true
	pass_priority()

func get_active_player_count() -> int:
	var cnt := 0
	for p in CLOCKWISE_ORDER:
		if not engine.has_method("is_player_eliminated") or not engine.is_player_eliminated(p):
			cnt += 1
	return maxi(1, cnt)

func pass_priority(from_network: bool = false) -> void:
	if not from_network and engine.is_network_multiplayer() and priority_player_id == engine.local_player_id:
		engine.network_manager.dispatch_game_action("PASS_PRIORITY", {})
	priority_passes_count += 1
	engine.event_ledger.log_event(GameEventLedger.EventType.PRIORITY_PASSED, {
		"passed_by": priority_player_id,
		"passes_count": priority_passes_count
	})

	if priority_passes_count >= get_active_player_count():
		priority_passes_count = 0
		priority_player_id = active_player_id
		if not engine.active_stack.is_empty():
			engine.resolve_top_stack_card()
			if engine.ai_controller and engine.ai_controller.should_ai_act_on_priority(priority_player_id):
				engine.ai_controller.schedule_ai_action(priority_player_id)
			elif (priority_player_id == engine.local_player_id and not has_local_player_interaction()) or (auto_pass_opponents and not engine.is_human_seat(priority_player_id)):
				_schedule_paced_auto_pass()
		else:
			advance_turn_phase(false)
	else:
		priority_player_id = get_next_player_id(priority_player_id)
		var should_auto_pass_local: bool = (
			(pass_until_end_step and priority_player_id == engine.local_player_id and engine.active_stack.is_empty() and not bool(phase_stops.get(current_turn_phase, false)) and not (current_turn_phase == TurnPhase.END and active_player_id == engine.local_player_id))
			or (priority_player_id == engine.local_player_id and not has_local_player_interaction())
		)
		if engine.ai_controller and engine.ai_controller.should_ai_act_on_priority(priority_player_id):
			engine.ai_controller.schedule_ai_action(priority_player_id)
		elif should_auto_pass_local or (auto_pass_opponents and not engine.is_human_seat(priority_player_id)):
			_schedule_paced_auto_pass()

	EventBus.notify_priority(priority_player_id, priority_passes_count)

func advance_turn_phase(force_manual: bool = false) -> void:
	var steps_guard := 0
	while steps_guard < 14:
		steps_guard += 1
		_step_single_phase()
		if force_manual:
			break
		if not _should_auto_skip_current_phase():
			break

	if current_turn_phase == TurnPhase.COMBAT_DECLARE_BLOCKERS and engine.combat_manager.has_attackers_declared():
		if engine.ai_controller: engine.ai_controller.assign_ai_blockers()

	var ai_will_act: bool = engine.ai_controller != null and engine.ai_controller.should_ai_act_on_priority(priority_player_id)
	if pass_until_end_step:
		var hit_end: bool = (current_turn_phase == TurnPhase.END and active_player_id == engine.local_player_id)
		if hit_end or not engine.active_stack.is_empty() or bool(phase_stops.get(current_turn_phase, false)):
			pass_until_end_step = false
		elif not ai_will_act and (auto_pass_opponents or engine.is_human_seat(active_player_id)):
			_schedule_paced_auto_pass()

	if ai_will_act:
		engine.ai_controller.schedule_ai_action(priority_player_id)
	elif (priority_player_id == engine.local_player_id and not has_local_player_interaction()) or (auto_pass_opponents and not engine.is_human_seat(priority_player_id)):
		_schedule_paced_auto_pass()

	EventBus.notify_phase(current_turn_phase)

func _should_auto_skip_current_phase() -> bool:
	if not engine.active_stack.is_empty():
		return false
	if bool(phase_stops.get(current_turn_phase, false)):
		return false

	match current_turn_phase:
		TurnPhase.UNTAP:
			return true
		TurnPhase.UPKEEP:
			return not _has_upkeep_or_draw_trigger(TurnPhase.UPKEEP)
		TurnPhase.DRAW_STEP:
			return not _has_upkeep_or_draw_trigger(TurnPhase.DRAW_STEP)
		TurnPhase.COMBAT_BEGIN:
			return (not _has_beginning_of_combat_trigger()) and (not _has_eligible_attackers(active_player_id)) and (not bool(phase_stops.get(TurnPhase.COMBAT_DECLARE_ATTACKERS, false)))
		TurnPhase.COMBAT_DECLARE_ATTACKERS:
			return not _has_eligible_attackers(active_player_id)
		TurnPhase.COMBAT_DECLARE_BLOCKERS, TurnPhase.COMBAT_DAMAGE, TurnPhase.COMBAT_END:
			return not engine.combat_manager.has_attackers_declared()
		TurnPhase.CLEANUP:
			return true
	return false

func _step_single_phase() -> void:
	priority_passes_count = 0

	match current_turn_phase:
		TurnPhase.UNTAP:
			engine.empty_mana_pool()
			for c in engine.battlefield_non_lands:
				if is_instance_valid(c):
					if "loyalty_activated_this_turn" in c: c.loyalty_activated_this_turn = false
					if "goaded_by_player_id" in c and int(c.goaded_by_player_id) == active_player_id:
						c.goaded_by_player_id = 0
						c.refresh_visual_status()
			current_turn_phase = TurnPhase.UPKEEP
			if engine.initiative_player_id == active_player_id and engine.has_method("advance_dungeon_for_player"):
				engine.advance_dungeon_for_player(active_player_id, "Undercity")
			var ex_pool: Array = engine.exile_stack if active_player_id == engine.local_player_id else engine.player_exile.get(active_player_id, [])
			for sc in ex_pool.duplicate():
				if is_instance_valid(sc) and sc.has_meta("suspended") and bool(sc.get_meta("suspended")) and sc.has_method("get_named_counter"):
					var t_cnt: int = sc.get_named_counter("time")
					if t_cnt > 0:
						sc.modify_named_counter("time", -1)
						if sc.get_named_counter("time") <= 0:
							sc.remove_meta("suspended")
							ex_pool.erase(sc)
							engine.zone_manager.move_to_stack(sc)
		TurnPhase.UPKEEP:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.DRAW_STEP
			if active_player_id == engine.local_player_id:
				engine.draw_card()
			else:
				engine._draw_opponent_card(active_player_id)
		TurnPhase.DRAW_STEP:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.PRECOMBAT_MAIN
			engine.advance_sagas_for_player(active_player_id)
		TurnPhase.PRECOMBAT_MAIN:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.COMBAT_BEGIN
		TurnPhase.COMBAT_BEGIN:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.COMBAT_DECLARE_ATTACKERS
		TurnPhase.COMBAT_DECLARE_ATTACKERS:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.COMBAT_DECLARE_BLOCKERS
		TurnPhase.COMBAT_DECLARE_BLOCKERS:
			engine.empty_mana_pool()
			if engine.combat_manager.has_method("prompt_damage_order_if_needed"):
				engine.combat_manager.prompt_damage_order_if_needed()
			current_turn_phase = TurnPhase.COMBAT_DAMAGE
		TurnPhase.COMBAT_DAMAGE:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.COMBAT_END
		TurnPhase.COMBAT_END:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.POSTCOMBAT_MAIN
		TurnPhase.POSTCOMBAT_MAIN:
			engine.empty_mana_pool()
			current_turn_phase = TurnPhase.END
			if engine.monarch_player_id == active_player_id:
				if active_player_id == engine.local_player_id: engine.draw_card()
				else: engine._draw_opponent_card(active_player_id)
		TurnPhase.END:
			engine.empty_mana_pool()
			if engine.monarch_player_id == active_player_id:
				if active_player_id == engine.local_player_id: engine.draw_card()
				else: engine._draw_opponent_card(active_player_id)
			for c in engine.battlefield_non_lands.duplicate():
				if is_instance_valid(c) and c.has_meta("unearthed") and bool(c.get_meta("unearthed")):
					c.remove_meta("unearthed")
					engine.zone_manager.move_to_exile(c)
			current_turn_phase = TurnPhase.CLEANUP
			for c in engine.battlefield_non_lands:
				if is_instance_valid(c):
					c.temp_power_modifier = 0
					c.temp_toughness_modifier = 0
					if c.has_meta("temp_granted_keywords"): c.remove_meta("temp_granted_keywords")
					if c.has_meta("base_pt_override"): c.remove_meta("base_pt_override")
					if c.has_meta("pt_switched"): c.remove_meta("pt_switched")
					if c.has_meta("crewed_until_eot"):
						c.remove_meta("crewed_until_eot")
						if "type_overrides" in c: c.type_overrides.erase("Creature")
					if c.has_meta("saddled_until_eot"):
						c.remove_meta("saddled_until_eot")
		TurnPhase.CLEANUP:
			engine.empty_mana_pool()
			if engine.battlefield_day_night == "Day" and engine.spells_cast_this_turn == 0:
				engine.set_day_night("Night")
			elif engine.battlefield_day_night == "Night" and engine.spells_cast_this_turn >= 2:
				engine.set_day_night("Day")
			engine.spells_cast_this_turn = 0
			active_player_id = get_next_player_id(active_player_id)
			priority_player_id = active_player_id
			if active_player_id == engine.starting_player_id:
				turn_number += 1
			current_turn_phase = TurnPhase.UNTAP
			engine.land_played_this_turn = false
			engine.zone_manager.untap_all(active_player_id)
			EventBus.notify_turn(active_player_id, turn_number)

	engine.event_ledger.log_event(GameEventLedger.EventType.PHASE_CHANGED, {
		"new_phase": current_turn_phase,
		"active_player_id": active_player_id,
		"turn_number": turn_number
	})

	engine.combat_manager.process_combat_step(current_turn_phase)
	EventBus.notify_phase(current_turn_phase)
	engine.run_state_based_actions()

func _has_upkeep_or_draw_trigger(phase: TurnPhase) -> bool:
	var all_permanents: Array = engine.battlefield_lands + engine.battlefield_non_lands
	for perm in all_permanents:
		if not is_instance_valid(perm): continue
		var oracle: String = str(MagicRules.get_card_attribute(perm.card_data, "oracle_text", "")).to_lower()
		if phase == TurnPhase.UPKEEP and ("beginning of your upkeep" in oracle or "beginning of each upkeep" in oracle):
			return true
		if phase == TurnPhase.DRAW_STEP and ("whenever you draw" in oracle or "beginning of your draw" in oracle):
			return true
	return false

func _has_eligible_attackers(pid: int) -> bool:
	for card in engine.battlefield_non_lands:
		if not is_instance_valid(card) or not card.is_on_battlefield: continue
		if engine.get_card_owner_id(card) != pid: continue
		if not MagicRules.is_creature(card.card_data): continue
		if card.is_tapped: continue
		var has_haste: bool = card.has_method("has_keyword") and bool(card.has_keyword("haste"))
		if not card.has_summoning_sickness or has_haste:
			return true
	return false

func _has_beginning_of_combat_trigger() -> bool:
	for perm in engine.battlefield_lands + engine.battlefield_non_lands:
		if not is_instance_valid(perm) or not perm.has_method("get_triggered_abilities"): continue
		var perm_owner: int = engine.get_card_owner_id(perm)
		for trig in perm.get_triggered_abilities():
			var ev := str(trig.get("trigger_event_raw", "")).to_lower()
			if "beginning of combat" in ev:
				if ("on your turn" in ev or "your combat" in ev) and perm_owner != active_player_id:
					continue
				return true
	return false
