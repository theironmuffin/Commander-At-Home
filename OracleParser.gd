class_name OracleParser
extends RefCounted

# Regex pattern cache
static var ACTIVATED_REGEX: RegEx
static var TRIGGERED_REGEX: RegEx
static var EQUIP_REGEX: RegEx
static var ENCHANT_REGEX: RegEx
static var REMINDER_REGEX: RegEx
static var PT_MOD_REGEX: RegEx
static var SHOCK_LIFE_REGEX: RegEx
static var FLASHBACK_REGEX: RegEx
static var ESCAPE_REGEX: RegEx
static var UNEARTH_REGEX: RegEx
static var LOYALTY_REGEX: RegEx
static var SAGA_REGEX: RegEx
static var WARD_REGEX: RegEx
static var PROT_REGEX: RegEx
static var CREW_REGEX: RegEx
static var SADDLE_REGEX: RegEx
static var PLOT_REGEX: RegEx
static var MADNESS_REGEX: RegEx
static var SUSPEND_REGEX: RegEx
static var MANA_NUM_REGEX: RegEx
static var MANA_SYM_REGEX: RegEx

static var KEYWORD_LIST: Array[String] = [
	"flying", "first strike", "double strike", "deathtouch", "trample",
	"vigilance", "lifelink", "haste", "reach", "indestructible", "hexproof", "shroud", "menace", "flash"
]

static func _static_init() -> void:
	_ensure_regex_initialized()

static func _ensure_regex_initialized() -> void:
	if ACTIVATED_REGEX == null:
		ACTIVATED_REGEX = RegEx.new()
		ACTIVATED_REGEX.compile("^([^:]+):\\s*(.+)$")

	if TRIGGERED_REGEX == null:
		TRIGGERED_REGEX = RegEx.new()
		TRIGGERED_REGEX.compile("^(When|Whenever|At)\\s+([^,]+),\\s*(.+)$")

	if EQUIP_REGEX == null:
		EQUIP_REGEX = RegEx.new()
		EQUIP_REGEX.compile("^Equip(?:\\s+([a-zA-Z\\s]+?))?[\\s—-]+(\\{.+\\}|\\d+)$")

	if ENCHANT_REGEX == null:
		ENCHANT_REGEX = RegEx.new()
		ENCHANT_REGEX.compile("^Enchant\\s+(.+)$")

	if REMINDER_REGEX == null:
		REMINDER_REGEX = RegEx.new()
		REMINDER_REGEX.compile("\\s*\\([^)]*\\)")

	if PT_MOD_REGEX == null:
		PT_MOD_REGEX = RegEx.new()
		PT_MOD_REGEX.compile("([+-]\\d+)/([+-]\\d+)")

	if SHOCK_LIFE_REGEX == null:
		SHOCK_LIFE_REGEX = RegEx.new()
		SHOCK_LIFE_REGEX.compile("pay\\s+(\\d+)\\s+life\\.\\s*if you don't,\\s*(?:it|this land)\\s+enters\\s+(?:the battlefield\\s+)?tapped")
	if FLASHBACK_REGEX == null:
		FLASHBACK_REGEX = RegEx.new()
		FLASHBACK_REGEX.compile("^Flashback[\\s—]+(\\{.+?\\}(?:\\{.+?\\})*)")
	if ESCAPE_REGEX == null:
		ESCAPE_REGEX = RegEx.new()
		ESCAPE_REGEX.compile("^Escape[\\s—]+(\\{.+?\\}(?:\\{.+?\\})*)")
	if UNEARTH_REGEX == null:
		UNEARTH_REGEX = RegEx.new()
		UNEARTH_REGEX.compile("^Unearth[\\s—]+(\\{.+?\\}(?:\\{.+?\\})*)")
	if LOYALTY_REGEX == null:
		LOYALTY_REGEX = RegEx.new()
		LOYALTY_REGEX.compile("^\\[?([+-]?(?:\\d+|X))\\]?:\\s*(.+)$")
	if SAGA_REGEX == null:
		SAGA_REGEX = RegEx.new()
		SAGA_REGEX.compile("^([IVX]+(?:,\\s*[IVX]+)*)\\s*[—-]+\\s*(.+)$")
	if WARD_REGEX == null:
		WARD_REGEX = RegEx.new()
		WARD_REGEX.compile("ward[\\s—]+(\\{.+?\\}(?:\\{.+?\\})*|pay\\s+\\d+\\s+life)")
	if PROT_REGEX == null:
		PROT_REGEX = RegEx.new()
		PROT_REGEX.compile("protection from ([a-zA-Z\\s,]+?)(?:$|\\.|,|;)")
		CREW_REGEX = RegEx.new()
		CREW_REGEX.compile("^Crew\\s+(\\d+)")
		SADDLE_REGEX = RegEx.new()
		SADDLE_REGEX.compile("^Saddle\\s+(\\d+)")
		PLOT_REGEX = RegEx.new()
		PLOT_REGEX.compile("^Plot\\s+((?:\\{[^\\}]+\\})+)")
		MADNESS_REGEX = RegEx.new()
		MADNESS_REGEX.compile("^Madness\\s+((?:\\{[^\\}]+\\})+)")
		SUSPEND_REGEX = RegEx.new()
		SUSPEND_REGEX.compile("^Suspend\\s+(\\d+)[\\s—-]+((?:\\{[^\\}]+\\})+)")
		MANA_NUM_REGEX = RegEx.new()
		MANA_NUM_REGEX.compile("(\\d+)")
		MANA_SYM_REGEX = RegEx.new()
		MANA_SYM_REGEX.compile("\\{([A-Z0-9/]+)\\}")

