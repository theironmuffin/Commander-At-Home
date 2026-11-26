class_name CombatManager
extends Node

var engine: Node = null
var selected_blocker: Node3D = null
var pending_attacker: Node3D = null
var blocker_damage_order: Dictionary = {}

func setup(main_engine: Node) -> void:
	engine = main_engine

func has_attackers_declared() -> bool:
	for card in engine.battlefield_non_lands + engine.battlefield_lands:
		if is_instance_valid(card) and bool(card.get("is_attacking")):
			return true
	return false

func process_combat_step(phase: int) -> void:
	match phase:
		TurnManager.TurnPhase.COMBAT_BEGIN:
			selected_blocker = null
		TurnManager.TurnPhase.COMBAT_DECLARE_BLOCKERS:
			selected_blocker = null
			_apply_declare_attackers_triggers()
		TurnManager.TurnPhase.COMBAT_DAMAGE:
			selected_blocker = null
			_resolve_combat_damage()
		TurnManager.TurnPhase.COMBAT_END:
			_cleanup_combat_declarations()

func handle_declare_attacker_key(card_node: Node3D, cycle_target: bool = false) -> bool:
	if not is_instance_valid(card_node) or not card_node.is_on_battlefield:
		return false
	if not MagicRules.is_creature(card_node.card_data, 0, card_node):
		return false
	if engine.get_card_owner_id(card_node) != engine.turn_manager.active_player_id:
		return false

	# Shift+A on an already-attacking creature cycles target opponent (P2 -> P3 -> P4)
	if cycle_target and bool(card_node.get("is_attacking")):
		var cur_target: int = int(card_node.get("attacking_target_player_id"))
		var next_target: int = (cur_target % 4) + 1
		if next_target == engine.turn_manager.active_player_id:
			next_target = (next_target % 4) + 1
		card_node.set("attacking_target_player_id", next_target)
		if card_node.has_method("set_combat_status"):
			card_node.set_combat_status("ATK -> %s" % engine.get_player_display_name(next_target))
		EventBus.combat_declared.emit(card_node, next_target)
		return true

	var toggling_on: bool = not bool(card_node.get("is_attacking"))
	if toggling_on:
		if card_node.is_tapped:
			return true
		var has_def: bool = card_node.has_method("has_keyword") and bool(card_node.has_keyword("defender"))
		var ol_def: String = str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "")).to_lower()
		if has_def and not ("as though it didn't have defender" in ol_def):
			return true
		var has_haste: bool = card_node.has_method("has_keyword") and bool(card_node.has_keyword("haste"))
		if card_node.has_summoning_sickness and not has_haste:
			return true

	var active_p: int = engine.turn_manager.active_player_id
	var goaded_by: int = int(card_node.get("goaded_by_player_id")) if "goaded_by_player_id" in card_node else 0
	var default_opp: int = (active_p % 4) + 1
	for cand_opp in [1, 2, 3, 4]:
		var p_cand: int = ((active_p + cand_opp - 1) % 4) + 1
		if p_cand != active_p and not engine.is_player_eliminated(p_cand) and p_cand != goaded_by:
			default_opp = p_cand
			break
	if toggling_on:
		var tax_total := _get_attack_tax_for_defender(default_opp)
		if tax_total > 0 and not engine.can_pay_and_drain_cost("{%d}" % tax_total, active_p):
			if engine.hud_manager and engine.hud_manager.has_method("show_toast"):
				engine.hud_manager.show_toast("Cannot attack P%d — requires paying {%d} tax" % [default_opp, tax_total])
			return true
	card_node.set("is_attacking", toggling_on)
	card_node.set("attacking_target_player_id", default_opp)

	if card_node.has_method("set_combat_status"):
		card_node.set_combat_status(("ATK -> %s" % engine.get_player_display_name(default_opp)) if toggling_on else "")

	var has_vigilance: bool = card_node.has_method("has_keyword") and bool(card_node.has_keyword("vigilance"))
	if toggling_on and not has_vigilance and not card_node.is_tapped:
		card_node.toggle_tap()
	elif not toggling_on and not has_vigilance and card_node.is_tapped:
		card_node.toggle_tap()
	if not toggling_on:
		if card_node.has_meta("attack_target_perm"): card_node.remove_meta("attack_target_perm")
		if pending_attacker == card_node: pending_attacker = null

	if toggling_on:
		EventBus.combat_declared.emit(card_node, default_opp)

	engine.zone_manager.update_battlefield_positions(true)
	EventBus.notify_phase(engine.turn_manager.current_turn_phase)
	return true

