class_name ContinuousEffectsEngine
extends RefCounted

const GRANTABLE_KEYWORDS: Array[String] = [
	"flying", "first strike", "double strike", "deathtouch", "trample",
	"vigilance", "lifelink", "haste", "reach", "indestructible", "hexproof",
	"shroud", "ward", "menace", "defender"
]

const BASIC_LAND_TYPES: Array[String] = ["plains", "island", "swamp", "mountain", "forest"]
const MTG_COLORS: Array[String] = ["white", "blue", "black", "red", "green"]

static var _BASE_PT_REGEX: RegEx

static func _ensure_regex() -> void:
	if _BASE_PT_REGEX == null:
		_BASE_PT_REGEX = RegEx.new()
		_BASE_PT_REGEX.compile("(?:base power and toughness|becomes a)\\s+(\\d+)/(\\d+)")

static func recalculate_layers(battlefield_lands: Array, battlefield_non_lands: Array, engine: Node = null) -> void:
	_ensure_regex()
	var all_permanents: Array = []
	all_permanents.append_array(battlefield_lands)
	all_permanents.append_array(battlefield_non_lands)
	for host_card in all_permanents.duplicate():
		if not is_instance_valid(host_card): continue
		var atts: Variant = host_card.get("attachments")
		if atts is Array:
			for att in atts:
				if is_instance_valid(att) and not (att in all_permanents):
					all_permanents.append(att)

	# Step 1: Reset layer modifiers on all permanents
	for card in all_permanents:
		if not is_instance_valid(card): continue
		_reset_card_layers(card)

	# Layer 1: Copy Effects
	_apply_layer_1_copies(all_permanents)

	# Layer 2: Control-Changing Effects
	_apply_layer_2_control(all_permanents)

	# Layer 3: Text-Changing Effects
	_apply_layer_3_text(all_permanents)

	# Layer 4: Type-Changing Effects
	_apply_layer_4_types(all_permanents)

	# Layer 5: Color-Changing Effects
	_apply_layer_5_colors(all_permanents)

	# Layer 6: Ability-Adding and Ability-Removing Effects
	_apply_layer_6_abilities(all_permanents)
	_apply_layer_4_land_ability_overwrite(all_permanents)

	# Layer 7: Power / Toughness Modifications (7a -> 7b -> 7c -> 7d -> 7e)
	_apply_layer_7_power_toughness(all_permanents, battlefield_lands, battlefield_non_lands, engine)

	# Step 2: Sync visual badges and stats
	for card in all_permanents:
		if not is_instance_valid(card): continue
		if card.has_method("refresh_visual_status"):
			card.refresh_visual_status()

static func _reset_card_layers(card: Node3D) -> void:
	if "layer_controller_id" in card:
		card.layer_controller_id = -1
	if "type_overrides" in card:
		card.type_overrides.clear()
	if "color_overrides" in card:
		card.color_overrides.clear()
	if "abilities_removed" in card:
		card.abilities_removed = false
	if "layer_granted_keywords" in card:
		card.layer_granted_keywords.clear()
	if "layer_base_power_override" in card:
		card.layer_base_power_override = -999
	if "layer_base_toughness_override" in card:
		card.layer_base_toughness_override = -999
	if "layer_power_modifier" in card:
		card.layer_power_modifier = 0
	if "layer_toughness_modifier" in card:
		card.layer_toughness_modifier = 0
	if "layer_pt_switched" in card:
		card.layer_pt_switched = false

static func _get_effective_controller(card: Node3D) -> int:
	if "layer_controller_id" in card and int(card.layer_controller_id) > 0:
		return int(card.layer_controller_id)
	if card.has_meta("control_override_player_id"):
		return int(card.get_meta("control_override_player_id"))
	return int(card.get_meta("owner_id")) if card.has_meta("owner_id") else 1

static func _apply_layer_1_copies(permanents: Array) -> void:
	for card in permanents:
		if not is_instance_valid(card): continue
		if card.has_meta("copy_of_card_data"):
			var copy_data: Variant = card.get_meta("copy_of_card_data")
			if copy_data is Dictionary and not copy_data.is_empty():
				for k in ["name", "type_line", "oracle_text", "power", "toughness", "colors"]:
					if copy_data.has(k):
						card.card_data[k] = copy_data[k]

