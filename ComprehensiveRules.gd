class_name ComprehensiveRules
extends RefCounted

# Queryable MTG Comprehensive Rules (CR) registry & ruling helper.
# Provides structured rule lookups by rule ID, category, keyword, or card attributes.

const RULES: Array[Dictionary] = [
	# --- 100s: Game Concepts ---
	{"id": "101.1", "section": "100 Game Concepts", "title": "Golden Rule — Card Text Overrides Rules",
	 "tags": ["golden rule", "override", "contradict"],
	 "text": "Whenever a card's text directly contradicts these rules, the card takes precedence. The card overrides only the rule that applies to that specific situation."},
	{"id": "104.3b", "section": "100 Game Concepts", "title": "Losing the Game (0 Life)",
	 "tags": ["life", "lose", "sba", "0 life"],
	 "text": "If a player's life total is 0 or less, that player loses the game the next time a player would receive priority (State-Based Action 704.5a)."},
	{"id": "106.4", "section": "100 Game Concepts", "title": "Mana Pool Empties",
	 "tags": ["mana", "mana pool", "empty", "phase", "step"],
	 "text": "When a step or phase ends, any unused mana left in a player's mana pool empties unless an effect states that mana doesn't empty."},
	{"id": "115.10a", "section": "100 Game Concepts", "title": "What Counts as a Target",
	 "tags": ["target", "hexproof", "shroud", "ward", "protection", "board wipe"],
	 "text": "Just because an object or player is affected by a spell or ability doesn't make it a target. Unless identified by the word 'target' (or Aura/keyword targeting rules), it is not a target."},
	{"id": "117.1", "section": "100 Game Concepts", "title": "Priority & Timing",
	 "tags": ["priority", "stack", "instant", "sorcery"],
	 "text": "The active player receives priority at the beginning of most steps and phases. A player may cast instants or activate abilities whenever they have priority; sorcery-speed actions require your own main phase with an empty stack."},
	{"id": "120.3", "section": "100 Game Concepts", "title": "Damage Results (Life, Loyalty, Infect, Wither, Lifelink)",
	 "tags": ["damage", "lifelink", "infect", "wither", "deathtouch", "loyalty"],
	 "text": "Damage to a player causes loss of that much life (or poison counters if source has Infect). Damage to a planeswalker removes that many loyalty counters. Damage to a creature marks damage (or puts -1/-1 counters if Infect/Wither)."},
	{"id": "121.1", "section": "100 Game Concepts", "title": "Drawing Cards",
	 "tags": ["draw", "library", "empty library"],
	 "text": "A player draws a card by putting the top card of their library into their hand. Drawing multiple cards is a sequence of individual draws; if a library is empty when instructed to draw, SBA 704.5b causes that player to lose."},
	{"id": "122.1", "section": "100 Game Concepts", "title": "Counters (+1/+1, -1/-1, Stun, Shield, Finality, Loyalty)",
	 "tags": ["counter", "stun", "shield", "finality", "loyalty", "lore", "oil", "poison"],
	 "text": "Stun counter: if a permanent would untap, remove a stun counter instead. Shield counter: if it would be destroyed or dealt damage, remove a shield counter instead. Finality counter: if it would go to a graveyard from the battlefield, exile it instead."},

	# --- 300s: Card Types ---
	{"id": "302.6", "section": "300 Card Types", "title": "Summoning Sickness",
	 "tags": ["summoning sickness", "creature", "haste", "tap", "attack"],
	 "text": "A creature's activated ability with {T} or {Q} in its cost can't be activated, and it can't attack, unless its controller has controlled it continuously since the beginning of their most recent turn (or it has Haste)."},
	{"id": "305.2", "section": "300 Card Types", "title": "Playing Lands (One Per Turn)",
	 "tags": ["land", "play land", "main phase"],
	 "text": "A player can normally play one land during each of their own turns, during a main phase when the stack is empty. Playing a land is a special action and does not use the stack."},
	{"id": "306.5", "section": "300 Card Types", "title": "Planeswalker Loyalty",
	 "tags": ["planeswalker", "loyalty", "damage", "0 loyalty"],
	 "text": "A planeswalker enters the battlefield with loyalty counters equal to its printed loyalty. If its loyalty reaches 0, it is put into its owner's graveyard as a State-Based Action (704.5i)."},

	# --- 400s: Zones ---
	{"id": "402.2", "section": "400 Zones", "title": "Maximum Hand Size (7 Cards)",
	 "tags": ["hand", "max hand size", "discard", "cleanup"],
	 "text": "Each player has a maximum hand size of seven cards unless an effect modifies it. During the Cleanup step, the active player discards down to their maximum hand size."},
	{"id": "405.5", "section": "400 Zones", "title": "The Stack (LIFO)",
	 "tags": ["stack", "resolve", "priority", "lifo"],
	 "text": "When all players pass priority in succession, the top spell or ability on the stack resolves. If the stack is empty, the current step or phase ends."},

	# --- 500s: Turn Structure ---
	{"id": "502.1", "section": "500 Turn Structure", "title": "Untap Step (No Priority)",
	 "tags": ["untap", "phasing", "stun"],
	 "text": "The active player untaps all permanents they control (unless prevented by an effect or a stun counter). No player receives priority during the Untap step."},
	{"id": "510.1", "section": "500 Turn Structure", "title": "Combat Damage Step",
	 "tags": ["combat", "damage", "first strike", "double strike", "trample", "deathtouch"],
	 "text": "If any attacking or blocking creature has First Strike or Double Strike, a First Strike combat damage step occurs first, followed by SBAs, then a second Combat Damage step for remaining creatures and Double Strikers."},
	{"id": "514.2", "section": "500 Turn Structure", "title": "Cleanup Step",
	 "tags": ["cleanup", "end of turn", "until end of turn", "damage clears"],
	 "text": "Active player discards down to max hand size, then simultaneously all damage marked on permanents is removed and all 'until end of turn' / 'this turn' effects end."},

	# --- 600s: Spells, Abilities & Layers ---
	{"id": "601.2f", "section": "600 Spells & Abilities", "title": "Determining Total Cost",
	 "tags": ["cost", "mana", "tax", "reduction", "affinity", "commander tax", "x"],
	 "text": "Total cost = Mana cost (or alternative cost) + additional costs & cost increases (such as Commander Tax) - cost reductions (such as Affinity or 'costs {1} less')."},
	{"id": "603.3b", "section": "600 Spells & Abilities", "title": "APNAP Trigger Ordering",
	 "tags": ["trigger", "apnap", "stack", "order"],
	 "text": "If multiple triggered abilities would be put onto the stack at the same time, the active player puts all their triggers onto the stack first (in any order), followed by each other player in turn order."},
	{"id": "605.3", "section": "600 Spells & Abilities", "title": "Mana Abilities Don't Use the Stack",
	 "tags": ["mana ability", "stack", "priority", "tap"],
	 "text": "Activated and triggered mana abilities resolve immediately without using the stack and cannot be responded to."},
	{"id": "606.3", "section": "600 Spells & Abilities", "title": "Loyalty Ability Timing (Once Per Turn)",
	 "tags": ["loyalty", "planeswalker", "sorcery speed", "once per turn"],
	 "text": "A player may activate a loyalty ability of a permanent they control only any time they have priority during their own main phase with an empty stack, and only if none of that permanent's loyalty abilities have been activated this turn."},
	{"id": "608.2b", "section": "600 Spells & Abilities", "title": "Fizzling (Illegal Targets on Resolution)",
	 "tags": ["fizzle", "target", "illegal", "countered", "resolve"],
	 "text": "If all targets of a spell or ability have become illegal by the time it would resolve, the spell or ability doesn't resolve and is removed from the stack (a spell is put into its owner's graveyard)."},
	{"id": "613.1", "section": "600 Spells & Abilities", "title": "Interaction of Continuous Effects (7-Layer System)",
	 "tags": ["layers", "continuous", "copy", "control", "type", "color", "abilities", "power", "toughness"],
	 "text": "Continuous effects apply in 7 layers: 1. Copy, 2. Control, 3. Text, 4. Type, 5. Color, 6. Abilities, 7. Power/Toughness (7a CDAs, 7b Set Base P/T, 7c +/- modifiers, 7d Counters, 7e Switch P/T)."},

	# --- 701: Keyword Actions ---
	{"id": "701.25", "section": "701 Keyword Actions", "title": "Surveil",
	 "tags": ["surveil", "library", "graveyard"],
	 "text": "Look at the top N cards of your library, then put any number of them into your graveyard and the rest on top of your library in any order."},
	{"id": "701.34", "section": "701 Keyword Actions", "title": "Proliferate",
	 "tags": ["proliferate", "counter", "loyalty", "poison", "+1/+1"],
	 "text": "Choose any number of permanents and/or players that have a counter, then give each another counter of each kind already there."},
	{"id": "701.71a", "section": "701 Keyword Actions", "title": "Empower Jace",
	 "tags": ["empower jace", "jace", "token", "planeswalker", "loyalty"],
	 "text": "If you don't control a Jace planeswalker token, create a blue nonlegendary Jace planeswalker token with 0 loyalty, '[-1]: Surveil 1,' and '[-3]: Draw a card.' Choose a Jace planeswalker token you control and put N loyalty counters on it."},

	# --- 702: Keyword Abilities ---
	{"id": "702.2", "section": "702 Keyword Abilities", "title": "Deathtouch",
	 "tags": ["deathtouch", "lethal", "trample", "damage"],
	 "text": "Any nonzero amount of damage dealt to a creature by a source with Deathtouch is considered lethal damage. Combined with Trample, only 1 damage needs to be assigned to each blocker."},
	{"id": "702.3", "section": "702 Keyword Abilities", "title": "Defender",
	 "tags": ["defender", "attack", "block"],
	 "text": "A creature with Defender can't attack."},
	{"id": "702.9", "section": "702 Keyword Abilities", "title": "Flying & Reach (702.17)",
	 "tags": ["flying", "reach", "block", "evasion"],
	 "text": "A creature with Flying can't be blocked except by creatures with Flying or Reach."},
	{"id": "702.11", "section": "702 Keyword Abilities", "title": "Hexproof & Shroud (702.18)",
	 "tags": ["hexproof", "shroud", "target"],
	 "text": "Hexproof: can't be the target of spells or abilities your opponents control. Shroud: can't be the target of any spells or abilities."},
	{"id": "702.12", "section": "702 Keyword Abilities", "title": "Indestructible",
	 "tags": ["indestructible", "destroy", "lethal damage"],
	 "text": "A permanent with Indestructible can't be destroyed by 'destroy' effects or lethal damage. It still dies if its toughness is 0 or less, or if sacrificed or exiled."},
	{"id": "702.15", "section": "702 Keyword Abilities", "title": "Lifelink",
	 "tags": ["lifelink", "life", "damage"],
	 "text": "Damage dealt by a source with Lifelink also causes its controller to gain that much life."},
	{"id": "702.16", "section": "702 Keyword Abilities", "title": "Protection (DEBT)",
	 "tags": ["protection", "debt", "damage", "enchant", "equip", "block", "target"],
	 "text": "Protection from [Quality] prevents: Damage, Enchanting/Equipping, Blocking, and Targeting by anything with that quality (DEBT)."},
	{"id": "702.19", "section": "702 Keyword Abilities", "title": "Trample",
	 "tags": ["trample", "combat", "excess damage", "deathtouch"],
	 "text": "If an attacking creature with Trample would assign enough damage to its blockers to destroy them (or 1 each with Deathtouch), you may assign the rest of its damage to the defending player or planeswalker."},
	{"id": "702.21", "section": "702 Keyword Abilities", "title": "Ward",
	 "tags": ["ward", "trigger", "target", "counter"],
	 "text": "Whenever this permanent becomes the target of a spell or ability an opponent controls, counter it unless that player pays the ward cost. Multiple instances of Ward trigger separately."},
	{"id": "702.41", "section": "702 Keyword Abilities", "title": "Affinity",
	 "tags": ["affinity", "cost reduction", "artifact"],
	 "text": "Affinity for [Quality] reduces the generic mana cost of the spell by {1} for each permanent you control with that quality."},
	{"id": "702.83", "section": "702 Keyword Abilities", "title": "Exalted",
	 "tags": ["exalted", "attack alone", "+1/+1"],
	 "text": "Whenever a creature you control attacks alone, each permanent you control with Exalted gives that creature +1/+1 until end of turn."},
	{"id": "702.86", "section": "702 Keyword Abilities", "title": "Annihilator",
	 "tags": ["annihilator", "attack", "sacrifice"],
	 "text": "Whenever this creature attacks, defending player sacrifices N permanents."},
	{"id": "702.93", "section": "702 Keyword Abilities", "title": "Undying & Persist (702.79)",
	 "tags": ["undying", "persist", "die", "counter"],
	 "text": "Undying: when this creature dies, if it had no +1/+1 counters on it, return it to the battlefield under its owner's control with a +1/+1 counter. Persist: same, with a -1/-1 counter if it had no -1/-1 counters."},
	{"id": "702.108", "section": "702 Keyword Abilities", "title": "Prowess",
	 "tags": ["prowess", "noncreature", "cast", "+1/+1"],
	 "text": "Whenever you cast a noncreature spell, this creature gets +1/+1 until end of turn."},
	{"id": "702.111", "section": "702 Keyword Abilities", "title": "Menace",
	 "tags": ["menace", "block", "two or more"],
	 "text": "A creature with Menace can't be blocked except by two or more creatures."},

	# --- 704: State-Based Actions ---
	{"id": "704.5j", "section": "704 State-Based Actions", "title": "Legend Rule",
	 "tags": ["legend", "legendary", "sba"],
	 "text": "If a player controls two or more legendary permanents with the same name, that player chooses one of them and puts the rest into their owners' graveyards."},
	{"id": "704.5q", "section": "704 State-Based Actions", "title": "+1/+1 and -1/-1 Counter Annihilation",
	 "tags": ["+1/+1", "-1/-1", "counter", "annihilate", "sba"],
	 "text": "If a permanent has both a +1/+1 counter and a -1/-1 counter on it, N +1/+1 and N -1/-1 counters are removed from it, where N is the smaller of the two numbers."},

	# --- 903: Commander ---
	{"id": "903.8", "section": "903 Commander", "title": "Commander Tax",
	 "tags": ["commander", "tax", "command zone", "cost"],
	 "text": "A player may cast a commander they own from the command zone. A commander cast from the command zone costs an additional {2} for each previous time the player cast it from the command zone this game."},
	{"id": "903.9", "section": "903 Commander", "title": "Commander Zone Replacement",
	 "tags": ["commander", "command zone", "graveyard", "exile"],
	 "text": "If a commander would be put into its owner's hand or library from anywhere, or put into a graveyard or exile from anywhere, its owner may put it into the command zone instead."},
	{"id": "903.10a", "section": "903 Commander", "title": "Commander Combat Damage (21)",
	 "tags": ["commander", "commander damage", "21", "combat damage"],
	 "text": "A player who has been dealt 21 or more combat damage by the same commander over the course of the game loses the game as a State-Based Action (704.6c)."}
]

