class_name MagicRules
extends RefCounted

const RULES_TEXT_KEYS := ["name", "type_line", "oracle_text"]

static func get_layout(card_data: Dictionary) -> String:
	return str(card_data.get("layout", "normal")).to_lower()

static func has_multiple_faces(card_data: Dictionary) -> bool:
	var faces = card_data.get("card_faces", [])
	return faces is Array and faces.size() >= 2

static func get_face_data(card_data: Dictionary, face_index: int = 0) -> Dictionary:
	var faces = card_data.get("card_faces", [])
	if faces is Array and face_index >= 0 and face_index < faces.size() and faces[face_index] is Dictionary:
		return faces[face_index]
	return card_data

static func is_room(card_data: Dictionary) -> bool:
	return "room" in get_card_type_line(card_data, 0).to_lower()

static func is_split(card_data: Dictionary) -> bool:
	return get_layout(card_data) == "split" and not is_room(card_data)

static func is_adventure(card_data: Dictionary) -> bool:
	return get_layout(card_data) == "adventure"

static func is_omen(card_data: Dictionary) -> bool:
	return "omen" in get_card_type_line(card_data, 1).to_lower()

static func is_modal_dfc(card_data: Dictionary) -> bool:
	return get_layout(card_data) == "modal_dfc"

static func is_transform(card_data: Dictionary) -> bool:
	var l := get_layout(card_data)
	return l == "transform" or l == "flip"

static func is_aura(card_data: Dictionary, face_index: int = 0) -> bool:
	return "aura" in get_card_type_line(card_data, face_index).to_lower()

static func is_equipment(card_data: Dictionary, face_index: int = 0) -> bool:
	return "equipment" in get_card_type_line(card_data, face_index).to_lower()

static func get_card_type_line(card_data: Dictionary, face_index: int = 0) -> String:
	if has_multiple_faces(card_data):
		var f := get_face_data(card_data, face_index)
		var ft := str(f.get("type_line", ""))
		if not ft.is_empty():
			return ft
	return str(card_data.get("type_line", ""))

static func get_card_combined_text(card_data: Dictionary) -> String:
	var builder := PackedStringArray()
	for key in RULES_TEXT_KEYS:
		if card_data.has(key) and card_data[key] != null:
			builder.append(str(card_data[key]).to_lower())

	if card_data.get("card_faces") is Array:
		for face in card_data["card_faces"]:
			if face is Dictionary:
				for key in RULES_TEXT_KEYS:
					if face.has(key) and face[key] != null:
						builder.append(str(face[key]).to_lower())

	return " ".join(builder).replace("\n", " ").replace("\r", " ")

static func has_text_condition(card_data: Dictionary, query: String) -> bool:
	return query.to_lower() in get_card_combined_text(card_data)

static func get_card_attribute(card_data: Dictionary, attribute_key: String, default = null, face_index: int = 0):
	if has_multiple_faces(card_data):
		var face := get_face_data(card_data, face_index)
		if face.has(attribute_key) and face[attribute_key] != null and str(face[attribute_key]) != "":
			return face[attribute_key]

	if card_data.has(attribute_key) and card_data[attribute_key] != null:
		return card_data[attribute_key]

	return default

static func is_planeswalker(card_data: Dictionary, face_index: int = 0) -> bool:
	return "planeswalker" in get_card_type_line(card_data, face_index).to_lower()

static func is_saga(card_data: Dictionary, face_index: int = 0) -> bool:
	return "saga" in get_card_type_line(card_data, face_index).to_lower()

static func is_creature(card_data: Dictionary, face_index: int = 0, card_node: Node = null) -> bool:
	if "creature" in get_card_type_line(card_data, face_index).to_lower():
		return true
	if card_node != null and is_instance_valid(card_node) and "type_overrides" in card_node:
		for ov in card_node.type_overrides:
			if str(ov).to_lower() == "creature":
				return true
	return false

static func is_land(card_data: Dictionary, face_index: int = 0) -> bool:
	return "land" in get_card_type_line(card_data, face_index).to_lower()