func handle_declare_blocker_click(card_node: Node3D) -> bool:
	if not is_instance_valid(card_node):
		return false

	if selected_blocker == null:
		if MagicRules.is_creature(card_node.card_data, 0, card_node) and engine.get_card_owner_id(card_node) != engine.turn_manager.active_player_id and not card_node.is_tapped:
			if bool(card_node.get("is_blocking")):
				card_node.set("is_blocking", false)
				card_node.set("blocking_target_creature", null)
				if card_node.has_method("set_combat_status"): card_node.set_combat_status("")
				EventBus.notify_phase(engine.turn_manager.current_turn_phase)
				return true
			selected_blocker = card_node
			if card_node.has_method("set_highlight"):
				card_node.set_highlight(true)
			return true
		return false

	if card_node == selected_blocker:
		selected_blocker.set_highlight(false)
		selected_blocker = null
		return true

	if bool(card_node.get("is_attacking")) and int(card_node.get("attacking_target_player_id")) == engine.get_card_owner_id(selected_blocker):
		var evasion_ok := can_creature_block(card_node, selected_blocker)
		if evasion_ok:
			selected_blocker.set("is_blocking", true)
			selected_blocker.set("blocking_target_creature", card_node)
			if selected_blocker.has_method("set_combat_status"):
				var badge_tag: String = get_combat_badge_tag(card_node, selected_blocker)
				selected_blocker.set_combat_status(badge_tag)
			EventBus.blocker_declared.emit(selected_blocker, card_node)
		selected_blocker.set_highlight(false)
		selected_blocker = null
		EventBus.notify_phase(engine.turn_manager.current_turn_phase)
		return true

	return false

func _resolve_combat_damage() -> void:
	var blockers_by_attacker := {}
	for card in engine.battlefield_non_lands + engine.battlefield_lands:
		if not is_instance_valid(card): continue
		if bool(card.get("is_blocking")) and card.get("blocking_target_creature") != null:
			var atk: Node3D = card.get("blocking_target_creature")
			if is_instance_valid(atk):
				if not blockers_by_attacker.has(atk):
					blockers_by_attacker[atk] = []
				blockers_by_attacker[atk].append(card)

	# Menace check: if an attacker with Menace has only 1 blocker, treat it as unblocked
	for atk in blockers_by_attacker.keys():
		if is_instance_valid(atk) and atk.has_method("has_keyword") and bool(atk.has_keyword("menace")):
			var blks: Array = blockers_by_attacker[atk]
			if blks.size() == 1:
				var invalid_blk: Node3D = blks[0]
				if is_instance_valid(invalid_blk):
					invalid_blk.set("is_blocking", false)
					invalid_blk.set("blocking_target_creature", null)
					if invalid_blk.has_method("set_combat_status"): invalid_blk.set_combat_status("")
				blockers_by_attacker.erase(atk)

	for atk in blockers_by_attacker.keys():
		if blocker_damage_order.has(atk):
			var ordered: Array = blocker_damage_order[atk]
			var cur_list: Array = blockers_by_attacker[atk]
			var sorted_blks: Array = []
			for ob in ordered:
				if ob in cur_list: sorted_blks.append(ob)
			for rem in cur_list:
				if not (rem in sorted_blks): sorted_blks.append(rem)
			blockers_by_attacker[atk] = sorted_blks

	var dmg_totals: Dictionary = {}
	engine.set("suppress_combat_damage_popups", true)
	# Step 1: First Strike / Double Strike
	_execute_combat_damage_pass(blockers_by_attacker, true, dmg_totals)
	engine.run_state_based_actions()

	# Step 2: Normal Combat Damage
	_execute_combat_damage_pass(blockers_by_attacker, false, dmg_totals)
	engine.set("suppress_combat_damage_popups", false)
	for tgt_k in dmg_totals.keys():
		var tot: int = int(dmg_totals[tgt_k])
		if tot > 0 and engine.has_method("spawn_floating_3d_text"):
			if tgt_k is int or (tgt_k is Node3D and is_instance_valid(tgt_k)):
				engine.spawn_floating_3d_text(tgt_k, "-%d" % tot, Color(1.0, 0.35, 0.25))
	engine.run_state_based_actions()