static func lookup(rule_id: String) -> Dictionary:
	var clean_id := rule_id.strip_edges().to_lower()
	for r in RULES:
		if str(r.get("id", "")).to_lower() == clean_id:
			return r
	return {}

static func search(query: String) -> Array[Dictionary]:
	var q := query.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	if q.is_empty():
		for r in RULES: out.append(r)
		return out
	for r in RULES:
		var hay := (str(r.get("id", "")) + " " + str(r.get("section", "")) + " " + str(r.get("title", "")) + " " + str(r.get("text", "")) + " " + " ".join(r.get("tags", []))).to_lower()
		if q in hay:
			out.append(r)
	return out

static func get_card_relevant_rules(card_data: Dictionary, card_node: Node = null) -> Array[Dictionary]:
	var matched_ids: Array[String] = []
	var out: Array[Dictionary] = []
	var tl := str(card_data.get("type_line", "")).to_lower()
	var ot := str(card_data.get("oracle_text", "")).to_lower()
	if card_node != null and is_instance_valid(card_node):
		if "active_face_index" in card_node:
			tl = MagicRules.get_card_type_line(card_data, int(card_node.active_face_index)).to_lower()
			ot = str(MagicRules.get_card_attribute(card_data, "oracle_text", "", int(card_node.active_face_index))).to_lower()
		if card_node.has_meta("is_commander") and bool(card_node.get_meta("is_commander")):
			for cid in ["903.8", "903.9", "903.10a"]:
				if not (cid in matched_ids): matched_ids.append(cid)

	var keyword_to_rule := {
		"deathtouch": "702.2", "defender": "702.3", "flying": "702.9", "reach": "702.9",
		"hexproof": "702.11", "shroud": "702.11", "indestructible": "702.12", "lifelink": "702.15",
		"protection": "702.16", "trample": "702.19", "ward": "702.21", "affinity": "702.41",
		"exalted": "702.83", "annihilator": "702.86", "undying": "702.93", "persist": "702.93",
		"prowess": "702.108", "menace": "702.111", "surveil": "701.25", "proliferate": "701.34",
		"empower jace": "701.71a", "stun": "122.1", "shield": "122.1", "finality": "122.1"
	}
	for kw in keyword_to_rule.keys():
		if kw in ot:
			var rid: String = keyword_to_rule[kw]
			if not (rid in matched_ids): matched_ids.append(rid)

	if "planeswalker" in tl:
		for rid in ["306.5", "606.3"]:
			if not (rid in matched_ids): matched_ids.append(rid)
	if "creature" in tl:
		if not ("302.6" in matched_ids): matched_ids.append("302.6")
	if "land" in tl:
		if not ("305.2" in matched_ids): matched_ids.append("305.2")
	if "legendary" in tl:
		if not ("704.5j" in matched_ids): matched_ids.append("704.5j")
	if "target" in ot:
		if not ("115.10a" in matched_ids): matched_ids.append("115.10a")
		if not ("608.2b" in matched_ids): matched_ids.append("608.2b")
	if "+1/+1 counter" in ot or "-1/-1 counter" in ot:
		if not ("704.5q" in matched_ids): matched_ids.append("704.5q")
	if "becomes a" in ot or "base power and toughness" in ot:
		if not ("613.1" in matched_ids): matched_ids.append("613.1")

	for rid in matched_ids:
		var r := lookup(rid)
		if not r.is_empty(): out.append(r)
	return out

static func explain_cost_breakdown(base_cost: String, tax_generic: int, reduction_generic: int, affinity_generic: int = 0) -> String:
	var parts: Array[String] = ["Base: %s" % (base_cost if not base_cost.is_empty() else "{0}")]
	if tax_generic > 0: parts.append("Tax (CR 903.8): +{%d}" % tax_generic)
	if reduction_generic > 0: parts.append("Reduction (CR 601.2f): -{%d}" % reduction_generic)
	if affinity_generic > 0: parts.append("Affinity (CR 702.41): -{%d}" % affinity_generic)
	return " | ".join(parts)