static func can_cast_at_instant_speed(card_data: Dictionary, face_index: int, caster_id: int, engine: Node) -> bool:
	if is_instant_speed(card_data, face_index):
		return true
	if not engine:
		return false
	var tl := get_card_type_line(card_data, face_index).to_lower()
	for perm in engine.battlefield_lands + engine.battlefield_non_lands:
		if not is_instance_valid(perm) or not bool(perm.get("is_on_battlefield")): continue
		if engine.get_card_owner_id(perm) != caster_id: continue
		var oracle := str(get_card_attribute(perm.card_data, "oracle_text", "")).to_lower()
		if "as though they had flash" in oracle or "as though it had flash" in oracle:
			if "creature spells" in oracle and not ("creature" in tl): continue
			if "artifact spells" in oracle and not ("artifact" in tl): continue
			if "enchantment spells" in oracle and not ("enchantment" in tl): continue
			if "sorcery spells" in oracle and not ("sorcery" in tl): continue
			if "legendary spells" in oracle and not ("legendary" in tl): continue
			if "historic spells" in oracle and not ("legendary" in tl or "artifact" in tl or "saga" in tl): continue
			return true
	return false

static func is_instant_speed(card_data: Dictionary, face_index: int = 0) -> bool:
	var type_line := get_card_type_line(card_data, face_index).to_lower()
	if "instant" in type_line:
		return true
	var oracle := str(get_card_attribute(card_data, "oracle_text", "", face_index)).to_lower()
	var flash_rx := RegEx.new()
	flash_rx.compile("(?:^|\\n|,\\s*)flash(?:\\s*(?:\\(|,|$|\\n))")
	return flash_rx.search(oracle) != null

static func get_base_power(card_data: Dictionary, face_index: int = 0) -> int:
	var raw := str(get_card_attribute(card_data, "power", "0", face_index)).strip_edges()
	return raw.to_int() if raw.is_valid_int() else 0

static func get_base_toughness(card_data: Dictionary, face_index: int = 0) -> int:
	var raw := str(get_card_attribute(card_data, "toughness", "0", face_index)).strip_edges()
	return raw.to_int() if raw.is_valid_int() else 0

static func count_legal_targets(requirement: String, caster_id: int, engine: Node, source_card: Node3D = null) -> int:
	if engine == null: return 99
	var req_l := requirement.to_lower().strip_edges()
	if req_l.is_empty(): return 99
	var cnt := 0
	var is_perm_word := ("permanent" in req_l or "creature" in req_l or "artifact" in req_l or "enchantment" in req_l or "planeswalker" in req_l or "land" in req_l)
	if ("opponent" in req_l or "player" in req_l) and not ("graveyard" in req_l) and not is_perm_word:
		for pid in [1, 2, 3, 4]:
			if int(engine.player_life.get(pid, 0)) <= 0: continue
			if "opponent" in req_l and not ("player" in req_l) and pid == caster_id: continue
			cnt += 1
		return cnt
	if "graveyard" in req_l:
		var pools: Array = [engine.graveyard_stack]
		for pk in engine.player_graveyards.keys(): pools.append(engine.player_graveyards[pk])
		for pl in pools:
			for c in pl:
				if is_legal_target(c, requirement, caster_id, source_card): cnt += 1
		return cnt
	if "exile" in req_l:
		var ex_pools: Array = [engine.exile_stack]
		for pk in engine.player_exile.keys(): ex_pools.append(engine.player_exile[pk])
		for pl in ex_pools:
			for c in pl:
				if is_legal_target(c, requirement, caster_id, source_card): cnt += 1
		return cnt
	if "spell" in req_l:
		for s in engine.active_stack:
			if is_legal_target(s, requirement, caster_id, source_card): cnt += 1
		return cnt
	for p in engine.battlefield_non_lands + engine.battlefield_lands:
		if is_legal_target(p, requirement, caster_id, source_card): cnt += 1
	return cnt

