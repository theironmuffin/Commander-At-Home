class_name AbilityResolver
extends RefCounted

static var _REMINDER_REGEX: RegEx
static var _PT_REGEX: RegEx
static var _TOKEN_PT_REGEX: RegEx
static var _MANA_SYM_REGEX: RegEx

static func _ensure_regex() -> void:
	if _REMINDER_REGEX == null:
		_REMINDER_REGEX = RegEx.new()
		_REMINDER_REGEX.compile("\\([^)]*\\)")
	if _PT_REGEX == null:
		_PT_REGEX = RegEx.new()
		_PT_REGEX.compile("([+-]\\d+)/([+-]\\d+)")
	if _TOKEN_PT_REGEX == null:
		_TOKEN_PT_REGEX = RegEx.new()
		_TOKEN_PT_REGEX.compile("(\\d+)/(\\d+)\\s+([a-zA-Z\\s]+?)\\s+creature token")
	if _MANA_SYM_REGEX == null:
		_MANA_SYM_REGEX = RegEx.new()
		_MANA_SYM_REGEX.compile("\\{([WUBRGC])\\}")

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

	var cleaned := _REMINDER_REGEX.sub(effect_text, "", true).strip_edges()
	var clauses := _split_clauses(cleaned)

	for clause in clauses:
		_execute_clause_with_conditions(clause, valid_source, valid_target, engine_main, owner_id)

static func _execute_clause_with_conditions(clause: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	var c := clause.strip_edges()
	var c_lower := c.to_lower()

	# Handle leading "If <condition>, <effect>"
	if c_lower.begins_with("if ") and "," in c:
		var comma_idx := c.find(",")
		var cond_str := c.substr(3, comma_idx - 3).strip_edges()
		var inner_eff := c.substr(comma_idx + 1).strip_edges()
		if not evaluate_condition(cond_str, source, engine, owner_id):
			return
		c = inner_eff
		c_lower = c.to_lower()

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
						_execute_clause(inner_action, source, target, engine, owner_id)
						engine.run_state_based_actions()
			)
			return
		# AI defaults to taking beneficial optional abilities
		c = inner_action

	_execute_clause(c, source, target, engine, owner_id)

static func _split_clauses(text: String) -> Array[String]:
	var out: Array[String] = []
	var normalized := text.replace("\n", ". ").replace(";", ".").replace(", then ", ". ").replace(". Then ", ". ")
	for comma_verb in [", scry ", ", surveil ", ", draw ", ", you gain ", ", gain ", ", you lose ", ", lose ", ", discard ", ", mill ", ", create ", ", destroy ", ", exile ", ", return ", ", put ", ", tap ", ", untap "]:
		normalized = normalized.replace(comma_verb, ". " + comma_verb.substr(2))
	for raw_sent in normalized.split("."):
		var s := raw_sent.strip_edges()
		if s.is_empty(): continue
		for p in _split_compound_and(s):
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

	if "search your library" in c:
		_handle_library_search(c, engine, owner_id); return
	if "counter target" in c or c.begins_with("counter "):
		_handle_counter_spell(target, engine); return
	if "create " in c and "token" in c:
		_handle_create_tokens(c, engine); return
	if "draw " in c and ("card" in c or c.ends_with("draws")):
		_handle_draw(c, engine, owner_id, target); return
	if "exile the top " in c and "library" in c:
		_handle_impulse_exile(c, engine, owner_id); return
	if "mill " in c:
		_handle_mill(c, engine, owner_id); return
	if "discard " in c:
		_handle_discard(c, target, engine, owner_id); return
	if "deals " in c and " damage" in c:
		_handle_damage(c, source, target, engine, owner_id); return
	if " life" in c and ("gain " in c or "lose " in c or "loses " in c or "pay " in c):
		_handle_life(c, engine, owner_id, target); return
	if c.begins_with("scry ") or " scry " in c:
		_handle_scry_or_surveil(c, engine, owner_id, false); return
	if c.begins_with("surveil ") or " surveil " in c:
		_handle_scry_or_surveil(c, engine, owner_id, true); return
	if "gain control of " in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			n.set_meta("control_override_player_id", owner_id)
		return
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
	if "sacrifice " in c:
		_handle_sacrifice(c, target, engine, owner_id); return
	if ("gains " in c or "gain " in c) and ("until end of turn" in c or "target " in c or "creatures you control" in c):
		_handle_temp_keywords(c, source, target, engine, owner_id)
		if _PT_REGEX.search(c) == null: return
	if "until end of turn" in c and _PT_REGEX.search(c) != null:
		_handle_temp_pt(c, source, target, engine, owner_id); return
	if " counter" in c:
		_handle_counters(c, source, target, engine, owner_id); return
	if c.begins_with("exile ") or " exile " in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if engine: engine._on_card_to_exile(n)
		return
	if c.begins_with("destroy ") or " destroy " in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if n.has_method("has_keyword") and bool(n.has_keyword("indestructible")): continue
			if engine: engine._on_card_to_graveyard(n)
		return
	if ("return " in c or "put " in c) and "onto the battlefield" in c and target is Node3D and is_instance_valid(target):
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
			if n.is_tapped: n.toggle_tap()
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

