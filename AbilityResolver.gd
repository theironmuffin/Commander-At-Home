class_name AbilityResolver
extends RefCounted

static var _REMINDER_REGEX: RegEx
static var _PT_REGEX: RegEx
static var _TOKEN_PT_REGEX: RegEx
static var _MANA_SYM_REGEX: RegEx
static var _ANY_COUNTER_REGEX: RegEx

static func _ensure_regex() -> void:
	if _REMINDER_REGEX == null:
		_REMINDER_REGEX = RegEx.new()
		_REMINDER_REGEX.compile("\\([^)]*\\)")
	if _PT_REGEX == null:
		_PT_REGEX = RegEx.new()
		_PT_REGEX.compile("([+-]\\d+)/([+-]\\d+)")
	if _TOKEN_PT_REGEX == null:
		_TOKEN_PT_REGEX = RegEx.new()
		_TOKEN_PT_REGEX.compile("(\\d+|x)/(\\d+|x)\\s+([a-zA-Z\\s]+?)\\s+creature token")
	if _MANA_SYM_REGEX == null:
		_MANA_SYM_REGEX = RegEx.new()
		_MANA_SYM_REGEX.compile("\\{([WUBRGC])\\}")
	if _ANY_COUNTER_REGEX == null:
		_ANY_COUNTER_REGEX = RegEx.new()
		_ANY_COUNTER_REGEX.compile("([+-]?\\d+/[+-]?\\d+|first strike|double strike|[a-z][a-z\\-]+)\\s+counter")

# Evaluate conditional MTG phrases ("you control a Forest or an Island", "you control two or more other lands", etc.)
static func evaluate_condition(cond_raw: String, source: Node3D, engine: Node, owner_id: int) -> bool:
	if not engine: return false
	var cond := cond_raw.to_lower().strip_edges().trim_suffix(".")
	if cond.is_empty(): return true

	var all_perms: Array = engine.battlefield_lands + engine.battlefield_non_lands

	# 1. "you control two or more other lands" / "you control two or fewer other lands"
	if "other lands" in cond:
		var other_land_count := 0
		for p in engine.battlefield_lands:
			if is_instance_valid(p) and p != source and engine.get_card_owner_id(p) == owner_id:
				other_land_count += 1
		if "two or more" in cond: return other_land_count >= 2
		if "two or fewer" in cond: return other_land_count <= 2
		if "three or more" in cond: return other_land_count >= 3

	# 2. "you have two or more opponents" (Battlebond / Crowdlands)
	if "two or more opponents" in cond:
		var living_opps := 0
		for pid in [1, 2, 3, 4]:
			if pid != owner_id and int(engine.player_life.get(pid, 0)) > 0:
				living_opps += 1
		return living_opps >= 2

	# 3. "you control a [Type/Subtype] or [Type/Subtype]" (Checklands, etc.)
	if "you control " in cond:
		var req_part := cond.substr(cond.find("you control ") + 12).strip_edges()
		var options := req_part.split(" or ")
		for opt in options:
			var clean_opt := opt.strip_edges()
			for prefix in ["a ", "an ", "another "]:
				if clean_opt.begins_with(prefix):
					clean_opt = clean_opt.substr(prefix.length()).strip_edges()
			if clean_opt.is_empty(): continue
			for p in all_perms:
				if not is_instance_valid(p) or p == source: continue
				if engine.get_card_owner_id(p) != owner_id: continue
				var t_line := MagicRules.get_card_type_line(p.card_data).to_lower()
				if clean_opt in t_line:
					return true
		return false

	# 4. "you have [N] or more life"
	if "life" in cond and "you have " in cond:
		var amt := _extract_number(cond, "you have ")
		return int(engine.player_life.get(owner_id, 0)) >= amt

	# 5. Linked-exile card type checks ("it's a land card", "it's a nonland card", etc.)
	if cond.begins_with("it's ") or cond.begins_with("it is "):
		var last_ex: Dictionary = engine.get_meta("last_linked_exile_card") if engine.has_meta("last_linked_exile_card") else {}
		if last_ex.is_empty():
			return false
		if "nonland" in cond:
			return not MagicRules.is_land(last_ex)
		if "land" in cond:
			return MagicRules.is_land(last_ex)
		var tl := MagicRules.get_card_type_line(last_ex).to_lower()
		for ctype in ["creature", "artifact", "enchantment", "planeswalker", "instant", "sorcery", "battle"]:
			if ctype in cond:
				return ctype in tl
		return false

	return false

# Entry point for spells, activated abilities, and triggered abilities
static func execute_effect_text(effect_text: String, source_card: Variant = null, target_node: Variant = null, engine_main: Node = null, controller_id_override: int = -1) -> void:
	if effect_text.is_empty():
		return
	_ensure_regex()

	var valid_source: Node3D = source_card if (source_card is Node3D and is_instance_valid(source_card)) else null
	var valid_target: Variant = target_node
	if target_node is Object and not is_instance_valid(target_node):
		valid_target = null

	var owner_id: int = controller_id_override if controller_id_override > 0 else (engine_main.get_card_owner_id(valid_source) if (engine_main and valid_source) else 1)
	if engine_main:
		engine_main.set_meta("last_linked_exile_card", {})
		if valid_target is Node3D and is_instance_valid(valid_target):
			engine_main.set_meta("last_target_controller_id", engine_main.get_card_controller_id(valid_target))
		else:
			engine_main.set_meta("last_target_controller_id", -1)
		engine_main.set_meta("spell_chosen_creature_type", "")

	var cleaned := _REMINDER_REGEX.sub(effect_text, "", true).strip_edges()
	var cl_low := cleaned.to_lower()
	if "exile the top " in cl_low and "at the beginning of the next end step" in cl_low and ("remain exiled" in cl_low or "eldrazi spawn" in cl_low):
		var ex_amt := _extract_number(cl_low, "exile the top ")
		var exiled_cards := _handle_impulse_exile_cards(ex_amt, engine_main, owner_id)
		if engine_main and engine_main.turn_manager:
			engine_main.turn_manager.delayed_triggers.append({
				"phase": TurnManager.TurnPhase.END,
				"owner_id": owner_id,
				"callback": func():
					if not is_instance_valid(engine_main): return
					var ex_arr: Array = engine_main.exile_stack if owner_id == engine_main.local_player_id else engine_main.player_exile.get(owner_id, [])
					var gy_cnt := 0
					for ec in exiled_cards:
						if is_instance_valid(ec) and (ec in ex_arr):
							ex_arr.erase(ec)
							if ec.has_meta("playable_from_exile"): ec.remove_meta("playable_from_exile")
							if ec.has_meta("playable_by_pid"): ec.remove_meta("playable_by_pid")
							engine_main._on_card_to_graveyard(ec)
							gy_cnt += 1
					if gy_cnt > 0 and engine_main.has_method("_spawn_new_token"):
						var spawn_data := {
							"name": "Eldrazi Spawn",
							"type_line": "Token Creature — Eldrazi Spawn",
							"mana_cost": "",
							"cmc": 0,
							"colors": [],
							"power": "0",
							"toughness": "1",
							"oracle_text": "Sacrifice this creature: Add {C}."
						}
						for _si in range(gy_cnt):
							engine_main._spawn_new_token(spawn_data, owner_id)
					if engine_main.zone_manager:
						engine_main.zone_manager.update_zone_counters()
			})
		return
	var clauses := _split_clauses(cleaned)

	_run_clause_chain(clauses, 0, valid_source, valid_target, engine_main, owner_id, true)