func _execute_combat_damage_pass(blockers_by_attacker: Dictionary, first_strike_pass: bool, dmg_totals: Dictionary = {}) -> void:
	for attacker in (engine.battlefield_non_lands + engine.battlefield_lands).duplicate():
		if not is_instance_valid(attacker) or not attacker.is_on_battlefield: continue
		if not bool(attacker.get("is_attacking")): continue

		var atk_has_fs: bool = attacker.has_method("has_keyword") and bool(attacker.has_keyword("first strike"))
		var atk_has_ds: bool = attacker.has_method("has_keyword") and bool(attacker.has_keyword("double strike"))
		var attacker_strikes: bool = (atk_has_fs or atk_has_ds) if first_strike_pass else (not atk_has_fs or atk_has_ds)

		var blockers: Array = blockers_by_attacker.get(attacker, [])
		var alive_blockers: Array = []
		for b in blockers:
			if is_instance_valid(b) and b.is_on_battlefield:
				alive_blockers.append(b)

		if attacker_strikes and attacker.dynamic_power > 0:
			if alive_blockers.is_empty():
				var target_pw: Variant = attacker.get_meta("attacking_target_planeswalker") if attacker.has_meta("attacking_target_planeswalker") else null
				if target_pw is Node3D and is_instance_valid(target_pw) and bool(target_pw.get("is_on_battlefield")):
					_deal_combat_damage_to_planeswalker(attacker, target_pw as Node3D, attacker.dynamic_power, dmg_totals)
				else:
					var target_pid: int = int(attacker.get("attacking_target_player_id"))
					if target_pid > 0:
						_deal_combat_damage_to_player(attacker, target_pid, attacker.dynamic_power, dmg_totals)
			else:
				var remaining_dmg: int = attacker.dynamic_power
				var atk_deathtouch: bool = attacker.has_method("has_keyword") and bool(attacker.has_keyword("deathtouch"))
				var atk_trample: bool = attacker.has_method("has_keyword") and bool(attacker.has_keyword("trample"))
				for blocker in alive_blockers:
					if remaining_dmg <= 0: break
					var lethal_needed: int = 1 if atk_deathtouch else max(0, blocker.dynamic_toughness - blocker.marked_damage)
					var assigned: int = min(remaining_dmg, lethal_needed) if lethal_needed > 0 else 0
					if blocker == alive_blockers[-1] and not atk_trample:
						assigned = remaining_dmg
					if assigned > 0:
						_deal_combat_damage_to_creature(attacker, blocker, assigned, dmg_totals)
						remaining_dmg -= assigned
				if remaining_dmg > 0 and atk_trample:
					var t_pw: Variant = attacker.get_meta("attacking_target_planeswalker") if attacker.has_meta("attacking_target_planeswalker") else null
					if t_pw is Node3D and is_instance_valid(t_pw) and bool(t_pw.get("is_on_battlefield")):
						_deal_combat_damage_to_planeswalker(attacker, t_pw as Node3D, remaining_dmg, dmg_totals)
					else:
						var target_pid: int = int(attacker.get("attacking_target_player_id"))
						if target_pid > 0:
							_deal_combat_damage_to_player(attacker, target_pid, remaining_dmg, dmg_totals)

		for blocker in alive_blockers:
			var blk_has_fs: bool = blocker.has_method("has_keyword") and bool(blocker.has_keyword("first strike"))
			var blk_has_ds: bool = blocker.has_method("has_keyword") and bool(blocker.has_keyword("double strike"))
			var blocker_strikes: bool = (blk_has_fs or blk_has_ds) if first_strike_pass else (not blk_has_fs or blk_has_ds)
			if blocker_strikes and blocker.dynamic_power > 0:
				_deal_combat_damage_to_creature(blocker, attacker, blocker.dynamic_power, dmg_totals)