static func _handle_impulse_exile(c: String, engine: Node, owner_id: int) -> void:
	if not engine or owner_id != engine.local_player_id: return
	var amount := _extract_number(c, "exile the top ")
	for i in range(amount):
		if engine.library_stack.is_empty(): break
		var top_card: Node3D = engine.library_stack.pop_back()
		if top_card.has_method("make_active"): top_card.make_active(top_card.card_data)
		engine.connect_card_signals(top_card)
		engine._on_card_to_exile(top_card)

static func _handle_mill(c: String, engine: Node, owner_id: int) -> void:
	if not engine: return
	var amount := _extract_number(c, "mill ")
	if owner_id == engine.local_player_id:
		for i in range(amount):
			if engine.library_stack.is_empty(): break
			var top_card: Node3D = engine.library_stack.pop_back()
			if top_card.has_method("make_active"): top_card.make_active(top_card.card_data)
			engine.connect_card_signals(top_card)
			engine._on_card_to_graveyard(top_card)

static func _handle_discard(c: String, target: Variant, engine: Node, owner_id: int) -> void:
	if not engine: return
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

	for pid in target_pids:
		var hand_arr: Array = engine.hand_cards if pid == engine.local_player_id else engine.player_hands.get(pid, [])
		if hand_arr.is_empty(): continue
		var count: int = mini(amount, hand_arr.size())
		if is_random:
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
				for i in range(count):
					if hand_arr.is_empty(): break
					var card_to_discard: Node3D = hand_arr.pop_back()
					engine.player_hands.get(pid, []).erase(card_to_discard)
					engine._on_card_to_graveyard(card_to_discard)
				engine.zone_manager.update_hand_positions(true)
			else:
				engine.hud_manager.open_discard_choice(count)
		else:
			# AI chooses least valuable card(s) to discard (excess lands or highest CMC)
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
				engine._on_card_to_graveyard(best_card)