static func parse_oracle_text(oracle_text: String) -> Dictionary:
	_ensure_regex_initialized()

	var parsed_data := {
		"keywords": [],
		"activated_abilities": [],
		"triggered_abilities": [],
		"static_effects": [],
		"enchant_target": "",
		"etb_tapped": {"mode": "none", "condition": "", "pay_life": 0},
		"flashback_cost": "",
		"escape_cost": "",
		"escape_exile_count": 0,
		"unearth_cost": "",
		"modal": {"count": 0, "allow_repeat": false, "modes": []},
		"additional_cost": {"type": "", "target": "", "amount": 0},
		"loyalty_abilities": [],
		"saga_chapters": [],
		"saga_max_chapter": 0,
		"ward_cost": "",
		"protection_from": [],
		"hexproof_from": [],
		"crew_cost": 0,
		"saddle_cost": 0,
		"foretell_cost": "",
		"has_storm": false,
		"has_split_second": false,
		"has_cascade": false,
		"discover_n": 0,
		"plot_cost": "",
		"madness_cost": "",
		"suspend_count": 0,
		"suspend_cost": "",
		"companion_text": ""
	}

	if oracle_text.is_empty():
		return parsed_data

	var clean_full := REMINDER_REGEX.sub(oracle_text, "", true)
	var full_lower := clean_full.to_lower()

	# Check Shockland pattern across sentences first ("you may pay N life. If you don't, it enters tapped.")
	var shock_m := SHOCK_LIFE_REGEX.search(full_lower)
	if shock_m:
		parsed_data["etb_tapped"] = {
			"mode": "shock_pay_life",
			"condition": "",
			"pay_life": shock_m.get_string(1).to_int()
		}

	var in_modal_block := false
	var lines := clean_full.split("\n")
	for line in lines:
		var clean_line := line.strip_edges()
		if clean_line.is_empty():
			continue
		var line_lower := clean_line.to_lower()

		# Modal spell header & bulleted modes (CR 700.2)
		if line_lower.begins_with("choose one") or line_lower.begins_with("choose two") or line_lower.begins_with("choose three") or line_lower.begins_with("choose up to"):
			var m_count := 1
			if "two" in line_lower: m_count = 2
			elif "three" in line_lower: m_count = 3
			parsed_data["modal"]["count"] = m_count
			parsed_data["modal"]["allow_repeat"] = "same mode more than once" in line_lower
			in_modal_block = true
			continue
		if in_modal_block and (clean_line.begins_with("•") or clean_line.begins_with("- ")):
			var mode_txt := clean_line.trim_prefix("•").trim_prefix("-").strip_edges()
			if not mode_txt.is_empty():
				parsed_data["modal"]["modes"].append(mode_txt)
			continue
		if in_modal_block and not (clean_line.begins_with("•") or clean_line.begins_with("- ")):
			in_modal_block = false

		# Additional cost parsing (CR 601.2b / 601.2f)
		if "as an additional cost to cast" in line_lower:
			if "sacrifice " in line_lower:
				var sac_tgt := "permanent"
				if "creature" in line_lower: sac_tgt = "creature"
				elif "artifact" in line_lower: sac_tgt = "artifact"
				elif "land" in line_lower: sac_tgt = "land"
				parsed_data["additional_cost"] = {"type": "sacrifice", "target": sac_tgt, "amount": 1}
			elif "discard " in line_lower:
				var d_amt := AbilityResolver._extract_number(line_lower, "discard ")
				parsed_data["additional_cost"] = {"type": "discard", "target": "card", "amount": d_amt}
			elif "pay " in line_lower and " life" in line_lower:
				var l_amt := AbilityResolver._extract_number(line_lower, "pay ")
				parsed_data["additional_cost"] = {"type": "pay_life", "target": "life", "amount": l_amt}
			continue

		# ETB Tapped Replacement Checks (Checklands, Fastlands, Slowlands, Taplands)
		if parsed_data["etb_tapped"]["mode"] == "none" and ("enters tapped" in line_lower or "enters the battlefield tapped" in line_lower):
			if "unless " in line_lower:
				var u_idx := line_lower.find("unless ")
				var cond := line_lower.substr(u_idx + 7).strip_edges().trim_suffix(".")
				parsed_data["etb_tapped"] = {"mode": "unless", "condition": cond, "pay_life": 0}
			elif not ("if you don't" in line_lower):
				parsed_data["etb_tapped"] = {"mode": "always", "condition": "", "pay_life": 0}

		# Graveyard casting mechanics: Flashback, Escape, Unearth
		var fb_m := FLASHBACK_REGEX.search(clean_line)
		if fb_m:
			parsed_data["flashback_cost"] = fb_m.get_string(1).strip_edges()
			continue
		var esc_m := ESCAPE_REGEX.search(clean_line)
		if esc_m:
			parsed_data["escape_cost"] = esc_m.get_string(1).strip_edges()
			parsed_data["escape_exile_count"] = AbilityResolver._extract_number(line_lower, "exile ") if "exile " in line_lower else 3
			continue
		var un_m := UNEARTH_REGEX.search(clean_line)
		if un_m:
			parsed_data["unearth_cost"] = un_m.get_string(1).strip_edges()
			continue

		# Planeswalker Loyalty Abilities ([+1]: ..., [-2]: ..., [-X]: ...)
		var loy_m := LOYALTY_REGEX.search(clean_line)
		if loy_m:
			var d_str := loy_m.get_string(1).strip_edges()
			var eff_raw := loy_m.get_string(2).strip_edges()
			parsed_data["loyalty_abilities"].append({
				"delta_str": d_str,
				"effect_raw": eff_raw,
				"target_requirement": extract_target_requirement(eff_raw)
			})
			continue

		# Saga Chapters (I — ..., II, III — ...)
		var saga_m := SAGA_REGEX.search(clean_line)
		if saga_m:
			var rom_str := saga_m.get_string(1).strip_edges()
			var eff_raw := saga_m.get_string(2).strip_edges()
			var chaps: Array[int] = []
			for r_part in rom_str.split(","):
				var ch_num := _roman_to_int(r_part.strip_edges())
				if ch_num > 0:
					chaps.append(ch_num)
					if ch_num > int(parsed_data["saga_max_chapter"]):
						parsed_data["saga_max_chapter"] = ch_num
			if not chaps.is_empty():
				parsed_data["saga_chapters"].append({
					"chapters": chaps,
					"effect_raw": eff_raw,
					"target_requirement": extract_target_requirement(eff_raw)
				})
				continue

		# Ward & Protection from ...
		var ward_m := WARD_REGEX.search(line_lower)
		if ward_m:
			parsed_data["ward_cost"] = ward_m.get_string(1).strip_edges().to_upper()
			if not ("ward" in parsed_data["keywords"]):
				parsed_data["keywords"].append("ward")
		var cm := CREW_REGEX.search(clean_line)
		if cm: parsed_data["crew_cost"] = cm.get_string(1).to_int()

		var sm := SADDLE_REGEX.search(clean_line)
		if sm: parsed_data["saddle_cost"] = sm.get_string(1).to_int()

		var plm := PLOT_REGEX.search(clean_line)
		if plm: parsed_data["plot_cost"] = plm.get_string(1)

		var mm := MADNESS_REGEX.search(clean_line)
		if mm: parsed_data["madness_cost"] = mm.get_string(1)

		var spm := SUSPEND_REGEX.search(clean_line)
		if spm:
			parsed_data["suspend_count"] = spm.get_string(1).to_int()
			parsed_data["suspend_cost"] = spm.get_string(2)

		if line_lower.begins_with("companion —") or line_lower.begins_with("companion -"):
			parsed_data["companion_text"] = clean_line

		var foretell_rx := RegEx.new()
		foretell_rx.compile("^Foretell\\s+((?:\\{[^\\}]+\\})+)")
		var fm := foretell_rx.search(clean_line)
		if fm: parsed_data["foretell_cost"] = fm.get_string(1)

		var disc_rx := RegEx.new()
		disc_rx.compile("(?i)discover\\s+(\\d+)")
		var dm := disc_rx.search(clean_line)
		if dm: parsed_data["discover_n"] = dm.get_string(1).to_int()

		var hf_rx := RegEx.new()
		hf_rx.compile("(?i)hexproof from ([a-zA-Z]+)")
		for hfm in hf_rx.search_all(clean_line):
			var h_val := hfm.get_string(1).strip_edges().to_lower()
			if not h_val.is_empty() and not (h_val in parsed_data["hexproof_from"]):
				parsed_data["hexproof_from"].append(h_val)

		if line_lower == "storm" or "storm" in line_lower.split(","):
			parsed_data["has_storm"] = true
		if line_lower == "split second":
			parsed_data["has_split_second"] = true
		if line_lower == "cascade":
			parsed_data["has_cascade"] = true

		var prot_m := PROT_REGEX.search(line_lower)
		if prot_m:
			var p_raw := prot_m.get_string(1).strip_edges()
			for p_tok in p_raw.replace(" and ", ",").replace(" from ", ",").split(","):
				var pt := p_tok.strip_edges()
				if not pt.is_empty() and not (pt in parsed_data["protection_from"]):
					parsed_data["protection_from"].append(pt)

		# 1. Keyword check (e.g., "Flying, Haste")
		var matched_keywords := _extract_keywords(clean_line)
		if not matched_keywords.is_empty():
			for kw in matched_keywords:
				if not kw in parsed_data["keywords"]:
					parsed_data["keywords"].append(kw)
			continue

		# 2. Enchant keyword (Aura targeting requirement)
		var ench_match := ENCHANT_REGEX.search(clean_line)
		if ench_match:
			parsed_data["enchant_target"] = ench_match.get_string(1).strip_edges().to_lower()
			parsed_data["static_effects"].append(clean_line)
			continue

		# 3. Equip keyword
		var eq_match := EQUIP_REGEX.search(clean_line)
		if eq_match:
			var eq_filter := eq_match.get_string(1).strip_edges().to_lower()
			var eq_cost := eq_match.get_string(2).strip_edges()
			if eq_cost.is_valid_int():
				eq_cost = "{%s}" % eq_cost
			var target_desc := ("target %s you control" % eq_filter) if not eq_filter.is_empty() else "target creature you control"
			parsed_data["activated_abilities"].append({
				"cost_raw": eq_cost,
				"effect_raw": "Attach this permanent to %s." % target_desc,
				"is_equip": true,
				"sorcery_only": true,
				"is_optional": false,
				"target_requirement": target_desc
			})
			continue

		# 4. Activated Ability check ("Cost: Effect")
		var act_match := ACTIVATED_REGEX.search(clean_line)
		if act_match:
			var eff := act_match.get_string(2).strip_edges()
			parsed_data["activated_abilities"].append({
				"cost_raw": act_match.get_string(1).strip_edges(),
				"effect_raw": eff,
				"is_equip": false,
				"sorcery_only": "activate only as a sorcery" in eff.to_lower(),
				"is_optional": "you may " in eff.to_lower(),
				"target_requirement": extract_target_requirement(eff)
			})
			continue

		# 5. Triggered Ability check ("When/Whenever/At ..., ...")
		var trig_match := TRIGGERED_REGEX.search(clean_line)
		if trig_match:
			var eff := trig_match.get_string(3).strip_edges()
			parsed_data["triggered_abilities"].append({
				"condition_type": trig_match.get_string(1).strip_edges(),
				"trigger_event_raw": trig_match.get_string(2).strip_edges(),
				"effect_raw": eff,
				"is_optional": "you may " in eff.to_lower(),
				"target_requirement": extract_target_requirement(eff)
			})
			continue

		# 6. Fallback: Static / Continuous ability
		parsed_data["static_effects"].append(clean_line)

	return parsed_data