static func _apply_layer_2_control(permanents: Array) -> void:
	for source in permanents:
		if not is_instance_valid(source): continue
		if source.has_meta("control_override_player_id") and "layer_controller_id" in source:
			source.layer_controller_id = int(source.get_meta("control_override_player_id"))
		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
		var controller: int = _get_effective_controller(source)
		var host: Node3D = source.get("attached_to")
		if host != null and is_instance_valid(host) and "layer_controller_id" in host:
			if "you control enchanted" in oracle or "control of enchanted" in oracle or "you control equipped" in oracle:
				host.layer_controller_id = controller

static func _apply_layer_3_text(permanents: Array) -> void:
	for source in permanents:
		if not is_instance_valid(source): continue
		if source.has_meta("text_replacements"):
			var rep: Variant = source.get_meta("text_replacements")
			if rep is Dictionary and source.card_data.has("oracle_text"):
				var txt: String = str(source.card_data["oracle_text"])
				for k in rep.keys():
					txt = txt.replace(str(k), str(rep[k]))
				source.card_data["oracle_text"] = txt

static func _apply_layer_4_types(permanents: Array) -> void:
	for source in permanents:
		if not is_instance_valid(source): continue
		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()

		# Global land type shifts (e.g. Urborg, Blood Moon)
		if "all lands are " in oracle or "nonbasic lands are " in oracle or "each land is a " in oracle:
			var nonbasic_only := "nonbasic lands are " in oracle
			var replace_existing := not ("in addition to its other" in oracle)
			for lt in BASIC_LAND_TYPES:
				if ("are " + lt) in oracle or ("are " + lt + "s") in oracle or ("is a " + lt) in oracle:
					for target in permanents:
						if not is_instance_valid(target) or not MagicRules.is_land(target.card_data): continue
						if nonbasic_only and "basic" in MagicRules.get_card_type_line(target.card_data).to_lower(): continue
						if "type_overrides" in target:
							if replace_existing:
								target.type_overrides.clear()
								target.set_meta("blood_moon_replaced", true)
							else:
								if target.has_meta("blood_moon_replaced"): target.remove_meta("blood_moon_replaced")
							if not (lt.capitalize() in target.type_overrides):
								target.type_overrides.append(lt.capitalize())

		# Attachment type changes (e.g. "Enchanted creature is an artifact" / "is a Treasure")
		var host: Node3D = source.get("attached_to")
		if host != null and is_instance_valid(host) and "type_overrides" in host:
			if "enchanted creature is " in oracle or "equipped creature is " in oracle:
				for t_word in ["artifact", "creature", "enchantment", "land", "dragon", "angel", "zombie", "elf", "goblin"]:
					if ("is a " + t_word) in oracle or ("is an " + t_word) in oracle:
						if not (t_word.capitalize() in host.type_overrides):
							host.type_overrides.append(t_word.capitalize())

static func _apply_layer_5_colors(permanents: Array) -> void:
	for source in permanents:
		if not is_instance_valid(source): continue
		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()

		if "all creatures are " in oracle:
			for col in MTG_COLORS:
				if ("are " + col) in oracle:
					for target in permanents:
						if not is_instance_valid(target) or not MagicRules.is_creature(target.card_data): continue
						if "color_overrides" in target and not (col in target.color_overrides):
							target.color_overrides.append(col)

		var host: Node3D = source.get("attached_to")
		if host != null and is_instance_valid(host) and "color_overrides" in host:
			if "enchanted creature is " in oracle or "equipped creature is " in oracle:
				if "colorless" in oracle:
					host.color_overrides.clear()
				elif "all colors" in oracle:
					for col in MTG_COLORS:
						if not (col in host.color_overrides): host.color_overrides.append(col)
				else:
					for col in MTG_COLORS:
						if ("is " + col) in oracle and not (col in host.color_overrides):
							host.color_overrides.append(col)