func _deal_combat_damage_to_creature(source: Node3D, target: Node3D, amount: int, dmg_totals: Dictionary = {}) -> void:
	if amount <= 0: return
	if MagicRules.has_protection_from(target, source) and not MagicRules.is_damage_unpreventable(source, engine): return
	var src_ol := str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
	if (source.has_method("has_keyword") and (bool(source.has_keyword("infect")) or bool(source.has_keyword("wither")))) or "infect" in src_ol or "wither" in src_ol:
		if target.has_method("modify_counters"):
			target.modify_counters(-amount)
	else:
		target.marked_damage += amount
	if source.has_method("has_keyword") and bool(source.has_keyword("deathtouch")):
		target.has_deathtouch_damage = true
	target.refresh_visual_status()
	dmg_totals[target] = int(dmg_totals.get(target, 0)) + amount
	EventBus.damage_dealt.emit(source, target, amount)
	if source.has_method("has_keyword") and bool(source.has_keyword("lifelink")):
		engine.modify_life(engine.get_card_owner_id(source), amount)

func _deal_combat_damage_to_planeswalker(source: Node3D, pw: Node3D, amount: int, dmg_totals: Dictionary = {}) -> void:
	if amount <= 0 or not is_instance_valid(pw): return
	if MagicRules.has_protection_from(pw, source) and not MagicRules.is_damage_unpreventable(source, engine): return
	if pw.has_method("modify_named_counter"):
		pw.modify_named_counter("loyalty", -amount)
	dmg_totals[pw] = int(dmg_totals.get(pw, 0)) + amount
	EventBus.damage_dealt.emit(source, pw, amount)
	if source.has_method("has_keyword") and bool(source.has_keyword("lifelink")):
		engine.modify_life(engine.get_card_owner_id(source), amount)

func _deal_combat_damage_to_player(source: Node3D, target_pid: int, amount: int, dmg_totals: Dictionary = {}) -> void:
	if amount <= 0 or target_pid <= 0 or target_pid == engine.get_card_owner_id(source): return
	var src_ol := str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
	var has_infect := (source.has_method("has_keyword") and bool(source.has_keyword("infect"))) or "infect" in src_ol
	if has_infect:
		engine.modify_player_counter(target_pid, "poison", amount)
	else:
		engine.modify_life(target_pid, -amount)
		var tox_rx := RegEx.new()
		tox_rx.compile("toxic\\s+(\\d+)")
		var tm := tox_rx.search(src_ol)
		if tm:
			engine.modify_player_counter(target_pid, "poison", tm.get_string(1).to_int())
	dmg_totals[target_pid] = int(dmg_totals.get(target_pid, 0)) + amount
	EventBus.damage_dealt.emit(source, target_pid, amount)
	var atk_owner: int = engine.get_card_owner_id(source)
	if engine.monarch_player_id == target_pid:
		engine.set_monarch(atk_owner)
	if engine.initiative_player_id == target_pid:
		engine.set_initiative(atk_owner)
	var is_cmd: bool = (source.has_meta("is_commander") and bool(source.get_meta("is_commander"))) or (source in engine.command_zone_cards)
	if is_cmd:
		if not engine.commander_damage.has(target_pid):
			engine.commander_damage[target_pid] = {}
		engine.commander_damage[target_pid][source] = int(engine.commander_damage[target_pid].get(source, 0)) + amount
	if source.has_method("has_keyword") and bool(source.has_keyword("lifelink")):
		engine.modify_life(engine.get_card_owner_id(source), amount)

func _cleanup_combat_declarations() -> void:
	selected_blocker = null
	blocker_damage_order.clear()
	for m_tok in (engine.battlefield_non_lands + engine.battlefield_lands).duplicate():
		if is_instance_valid(m_tok) and m_tok.has_meta("exile_at_end_of_combat") and bool(m_tok.get_meta("exile_at_end_of_combat")):
			m_tok.remove_meta("exile_at_end_of_combat")
			engine.zone_manager.move_to_exile(m_tok)
	for card in engine.battlefield_non_lands + engine.battlefield_lands:
		if not is_instance_valid(card): continue
		card.set("is_attacking", false)
		if card.has_meta("attacking_target_planeswalker"): card.remove_meta("attacking_target_planeswalker")
		card.set("is_blocking", false)
		card.set("blocking_target_creature", null)
		card.set("marked_damage", 0)
		card.set("has_deathtouch_damage", false)
		if card.has_method("set_combat_status"):
			card.set_combat_status("")
		card.refresh_visual_status()
	engine.zone_manager.update_battlefield_positions(true)