static func extract_target_requirement(text: String) -> String:
	_ensure_regex_initialized()
	var clean := REMINDER_REGEX.sub(text, "", true)
	var lower := clean.to_lower()
	var idx := lower.find("target ")
	if idx == -1:
		return ""
	var sub := lower.substr(idx + 7).strip_edges()
	for stop_word in [".", ",", " until ", " gets ", " gains ", " deals ", " and ", " to ", " with "]:
		var s_idx := sub.find(stop_word)
		if s_idx != -1:
			sub = sub.substr(0, s_idx).strip_edges()
	return sub

static func count_required_targets(text: String) -> int:
	_ensure_regex_initialized()
	var clean := REMINDER_REGEX.sub(text, "", true).to_lower()
	if not ("target " in clean):
		return 0
	if "up to " in clean or "any number of target" in clean:
		var idx_up := clean.find("up to ")
		var idx_tg := clean.find("target ")
		if (idx_up != -1 and idx_up < idx_tg and idx_tg - idx_up < 24) or "any number of target" in clean:
			return 0
	var max_cnt := 1
	if "two target" in clean: max_cnt = maxi(max_cnt, 2)
	elif "three target" in clean: max_cnt = maxi(max_cnt, 3)
	elif "four target" in clean: max_cnt = maxi(max_cnt, 4)
	elif "five target" in clean: max_cnt = maxi(max_cnt, 5)
	var occ := 0
	var pos := 0
	while true:
		pos = clean.find("target ", pos)
		if pos == -1: break
		occ += 1
		pos += 7
	return maxi(max_cnt, occ)