static func _apply_layer_6_abilities(permanents: Array) -> void:
	# Pass A: Ability Removal ("loses all abilities")
	for source in permanents:
		if not is_instance_valid(source): continue
		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
		var host: Node3D = source.get("attached_to")
		if host != null and is_instance_valid(host) and "abilities_removed" in host:
			if "loses all abilities" in oracle or "lose all abilities" in oracle:
				host.abilities_removed = true
		if "all creatures lose all abilities" in oracle:
			for target in permanents:
				if is_instance_valid(target) and MagicRules.is_creature(target.card_data) and "abilities_removed" in target:
					target.abilities_removed = true

	# Pass B: Ability Additions (Equipment, Auras, Anthems, Temporary EOT Grants)
	for source in permanents:
		if not is_instance_valid(source): continue
		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
		var controller: int = _get_effective_controller(source)

		# Temporary EOT keyword grants (from spells/abilities)
		if source.has_meta("temp_granted_keywords"):
			var tmp_kws: Variant = source.get_meta("temp_granted_keywords")
			if tmp_kws is Array:
				for kw in tmp_kws:
					if source.has_method("grant_layer_keyword"):
						source.grant_layer_keyword(str(kw))

		# Equipment / Aura granting abilities to host
		var host: Node3D = source.get("attached_to")
		if host != null and is_instance_valid(host):
			if "equipped creature" in oracle or "enchanted creature" in oracle or "equipped permanent" in oracle or "enchanted permanent" in oracle:
				for kw in GRANTABLE_KEYWORDS:
					if kw in oracle and host.has_method("grant_layer_keyword"):
						host.grant_layer_keyword(kw)

		# Generic & tribal anthems granting keywords ("Artifact creatures you control have reach", "Other Squirrels have...", etc.)
		for line in oracle.split("\n"):
			if not (" have " in line or " has " in line): continue
			if "enchanted " in line or "equipped " in line: continue
			var split_tok := " have " if " have " in line else " has "
			var subj := line.split(split_tok)[0].strip_edges()
			var eff_part := line.split(split_tok)[1]
			for kw in GRANTABLE_KEYWORDS:
				if kw in eff_part:
					for target in permanents:
						if not is_instance_valid(target): continue
						if _matches_anthem_subject(subj, target, source, controller):
							if target.has_method("grant_layer_keyword"):
								target.grant_layer_keyword(kw)

static func _apply_layer_7_power_toughness(permanents: Array, battlefield_lands: Array, battlefield_non_lands: Array, engine: Node = null) -> void:
	# Layer 7a: Characteristic-Defining Abilities (*/*)
	for source in permanents:
		if not is_instance_valid(source) or not MagicRules.is_creature(source.card_data): continue
		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
		if "power and toughness are each equal to " in oracle:
			var controller: int = _get_effective_controller(source)
			var val: int = _count_matching_objects(oracle, controller, battlefield_lands, battlefield_non_lands, engine)
			if "layer_base_power_override" in source: source.layer_base_power_override = val
			if "layer_base_toughness_override" in source: source.layer_base_toughness_override = val

	# Layer 7b: Set Base Power / Toughness ("has base power and toughness X/Y", "becomes a X/Y")
	for source in permanents:
		if not is_instance_valid(source): continue
		if source.has_meta("base_pt_override"):
			var bpt: Variant = source.get_meta("base_pt_override")
			if bpt is Vector2i:
				if "layer_base_power_override" in source: source.layer_base_power_override = bpt.x
				if "layer_base_toughness_override" in source: source.layer_base_toughness_override = bpt.y

		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
		var bm := _BASE_PT_REGEX.search(oracle)
		if bm:
			var bp := bm.get_string(1).to_int()
			var bt := bm.get_string(2).to_int()
			var host: Node3D = source.get("attached_to")
			if host != null and is_instance_valid(host) and MagicRules.is_creature(host.card_data):
				if "enchanted creature" in oracle or "equipped creature" in oracle:
					if "layer_base_power_override" in host: host.layer_base_power_override = bp
					if "layer_base_toughness_override" in host: host.layer_base_toughness_override = bt
			elif "all creatures" in oracle:
				for target in battlefield_non_lands:
					if is_instance_valid(target) and MagicRules.is_creature(target.card_data):
						if "layer_base_power_override" in target: target.layer_base_power_override = bp
						if "layer_base_toughness_override" in target: target.layer_base_toughness_override = bt

	# Layer 7c: Modify P/T without setting (Anthems + Equipment/Auras)
	for source in permanents:
		if not is_instance_valid(source): continue
		var oracle: String = str(MagicRules.get_card_attribute(source.card_data, "oracle_text", "")).to_lower()
		var controller: int = _get_effective_controller(source)

		# Generic & tribal P/T anthems ("Other Squirrels get +1/+1", "Artifact creatures you control get +2/+2", etc.)
		for line in oracle.split("\n"):
			if not (" get " in line or " gets " in line): continue
			if "enchanted " in line or "equipped " in line: continue
			var split_tok := " get " if " get " in line else " gets "
			var subj := line.split(split_tok)[0].strip_edges()
			var mod := OracleParser.parse_pt_modifier(line)
			if mod != Vector2i.ZERO:
				for target in battlefield_non_lands:
					if not is_instance_valid(target): continue
					if _matches_anthem_subject(subj, target, source, controller):
						target.layer_power_modifier += mod.x
						target.layer_toughness_modifier += mod.y

		# Attachments (Auras & Equipment): apply every P/T modifier line referencing enchanted/equipped host
		var host: Node3D = source.get("attached_to")
		if host != null and is_instance_valid(host) and MagicRules.is_creature(host.card_data):
			for line in oracle.split("\n"):
				if "equipped creature" in line or "enchanted creature" in line or "equipped permanent" in line or "enchanted permanent" in line or ("it gets " in line and ("enchanted " in oracle or "equipped " in oracle)):
					var mod := OracleParser.parse_pt_modifier(line)
					if mod != Vector2i.ZERO:
						host.layer_power_modifier += mod.x
						host.layer_toughness_modifier += mod.y

	# Layer 7d (+1/+1 and -1/-1 counters) is folded into Card3D.reset_dynamic_stats().

	# Layer 7e: Switch Power and Toughness
	for source in permanents:
		if not is_instance_valid(source): continue
		if source.has_meta("pt_switched") and bool(source.get_meta("pt_switched")) and "layer_pt_switched" in source:
			source.layer_pt_switched = true