static func _compute_combat_outcome(attacker: Node3D, blocker: Node3D) -> Dictionary:
	var atk_pow: int = int(attacker.get("dynamic_power")) if attacker.get("dynamic_power") != null else 0
	var atk_tou: int = int(attacker.get("dynamic_toughness")) if attacker.get("dynamic_toughness") != null else 0
	var blk_pow: int = int(blocker.get("dynamic_power")) if blocker.get("dynamic_power") != null else 0
	var blk_tou: int = int(blocker.get("dynamic_toughness")) if blocker.get("dynamic_toughness") != null else 0

	var atk_fs: bool = attacker.has_method("has_keyword") and (bool(attacker.has_keyword("first strike")) or bool(attacker.has_keyword("double strike")))
	var blk_fs: bool = blocker.has_method("has_keyword") and (bool(blocker.has_keyword("first strike")) or bool(blocker.has_keyword("double strike")))
	var atk_dt: bool = attacker.has_method("has_keyword") and bool(attacker.has_keyword("deathtouch"))
	var blk_dt: bool = blocker.has_method("has_keyword") and bool(blocker.has_keyword("deathtouch"))
	var atk_ind: bool = attacker.has_method("has_keyword") and bool(attacker.has_keyword("indestructible"))
	var blk_ind: bool = blocker.has_method("has_keyword") and bool(blocker.has_keyword("indestructible"))

	var blk_dies: bool = (not blk_ind) and (atk_pow >= blk_tou or (atk_dt and atk_pow > 0))
	var atk_dies: bool = (not atk_ind) and (blk_pow >= atk_tou or (blk_dt and blk_pow > 0))

	if atk_fs and not blk_fs and blk_dies:
		# Blocker dies in First Strike step before dealing normal damage
		if not (attacker.has_method("has_keyword") and bool(attacker.has_keyword("double strike"))):
			atk_dies = false
		else:
			atk_dies = false
	elif blk_fs and not atk_fs and atk_dies:
		# Attacker dies in First Strike step before dealing normal damage
		blk_dies = false

	return {
		"atk_pow": atk_pow, "atk_tou": atk_tou,
		"blk_pow": blk_pow, "blk_tou": blk_tou,
		"atk_dies": atk_dies, "blk_dies": blk_dies
	}

static func get_combat_badge_tag(attacker: Node3D, blocker: Node3D) -> String:
	var res := _compute_combat_outcome(attacker, blocker)
	var blk_dies := bool(res["blk_dies"])
	var atk_dies := bool(res["atk_dies"])
	if blk_dies and atk_dies: return "BLK (Trade)"
	if blk_dies: return "BLK (Dies)"
	if atk_dies: return "BLK (Wins)"
	return "BLK (Survives)"

static func get_combat_math_preview(attacker: Node3D, blocker: Node3D) -> String:
	var res := _compute_combat_outcome(attacker, blocker)
	var blk_dies := bool(res["blk_dies"])
	var atk_dies := bool(res["atk_dies"])
	var outcome := "Both Survive"
	if blk_dies and atk_dies: outcome = "Trade (Both Die)"
	elif blk_dies: outcome = "Blocker Dies"
	elif atk_dies: outcome = "Attacker Dies (Blocker Survives)"
	return "%d/%d vs %d/%d — %s" % [int(res["atk_pow"]), int(res["atk_tou"]), int(res["blk_pow"]), int(res["blk_tou"]), outcome]

func cycle_next_attacker() -> void:
	var active_pid: int = engine.turn_manager.active_player_id
	var eligible: Array[Node3D] = []
	for c in engine.battlefield_non_lands + engine.battlefield_lands:
		if not is_instance_valid(c) or not c.is_on_battlefield: continue
		if engine.get_card_owner_id(c) != active_pid: continue
		if not MagicRules.is_creature(c.card_data, 0, c): continue
		var is_atk: bool = bool(c.get("is_attacking"))
		var has_haste: bool = c.has_method("has_keyword") and bool(c.has_keyword("haste"))
		if is_atk or (not c.is_tapped and (not c.has_summoning_sickness or has_haste)):
			eligible.append(c)
	if eligible.is_empty(): return
	var idx: int = eligible.find(engine.hovered_card)
	var next_card: Node3D = eligible[(idx + 1) % eligible.size()]
	var cam := engine.get_node_or_null("Camera3D") as Camera3D
	if cam:
		var sp: Vector2 = cam.unproject_position(next_card.global_position)
		engine.get_viewport().warp_mouse(sp.clamp(Vector2.ZERO, engine.get_viewport().get_visible_rect().size))
	engine._on_card_hovered(next_card)