static func extract_target_zone(requirement: String) -> String:
	var r := requirement.to_lower()
	if "graveyard" in r:
		return "graveyard"
	if "exile" in r:
		return "exile"
	if "spell" in r or "activated ability" in r or "triggered ability" in r:
		return "stack"
	return "battlefield"

static func _extract_keywords(line: String) -> Array[String]:
	var found: Array[String] = []
	var parts := line.to_lower().split(",")
	for part in parts:
		var candidate := part.strip_edges()
		if candidate in KEYWORD_LIST:
			found.append(candidate)
	if found.size() == parts.size():
		return found
	return []

static func parse_pt_modifier(text: String) -> Vector2i:
	_ensure_regex_initialized()
	var m := PT_MOD_REGEX.search(text)
	if m:
		return Vector2i(m.get_string(1).to_int(), m.get_string(2).to_int())
	return Vector2i.ZERO

static func count_x_in_mana_cost(mana_cost: String) -> int:
	var upper := mana_cost.to_upper()
	var count := 0
	var idx := 0
	while true:
		idx = upper.find("{X}", idx)
		if idx == -1: break
		count += 1
		idx += 3
	return count

static func substitute_x_in_text(text: String, x_val: int) -> String:
	var rx := RegEx.new()
	rx.compile("(?<![A-Za-z0-9])([+-]?)X(?![A-Za-z0-9])")
	var x_str := str(x_val)
	var res := text
	var matches := rx.search_all(res)
	for i in range(matches.size() - 1, -1, -1):
		var m: RegExMatch = matches[i]
		var sign_str := m.get_string(1)
		var start := m.get_start()
		var end := m.get_end()
		res = res.substr(0, start) + sign_str + x_str + res.substr(end)
	return res