static func _apply_layer_4_land_ability_overwrite(permanents: Array) -> void:
	for p in permanents:
		if is_instance_valid(p) and p.has_meta("blood_moon_replaced") and bool(p.get_meta("blood_moon_replaced")):
			if "abilities_removed" in p: p.abilities_removed = true

static func _count_matching_objects(oracle: String, controller: int, battlefield_lands: Array, battlefield_non_lands: Array, engine: Node = null) -> int:
	var count := 0
	if "creatures you control" in oracle:
		for c in battlefield_non_lands:
			if is_instance_valid(c) and MagicRules.is_creature(c.card_data) and _get_effective_controller(c) == controller:
				count += 1
	elif "lands you control" in oracle:
		for l in battlefield_lands:
			if is_instance_valid(l) and _get_effective_controller(l) == controller:
				count += 1
	elif "artifacts you control" in oracle:
		for c in battlefield_non_lands:
			if is_instance_valid(c) and "artifact" in MagicRules.get_card_type_line(c.card_data).to_lower() and _get_effective_controller(c) == controller:
				count += 1
	elif "enchantments you control" in oracle:
		for c in battlefield_non_lands:
			if is_instance_valid(c) and "enchantment" in MagicRules.get_card_type_line(c.card_data).to_lower() and _get_effective_controller(c) == controller:
				count += 1
	elif engine != null:
		if "cards in your hand" in oracle:
			var h_arr: Array = engine.hand_cards if controller == engine.local_player_id else engine.player_hands.get(controller, [])
			count = h_arr.size()
		elif "your life total" in oracle:
			count = maxi(0, int(engine.player_life.get(controller, 0)))
		elif "all graveyards" in oracle:
			var gys: Array = [engine.graveyard_stack]
			for pid in [2, 3, 4]: gys.append(engine.player_graveyards.get(pid, []))
			for gy in gys:
				for c in gy:
					if is_instance_valid(c) and (not ("creature" in oracle) or MagicRules.is_creature(c.card_data)):
						count += 1
		elif "your graveyard" in oracle:
			var gy: Array = engine.graveyard_stack if controller == engine.local_player_id else engine.player_graveyards.get(controller, [])
			for c in gy:
				if is_instance_valid(c) and (not ("creature" in oracle) or MagicRules.is_creature(c.card_data)):
					count += 1
	return count