func prompt_damage_order_if_needed() -> void:
	if engine.turn_manager.active_player_id != engine.local_player_id: return
	var blockers_by_atk := {}
	for card in engine.battlefield_non_lands + engine.battlefield_lands:
		if is_instance_valid(card) and bool(card.get("is_blocking")) and card.get("blocking_target_creature") != null:
			var atk: Node3D = card.get("blocking_target_creature")
			if is_instance_valid(atk):
				if not blockers_by_atk.has(atk): blockers_by_atk[atk] = []
				blockers_by_atk[atk].append(card)
	for atk in blockers_by_atk.keys():
		var blks: Array = blockers_by_atk[atk]
		if blks.size() >= 2 and engine.hud_manager.has_method("open_damage_order_popup"):
			engine.hud_manager.open_damage_order_popup(atk, blks, func(ordered: Array):
				blocker_damage_order[atk] = ordered
			)
			break

func assign_attacker_target(attacker: Node3D, target_val: Variant) -> bool:
	if not is_instance_valid(attacker) or not bool(attacker.get("is_attacking")):
		return false
	if target_val is int:
		var pid := int(target_val)
		if pid == engine.get_card_owner_id(attacker): return false
		attacker.set("attacking_target_player_id", pid)
		if attacker.has_meta("attack_target_perm"): attacker.remove_meta("attack_target_perm")
		if attacker.has_method("set_combat_status"):
			attacker.set_combat_status("ATK -> %s" % engine.get_player_display_name(pid))
		EventBus.combat_declared.emit(attacker, pid)
		pending_attacker = null
		return true
	elif target_val is Node3D and is_instance_valid(target_val):
		var t_perm := target_val as Node3D
		var ctrl_id: int = engine.get_card_controller_id(t_perm)
		if ctrl_id == engine.get_card_owner_id(attacker): return false
		attacker.set("attacking_target_player_id", ctrl_id)
		attacker.set_meta("attack_target_perm", t_perm)
		if attacker.has_method("set_combat_status"):
			attacker.set_combat_status("ATK -> %s" % str(t_perm.card_data.get("name", "Target")).left(12))
		EventBus.combat_declared.emit(attacker, ctrl_id)
		pending_attacker = null
		return true
	return false


func _apply_declare_attackers_triggers() -> void:
	var active_pid: int = engine.turn_manager.active_player_id
	var attackers: Array[Node3D] = []
	for c in engine.battlefield_non_lands + engine.battlefield_lands:
		if is_instance_valid(c) and bool(c.get("is_attacking")) and engine.get_card_owner_id(c) == active_pid:
			attackers.append(c)
	if attackers.is_empty(): return
	if attackers.size() == 1:
		var exalted_cnt := 0
		for p in engine.battlefield_non_lands + engine.battlefield_lands:
			if not is_instance_valid(p) or engine.get_card_owner_id(p) != active_pid: continue
			var p_ol := str(MagicRules.get_card_attribute(p.card_data, "oracle_text", "")).to_lower()
			if (p.has_method("has_keyword") and bool(p.has_keyword("exalted"))) or "exalted" in p_ol:
				exalted_cnt += 1
		if exalted_cnt > 0:
			attackers[0].temp_power_modifier += exalted_cnt
			attackers[0].temp_toughness_modifier += exalted_cnt
			attackers[0].refresh_visual_status()
	var ann_rx := RegEx.new()
	ann_rx.compile("annihilator\\s+(\\d+)")
	for atk in attackers:
		if not is_instance_valid(atk): continue
		if engine.has_method("check_and_queue_triggers"):
			engine.check_and_queue_triggers("ATTACK", atk)
		var a_ol := str(MagicRules.get_card_attribute(atk.card_data, "oracle_text", "")).to_lower()
		var am := ann_rx.search(a_ol)
		if am:
			var ann_n := am.get_string(1).to_int()
			var def_pid: int = int(atk.get("attacking_target_player_id"))
			if ann_n > 0 and def_pid > 0:
				AbilityResolver.execute_effect_text("target player sacrifices %d permanents" % ann_n, atk, def_pid, engine, active_pid)
		var has_myriad: bool = (atk.has_method("has_keyword") and bool(atk.has_keyword("myriad"))) or ("myriad" in a_ol)
		if has_myriad and engine.has_method("_spawn_new_token"):
			var def_pid_m: int = int(atk.get("attacking_target_player_id"))
			for opp_pid in [1, 2, 3, 4]:
				if opp_pid == active_pid or opp_pid == def_pid_m: continue
				if engine.has_method("is_player_eliminated") and engine.is_player_eliminated(opp_pid): continue
				var copy_data: Dictionary = atk.card_data.duplicate(true)
				var tok: Node3D = engine._spawn_new_token(copy_data, active_pid)
				if is_instance_valid(tok):
					tok.set_meta("exile_at_end_of_combat", true)
					tok.set("has_summoning_sickness", false)
					tok.set("is_tapped", true)
					tok.rotation_degrees.y = -90.0
					tok.set("is_attacking", true)
					tok.set("attacking_target_player_id", opp_pid)
					if tok.has_method("set_combat_status"): tok.set_combat_status("ATK -> P%d" % opp_pid)
					if tok.has_method("refresh_visual_status"): tok.refresh_visual_status()