static func is_legal_target(target_node: Variant, requirement: String, caster_id: int, source_card: Node3D = null) -> bool:
	var req_check := requirement.to_lower().strip_edges()
	if target_node is int:
		var pid := int(target_node)
		if pid < 1 or pid > 4: return false
		if req_check.is_empty() or "any target" in req_check or "player" in req_check or "opponent" in req_check:
			if "opponent" in req_check and not ("player" in req_check) and pid == caster_id:
				return false
			return true
		return false
	if not (target_node is Node3D) or not is_instance_valid(target_node):
		return false
	if "graveyard" in req_check or "exile" in req_check:
		if bool(target_node.get("is_on_battlefield")):
			return false
		var g_owner: int = int(target_node.get_meta("owner_id")) if target_node.has_meta("owner_id") else 1
		if "your graveyard" in req_check and g_owner != caster_id: return false
		if "opponent" in req_check and g_owner == caster_id: return false
		var f_i: int = int(target_node.get("active_face_index")) if "active_face_index" in target_node else 0
		var g_tl := get_card_type_line(target_node.card_data, f_i).to_lower()
		if "creature" in req_check and not ("creature" in g_tl): return false
		if "artifact" in req_check and not ("artifact" in g_tl): return false
		if "enchantment" in req_check and not ("enchantment" in g_tl): return false
		if "instant" in req_check and not ("instant" in g_tl): return false
		if "sorcery" in req_check and not ("sorcery" in g_tl): return false
		if "land" in req_check and not ("land" in g_tl): return false
		return true
	if "spell" in req_check:
		if bool(target_node.get("is_on_battlefield")) or source_card == target_node:
			return false
		var f_idx: int = int(target_node.get("active_face_index")) if "active_face_index" in target_node else 0
		var tl := get_card_type_line(target_node.card_data, f_idx).to_lower()
		if "noncreature" in req_check and "creature" in tl: return false
		if "creature spell" in req_check and not ("creature" in tl): return false
		if "instant or sorcery" in req_check and not ("instant" in tl or "sorcery" in tl): return false
		return true
	if not bool(target_node.get("is_on_battlefield")):
		return false
	if source_card != null and target_node == source_card and "another" in requirement.to_lower():
		return false

	# Protection blocks targeting from matching sources
	if source_card != null and has_protection_from(target_node, source_card):
		return false

	# Shroud blocks all targeting; Hexproof / Hexproof from [X] blocks opponents
	if target_node.has_method("has_keyword"):
		if bool(target_node.has_keyword("shroud")):
			return false
		var target_owner: int = int(target_node.get_meta("owner_id")) if target_node.has_meta("owner_id") else 1
		if bool(target_node.has_keyword("hexproof")) and target_owner != caster_id:
			return false
		if target_owner != caster_id and source_card != null and has_hexproof_from(target_node, source_card):
			return false

	var req := requirement.to_lower().strip_edges()
	if req.is_empty():
		return true

	var t_owner: int = int(target_node.get_meta("owner_id")) if target_node.has_meta("owner_id") else 1
	if "you control" in req and t_owner != caster_id:
		return false
	if ("opponent controls" in req or "you don't control" in req) and t_owner == caster_id:
		return false

	var face_idx: int = int(target_node.get("active_face_index")) if "active_face_index" in target_node else 0
	var type_line := get_card_type_line(target_node.card_data, face_idx).to_lower()
	if "type_overrides" in target_node:
		for ov in target_node.type_overrides:
			type_line += " " + str(ov).to_lower()

	if "nonland permanent" in req and "land" in type_line:
		return false
	if "noncreature" in req and "creature" in type_line:
		return false
	if "any target" in req:
		return ("creature" in type_line) or ("planeswalker" in type_line)
	if "creature" in req and not ("creature" in type_line):
		return false
	if "artifact" in req and not ("artifact" in type_line):
		return false
	if "enchantment" in req and not ("enchantment" in type_line):
		return false
	if "planeswalker" in req and not ("planeswalker" in type_line):
		return false
	if "land" in req and not ("nonland" in req) and not ("land" in type_line):
		return false
	if "legendary" in req and not ("legendary" in type_line):
		return false

	return true