static func get_cost_reduction(card_data: Dictionary, caster_id: int, battlefield_lands: Array, battlefield_non_lands: Array) -> int:
	var tl := MagicRules.get_card_type_line(card_data).to_lower()
	var rx := RegEx.new()
	rx.compile("costs?\\s+\\{(\\d+)\\}\\s+less\\s+to\\s+cast")
	var total_red := 0
	for p in battlefield_lands + battlefield_non_lands:
		if not is_instance_valid(p) or _get_effective_controller(p) != caster_id: continue
		var oracle := str(MagicRules.get_card_attribute(p.card_data, "oracle_text", "")).to_lower()
		for line in oracle.split("\n"):
			var m := rx.search(line)
			if not m: continue
			var amt := m.get_string(1).to_int()
			var applies := false
			if ("creature spells you cast" in line or "creature spell you cast" in line) and "creature" in tl:
				applies = true
				if "toughness greater than its power" in line:
					var p_val := str(MagicRules.get_card_attribute(card_data, "power", "0")).to_int()
					var t_val := str(MagicRules.get_card_attribute(card_data, "toughness", "0")).to_int()
					if t_val <= p_val:
						applies = false
			elif "artifact spells you cast" in line and "artifact" in tl: applies = true
			elif "enchantment spells you cast" in line and "enchantment" in tl: applies = true
			elif "instant and sorcery spells you cast" in line and ("instant" in tl or "sorcery" in tl): applies = true
			elif "noncreature spells you cast" in line and not ("creature" in tl): applies = true
			elif "spells you cast" in line and not ("creature spells" in line or "artifact spells" in line or "enchantment spells" in line or "instant" in line or "sorcery" in line or "noncreature" in line): applies = true
			if applies: total_red += amt
	return total_red

static func apply_cost_reduction(mana_cost_str: String, reduction: int) -> String:
	if reduction <= 0 or mana_cost_str.is_empty(): return mana_cost_str
	var rx := RegEx.new()
	rx.compile("\\{(\\d+)\\}")
	var rem := reduction
	var res := mana_cost_str
	var m := rx.search(res)
	if m:
		var gen := m.get_string(1).to_int()
		var new_gen := maxi(0, gen - rem)
		var rep := ("{%d}" % new_gen) if new_gen > 0 else ""
		res = res.substr(0, m.get_start()) + rep + res.substr(m.get_end())
	return res if not res.is_empty() else "{0}"

static func _matches_anthem_subject(subj: String, target: Node3D, source: Node3D, controller: int) -> bool:
	if not MagicRules.is_creature(target.card_data) and not ("permanents" in subj):
		return false
	if "other" in subj and target == source:
		return false
	if "you control" in subj and _get_effective_controller(target) != controller:
		return false
	if "opponents control" in subj and _get_effective_controller(target) == controller:
		return false

	var tl := MagicRules.get_card_type_line(target.card_data).to_lower()
	if "type_overrides" in target:
		for ov in target.type_overrides:
			tl += " " + str(ov).to_lower()
	if "artifact" in subj and not ("artifact" in tl): return false
	if "enchantment" in subj and not ("enchantment" in tl): return false
	if "legendary" in subj and not ("legendary" in tl): return false
	if "token" in subj and not ("token" in tl): return false
	if "nontoken" in subj and "token" in tl: return false
	if "equipped" in subj:
		var atts: Variant = target.get("attachments")
		if not (atts is Array) or atts.is_empty(): return false

	var color_map := {"white": "W", "blue": "U", "black": "B", "red": "R", "green": "G"}
	var t_cols: Array = target.card_data.get("colors", [])
	for col_w in color_map.keys():
		if col_w in subj and not (color_map[col_w] in t_cols):
			return false

	# Check tribal creature subtypes (e.g. "squirrels", "goblins", "elves", "zombies", "faeries")
	var skip_words := ["all", "other", "creatures", "creature", "permanents", "permanent", "you", "control", "opponents", "each", "artifact", "enchantment", "legendary", "token", "nontoken", "equipped", "enchanted", "white", "blue", "black", "red", "green", "and", "or", "non"]
	for raw_w in subj.replace(",", " ").split(" ", false):
		var w := raw_w.strip_edges().to_lower()
		if w.is_empty() or w in skip_words: continue
		var stem := w
		if stem.ends_with("ves") and stem.length() > 3: stem = stem.substr(0, stem.length() - 3) + "f"
		elif stem.ends_with("ies") and stem.length() > 3: stem = stem.substr(0, stem.length() - 3) + "y"
		elif stem.ends_with("s") and stem.length() > 2: stem = stem.substr(0, stem.length() - 1)
		if not (stem in tl):
			return false
	return true