func _get_attack_tax_for_defender(def_pid: int) -> int:
	var tax := 0
	var rx := RegEx.new()
	rx.compile("can't attack you unless.*pays?\\s+\\{(\\d+)\\}")
	for p in engine.battlefield_lands + engine.battlefield_non_lands:
		if not is_instance_valid(p) or engine.get_card_controller_id(p) != def_pid: continue
		var ol := str(MagicRules.get_card_attribute(p.card_data, "oracle_text", "")).to_lower()
		var m := rx.search(ol)
		if m: tax += m.get_string(1).to_int()
	return tax

static func can_creature_block(atk: Node3D, blk: Node3D) -> bool:
	if not is_instance_valid(atk) or not is_instance_valid(blk):
		return false
	var atk_ol := str(MagicRules.get_card_attribute(atk.card_data, "oracle_text", "")).to_lower()
	if "can't be blocked" in atk_ol:
		if not ("can't be blocked except" in atk_ol) and not ("can't be blocked by" in atk_ol):
			return false
		var p_rx := RegEx.new()
		p_rx.compile("can't be blocked by creatures with power (\\d+) or (greater|less)")
		var pm := p_rx.search(atk_ol)
		if pm:
			var p_lim := pm.get_string(1).to_int()
			var cmp_dir := pm.get_string(2)
			if cmp_dir == "greater" and int(blk.dynamic_power) >= p_lim: return false
			if cmp_dir == "less" and int(blk.dynamic_power) <= p_lim: return false
	if atk.has_method("has_keyword") and bool(atk.has_keyword("shadow")):
		if not (blk.has_method("has_keyword") and bool(blk.has_keyword("shadow"))):
			return false
	if atk.has_method("has_keyword") and bool(atk.has_keyword("horsemanship")):
		if not (blk.has_method("has_keyword") and bool(blk.has_keyword("horsemanship"))):
			return false
	var atk_flying: bool = atk.has_method("has_keyword") and bool(atk.has_keyword("flying"))
	var blk_can_reach: bool = blk.has_method("has_keyword") and (bool(blk.has_keyword("flying")) or bool(blk.has_keyword("reach")))
	if atk_flying and not blk_can_reach:
		return false
	if MagicRules.has_protection_from(atk, blk):
		return false
	var blk_tl := MagicRules.get_card_type_line(blk.card_data).to_lower()
	var blk_cols: Array = blk.card_data.get("colors", [])
	if atk.has_method("has_keyword") and bool(atk.has_keyword("fear")):
		if not ("artifact" in blk_tl) and not ("B" in blk_cols):
			return false
	if atk.has_method("has_keyword") and bool(atk.has_keyword("intimidate")):
		var shares_col := false
		for ac in atk.card_data.get("colors", []):
			if ac in blk_cols: shares_col = true; break
		if not ("artifact" in blk_tl) and not shares_col:
			return false
	if atk.has_method("has_keyword") and bool(atk.has_keyword("skulk")):
		if int(blk.dynamic_power) > int(atk.dynamic_power):
			return false
	return true