static func _handle_damage(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
	var amount := _extract_number(c, "deals ")
	var has_deathtouch: bool = source != null and source.has_method("has_keyword") and bool(source.has_keyword("deathtouch"))
	var has_lifelink: bool = source != null and source.has_method("has_keyword") and bool(source.has_keyword("lifelink"))
	var total_dealt := 0

	if "each creature" in c or "all creatures" in c:
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if "marked_damage" in n:
				n.marked_damage += amount
				if has_deathtouch: n.has_deathtouch_damage = true
				n.refresh_visual_status()
				total_dealt += amount
	elif "each opponent" in c or "each player" in c:
		for pid in _resolve_affected_players(c, engine, owner_id, target):
			if engine: engine.modify_life(pid, -amount); total_dealt += amount
	elif target is Node3D and is_instance_valid(target):
		var t_node := target as Node3D
		if MagicRules.has_protection_from(t_node, source):
			pass
		elif MagicRules.is_planeswalker(t_node.card_data):
			if t_node.has_method("modify_named_counter"):
				t_node.modify_named_counter("loyalty", -amount)
			EventBus.damage_dealt.emit(source, t_node, amount)
			total_dealt += amount
		elif "marked_damage" in t_node:
			t_node.marked_damage += amount
			if has_deathtouch: t_node.has_deathtouch_damage = true
			t_node.refresh_visual_status()
			EventBus.damage_dealt.emit(source, t_node, amount)
			total_dealt += amount
	elif target is int and engine:
		engine.modify_life(int(target), -amount)
		EventBus.damage_dealt.emit(source, int(target), amount)
		total_dealt += amount
	elif engine:
		var opp_id: int = (owner_id % 4) + 1
		engine.modify_life(opp_id, -amount)
		total_dealt += amount

	if has_lifelink and total_dealt > 0 and engine:
		engine.modify_life(owner_id, total_dealt)

static func _handle_life(c: String, engine: Node, owner_id: int, target: Variant) -> void:
	if not engine: return
	var is_loss := ("lose " in c or "loses " in c or "pay " in c)
	var prefix := "pay " if "pay " in c else ("loses " if "loses " in c else ("lose " if "lose " in c else "gain "))
	var amount := _extract_number(c, prefix)
	var delta := -amount if is_loss else amount
	for pid in _resolve_affected_players(c, engine, owner_id, target):
		engine.modify_life(pid, delta)

static func _handle_temp_pt(c: String, source: Node3D, target: Variant, engine: Node, owner_id: int) -> void:
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
	var amount := _extract_number(c, "put ")
	if "remove " in c: amount = -_extract_number(c, "remove ")
	if "+1/+1 counter" in c or "-1/-1 counter" in c:
		if "-1/-1 counter" in c: amount = -amount
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if n.has_method("modify_counters"): n.modify_counters(amount)
		return

	var c_type := ""
	for known in ["oil", "charge", "time", "loyalty", "stun", "shield", "lore", "energy", "poison", "experience"]:
		if (known + " counter") in c: c_type = known; break
	if not c_type.is_empty():
		for n in _resolve_affected_permanents(c, source, target, engine, owner_id):
			if n.has_method("modify_named_counter"): n.modify_named_counter(c_type, amount)

static func _handle_create_tokens(c: String, engine: Node) -> void:
	if not engine or not engine.has_method("_spawn_new_token"): return
	var amount := _extract_number(c, "create ")
	var artifact_presets := {"treasure": "Treasure", "clue": "Clue", "food": "Food", "blood": "Blood", "map": "Map", "powerstone": "Powerstone"}
	for key in artifact_presets.keys():
		if key in c:
			var target_name: String = artifact_presets[key]
			for t in engine.COMMON_TOKENS:
				if t["name"] == target_name:
					for i in range(amount): engine._spawn_new_token(t)
					return

	var m := _TOKEN_PT_REGEX.search(c)
	if m:
		var pow_str := m.get_string(1)
		var tou_str := m.get_string(2)
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

		var extra_tl := (" ".join(extras_found).capitalize() + " ") if not extras_found.is_empty() else ""
		var token_dict := {
			"name": "%s/%s %s" % [pow_str, tou_str, subtype_str],
			"type_line": "Token %sCreature — %s" % [extra_tl, subtype_str],
			"power": pow_str,
			"toughness": tou_str,
			"oracle_text": "Flying" if "flying" in c else "",
			"query": " ".join(query_parts)
		}
		for i in range(amount): engine._spawn_new_token(token_dict)

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
	if "all creatures" in c or "each creature" in c:
		for p in all_perms:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data): result.append(p)
		return result
	if "creatures you control" in c:
		for p in all_perms:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data) and engine.get_card_owner_id(p) == owner_id: result.append(p)
		return result
	if "creatures your opponents control" in c or "creatures you don't control" in c:
		for p in all_perms:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data) and engine.get_card_owner_id(p) != owner_id: result.append(p)
		return result
	if "all artifacts" in c or "each artifact" in c:
		for p in all_perms:
			if is_instance_valid(p) and "artifact" in MagicRules.get_card_type_line(p.card_data).to_lower(): result.append(p)
		return result
	if "all enchantments" in c or "each enchantment" in c:
		for p in all_perms:
			if is_instance_valid(p) and "enchantment" in MagicRules.get_card_type_line(p.card_data).to_lower(): result.append(p)
		return result
	if "all permanents" in c or "all nonland permanents" in c:
		var skip_lands := "nonland" in c
		for p in all_perms:
			if is_instance_valid(p):
				if skip_lands and MagicRules.is_land(p.card_data): continue
				result.append(p)
		return result

	if target is Node3D and is_instance_valid(target): result.append(target)
	elif source and is_instance_valid(source) and ("this " in c or "itself" in c or "on it" in c): result.append(source)
	return result

static func _resolve_affected_players(c: String, _engine: Node, owner_id: int, target: Variant) -> Array[int]:
	var pids: Array[int] = []
	if "each player" in c: return [1, 2, 3, 4]
	if "each opponent" in c:
		for pid in [1, 2, 3, 4]:
			if pid != owner_id: pids.append(pid)
		return pids
	if "target opponent" in c or "target player" in c:
		if target is int: return [int(target)]
		return [(owner_id % 4) + 1]
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

static func _evaluate_for_each_count(c: String, source: Node3D, engine: Node, owner_id: int) -> int:
	if not ("for each " in c) or not engine: return 1
	var count := 0
	if "creature you control" in c or "creatures you control" in c:
		for p in engine.battlefield_non_lands:
			if is_instance_valid(p) and MagicRules.is_creature(p.card_data) and engine.get_card_owner_id(p) == owner_id:
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

static func _handle_fight(source: Node3D, target: Variant, engine: Node) -> void:
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

static func _handle_sacrifice(c: String, target: Variant, engine: Node, owner_id: int) -> void:
	if not engine: return
	var pid: int = int(target) if ("target " in c and target is int) else owner_id
	for n in engine.battlefield_non_lands.duplicate():
		if is_instance_valid(n) and engine.get_card_owner_id(n) == pid:
			if ("creature" in c and MagicRules.is_creature(n.card_data)) or ("artifact" in c and "artifact" in MagicRules.get_card_type_line(n.card_data).to_lower()) or ("permanent" in c):
				engine._on_card_to_graveyard(n)
				return

static func _handle_counter_spell(target: Variant, engine: Node) -> void:
	if not engine or target == null: return
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