static func _run_clause_chain(clauses: Array[String], idx: int, source: Node3D, target: Variant, engine: Node, owner_id: int, last_succeeded: bool) -> void:
	if idx >= clauses.size():
		if engine and engine.has_method("run_state_based_actions"):
			engine.run_state_based_actions()
		return
	var c := clauses[idx].strip_edges()
	var c_lower := c.to_lower()

	if "choose a creature type" in c_lower and engine:
		var types: Array[String] = engine._collect_deck_creature_types(owner_id) if engine.has_method("_collect_deck_creature_types") else ["Human", "Elf", "Goblin", "Wizard", "Dragon"]
		for bp in engine.battlefield_non_lands:
			if is_instance_valid(bp) and MagicRules.is_creature(bp.card_data, 0, bp):
				var b_tl := MagicRules.get_card_type_line(bp.card_data)
				if "—" in b_tl:
					for st_w in b_tl.split("—")[1].strip_edges().split(" "):
						var cw := st_w.strip_edges()
						if not cw.is_empty() and not (cw in types): types.append(cw)
		if owner_id == engine.local_player_id and engine.hud_manager and engine.hud_manager.has_method("open_etb_creature_type_popup"):
			var dummy_card := source if source != null else Node3D.new()
			engine.hud_manager.open_etb_creature_type_popup(dummy_card, types, func(chosen_t: String):
				engine.set_meta("spell_chosen_creature_type", chosen_t)
				_run_clause_chain(clauses, idx + 1, source, target, engine, owner_id, true)
			)
			return
		else:
			engine.set_meta("spell_chosen_creature_type", types[0] if not types.is_empty() else "Human")
			_run_clause_chain(clauses, idx + 1, source, target, engine, owner_id, true)
			return

	# Handle leading "If <condition>, <effect>" including "If you do," and "If you don't,"
	if c_lower.begins_with("if ") and "," in c:
		var comma_idx := c.find(",")
		var cond_str := c.substr(3, comma_idx - 3).strip_edges().to_lower()
		var inner_eff := c.substr(comma_idx + 1).strip_edges()
		var cond_ok := false
		if cond_str == "you do" or cond_str == "you did" or cond_str == "you win the flip" or cond_str == "it comes up heads" or cond_str.begins_with("you discard") or cond_str.begins_with("a card is discarded"):
			cond_ok = last_succeeded
		elif cond_str == "you don't" or cond_str == "you didn't":
			cond_ok = not last_succeeded
		else:
			cond_ok = evaluate_condition(cond_str, source, engine, owner_id)
		if not cond_ok:
			_run_clause_chain(clauses, idx + 1, source, target, engine, owner_id, false)
			return
		c = inner_eff
		c_lower = c.to_lower()

	var next_step := func(did_ok: bool):
		_run_clause_chain(clauses, idx + 1, source, target, engine, owner_id, did_ok)

	# Handle "<action> unless that player / its controller / they pays {cost}" (e.g. Rhystic Study, Mystic Remora, Esper Sentinel)
	var tax_rx := RegEx.new()
	tax_rx.compile("^(.*?)\\s+unless\\s+(?:that player|its controller|they)\\s+pays?\\s+((?:\\{[^\\}]+\\})+)")
	var tax_m := tax_rx.search(c_lower)
	if tax_m:
		var inner_eff := tax_m.get_string(1).strip_edges()
		var tax_cost := tax_m.get_string(2).strip_edges().to_upper()
		var taxed_pid: int = -1
		if target is int and int(target) > 0:
			taxed_pid = int(target)
		elif target is Node3D and is_instance_valid(target) and engine:
			taxed_pid = engine.get_card_owner_id(target)
		elif engine and engine.turn_manager:
			taxed_pid = engine.turn_manager.active_player_id
		var src_name := str(source.card_data.get("name", "Trigger")) if source else "Trigger"
		var run_taxed_eff := func():
			if inner_eff.begins_with("you may "):
				var may_act := inner_eff.substr(8).strip_edges()
				if engine and owner_id == engine.local_player_id and engine.hud_manager and engine.hud_manager.has_method("open_choice_popup"):
					engine.hud_manager.open_choice_popup(
						"%s (Optional)" % src_name.to_upper(),
						["Yes: %s" % may_act.capitalize(), "No (Decline)"],
						func(choice_idx: int):
							if choice_idx == 0:
								_execute_clause_async(may_act, source, target, engine, owner_id, next_step)
							else:
								next_step.call(false)
					)
					return
				_execute_clause_async(may_act, source, target, engine, owner_id, next_step)
			else:
				_execute_clause_async(inner_eff, source, target, engine, owner_id, next_step)

		if taxed_pid > 0 and engine:
			if taxed_pid == engine.local_player_id and engine.hud_manager and engine.hud_manager.has_method("open_choice_popup"):
				engine.hud_manager.open_choice_popup(
					"%s — PAY %s?" % [src_name.to_upper(), tax_cost],
					["Pay %s" % tax_cost, "Decline (%s)" % inner_eff.capitalize()],
					func(p_idx: int):
						if p_idx == 0 and engine.can_pay_and_drain_cost(tax_cost, taxed_pid, {}):
							if engine.event_ledger:
								engine.event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": "P%d paid %s for %s" % [taxed_pid, tax_cost, src_name]})
							next_step.call(false)
						else:
							run_taxed_eff.call()
				)
				return
			elif taxed_pid != engine.local_player_id:
				if engine.can_pay_and_drain_cost(tax_cost, taxed_pid, {}):
					if engine.event_ledger:
						engine.event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": "P%d paid %s for %s" % [taxed_pid, tax_cost, src_name]})
					next_step.call(false)
					return
		run_taxed_eff.call()
		return

	# Handle "You may <effect>" interactively for local player
	if c_lower.begins_with("you may "):
		var inner_action := c.substr(8).strip_edges()
		if engine and owner_id == engine.local_player_id and engine.hud_manager and engine.hud_manager.has_method("open_choice_popup"):
			var src_name := str(source.card_data.get("name", "Card")) if source else "Ability"
			engine.hud_manager.open_choice_popup(
				"%s (Optional)" % src_name.to_upper(),
				["Yes: %s" % inner_action.capitalize(), "No (Decline)"],
				func(choice_idx: int):
					if choice_idx == 0:
						_execute_clause_async(inner_action, source, target, engine, owner_id, next_step)
					else:
						next_step.call(false)
			)
			return
		c = inner_action

	_execute_clause_async(c, source, target, engine, owner_id, next_step)

static func _execute_clause_async(clause: String, source: Node3D, target: Variant, engine: Node, owner_id: int, on_done: Callable) -> void:
	var c_l := clause.strip_edges().to_lower()
	if "flip a coin" in c_l and engine and engine.has_method("flip_3d_coin_for_player"):
		var won: bool = engine.flip_3d_coin_for_player(owner_id, str(source.card_data.get("name", "")) if source else "")
		on_done.call(won)
		return
	if ("roll a d20" in c_l or "roll a twenty-sided die" in c_l) and engine and engine.has_method("roll_3d_die_for_player"):
		var r20: int = engine.roll_3d_die_for_player(owner_id, 20, str(source.card_data.get("name", "")) if source else "")
		on_done.call(r20 >= 10)
		return
	if ("roll a d6" in c_l or "roll a six-sided die" in c_l) and engine and engine.has_method("roll_3d_die_for_player"):
		var r6: int = engine.roll_3d_die_for_player(owner_id, 6, str(source.card_data.get("name", "")) if source else "")
		on_done.call(r6 >= 4)
		return
	if c_l == "proliferate" or c_l.begins_with("proliferate "):
		_handle_proliferate(engine, owner_id, on_done)
		return
	if "discard" in c_l and not ("each opponent discards" in c_l and false):
		_handle_discard(c_l, target, engine, owner_id, on_done)
		return
	_execute_clause(clause, source, target, engine, owner_id)
	on_done.call(true)

static func _split_clauses(text: String) -> Array[String]:
	var out: Array[String] = []
	var normalized := text.replace("\n", ". ").replace(";", ".").replace(", then ", ". ").replace(". Then ", ". ")
	if "create " in normalized.to_lower() and "token" in normalized.to_lower() and "\"" in normalized:
		out.append(normalized.strip_edges())
		return out
	var comma_verbs := [", scry ", ", surveil ", ", draw ", ", you gain ", ", gain ", ", you lose ", ", lose ", ", discard ", ", mill ", ", create ", ", destroy ", ", exile ", ", return ", ", put ", ", tap ", ", untap "]
	var raw_sents := normalized.split(".")
	var si := 0
	while si < raw_sents.size():
		var s := raw_sents[si].strip_edges()
		si += 1
		if s.is_empty(): continue
		if "look at the top " in s.to_lower() and "library" in s.to_lower() and si < raw_sents.size():
			var nxt := raw_sents[si].strip_edges()
			var nxt_l := nxt.to_lower()
			if "of them" in nxt_l or "put " in nxt_l or "reveal " in nxt_l:
				s = s + ". " + nxt
				si += 1
				out.append(s)
				continue
		var s_low := s.to_lower()
		var is_cond := s_low.begins_with("if ") or s_low.begins_with("when ") or s_low.begins_with("whenever ") or s_low.begins_with("unless ")
		if is_cond:
			out.append(s)
			continue
		var sub_norm := s
		for comma_verb in comma_verbs:
			if comma_verb == ", put " and "search your library" in s_low:
				continue
			sub_norm = sub_norm.replace(comma_verb, ". " + comma_verb.substr(2))
		for sub_sent in sub_norm.split("."):
			var ss := sub_sent.strip_edges()
			if ss.is_empty(): continue
			for p in _split_compound_and(ss):
				if not p.is_empty(): out.append(p)
	return out

static func _split_compound_and(sentence: String) -> Array[String]:
	var verbs := [
		" and draw ", " and gain ", " and gains ", " and you gain ", " and lose ", " and loses ", " and you lose ",
		" and create ", " and destroy ", " and exile ", " and return ", " and put ",
		" and tap ", " and untap ", " and mill ", " and scry ", " and surveil ", " and discard ",
		" and fights ", " and fight "
	]
	var lower := sentence.to_lower()
	for v in verbs:
		var idx := lower.find(v)
		if idx != -1:
			var left := sentence.substr(0, idx).strip_edges()
			var right := sentence.substr(idx + 5).strip_edges()
			if "until end of turn" in lower and not ("until end of turn" in left.to_lower()):
				left += " until end of turn"
			var res: Array[String] = []
			if not left.is_empty(): res.append(left)
			res.append_array(_split_compound_and(right))
			return res
	return [sentence]