static func get_land_colors(card_data: Dictionary) -> Array[String]:
	var colors: Array[String] = []

	var produced = card_data.get("produced_mana")
	if produced is Array and not produced.is_empty():
		for c in produced:
			var upper := str(c).to_upper()
			if not upper in colors:
				colors.append(upper)
		return colors

	var text := get_card_combined_text(card_data).to_upper()
	for color_char in ["W", "U", "B", "R", "G", "C"]:
		if ("{" + color_char + "}") in text and not color_char in colors:
			colors.append(color_char)

	if not colors.is_empty():
		return colors

	var type_line := get_card_type_line(card_data).to_lower()
	var card_name: String = card_data.get("name", "").to_lower()

	if "mountain" in type_line or "mountain" in card_name: colors.append("R")
	if "swamp" in type_line or "swamp" in card_name: colors.append("B")
	if "island" in type_line or "island" in card_name: colors.append("U")
	if "plains" in type_line or "plains" in card_name: colors.append("W")
	if "forest" in type_line or "forest" in card_name: colors.append("G")

	if colors.is_empty():
		colors.append("C")

	return colors

static func has_protection_from(target_node: Node3D, source_card: Node3D) -> bool:
	if not target_node or not is_instance_valid(target_node) or not source_card or not is_instance_valid(source_card):
		return false
	var pa: Variant = target_node.get("parsed_abilities")
	if not (pa is Dictionary): return false
	var prot_list: Array = pa.get("protection_from", [])
	if prot_list.is_empty(): return false

	var src_tl := get_card_type_line(source_card.card_data).to_lower()
	var src_colors: Array = source_card.card_data.get("colors", [])
	var color_names := {"W": "white", "U": "blue", "B": "black", "R": "red", "G": "green"}
	var src_color_words: Array[String] = []
	for c in src_colors:
		if color_names.has(str(c)): src_color_words.append(color_names[str(c)])
	if "color_overrides" in source_card and not source_card.color_overrides.is_empty():
		src_color_words = source_card.color_overrides.duplicate()

	for prot in prot_list:
		var p := str(prot).to_lower()
		if p == "everything": return true
		if p in src_color_words: return true
		if p.trim_suffix("s") in src_tl: return true
	return false


static func has_hexproof_from(target_node: Node3D, source_card: Node3D) -> bool:
	if not target_node or not is_instance_valid(target_node) or not source_card or not is_instance_valid(source_card):
		return false
	var pa: Variant = target_node.get("parsed_abilities")
	if not (pa is Dictionary): return false
	var hf_list: Array = pa.get("hexproof_from", [])
	if hf_list.is_empty(): return false
	var src_tl := get_card_type_line(source_card.card_data).to_lower()
	var src_colors: Array = source_card.card_data.get("colors", [])
	var color_names := {"W": "white", "U": "blue", "B": "black", "R": "red", "G": "green"}
	var src_color_words: Array[String] = []
	for c in src_colors:
		if color_names.has(str(c)): src_color_words.append(color_names[str(c)])
	for hf in hf_list:
		var h := str(hf).to_lower()
		if h in src_color_words: return true
		if h.trim_suffix("s") in src_tl: return true
	return false

static func is_damage_unpreventable(source_card: Node3D, engine: Node = null) -> bool:
	if source_card and is_instance_valid(source_card):
		var ot := str(get_card_attribute(source_card.card_data, "oracle_text", "")).to_lower()
		if "damage can't be prevented" in ot: return true
	if engine:
		for p in engine.battlefield_lands + engine.battlefield_non_lands:
			if not is_instance_valid(p): continue
			var pot := str(get_card_attribute(p.card_data, "oracle_text", "")).to_lower()
			if "damage can't be prevented" in pot: return true
	return false

static func is_spell_uncounterable(spell_node: Node3D, engine: Node = null) -> bool:
	if not spell_node or not is_instance_valid(spell_node): return false
	var ot := str(get_card_attribute(spell_node.card_data, "oracle_text", "")).to_lower()
	if "this spell can't be countered" in ot or "can't be countered" in ot:
		return true
	if engine:
		var caster_id: int = engine.get_card_owner_id(spell_node)
		var tl := get_card_type_line(spell_node.card_data).to_lower()
		for p in engine.battlefield_lands + engine.battlefield_non_lands:
			if not is_instance_valid(p) or engine.get_card_owner_id(p) != caster_id: continue
			var pot := str(get_card_attribute(p.card_data, "oracle_text", "")).to_lower()
			if "spells you control can't be countered" in pot: return true
			if "creature spells you control can't be countered" in pot and "creature" in tl: return true
	return false