static func _roman_to_int(roman: String) -> int:
	var map := {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6}
	return int(map.get(roman.to_upper(), 0))


static func parse_mana_abilities(card_data: Dictionary, card_node: Node = null) -> Array[Dictionary]:
	_ensure_regex_initialized()
	var out: Array[Dictionary] = []
	if card_node != null and is_instance_valid(card_node) and card_node.has_meta("blood_moon_replaced") and bool(card_node.get_meta("blood_moon_replaced")):
		out.append({
			"label": "{T}: Add {R}",
			"colors": ["R"] as Array[String],
			"amount": 1,
			"fixed_combo": [] as Array[String],
			"tap_cost": true,
			"mana_cost": "",
			"life_cost": 0,
			"sac_cost": false,
			"restriction": "",
			"restriction_text": ""
		})
		return out

	var tl := MagicRules.get_card_type_line(card_data).to_lower()
	if card_node != null and is_instance_valid(card_node) and "type_overrides" in card_node:
		for ov in card_node.type_overrides:
			tl += " " + str(ov).to_lower()

	var oracle := str(MagicRules.get_card_attribute(card_data, "oracle_text", ""))
	var tap_trigger_damage := 0
	var tap_num_rx := MANA_NUM_REGEX
	for t_line in oracle.split("\n"):
		var tl_c := REMINDER_REGEX.sub(t_line, "", true).strip_edges().to_lower()
		if "becomes tapped" in tl_c and "deals " in tl_c and ("damage to you" in tl_c or "damage to its controller" in tl_c):
			var tm := tap_num_rx.search(tl_c.substr(tl_c.find("deals ")))
			if tm: tap_trigger_damage += tm.get_string(1).to_int()
	var sym_rx := MANA_SYM_REGEX
	var num_rx := MANA_NUM_REGEX

	var chosen_type: String = str(card_node.get_meta("chosen_creature_type")) if (card_node != null and is_instance_valid(card_node) and card_node.has_meta("chosen_creature_type")) else ""
	var chosen_color: String = str(card_node.get_meta("chosen_color")) if (card_node != null and is_instance_valid(card_node) and card_node.has_meta("chosen_color")) else ""

	var seen_keys := {}
	var basic_map := {"plains": "W", "island": "U", "swamp": "B", "mountain": "R", "forest": "G"}
	for b_sub in basic_map.keys():
		if b_sub in tl:
			var col_c: String = basic_map[b_sub]
			var key := "basic_" + col_c
			if not seen_keys.has(key):
				seen_keys[key] = true
				out.append({
					"label": "{T}: Add {%s}" % col_c,
					"colors": [col_c] as Array[String],
					"amount": 1,
					"fixed_combo": [] as Array[String],
					"tap_cost": true,
					"mana_cost": "",
					"life_cost": 0,
					"sac_cost": false,
					"restriction": "",
					"restriction_text": ""
				})

	for raw_line in oracle.split("\n"):
		var clean_line := REMINDER_REGEX.sub(raw_line, "", true).strip_edges()
		if clean_line.is_empty(): continue
		var lower := clean_line.to_lower()
		var colon_idx := clean_line.find(":")
		if colon_idx == -1 or not ("add " in lower):
			continue
		var cost_part := clean_line.substr(0, colon_idx).strip_edges()
		var cost_lower := cost_part.to_lower()
		var eff_part := clean_line.substr(colon_idx + 1).strip_edges()
		var eff_lower := eff_part.to_lower()
		if not ("add " in eff_lower):
			continue

		var tap_cost := "{t}" in cost_lower
		var sac_cost := "sacrifice" in cost_lower
		var mana_cost := ""
		for m in sym_rx.search_all(cost_part.to_upper()):
			var s := m.get_string(1)
			if s != "T" and s != "Q":
				mana_cost += "{" + s + "}"

		var life_cost := tap_trigger_damage if tap_cost else 0
		if "pay " in cost_lower and " life" in cost_lower:
			var lm := num_rx.search(cost_lower.substr(cost_lower.find("pay ")))
			if lm: life_cost += lm.get_string(1).to_int()
		if "deals " in eff_lower and ("damage to you" in eff_lower or "damage to its controller" in eff_lower):
			var dm := num_rx.search(eff_lower.substr(eff_lower.find("deals ")))
			if dm: life_cost += dm.get_string(1).to_int()
		if "lose " in eff_lower and " life" in eff_lower:
			var lom := num_rx.search(eff_lower.substr(eff_lower.find("lose ")))
			if lom: life_cost += lom.get_string(1).to_int()

		var restriction := ""
		var restriction_text := ""
		if "spend this mana only to cast" in eff_lower:
			if "chosen type" in eff_lower or "chosen creature type" in eff_lower:
				restriction = "chosen_type"
				restriction_text = "Only for %s spells" % (chosen_type if not chosen_type.is_empty() else "chosen type")
			elif "creature" in eff_lower:
				restriction = "creature"
				restriction_text = "Only for Creature spells"
			elif "artifact" in eff_lower:
				restriction = "artifact"
				restriction_text = "Only for Artifact spells"
			elif "instant or sorcery" in eff_lower:
				restriction = "instant_or_sorcery"
				restriction_text = "Only for Instant/Sorcery"
			elif "commander" in eff_lower:
				restriction = "commander"
				restriction_text = "Only for Commander"
			elif "enchantment" in eff_lower:
				restriction = "enchantment"
				restriction_text = "Only for Enchantment spells"
			elif "planeswalker" in eff_lower:
				restriction = "planeswalker"
				restriction_text = "Only for Planeswalker spells"
			elif "legendary" in eff_lower:
				restriction = "legendary"
				restriction_text = "Only for Legendary spells"
			elif "multicolored" in eff_lower:
				restriction = "multicolored"
				restriction_text = "Only for Multicolored spells"
		elif "can't be spent to cast a nonartifact spell" in eff_lower:
			restriction = "non_nonartifact"
			restriction_text = "Not for Nonartifact spells"
		elif "can't be spent to cast a creature spell" in eff_lower:
			restriction = "non_creature"
			restriction_text = "Not for Creature spells"
		elif "spend this mana only to activate" in eff_lower or "only on activated abilities" in eff_lower:
			restriction = "activated"
			restriction_text = "Only for Activated abilities"

		var colors: Array[String] = []
		var fixed_combo: Array[String] = []
		var amount := 1

		if "two mana" in eff_lower: amount = 2
		elif "three mana" in eff_lower: amount = 3
		elif "four mana" in eff_lower: amount = 4
		elif "five mana" in eff_lower: amount = 5
		if "of the chosen color" in eff_lower and not chosen_color.is_empty():
			colors = [chosen_color] as Array[String]
		elif "any color" in eff_lower or "any one color" in eff_lower or "mana of any" in eff_lower:
			colors = ["W", "U", "B", "R", "G"] as Array[String]
		else:
			var syms: Array[String] = []
			for m in sym_rx.search_all(eff_part.to_upper()):
				var sym := m.get_string(1)
				if sym in ["W", "U", "B", "R", "G", "C"]:
					syms.append(sym)
			var add_clause_lower := eff_lower.split(".")[0]
			if " or " in add_clause_lower:
				var first_opt := eff_part.split(".")[0].split(",")[0].split(" or ")[0].to_upper()
				var opt_cnt := sym_rx.search_all(first_opt).size()
				if opt_cnt > 1: amount = opt_cnt
				for s in syms:
					if not (s in colors): colors.append(s)
			elif syms.size() == 1:
				colors = [syms[0]] as Array[String]
			elif syms.size() > 1:
				var all_same := true
				for s in syms:
					if s != syms[0]: all_same = false; break
				if all_same:
					colors = [syms[0]] as Array[String]
					amount = syms.size()
				else:
					fixed_combo = syms
					colors = syms.duplicate()

		if colors.is_empty() and fixed_combo.is_empty():
			continue

		var sig := "%s|%s|%d|%s|%d|%s" % [",".join(colors), ",".join(fixed_combo), amount, mana_cost, life_cost, restriction]
		if seen_keys.has(sig): continue
		seen_keys[sig] = true
		if colors.size() == 1 and seen_keys.has("basic_" + colors[0]) and mana_cost.is_empty() and life_cost == 0 and not sac_cost and restriction.is_empty() and amount == 1:
			continue

		var cost_desc_parts: Array[String] = []
		if tap_cost: cost_desc_parts.append("{T}")
		if not mana_cost.is_empty(): cost_desc_parts.append(mana_cost)
		if life_cost > 0: cost_desc_parts.append("Pay %d life" % life_cost)
		if sac_cost: cost_desc_parts.append("Sacrifice")
		var cost_str := ", ".join(cost_desc_parts) if not cost_desc_parts.is_empty() else "Free"
		var out_str := ""
		if not fixed_combo.is_empty():
			for fc in fixed_combo: out_str += "{" + fc + "}"
		elif colors.size() == 5 and "any color" in eff_lower:
			out_str = "Any Color"
		else:
			var p_arr: Array[String] = []
			for c in colors: p_arr.append("{" + c + "}")
			out_str = " or ".join(p_arr)
			if amount > 1: out_str = "%dx %s" % [amount, out_str]
		var full_lbl := "%s: Add %s" % [cost_str, out_str]
		if not restriction_text.is_empty():
			full_lbl += " (" + restriction_text + ")"

		out.append({
			"label": full_lbl,
			"colors": colors,
			"amount": amount,
			"fixed_combo": fixed_combo,
			"tap_cost": tap_cost,
			"mana_cost": mana_cost,
			"life_cost": life_cost,
			"sac_cost": sac_cost,
			"restriction": restriction,
			"restriction_text": restriction_text,
			"chosen_type": chosen_type
		})

	if out.is_empty() and "land" in tl:
		for c in MagicRules.get_land_colors(card_data):
			out.append({
				"label": "{T}: Add {%s}" % c,
				"colors": [c] as Array[String],
				"amount": 1,
				"fixed_combo": [] as Array[String],
				"tap_cost": true,
				"mana_cost": "",
				"life_cost": 0,
				"sac_cost": false,
				"restriction": "",
				"restriction_text": ""
			})
	return out