static func _execute_clause(clause: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	var c := clause.to_lower().strip_edges()
	if c.is_empty(): return

	if ("on top of" in c or "on the bottom of" in c) and "library" in c:
		_handle_put_on_library(c, source, target, engine); return
	if "exiled with" in c and ("into your graveyard" in c or "into its owner's graveyard" in c):
		_handle_put_linked_exile_to_gy(source, engine); return
	if "search your library" in c:
		_handle_library_search(c, engine, owner_id); return
	if ("whenever a player taps" in c or "whenever you tap" in c) and "for mana" in c and engine and "eot_mana_bonuses" in engine:
		var flt := "land"
		for l_sub in ["island", "swamp", "mountain", "forest", "plains"]:
			if l_sub in c: flt = l_sub; break
		var add_col := ""
		for sm in _MANA_SYM_REGEX.search_all(c.to_upper()):
			add_col = sm.get_string(1)
			break
		engine.eot_mana_bonuses.append({"filter": flt, "add_color": add_col, "all_players": "a player" in c, "owner_id": owner_id})
		return
	if "become the monarch" in c or "becomes the monarch" in c:
		if engine: engine.set_monarch(owner_id)
		return
	if "take the initiative" in c:
		if engine: engine.set_initiative(owner_id)
		return
	if "venture into the dungeon" in c:
		if engine and engine.has_method("advance_dungeon_for_player"):
			engine.advance_dungeon_for_player(owner_id, "Lost Mine of Phandelver")
		return
	if "the ring tempts you" in c:
		if engine:
			engine.modify_player_counter(owner_id, "ring", 1)
			for p in engine.battlefield_non_lands:
				if is_instance_valid(p) and engine.get_card_owner_id(p) == owner_id and MagicRules.is_creature(p.card_data, 0, p):
					if p.has_method("set_custom_status"):
						p.set_custom_status("Ring-bearer", true)
						break
		return
	if "becomes day" in c:
		if engine: engine.set_day_night("Day")
		return
	if "becomes night" in c:
		if engine: engine.set_day_night("Night")
		return
	if c == "proliferate" or c.begins_with("proliferate "):
		if engine:
			for p_node in engine.battlefield_lands + engine.battlefield_non_lands:
				if not is_instance_valid(p_node): continue
				if "counter_amount" in p_node and int(p_node.counter_amount) != 0 and p_node.has_method("modify_counters"):
					p_node.modify_counters(1 if int(p_node.counter_amount) > 0 else -1)
				if "custom_counters" in p_node and p_node.custom_counters is Dictionary:
					for ck in p_node.custom_counters.keys():
						p_node.modify_named_counter(str(ck), 1)
			for pid in [1, 2, 3, 4]:
				var pc_dict: Dictionary = engine.player_counters.get(pid, {})
				for pk in pc_dict.keys():
					if int(pc_dict[pk]) > 0:
						engine.modify_player_counter(pid, str(pk), 1)
		return
	if " counter" in c and ("put " in c or "remove " in c or "get " in c or "gets " in c or "double " in c or "distribute " in c):
		_handle_counters(c, source, target, engine, owner_id); return
	if "copy target" in c and "spell" in c:
		_handle_copy_spell(target, engine, owner_id); return
	if "discover " in c:
		var d_val := _extract_number(c, "discover ")
		if engine and engine.has_method("trigger_cascade_or_discover"):
			engine.trigger_cascade_or_discover(owner_id, d_val, true)
		return
	if "counter target" in c or c.begins_with("counter "):
		_handle_counter_spell(target, engine); return
	if "create " in c and "token" in c:
		if "copy of" in c:
			var copy_src: Node3D = (target as Node3D) if (target is Node3D and is_instance_valid(target)) else source
			if copy_src != null and is_instance_valid(copy_src) and engine and engine.has_method("_spawn_new_token"):
				var cd: Dictionary = copy_src.card_data.duplicate(true)
				cd["type_line"] = "Token " + str(cd.get("type_line", "Creature"))
				var amt_cp := _extract_number(c, "create ")
				for _ci in range(amt_cp): engine._spawn_new_token(cd)
			return
		_handle_create_tokens(c, engine, owner_id, target); return
	if "draw " in c and ("card" in c or c.ends_with("draws")):
		_handle_draw(c, engine, owner_id, target); return
	if "manifest dread" in c:
		_handle_manifest_dread(engine, owner_id); return
	if ("manifests the top card" in c or "manifest the top card" in c) and "library" in c:
		_handle_manifest_top(c, target, engine, owner_id); return
	if "exile the top " in c and "library" in c:
		_handle_impulse_exile(c, engine, owner_id); return
	if "mill " in c or "mills " in c:
		_handle_mill(c, target, engine, owner_id); return
	if "discard " in c:
		_handle_discard(c, target, engine, owner_id); return
	if "deals " in c and " damage" in c:
		_handle_damage(c, source, target, engine, owner_id); return
	if " life" in c and ("gain " in c or "lose " in c or "loses " in c or "pay " in c):
		_handle_life(c, engine, owner_id, target); return
	if "empower jace" in c:
		_handle_empower_jace(c, engine, owner_id); return
	if "look at the top " in c and "library" in c:
		_handle_look_top_cards(c, engine, owner_id); return
	if c.begins_with("scry ") or " scry " in c:
		_handle_scry_or_surveil(c, engine, owner_id, false); return
	if c.begins_with("surveil ") or " surveil " in c:
		_handle_scry_or_surveil(c, engine, owner_id, true); return
	if "at the beginning of the next end step" in c and engine and engine.turn_manager:
		var eff_part := c.substr(c.find(",") + 1).strip_edges() if "," in c else c
		engine.turn_manager.delayed_triggers.append({"phase": TurnManager.TurnPhase.END, "effect": eff_part, "source": source, "target": target, "owner_id": owner_id})
		return
	if "take an extra turn" in c and engine and engine.turn_manager:
		engine.turn_manager.extra_turn_queue.append(owner_id)
		return
	if "additional combat phase" in c and engine and engine.turn_manager:
		engine.turn_manager.extra_combat_phases += 1
		return
	if "gain control of " in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			n.set_meta("control_override_player_id", owner_id)
			if "until end of turn" in c: n.set_meta("control_until_eot", true)
			engine.zone_manager.update_battlefield_positions(true)
		return
	if "exile " in c and ("return it" in c or "return that card" in c) and "battlefield" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if engine:
				engine._on_card_to_exile(n)
				engine.zone_manager.move_to_battlefield_from_zone(n, owner_id if "your control" in c else engine.get_card_owner_id(n), "tapped" in c)
		return
	if ("becomes a " in c or "become a " in c) and ("creature" in c or "base power" in c):
		_handle_animate_permanent(c, source, target, engine, owner_id); return
	if "base power and toughness " in c:
		_handle_set_base_pt(c, source, target, engine, owner_id); return
	if "switch " in c and "power and toughness" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			var cur_sw: bool = n.has_meta("pt_switched") and bool(n.get_meta("pt_switched"))
			n.set_meta("pt_switched", not cur_sw)
		return
	if "fights " in c or " fight " in c:
		_handle_fight(source, target, engine); return
	if "goad " in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if "goaded_by_player_id" in n:
				n.goaded_by_player_id = owner_id
				n.refresh_visual_status()
		return
	if "sacrifice" in c:
		_handle_sacrifice(c, source, target, engine, owner_id); return
	if ("gains " in c or "gain " in c) and ("until end of turn" in c or "target " in c or "creatures you control" in c):
		_handle_temp_keywords(c, source, target, engine, owner_id)
		if _PT_REGEX.search(c) == null: return
	if "until end of turn" in c and (_PT_REGEX.search(c) != null or ("+x/+x" in c and "difference between its power and toughness" in c)):
		_handle_temp_pt(c, source, target, engine, owner_id); return
	if "{e}" in c or "energy counter" in c or " counter" in c:
		_handle_counters(c, source, target, engine, owner_id); return
	if c.begins_with("exile ") or " exile " in c:
		var is_ltb_exile := ("until " in c and "leaves the battlefield" in c)
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if is_ltb_exile and source != null and is_instance_valid(source):
				var ltb_arr: Array = source.get_meta("ltb_return_cards") if source.has_meta("ltb_return_cards") else []
				ltb_arr.append(n)
				source.set_meta("ltb_return_cards", ltb_arr)
			if engine: engine._on_card_to_exile(n)
		return
	if c.begins_with("destroy ") or " destroy " in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if n.has_method("has_keyword") and bool(n.has_keyword("indestructible")): continue
			if n.has_method("get_named_counter") and n.get_named_counter("shield") > 0:
				n.modify_named_counter("shield", -1)
				continue
			if engine: engine._on_card_to_graveyard(n)
		return
	if ("return " in c or "put " in c) and ("onto the battlefield" in c or "to the battlefield" in c) and target is Node3D and is_instance_valid(target):
		if engine: engine.zone_manager.move_to_battlefield_from_zone(target as Node3D, owner_id, "tapped" in c)
		return
	if "return " in c and "hand" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if engine: engine._on_card_returned_to_hand(n)
		return
	if c.begins_with("tap ") or " tap target" in c or " tap all" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if not n.is_tapped: n.toggle_tap()
		return
	if c.begins_with("untap ") or " untap target" in c or " untap all" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if n.is_tapped:
				if n.has_method("get_named_counter") and n.get_named_counter("stun") > 0:
					n.modify_named_counter("stun", -1)
				else:
					n.toggle_tap()
		return
	if "attach " in c and engine:
		if source and is_instance_valid(source) and target is Node3D and is_instance_valid(target):
			engine.zone_manager.attach_card_to_creature(source, target, false)
		return
	if c.begins_with("transform") or " transform " in c:
		if source and is_instance_valid(source) and source.has_method("transform_card"):
			source.transform_card()
		return
	if "add " in c and engine:
		_handle_add_mana(clause, source, engine)

# --- ACTION HANDLERS ---

static func _handle_draw(c: String, engine: Node, owner_id: int, target: Variant) -> void:
	if not engine: return
	var amount := _extract_number(c, "draw ")
	for pid in _resolve_affected_players(c, engine, owner_id, target):
		for i in range(amount):
			if pid == engine.local_player_id: engine.draw_card()
			else: engine._draw_opponent_card(pid)

static func _handle_impulse_exile_cards(amount: int, engine: Node, owner_id: int) -> Array[Node3D]:
	var exiled: Array[Node3D] = []
	if not engine: return exiled
	var lib: Array = engine.library_stack if owner_id == engine.local_player_id else engine.player_libraries.get(owner_id, [])
	for i in range(amount):
		if lib.is_empty(): break
		var top_card: Node3D = lib.pop_back()
		if owner_id == engine.local_player_id:
			engine.player_libraries.get(owner_id, []).erase(top_card)
		if is_instance_valid(top_card):
			if top_card.has_method("make_active"): top_card.make_active(top_card.card_data)
			engine.connect_card_signals(top_card)
			top_card.set_meta("playable_from_exile", true)
			top_card.set_meta("playable_by_pid", owner_id)
			if engine.turn_manager:
				top_card.set_meta("playable_until_turn", engine.turn_manager.turn_number)
			engine._on_card_to_exile(top_card)
			exiled.append(top_card)
	if engine.zone_manager:
		engine.zone_manager.update_zone_counters()
	return exiled

static func _handle_impulse_exile(c: String, engine: Node, owner_id: int) -> void:
	var amount := _extract_number(c, "exile the top ")
	_handle_impulse_exile_cards(amount, engine, owner_id)

static func _manifest_card_node(card_node: Node3D, pid: int, engine: Node) -> void:
	if not is_instance_valid(card_node) or not engine or not engine.zone_manager: return
	var real_data: Dictionary = card_node.card_data.duplicate(true)
	card_node.set_meta("is_manifested", true)
	card_node.set_meta("manifested_card_data", real_data)
	var face_down_data := {
		"name": "Manifested Creature",
		"type_line": "Creature",
		"mana_cost": "",
		"cmc": 0,
		"colors": [],
		"power": "2",
		"toughness": "2",
		"oracle_text": "Face-down 2/2 manifested creature (Pay its mana cost anytime to turn face up if it's a creature card)."
	}
	card_node.card_data = face_down_data
	if card_node.has_method("make_active"): card_node.make_active(face_down_data)
	engine.zone_manager.move_to_battlefield_from_zone(card_node, pid, false)

static func _handle_manifest_top(c: String, target: Variant, engine: Node, owner_id: int) -> void:
	if not engine: return
	var pid: int = owner_id
	if "its controller" in c and target is Node3D and is_instance_valid(target):
		pid = engine.get_card_owner_id(target)
	elif "target " in c and target is int:
		pid = int(target)
	var lib: Array = engine.library_stack if pid == engine.local_player_id else engine.player_libraries.get(pid, [])
	if lib.is_empty(): return
	var top_c: Node3D = lib.pop_back()
	if pid == engine.local_player_id:
		engine.player_libraries.get(pid, []).erase(top_c)
	_manifest_card_node(top_c, pid, engine)
	if engine.zone_manager: engine.zone_manager.update_zone_counters()

static func _handle_manifest_dread(engine: Node, owner_id: int) -> void:
	if not engine: return
	var lib: Array = engine.library_stack if owner_id == engine.local_player_id else engine.player_libraries.get(owner_id, [])
	if lib.is_empty(): return
	var top_cards: Array[Node3D] = []
	for _i in range(mini(2, lib.size())):
		var tc: Node3D = lib.pop_back()
		if owner_id == engine.local_player_id:
			engine.player_libraries.get(owner_id, []).erase(tc)
		if is_instance_valid(tc): top_cards.append(tc)
	if top_cards.is_empty(): return
	if top_cards.size() == 1:
		_manifest_card_node(top_cards[0], owner_id, engine)
		return
	if owner_id == engine.local_player_id and engine.hud_manager and engine.hud_manager.has_method("open_zone_viewer"):
		engine.hud_manager.open_zone_viewer("MANIFEST DREAD — CHOOSE 1 TO MANIFEST (OTHER -> GRAVEYARD)", top_cards, owner_id, func(chosen: Node3D):
			for tc in top_cards:
				if tc == chosen:
					_manifest_card_node(tc, owner_id, engine)
				else:
					if tc.has_method("make_active"): tc.make_active(tc.card_data)
					engine.connect_card_signals(tc)
					engine._on_card_to_graveyard(tc)
			if engine.zone_manager: engine.zone_manager.update_zone_counters()
		)
	else:
		var pick: Node3D = top_cards[0]
		for tc in top_cards:
			if MagicRules.is_creature(tc.card_data):
				pick = tc; break
		for tc in top_cards:
			if tc == pick:
				_manifest_card_node(tc, owner_id, engine)
			else:
				engine._on_card_to_graveyard(tc)
		if engine.zone_manager: engine.zone_manager.update_zone_counters()

static func _handle_mill(c: String, target: Variant, engine: Node, owner_id: int) -> void:
	if not engine: return
	var is_half_lib: bool = ("half" in c and "library" in c)
	var base_amount := _extract_number(c, "mills " if "mills " in c else "mill ")
	for pid in _resolve_affected_players(c, engine, owner_id, target):
		var lib: Array = engine.library_stack if pid == engine.local_player_id else engine.player_libraries.get(pid, [])
		var amount: int = base_amount
		if is_half_lib:
			var lib_cnt: int = lib.size()
			amount = ceili(float(lib_cnt) / 2.0) if ("rounded up" in c) else int(floor(float(lib_cnt) / 2.0))
		if amount > 0:
			for perm in engine.battlefield_non_lands + engine.battlefield_lands:
				if not is_instance_valid(perm) or not perm.is_on_battlefield: continue
				var p_ol: String = str(MagicRules.get_card_attribute(perm.card_data, "oracle_text", "")).to_lower()
				if "would mill" in p_ol and "twice that many" in p_ol:
					var p_owner: int = engine.get_card_owner_id(perm)
					if ("an opponent would mill" in p_ol and pid != p_owner) or ("you would mill" in p_ol and pid == p_owner) or ("a player would mill" in p_ol):
						amount *= 2
		for i in range(amount):
			if lib.is_empty(): break
			var top_card: Node3D = lib.pop_back()
			if pid == engine.local_player_id:
				engine.player_libraries.get(pid, []).erase(top_card)
			if is_instance_valid(top_card):
				if top_card.has_method("make_active"): top_card.make_active(top_card.card_data)
				engine.connect_card_signals(top_card)
				engine._on_card_to_graveyard(top_card)
		if engine.zone_manager:
			engine.zone_manager.update_zone_counters()

static func _handle_discard(c: String, target: Variant, engine: Node, owner_id: int, on_done: Callable = Callable()) -> void:
	if not engine:
		if on_done.is_valid(): on_done.call(false)
		return
	var amount := _extract_number(c, "discard ")
	var is_random := "at random" in c
	var target_pids: Array[int] = []
	if "each opponent" in c:
		for pid in [1, 2, 3, 4]:
			if pid != owner_id and int(engine.player_life.get(pid, 0)) > 0:
				target_pids.append(pid)
	elif "each player" in c:
		for pid in [1, 2, 3, 4]:
			if int(engine.player_life.get(pid, 0)) > 0:
				target_pids.append(pid)
	elif "target " in c and target is int:
		target_pids.append(int(target))
	else:
		target_pids.append(owner_id)

	var did_any_discard := false
	var waiting_human_discard := false
	for pid in target_pids:
		var hand_arr: Array = engine.hand_cards if pid == engine.local_player_id else engine.player_hands.get(pid, [])
		if hand_arr.is_empty(): continue
		var count: int = mini(amount, hand_arr.size())
		if is_random:
			did_any_discard = true
			for i in range(count):
				if hand_arr.is_empty(): break
				var idx := randi() % hand_arr.size()
				var card_to_discard: Node3D = hand_arr[idx]
				hand_arr.remove_at(idx)
				if pid == engine.local_player_id:
					engine.player_hands.get(pid, []).erase(card_to_discard)
					engine.zone_manager.update_hand_positions(true)
				else:
					if card_to_discard.has_method("make_active"): card_to_discard.make_active(card_to_discard.card_data)
					engine.zone_manager.update_opponent_hand_positions(pid, true)
				engine._on_card_to_graveyard(card_to_discard)
		elif pid == engine.local_player_id:
			if hand_arr.size() <= count:
				did_any_discard = true
				for i in range(count):
					if hand_arr.is_empty(): break
					var card_to_discard: Node3D = hand_arr.pop_back()
					engine.player_hands.get(pid, []).erase(card_to_discard)
					engine._on_card_to_graveyard(card_to_discard)
				engine.zone_manager.update_hand_positions(true)
			else:
				waiting_human_discard = true
				engine.hud_manager.open_discard_choice(count, on_done)
		else:
			did_any_discard = true
			for i in range(count):
				if hand_arr.is_empty(): break
				var best_card: Node3D = hand_arr[0]
				var best_score := -999
				for cand in hand_arr:
					var is_l := MagicRules.is_land(cand.card_data)
					var cmc := int(cand.card_data.get("cmc", 0))
					var score := 10 if is_l else cmc
					if score > best_score:
						best_score = score
						best_card = cand
				hand_arr.erase(best_card)
				if best_card.has_method("make_active"): best_card.make_active(best_card.card_data)
				engine.zone_manager.update_opponent_hand_positions(pid, true)
				if engine.has_method("handle_discard_with_madness"):
					engine.handle_discard_with_madness(best_card, pid)
				else:
					engine._on_card_to_graveyard(best_card)
	if not waiting_human_discard and on_done.is_valid():
		on_done.call(did_any_discard)

static func _apply_noncombat_damage_modifiers(base_amount: int, source_controller_id: int, target_owner_id: int, target_is_permanent: bool, engine: Node) -> int:
	if base_amount <= 0 or engine == null:
		return base_amount
	var amt := base_amount
	var plus_rx := RegEx.new()
	plus_rx.compile("plus\\s+(\\d+)")
	for perm in engine.battlefield_lands + engine.battlefield_non_lands:
		if not is_instance_valid(perm) or not perm.is_on_battlefield:
			continue
		var perm_ctrl: int = engine.get_card_owner_id(perm)
		var oracle := str(MagicRules.get_card_attribute(perm.card_data, "oracle_text", "")).to_lower()
		for line in oracle.split("\n"):
			if not ("would deal" in line and "damage" in line and "instead" in line):
				continue
			if "source you control" in line and perm_ctrl != source_controller_id:
				continue
			if "to an opponent or a permanent an opponent controls" in line:
				if target_owner_id == perm_ctrl:
					continue
			elif "to an opponent" in line and not ("permanent" in line):
				if target_is_permanent or target_owner_id == perm_ctrl:
					continue
			if "plus x, where x is" in line and "'s power" in line:
				var p_pow: int = maxi(0, int(perm.dynamic_power)) if "dynamic_power" in perm else 0
				amt += p_pow
			else:
				var pm := plus_rx.search(line)
				if pm:
					amt += pm.get_string(1).to_int()
			if "double that damage" in line or "twice that much damage" in line:
				amt *= 2
			elif "triple that damage" in line:
				amt *= 3
	return amt

static func _handle_damage(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	var amount := _extract_dynamic_amount(c, "deals ", source, target, engine, owner_id)
	var has_deathtouch: bool = source != null and source.has_method("has_keyword") and bool(source.has_keyword("deathtouch"))
	var has_lifelink: bool = source != null and source.has_method("has_keyword") and bool(source.has_keyword("lifelink"))
	var total_dealt := 0

	var src_ol_d := str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower() if source != null else ""
	var has_infect: bool = (source != null and source.has_method("has_keyword") and bool(source.has_keyword("infect"))) or ("infect" in src_ol_d)
	var has_wither: bool = has_infect or (source != null and source.has_method("has_keyword") and bool(source.has_keyword("wither"))) or ("wither" in src_ol_d)
	if "each creature" in c or "all creatures" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if MagicRules.has_protection_from(n, source) and not MagicRules.is_damage_unpreventable(source, engine): continue
			if "marked_damage" in n:
				var tgt_owner: int = engine.get_card_owner_id(n) if engine else -1
				var final_amt := _apply_noncombat_damage_modifiers(amount, owner_id, tgt_owner, true, engine)
				if has_wither and n.has_method("modify_counters"):
					n.modify_counters(-final_amt)
				else:
					n.marked_damage += final_amt
				if has_deathtouch: n.has_deathtouch_damage = true
				n.refresh_visual_status()
				total_dealt += final_amt
	elif "each opponent" in c or "each player" in c:
		for pid in _resolve_affected_players(c, engine, owner_id, target):
			if engine:
				var final_amt := _apply_noncombat_damage_modifiers(amount, owner_id, pid, false, engine)
				engine.modify_life(pid, -final_amt)
				total_dealt += final_amt
	elif target is Node3D and is_instance_valid(target):
		var t_node := target as Node3D
		var tgt_owner: int = engine.get_card_owner_id(t_node) if engine else -1
		var final_amt := _apply_noncombat_damage_modifiers(amount, owner_id, tgt_owner, true, engine)
		if MagicRules.has_protection_from(t_node, source) and not MagicRules.is_damage_unpreventable(source, engine):
			pass
		elif MagicRules.is_planeswalker(t_node.card_data):
			if t_node.has_method("modify_named_counter"):
				t_node.modify_named_counter("loyalty", -final_amt)
			EventBus.damage_dealt.emit(source, t_node, final_amt)
			total_dealt += final_amt
		elif "marked_damage" in t_node:
			if has_wither and t_node.has_method("modify_counters"):
				t_node.modify_counters(-final_amt)
			else:
				t_node.marked_damage += final_amt
			if has_deathtouch: t_node.has_deathtouch_damage = true
			t_node.refresh_visual_status()
			EventBus.damage_dealt.emit(source, t_node, final_amt)
			total_dealt += final_amt
	elif target is int and engine:
		var tgt_pid := int(target)
		var final_amt := _apply_noncombat_damage_modifiers(amount, owner_id, tgt_pid, false, engine)
		if has_infect:
			engine.modify_player_counter(tgt_pid, "poison", final_amt)
		else:
			engine.modify_life(tgt_pid, -final_amt)
		EventBus.damage_dealt.emit(source, tgt_pid, final_amt)
		total_dealt += final_amt
	elif engine:
		var opp_id: int = (owner_id % 4) + 1
		var final_amt := _apply_noncombat_damage_modifiers(amount, owner_id, opp_id, false, engine)
		engine.modify_life(opp_id, -final_amt)
		total_dealt += final_amt

	if has_lifelink and total_dealt > 0 and engine:
		engine.modify_life(owner_id, total_dealt)

static func _handle_life(c: String, engine: Node, owner_id: int, target: Variant) -> void:
	if not engine: return
	var is_loss := ("lose " in c or "loses " in c or "pay " in c)
	var prefix := "pay " if "pay " in c else ("loses " if "loses " in c else ("lose " if "lose " in c else "gain "))
	var amount := _extract_dynamic_amount(c, prefix, null, target, engine, owner_id)
	var delta := -amount if is_loss else amount
	for pid in _resolve_affected_players(c, engine, owner_id, target):
		engine.modify_life(pid, delta)

static func _handle_temp_pt(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	if "difference between its power and toughness" in c and "+x/+x" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if "temp_power_modifier" in n:
				var cur_p: int = int(n.dynamic_power) if "dynamic_power" in n else 0
				var cur_t: int = int(n.dynamic_toughness) if "dynamic_toughness" in n else 0
				var diff: int = absi(cur_p - cur_t)
				n.temp_power_modifier += diff
				n.temp_toughness_modifier += diff
				n.refresh_visual_status()
		return
	var m := _PT_REGEX.search(c)
	if not m: return
	var p_mod := m.get_string(1).to_int()
	var t_mod := m.get_string(2).to_int()
	for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
		if "temp_power_modifier" in n:
			n.temp_power_modifier += p_mod
			n.temp_toughness_modifier += t_mod
			n.refresh_visual_status()

static func _handle_counters(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	_ensure_regex()
	var is_remove := "remove " in c
	var is_double := "double " in c and "counter" in c
	var amount := 1
	if is_remove:
		amount = -_extract_number(c, "remove ")
	elif "distribute " in c:
		amount = _extract_number(c, "distribute ")
	elif "get " in c:
		amount = _extract_number(c, "get ")
	elif "gets " in c:
		amount = _extract_number(c, "gets ")
	else:
		amount = _extract_dynamic_amount(c, "put ", source, target, engine, owner_id)

	var c_type := ""
	if "{e}" in c:
		c_type = "energy"
		var e_cnt := c.count("{e}")
		if e_cnt > 0:
			amount = -e_cnt if is_remove else e_cnt
	elif "+1/+1 counter" in c:
		c_type = "+1/+1"
	elif "-1/-1 counter" in c:
		c_type = "-1/-1"
	else:
		var cm := _ANY_COUNTER_REGEX.search(c)
		if cm:
			c_type = cm.get_string(1).strip_edges().to_lower()
	if c_type.is_empty():
		return

	# Player counters ("you get", "target player gets", "remove ... from target player")
	var is_player_counter := ("{e}" in c or c_type in ["energy", "poison", "experience", "rad"] or "get " in c or "gets " in c or "target player" in c or "each player" in c or "target opponent" in c or "each opponent" in c or "from you" in c) and not ("creature" in c or "permanent" in c or "artifact" in c or "planeswalker" in c)
	if is_player_counter and engine:
		for pid in _resolve_affected_players(c, engine, owner_id, target):
			if is_double:
				var cur_pc: int = int(engine.player_counters.get(pid, {}).get(c_type, 0))
				if cur_pc > 0: engine.modify_player_counter(pid, c_type, cur_pc)
			else:
				engine.modify_player_counter(pid, c_type, amount)
		return

	for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
		if c_type == "+1/+1" or c_type == "-1/-1":
			var delta: int = (-amount if c_type == "-1/-1" else amount)
			if is_double and "counter_amount" in n:
				delta = int(n.counter_amount)
			if delta != 0 and n.has_method("modify_counters"):
				n.modify_counters(delta)
		else:
			var n_delta: int = amount
			if is_double and n.has_method("get_named_counter"):
				n_delta = n.get_named_counter(c_type)
			if n_delta != 0 and n.has_method("modify_named_counter"):
				n.modify_named_counter(c_type, n_delta)

static func _handle_create_tokens(c: String, engine: Node, owner_id: int = 1, target: Variant = null) -> void:
	if not engine or not engine.has_method("_spawn_new_token"): return
	var amount := _extract_number(c, "create ")
	if "for each opponent" in c and ("dealt damage this turn" in c or "lost life this turn" in c):
		var dmg_map: Dictionary = engine.get("players_damaged_this_turn") if "players_damaged_this_turn" in engine else {}
		var opp_cnt := 0
		for pid in [1, 2, 3, 4]:
			if pid != owner_id and bool(dmg_map.get(pid, false)):
				opp_cnt += 1
		amount = opp_cnt
	elif "for each player" in c and "dealt damage this turn" in c:
		var dmg_map2: Dictionary = engine.get("players_damaged_this_turn") if "players_damaged_this_turn" in engine else {}
		var p_cnt := 0
		for pid in [1, 2, 3, 4]:
			if bool(dmg_map2.get(pid, false)):
				p_cnt += 1
		amount = p_cnt
	if amount <= 0:
		return
	var tok_pids: Array[int] = [owner_id]
	if "its controller" in c or "that creature's controller" in c or "that permanent's controller" in c or "that spell's controller" in c:
		var ctrl_pid: int = int(engine.get_meta("last_target_controller_id")) if engine.has_meta("last_target_controller_id") else -1
		if ctrl_pid <= 0 and target is Node3D and is_instance_valid(target):
			ctrl_pid = engine.get_card_controller_id(target)
		elif ctrl_pid <= 0 and target is int and int(target) > 0:
			ctrl_pid = int(target)
		if ctrl_pid > 0:
			tok_pids = [ctrl_pid]
	elif ("target opponent creates" in c or "target player creates" in c) and target is int and int(target) > 0:
		tok_pids = [int(target)]
	elif "each opponent creates" in c:
		tok_pids = []
		for op in [1, 2, 3, 4]:
			if op != owner_id and int(engine.player_life.get(op, 0)) > 0:
				tok_pids.append(op)
	var artifact_presets := {"treasure": "Treasure", "clue": "Clue", "food": "Food", "blood": "Blood", "map": "Map", "powerstone": "Powerstone"}
	for key in artifact_presets.keys():
		if key in c:
			var target_name: String = artifact_presets[key]
			for t in engine.COMMON_TOKENS:
				if t["name"] == target_name:
					for p_dest in tok_pids:
						for i in range(amount): engine._spawn_new_token(t, p_dest)
					return

	var m := _TOKEN_PT_REGEX.search(c)
	if m:
		var pow_str := m.get_string(1)
		var tou_str := m.get_string(2)
		if pow_str == "x" or tou_str == "x":
			var x_pt := 0
			if "mana value" in c and target is Node3D and is_instance_valid(target):
				x_pt = int(target.card_data.get("cmc", 0))
			elif "cards in your hand" in c and engine:
				x_pt = engine.hand_cards.size() if owner_id == engine.local_player_id else (engine.player_hands.get(owner_id, []) as Array).size()
			elif "your life" in c and engine:
				x_pt = maxi(0, int(engine.player_life.get(owner_id, 0)))
			if pow_str == "x": pow_str = str(x_pt)
			if tou_str == "x": tou_str = str(x_pt)
		var raw_desc := m.get_string(3).strip_edges().to_lower()
		var color_map := {"white": "w", "blue": "u", "black": "b", "red": "r", "green": "g", "colorless": "c"}
		var extra_types := ["artifact", "enchantment", "legendary", "snow"]
		var colors_found: Array[String] = []
		var extras_found: Array[String] = []
		var subtypes: Array[String] = []
		for w in raw_desc.split(" ", false):
			if w == "and": continue
			elif color_map.has(w):
				colors_found.append(color_map[w])
			elif w in extra_types:
				extras_found.append(w)
			else:
				subtypes.append(w.capitalize())

		var subtype_str := " ".join(subtypes) if not subtypes.is_empty() else "Creature"
		var query_parts: Array[String] = []
		for st in subtypes: query_parts.append("t:" + st.to_lower())
		for et in extras_found: query_parts.append("t:" + et)
		for col in colors_found:
			if col != "c": query_parts.append("c:" + col)
		query_parts.append("t:token")
		query_parts.append("pow=" + pow_str)
		query_parts.append("tou=" + tou_str)
		if "flying" in c: query_parts.append("o:flying")
		query_parts.append("-is:dfc")

		var tok_oracle_parts: Array[String] = []
		if "flying" in c: tok_oracle_parts.append("Flying")
		var q_start := c.find("\"")
		if q_start != -1:
			var q_end := c.find("\"", q_start + 1)
			if q_end != -1:
				tok_oracle_parts.append(c.substr(q_start + 1, q_end - q_start - 1).strip_edges())
		var tok_oracle := "\n".join(tok_oracle_parts)
		var extra_tl := (" ".join(extras_found).capitalize() + " ") if not extras_found.is_empty() else ""
		var token_dict := {
			"name": "%s/%s %s" % [pow_str, tou_str, subtype_str],
			"type_line": "Token %sCreature — %s" % [extra_tl, subtype_str],
			"power": pow_str,
			"toughness": tou_str,
			"oracle_text": tok_oracle,
			"query": " ".join(query_parts)
		}
		for p_dest in tok_pids:
			for i in range(amount): engine._spawn_new_token(token_dict, p_dest)

static func _handle_add_mana(clause: String, source: Node3D, engine: Node) -> void:
	var lower := clause.to_lower()
	if "any color" in lower or "mana of any" in lower:
		engine.show_mana_choice_popup(source, ["W", "U", "B", "R", "G"])
		return
	for m in _MANA_SYM_REGEX.search_all(clause.to_upper()):
		var col := m.get_string(1)
		if engine.mana_pool.has(col):
			engine.mana_pool[col] += 1
			if source: engine.spawn_mana_produced_animation(source, [col])
	engine.update_mana_ui()

static func _resolve_affected_permanents(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not engine:
		if target is Node3D and is_instance_valid(target): result.append(target)
		elif source and is_instance_valid(source): result.append(source)
		return result

	var all_perms: Array = engine.battlefield_lands + engine.battlefield_non_lands
	var matched_group := false
	if "creatures you control" in c or "each creature you control" in c:
		matched_group = true
		for p in all_perms:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data, 0, p) and engine.get_card_controller_id(p) == owner_id: result.append(p)
	elif "creatures your opponents control" in c or "creatures you don't control" in c or "each creature your opponents control" in c:
		matched_group = true
		for p in all_perms:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data, 0, p) and engine.get_card_controller_id(p) != owner_id: result.append(p)
	elif "all creatures" in c or "each creature" in c:
		matched_group = true
		for p in all_perms:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data, 0, p): result.append(p)
	elif "all artifacts" in c or "each artifact" in c:
		matched_group = true
		for p in all_perms:
			if is_instance_valid(p) and "artifact" in MagicRules.get_card_type_line(p.card_data).to_lower(): result.append(p)
	elif "all enchantments" in c or "each enchantment" in c:
		matched_group = true
		for p in all_perms:
			if is_instance_valid(p) and "enchantment" in MagicRules.get_card_type_line(p.card_data).to_lower(): result.append(p)
	elif "all permanents" in c or "all nonland permanents" in c:
		matched_group = true
		var skip_lands := "nonland" in c
		for p in all_perms:
			if is_instance_valid(p):
				if skip_lands and MagicRules.is_land(p.card_data): continue
				result.append(p)

	if matched_group:
		if ("chosen type" in c or "that type" in c) and engine:
			var ch_t: String = str(source.get_meta("chosen_creature_type")) if (source != null and is_instance_valid(source) and source.has_meta("chosen_creature_type")) else str(engine.get_meta("spell_chosen_creature_type") if engine.has_meta("spell_chosen_creature_type") else "")
			if not ch_t.is_empty():
				var ch_low := ch_t.to_lower()
				var is_neg := ("aren't of" in c or "not of" in c or "except" in c or "other than" in c)
				var ct_filtered: Array[Node3D] = []
				for p in result:
					var p_tl := MagicRules.get_card_type_line(p.card_data).to_lower()
					var has_t := ch_low in p_tl
					if (not has_t if is_neg else has_t):
						ct_filtered.append(p)
				result = ct_filtered
		if "with mana value " in c:
			var mv := _extract_number(c, "with mana value ")
			var filtered: Array[Node3D] = []
			for p in result:
				var p_mv := int(round(float(p.card_data.get("cmc", 0.0))))
				if "or less" in c and p_mv <= mv: filtered.append(p)
				elif ("or greater" in c or "or more" in c) and p_mv >= mv: filtered.append(p)
				elif not ("or less" in c or "or greater" in c or "or more" in c) and p_mv == mv: filtered.append(p)
			return filtered
		return result

	if target is Node3D and is_instance_valid(target): result.append(target)
	elif source and is_instance_valid(source):
		var src_name := str(source.card_data.get("name", "")).to_lower().split(" // ")[0].strip_edges()
		var src_short := src_name.split(",")[0].strip_edges() if "," in src_name else src_name
		var mentions_self := ("this " in c or "itself" in c or "on it" in c or "~" in c or (not src_name.is_empty() and src_name in c) or (src_short.length() >= 3 and src_short in c))
		if mentions_self or not ("target" in c):
			result.append(source)
	return result

static func _resolve_affected_players(c: String, _engine: Node, owner_id: int, target: Variant) -> Array[int]:
	var pids: Array[int] = []
	var is_living := func(p: int) -> bool:
		return _engine == null or int(_engine.player_life.get(p, 40)) > 0
	if "each player" in c:
		for pid in [1, 2, 3, 4]:
			if is_living.call(pid): pids.append(pid)
		return pids
	var includes_you: bool = ("you and " in c or "and you " in c or "you each" in c)
	if "each opponent" in c:
		if includes_you and is_living.call(owner_id):
			pids.append(owner_id)
		for pid in [1, 2, 3, 4]:
			if pid != owner_id and is_living.call(pid): pids.append(pid)
		return pids
	if "target opponent" in c or "target player" in c:
		var tgt_pid: int = int(target) if target is int else ((owner_id % 4) + 1)
		if includes_you and is_living.call(owner_id):
			pids.append(owner_id)
		if not (tgt_pid in pids) and is_living.call(tgt_pid):
			pids.append(tgt_pid)
		return pids
	if ("that player" in c or "they " in c) and target is int:
		var t_p: int = int(target)
		if is_living.call(t_p):
			return [t_p]
	return [owner_id]

static func _extract_number(text: String, prefix: String) -> int:
	var idx := text.find(prefix)
	if idx == -1: return 1
	var sub := text.substr(idx + prefix.length()).strip_edges()
	var words := sub.split(" ")
	if words.size() == 0: return 1
	var num_str := words[0].strip_edges().trim_suffix(",").trim_suffix(".")
	match num_str:
		"a", "an", "one": return 1
		"two": return 2
		"three": return 3
		"four": return 4
		"five": return 5
		"six": return 6
		"seven": return 7
		"eight": return 8
		"nine": return 9
		"ten": return 10
		"twenty": return 20
		_:
			if num_str.is_valid_int(): return num_str.to_int()
	return 1

static func _evaluate_for_each_count(c: String, _source: Node3D, engine: Node, owner_id: int) -> int:
	if not ("for each " in c) or not engine: return 1
	var count := 0
	if "creature you control" in c or "creatures you control" in c:
		for p in engine.battlefield_non_lands:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data, 0, p) and engine.get_card_owner_id(p) == owner_id:
				count += 1
	elif "opponent" in c:
		for pid in [1, 2, 3, 4]:
			if pid != owner_id and int(engine.player_life.get(pid, 0)) > 0:
				count += 1
	elif "card in your graveyard" in c or "cards in your graveyard" in c:
		var gy: Array = engine.graveyard_stack if owner_id == engine.local_player_id else engine.player_graveyards.get(owner_id, [])
		count = gy.size()
	elif "land you control" in c or "lands you control" in c:
		for l in engine.battlefield_lands:
			if is_instance_valid(l) and engine.get_card_owner_id(l) == owner_id:
				count += 1
	return max(1, count)

static func _handle_scry_or_surveil(c: String, engine: Node, owner_id: int, is_surveil: bool) -> void:
	if not engine: return
	var kw := "surveil " if is_surveil else "scry "
	var amount := _extract_number(c, kw)
	var lib: Array = engine.library_stack if owner_id == engine.local_player_id else engine.player_libraries.get(owner_id, [])
	if lib.is_empty() or amount <= 0: return
	var count: int = mini(amount, lib.size())
	var top_cards: Array = []
	for i in range(count):
		var idx: int = lib.size() - 1 - i
		var card_n: Node3D = lib[idx]
		if is_instance_valid(card_n):
			top_cards.append(card_n)

	if owner_id != engine.local_player_id:
		var my_lands := 0
		for l in engine.battlefield_lands:
			if is_instance_valid(l) and engine.get_card_owner_id(l) == owner_id: my_lands += 1
		for card_n in top_cards:
			var is_l := MagicRules.is_land(card_n.card_data)
			var cmc := int(card_n.card_data.get("cmc", 0))
			var ol := str(MagicRules.get_card_attribute(card_n.card_data, "oracle_text", "")).to_lower()
			var has_gy_play := "flashback" in ol or "escape" in ol or "unearth" in ol
			var send_away := (my_lands >= 4 and is_l) or (my_lands <= 2 and not is_l and cmc >= 5) or (is_surveil and has_gy_play)
			if send_away:
				lib.erase(card_n)
				if is_surveil:
					if card_n.has_method("make_active"): card_n.make_active(card_n.card_data)
					engine._on_card_to_graveyard(card_n)
				else:
					lib.push_front(card_n)
		engine.zone_manager.update_zone_counters()
		return

	for card_n in top_cards:
		if card_n.has_method("make_active"): card_n.make_active(card_n.card_data)
	engine.hud_manager.open_scry_surveil_popup(is_surveil, top_cards)

static func _handle_temp_keywords(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	var granted: Array[String] = []
	for kw in ContinuousEffectsEngine.GRANTABLE_KEYWORDS:
		if kw in c:
			granted.append(kw)
	if granted.is_empty(): return
	for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
		var existing: Array = n.get_meta("temp_granted_keywords") if n.has_meta("temp_granted_keywords") else []
		for kw in granted:
			if not (kw in existing): existing.append(kw)
		n.set_meta("temp_granted_keywords", existing)

static func _handle_set_base_pt(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	ContinuousEffectsEngine._ensure_regex()
	var m := ContinuousEffectsEngine._BASE_PT_REGEX.search(c)
	if not m: return
	var bp := m.get_string(1).to_int()
	var bt := m.get_string(2).to_int()
	for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
		n.set_meta("base_pt_override", Vector2i(bp, bt))

static func _handle_fight(source: Node3D, target: Variant, _engine: Node) -> void:
	if not source or not is_instance_valid(source) or not (target is Node3D) or not is_instance_valid(target): return
	var tgt := target as Node3D
	var src_pow: int = int(source.get("dynamic_power")) if source.get("dynamic_power") != null else 0
	var tgt_pow: int = int(tgt.get("dynamic_power")) if tgt.get("dynamic_power") != null else 0
	if src_pow > 0 and "marked_damage" in tgt:
		tgt.marked_damage += src_pow
		if source.has_method("has_keyword") and bool(source.has_keyword("deathtouch")):
			tgt.has_deathtouch_damage = true
		tgt.refresh_visual_status()
		EventBus.damage_dealt.emit(source, tgt, src_pow)
	if tgt_pow > 0 and "marked_damage" in source:
		source.marked_damage += tgt_pow
		if tgt.has_method("has_keyword") and bool(tgt.has_keyword("deathtouch")):
			source.has_deathtouch_damage = true
		source.refresh_visual_status()
		EventBus.damage_dealt.emit(tgt, source, tgt_pow)

static func _matches_sacrifice_filter(c: String, n: Node3D, source: Node3D) -> bool:
	if "another" in c and n == source: return false
	var tl := MagicRules.get_card_type_line(n.card_data).to_lower()
	if "nonland" in c and MagicRules.is_land(n.card_data): return false
	if "creature" in c and not ("noncreature" in c): return MagicRules.is_creature(n.card_data)
	if "artifact" in c: return "artifact" in tl
	if "enchantment" in c: return "enchantment" in tl
	if "planeswalker" in c: return "planeswalker" in tl
	if "land" in c and not ("nonland" in c): return MagicRules.is_land(n.card_data)
	if "permanent" in c: return true
	return false

static func _handle_sacrifice(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	if not engine: return
	var pids: Array[int] = _resolve_affected_players(c, engine, owner_id, target)
	var all_perms: Array = engine.battlefield_non_lands + engine.battlefield_lands
	for pid in pids:
		var cands: Array[Node3D] = []
		for n in all_perms:
			if is_instance_valid(n) and n.is_on_battlefield and engine.get_card_controller_id(n) == pid:
				if _matches_sacrifice_filter(c, n, source):
					cands.append(n)
		if cands.is_empty(): continue
		if pid == engine.local_player_id and cands.size() > 1 and engine.hud_manager and engine.hud_manager.has_method("open_choice_popup"):
			var opts: Array[String] = []
			for cand in cands:
				var lbl := str(cand.card_data.get("name", "Permanent"))
				if MagicRules.is_creature(cand.card_data):
					lbl += " (%d/%d)" % [int(cand.dynamic_power), int(cand.dynamic_toughness)]
				opts.append(lbl)
			engine.hud_manager.open_choice_popup("CHOOSE A PERMANENT TO SACRIFICE", opts, func(idx: int):
				if idx >= 0 and idx < cands.size() and is_instance_valid(cands[idx]):
					engine._on_card_to_graveyard(cands[idx])
			)
		elif pid == engine.local_player_id:
			engine._on_card_to_graveyard(cands[0])
		else:
			cands.sort_custom(func(a: Node3D, b: Node3D):
				var sa: float = float(a.card_data.get("cmc", 0.0)) + (100.0 if (a.has_meta("is_commander") and bool(a.get_meta("is_commander"))) else 0.0)
				var sb: float = float(b.card_data.get("cmc", 0.0)) + (100.0 if (b.has_meta("is_commander") and bool(b.get_meta("is_commander"))) else 0.0)
				return sa < sb
			)
			engine._on_card_to_graveyard(cands[0])

static func _handle_counter_spell(target: Variant, engine: Node) -> void:
	if not engine or target == null: return
	if target is Node3D and MagicRules.is_spell_uncounterable(target as Node3D, engine):
		return
	if target in engine.active_stack:
		engine.active_stack.erase(target)
		EventBus.play_sfx("fizzle")
		EventBus.notify_stack(engine.active_stack.size())
		if target is Node3D and is_instance_valid(target):
			var t_node := target as Node3D
			if t_node.has_method("set_highlight"): t_node.set_highlight(false)
			if t_node.has_meta("cast_via_flashback") and bool(t_node.get_meta("cast_via_flashback")):
				t_node.remove_meta("cast_via_flashback")
				engine.zone_manager.move_to_exile(t_node)
			else:
				engine.zone_manager.move_to_graveyard(t_node)
			engine.event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": str(t_node.card_data.get("name", "Spell")) + " (Countered)"})
		else:
			engine.event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": str(target.name) + " (Countered)"})

static func _matches_library_filter(card_data: Dictionary, clause: String) -> bool:
	var tl := MagicRules.get_card_type_line(card_data).to_lower()
	var must_basic := "basic " in clause
	if must_basic and not ("basic" in tl):
		return false

	var land_subtypes := ["plains", "island", "swamp", "mountain", "forest"]
	var mentioned_subtypes: Array[String] = []
	for st in land_subtypes:
		if st in clause:
			mentioned_subtypes.append(st)

	if not mentioned_subtypes.is_empty():
		for st in mentioned_subtypes:
			if st in tl:
				return true
		return false

	if "land" in clause:
		return "land" in tl
	if "creature" in clause:
		return "creature" in tl
	if "artifact" in clause:
		return "artifact" in tl
	if "enchantment" in clause:
		return "enchantment" in tl
	if "instant" in clause or "sorcery" in clause:
		return ("instant" in tl and "instant" in clause) or ("sorcery" in tl and "sorcery" in clause)
	return true

static func _handle_library_search(c: String, engine: Node, owner_id: int) -> void:
	if not engine: return
	var lib: Array = engine.library_stack if owner_id == engine.local_player_id else engine.player_libraries.get(owner_id, [])
	var matches: Array = []
	for card in lib:
		if is_instance_valid(card) and _matches_library_filter(card.card_data, c):
			matches.append(card)

	var to_battlefield := "onto the battlefield" in c
	var enter_tapped := "tapped" in c

	if matches.is_empty():
		if owner_id == engine.local_player_id:
			engine.zone_manager.shuffle_library()
		else:
			lib.shuffle()
			EventBus.play_sfx("shuffle")
		return

	if owner_id != engine.local_player_id:
		var chosen: Node3D = matches[0]
		if to_battlefield:
			engine.put_library_card_onto_battlefield(chosen, owner_id, enter_tapped)
		else:
			lib.erase(chosen)
			lib.shuffle()
			EventBus.play_sfx("shuffle")
			if chosen.has_method("make_active"): chosen.make_active(chosen.card_data)
			engine.player_hands.get(owner_id, []).append(chosen)
			engine.zone_manager.update_opponent_hand_positions(owner_id, true)
		return

	var label_dest := "Battlefield" if to_battlefield else "Hand"
	var title := "SEARCH LIBRARY -> %s (%d matching)" % [label_dest.to_upper(), matches.size()]
	engine.hud_manager.open_zone_viewer(title, matches, owner_id, func(chosen_card: Node3D):
		if to_battlefield:
			engine.put_library_card_onto_battlefield(chosen_card, owner_id, enter_tapped)
		else:
			engine._on_tutor_card_selected(chosen_card)
	)


static func _handle_copy_spell(target: Variant, engine: Node, _owner_id: int) -> void:
	if not engine or target == null: return
	if target is Node3D and is_instance_valid(target):
		var t_node := target as Node3D
		var face_idx: int = int(t_node.get("active_face_index")) if "active_face_index" in t_node else 0
		var eff := str(MagicRules.get_card_attribute(t_node.card_data, "oracle_text", "", face_idx))
		var copy_obj := {
			"effect_raw": eff,
			"target_requirement": str(t_node.get_meta("target_requirement")) if t_node.has_meta("target_requirement") else ""
		}
		if engine.has_method("_finalize_push_ability_to_stack"):
			var tgt_ref: Variant = t_node.get_meta("chosen_target") if t_node.has_meta("chosen_target") else null
			engine._finalize_push_ability_to_stack(t_node, copy_obj, "Spell Copy", tgt_ref)

static func _handle_put_linked_exile_to_gy(source: Node3D, engine: Node) -> void:
	if not engine: return
	engine.set_meta("last_linked_exile_card", {})
	if not source or not is_instance_valid(source) or not source.has_meta("linked_exiled_cards"):
		return
	var linked: Array = source.get_meta("linked_exiled_cards")
	if linked.is_empty():
		return
	var entry: Variant = linked.pop_front()
	source.set_meta("linked_exiled_cards", linked)
	if entry is Node3D and is_instance_valid(entry):
		engine.set_meta("last_linked_exile_card", entry.card_data.duplicate() if "card_data" in entry else {})
		if engine.zone_manager and engine.zone_manager.has_method("move_to_graveyard"):
			engine.zone_manager.move_to_graveyard(entry)
	elif entry is Dictionary:
		engine.set_meta("last_linked_exile_card", entry.duplicate())

static func _handle_put_on_library(c: String, source: Node3D, target: Variant, engine: Node) -> void:
	if not engine or not engine.zone_manager: return
	var card_to_move: Node3D = null
	if "target" in c and target is Node3D and is_instance_valid(target):
		card_to_move = target as Node3D
	elif source != null and is_instance_valid(source):
		card_to_move = source
	if card_to_move == null: return
	if "bottom" in c:
		engine.zone_manager.move_to_bottom_library(card_to_move)
	else:
		engine.zone_manager.move_to_top_library(card_to_move)

static func _handle_look_top_cards(c: String, engine: Node, owner_id: int) -> void:
	if not engine: return
	var amount := _extract_number(c, "top ")
	var pick_count := 1
	if "put " in c:
		pick_count = maxi(1, _extract_number(c, "put "))
	var dest_zone := "hand"
	var rest_zone := "graveyard" if ("rest into your graveyard" in c or "rest into a graveyard" in c) else "bottom"
	if owner_id == engine.local_player_id:
		var top_cards: Array = []
		for i in range(amount):
			if engine.library_stack.is_empty(): break
			var card_n: Node3D = engine.library_stack.pop_back()
			if card_n.has_method("make_active"): card_n.make_active(card_n.card_data)
			engine.connect_card_signals(card_n)
			top_cards.append(card_n)
		if not top_cards.is_empty() and engine.hud_manager and engine.hud_manager.has_method("open_look_and_pick_popup"):
			engine.hud_manager.open_look_and_pick_popup(top_cards, mini(pick_count, top_cards.size()), dest_zone, rest_zone)
	else:
		var lib: Array = engine.player_libraries.get(owner_id, [])
		var hand: Array = engine.player_hands.get(owner_id, [])
		var picked := 0
		for i in range(amount):
			if lib.is_empty(): break
			var card_n: Node3D = lib.pop_back()
			if picked < pick_count:
				picked += 1
				hand.append(card_n)
				if engine.zone_manager: engine.zone_manager.update_opponent_hand_positions(owner_id)
			else:
				if rest_zone == "graveyard" and engine.zone_manager:
					engine.zone_manager.move_to_graveyard(card_n)
				else:
					lib.push_front(card_n)

static func _extract_dynamic_amount(c: String, prefix: String, source: Node3D, _target: Variant, engine: Node, owner_id: int) -> int:
	if "equal to " in c or "where x is " in c:
		if "its power" in c or "source's power" in c or "this creature's power" in c or "'s power" in c:
			if source != null and is_instance_valid(source) and "dynamic_power" in source:
				return maxi(0, int(source.dynamic_power))
		if "cards in your hand" in c and engine:
			return engine.hand_cards.size() if owner_id == engine.local_player_id else (engine.player_hands.get(owner_id, []) as Array).size()
		if "the number of " in c and engine:
			var cnt := 0
			var only_yours := "you control" in c
			for p in engine.battlefield_lands + engine.battlefield_non_lands:
				if not is_instance_valid(p) or not p.is_on_battlefield: continue
				if only_yours and engine.get_card_controller_id(p) != owner_id: continue
				var tl := MagicRules.get_card_type_line(p.card_data).to_lower()
				if "creatures" in c and MagicRules.is_creature(p.card_data, 0, p): cnt += 1
				elif "artifacts" in c and "artifact" in tl: cnt += 1
				elif "enchantments" in c and "enchantment" in tl: cnt += 1
				elif "lands" in c and MagicRules.is_land(p.card_data): cnt += 1
				elif "permanents" in c: cnt += 1
			return cnt
	return _extract_number(c, prefix)


static func _handle_empower_jace(c: String, engine: Node, owner_id: int) -> void:
	if not engine: return
	var n_val: int = maxi(1, _extract_number(c, "empower jace "))
	var jace_tokens: Array[Node3D] = []
	for p in engine.battlefield_non_lands:
		if not is_instance_valid(p) or not p.is_on_battlefield: continue
		if engine.get_card_controller_id(p) != owner_id: continue
		if not bool(p.get("is_token")): continue
		if not MagicRules.is_planeswalker(p.card_data): continue
		var tl := MagicRules.get_card_type_line(p.card_data).to_lower()
		var nm := str(p.card_data.get("name", "")).to_lower()
		if "jace" in tl or "jace" in nm:
			jace_tokens.append(p)
	if jace_tokens.is_empty():
		if engine.has_method("_spawn_new_token"):
			var jace_data := {
				"name": "Jace",
				"type_line": "Token Planeswalker — Jace",
				"colors": ["U"],
				"loyalty": "0",
				"oracle_text": "-1: Surveil 1.\n-3: Draw a card.",
				"query": "t:token t:planeswalker t:jace",
				"starting_loyalty_counters": n_val
			}
			engine._spawn_new_token(jace_data, 1, owner_id)
		return
	if jace_tokens.size() == 1 or owner_id != engine.local_player_id:
		var target_jace: Node3D = jace_tokens[0]
		if target_jace.has_method("modify_named_counter"):
			target_jace.modify_named_counter("loyalty", n_val)
		return
	if engine.hud_manager and engine.hud_manager.has_method("open_choice_popup"):
		var opts: Array[String] = []
		for jt in jace_tokens:
			var cur_l: int = jt.get_named_counter("loyalty") if jt.has_method("get_named_counter") else 0
			opts.append("%s (%d Loyalty)" % [str(jt.card_data.get("name", "Jace")), cur_l])
		engine.hud_manager.open_choice_popup("EMPOWER JACE %d — CHOOSE JACE TOKEN" % n_val, opts, func(idx: int):
			if idx >= 0 and idx < jace_tokens.size() and is_instance_valid(jace_tokens[idx]):
				jace_tokens[idx].modify_named_counter("loyalty", n_val)
		)


static func _handle_animate_permanent(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	var pt_rx := RegEx.new()
	pt_rx.compile("(\\d+|x)\\s*/\\s*(\\d+|x)")
	var m := pt_rx.search(c)
	var bp := 0
	var bt := 0
	var has_pt: bool = false
	if m:
		has_pt = true
		var ps := m.get_string(1).to_lower()
		var ts := m.get_string(2).to_lower()
		var x_v: int = int(source.get_meta("chosen_x")) if (source != null and is_instance_valid(source) and source.has_meta("chosen_x")) else 0
		bp = x_v if ps == "x" else ps.to_int()
		bt = x_v if ts == "x" else ts.to_int()
	var is_eot := ("until end of turn" in c or "until your next turn" in c)
	var granted: Array[String] = []
	for kw in ContinuousEffectsEngine.GRANTABLE_KEYWORDS:
		if kw in c:
			granted.append(kw)
	if "can't be blocked" in c and not ("unblockable" in granted):
		granted.append("unblockable")
	for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
		if "type_overrides" in n and not ("Creature" in n.type_overrides):
			n.type_overrides.append("Creature")
		if is_eot:
			n.set_meta("animated_until_eot", true)
			n.set_meta("base_pt_until_eot", true)
		else:
			n.set_meta("animated_perm", true)
			n.remove_meta("animated_until_eot")
			n.remove_meta("base_pt_until_eot")
		if has_pt:
			n.set_meta("base_pt_override", Vector2i(bp, bt))
		if not granted.is_empty():
			var meta_key := "temp_granted_keywords" if is_eot else "perm_granted_keywords"
			var existing: Array = n.get_meta(meta_key) if n.has_meta(meta_key) else []
			for kw in granted:
				if not (kw in existing): existing.append(kw)
			n.set_meta(meta_key, existing)
		if n.has_method("refresh_visual_status"):
			n.refresh_visual_status()
	if engine and engine.has_method("run_state_based_actions"):
		engine.run_state_based_actions()


static func _handle_proliferate(engine: Node, owner_id: int, on_done: Callable) -> void:
	if not engine:
		on_done.call(true)
		return
	var candidates: Array = []
	for p_node in engine.battlefield_lands + engine.battlefield_non_lands:
		if not is_instance_valid(p_node): continue
		var has_pt: bool = "counter_amount" in p_node and int(p_node.counter_amount) != 0
		var has_named: bool = "custom_counters" in p_node and p_node.custom_counters is Dictionary and not (p_node.custom_counters as Dictionary).is_empty()
		if not has_pt and not has_named: continue
		var p_owner: int = engine.get_card_controller_id(p_node)
		var c_parts: Array[String] = []
		if has_pt:
			c_parts.append("%+d/%+d" % [int(p_node.counter_amount), int(p_node.counter_amount)])
		if has_named:
			for ck in p_node.custom_counters.keys():
				c_parts.append("%s:%d" % [str(ck), int(p_node.custom_counters[ck])])
		var def_sel: bool = (p_owner == owner_id and (not has_pt or int(p_node.counter_amount) > 0)) or (p_owner != owner_id and has_pt and int(p_node.counter_amount) < 0)
		candidates.append({
			"kind": "perm",
			"node": p_node,
			"label": "P%d %s (%s)" % [p_owner, str(p_node.card_data.get("name", "Permanent")), ", ".join(c_parts)],
			"default_selected": def_sel
		})
	for pid in [1, 2, 3, 4]:
		var pc_dict: Dictionary = engine.player_counters.get(pid, {})
		var p_parts: Array[String] = []
		for pk in pc_dict.keys():
			if int(pc_dict[pk]) > 0:
				p_parts.append("%s:%d" % [str(pk), int(pc_dict[pk])])
		if not p_parts.is_empty():
			var p_def: bool = (pid == owner_id) or (pid != owner_id and int(pc_dict.get("poison", 0)) > 0)
			candidates.append({
				"kind": "player",
				"pid": pid,
				"label": "Player P%d (%s)" % [pid, ", ".join(p_parts)],
				"default_selected": p_def
			})

	if candidates.is_empty():
		on_done.call(true)
		return

	var apply_chosen := func(chosen_list: Array):
		for item in chosen_list:
			if item.get("kind") == "perm":
				var pn: Node3D = item.get("node")
				if not is_instance_valid(pn): continue
				if "counter_amount" in pn and int(pn.counter_amount) != 0 and pn.has_method("modify_counters"):
					pn.modify_counters(1 if int(pn.counter_amount) > 0 else -1)
				if "custom_counters" in pn and pn.custom_counters is Dictionary:
					for ck in pn.custom_counters.keys():
						pn.modify_named_counter(str(ck), 1)
			elif item.get("kind") == "player":
				var t_pid: int = int(item.get("pid", 0))
				var d_pc: Dictionary = engine.player_counters.get(t_pid, {})
				for pk in d_pc.keys():
					if int(d_pc[pk]) > 0:
						engine.modify_player_counter(t_pid, str(pk), 1)
		on_done.call(true)

	if owner_id == engine.local_player_id and engine.hud_manager and engine.hud_manager.has_method("open_proliferate_popup"):
		engine.hud_manager.open_proliferate_popup(candidates, apply_chosen)
	else:
		var ai_picks: Array = []
		for cand in candidates:
			if bool(cand.get("default_selected", false)):
				ai_picks.append(cand)
		apply_chosen.call(ai_picks)
