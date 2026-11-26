extends SceneTree

# Comprehensive headless test & soak suite for Commander At Home.
# Run from your project directory:
#   godot --headless --path . --script res://test_soak.gd --log-file soak_log.txt

var _failures: Array[String] = []
var _passes: int = 0

var _OracleParser: GDScript
var _AbilityResolver: GDScript
var _MagicRules: GDScript
var _GameSerializer: GDScript
var _TurnManager: GDScript
var _ContinuousEffectsEngine: GDScript
var _ComprehensiveRules: GDScript

func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  [PASS] %s" % label)
	else:
		_failures.append(label)
		printerr("  [FAIL] %s" % label)

func _initialize() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	await process_frame
	print("\n============================================================")
	print("  COMMANDER AT HOME — FULL REGRESSION & SOAK TEST SUITE")
	print("============================================================")

	_OracleParser = load("res://OracleParser.gd")
	_AbilityResolver = load("res://AbilityResolver.gd")
	_MagicRules = load("res://MagicRules.gd")
	_GameSerializer = load("res://GameSerializer.gd")
	_TurnManager = load("res://TurnManager.gd")
	_ContinuousEffectsEngine = load("res://ContinuousEffectsEngine.gd")
	_ComprehensiveRules = load("res://ComprehensiveRules.gd")

	var main_scene := load("res://Main.tscn") as PackedScene
	if main_scene == null:
		printerr("FATAL: Could not load res://Main.tscn")
		quit(1)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var ds := main.get_node_or_null("DeckSelectorUI")
	if ds and is_instance_valid(ds):
		ds.queue_free()
	await process_frame

	_test_oracle_parser_and_cr()
	_test_targeting_costs_and_ward(main)
	_test_triggers_counters_and_mechanics(main)
	_test_combat_and_sbas(main)
	_test_serializer_and_surfaces(main)
	await _test_ai_soak_turns(main, 12)
	await _test_cached_deck_games(main, 3, 10)

	print("\n============================================================")
	print("  SUMMARY: %d PASSED, %d FAILED" % [_passes, _failures.size()])
	if not _failures.is_empty():
		print("  FAILURES:")
		for f in _failures:
			print("    - %s" % f)
	print("============================================================\n")
	quit(0 if _failures.is_empty() else 1)

func _make_card_node(main: Node, data: Dictionary, owner_id: int, on_bf: bool) -> Node3D:
	var c: Node3D = main._instantiate_card()
	c.card_data = data.duplicate(true)
	c.set_meta("owner_id", owner_id)
	main.connect_card_signals(c)
	if on_bf:
		var is_l: bool = _MagicRules.is_land(c.card_data)
		var anc: Node3D = main.player_stations[owner_id]["lands_anchor" if is_l else "non_lands_anchor"]
		anc.add_child(c)
		if c.has_method("make_active"): c.make_active(c.card_data)
		c.is_on_battlefield = true
		if is_l: main.battlefield_lands.append(c)
		else: main.battlefield_non_lands.append(c)
	else:
		main.add_child(c)
	return c

func _reset_board(main: Node) -> void:
	_GameSerializer._clear_all_cards(main)
	main.drawn_from_empty_library = {1: false, 2: false, 3: false, 4: false}
	main.monarch_player_id = 0
	main.initiative_player_id = 0
	main.battlefield_day_night = ""
	main.mulligan_phase_active = false
	main.spells_cast_this_turn = 0
	main.land_played_this_turn = false
	for pid in [1, 2, 3, 4]:
		main.eliminated_players[pid] = false
		main.player_life[pid] = 40
		main.player_counters[pid] = {}
		main.player_statuses[pid] = []
		main.player_dungeons[pid] = {}
		main.player_libraries[pid] = []
		main.player_hands[pid] = []
		main.player_graveyards[pid] = []
		main.player_exile[pid] = []
		main.player_command_zones[pid] = []
	for k in main.mana_pool.keys():
		main.mana_pool[k] = 0
	main.restricted_mana.clear()
	main.local_player_id = 1
	main.turn_manager.turn_number = 1
	main.turn_manager.active_player_id = 1
	main.turn_manager.priority_player_id = 1
	main.turn_manager.current_turn_phase = _TurnManager.TurnPhase.PRECOMBAT_MAIN

func _seed_library(main: Node, pid: int, count: int) -> void:
	for i in range(count):
		var lib_c: Node3D = main._instantiate_card()
		lib_c.card_data = {"name": "Island %d" % i, "type_line": "Basic Land — Island", "oracle_text": "{T}: Add {U}.", "produced_mana": ["U"]}
		lib_c.set_meta("owner_id", pid)
		var anc: Node3D = main.library_anchor if pid == main.local_player_id else main.player_stations[pid]["library"]
		anc.add_child(lib_c)
		lib_c.setup_library()
		if pid == main.local_player_id: main.library_stack.append(lib_c)
		main.player_libraries[pid].append(lib_c)

func _test_oracle_parser_and_cr() -> void:
	print("\n[1/6] Testing OracleParser & ComprehensiveRules...")
	var pw: Dictionary = _OracleParser.parse_oracle_text("−1: Surveil 1.\n−3: Draw a card.\n−X: Deal X damage.")
	_assert_true(pw.get("loyalty_abilities", []).size() == 3, "Planeswalker Unicode minus loyalty abilities parsed (3)")
	var d0: String = str(pw["loyalty_abilities"][0].get("delta_str", ""))
	_assert_true(d0 == "-1", "Unicode minus normalized to ASCII '-1'")

	var mana_abs: Array = _OracleParser.parse_mana_abilities({"oracle_text": "{T}: Add {U} or {B}.", "type_line": "Land"}, null)
	_assert_true(mana_abs.size() == 1 and mana_abs[0].get("colors", []).size() == 2, "Dual-color mana ability parsed")

	var kw_p: Dictionary = _OracleParser.parse_oracle_text("Flying, First strike, Deathtouch, Trample, Vigilance, Lifelink, Menace\nWard {2}\nCrew 3")
	var kws: Array = kw_p.get("keywords", [])
	_assert_true("flying" in kws and "deathtouch" in kws and "trample" in kws and "menace" in kws, "Multi-keyword line parsed")
	_assert_true(str(kw_p.get("ward_cost", "")) == "{2}", "Ward {2} parsed")
	_assert_true(int(kw_p.get("crew_cost", 0)) == 3, "Crew 3 parsed")

	var alt_p: Dictionary = _OracleParser.parse_oracle_text("Flashback {2}{R}\nForetell {1}{U}\nStorm")
	_assert_true(str(alt_p.get("flashback_cost", "")) == "{2}{R}", "Flashback cost parsed")
	_assert_true(str(alt_p.get("foretell_cost", "")) == "{1}{U}", "Foretell cost parsed")
	_assert_true(bool(alt_p.get("has_storm", false)), "Storm parsed")

	var cr_q: Dictionary = _ComprehensiveRules.lookup("704.5q")
	_assert_true(not cr_q.is_empty() and "annihilat" in str(cr_q.get("title", "")).to_lower(), "ComprehensiveRules.lookup('704.5q') works")

func _test_targeting_costs_and_ward(main: Node) -> void:
	print("\n[2/6] Testing Targeting, Protection (DEBT), Affinity & Fizzle...")
	_reset_board(main)

	var red_src := _make_card_node(main, {"name": "Shock", "type_line": "Instant", "colors": ["R"], "oracle_text": "Shock deals 2 damage to any target."}, 1, false)
	var pro_red := _make_card_node(main, {"name": "Silver Knight", "type_line": "Creature — Human Knight", "colors": ["W"], "power": "2", "toughness": "2", "oracle_text": "First strike, protection from red"}, 2, true)
	var hex_c := _make_card_node(main, {"name": "Invisible Stalker", "type_line": "Creature — Human Rogue", "colors": ["U"], "power": "1", "toughness": "1", "oracle_text": "Hexproof"}, 2, true)
	var shroud_c := _make_card_node(main, {"name": "Plaxmanta", "type_line": "Creature — Beast", "colors": ["G", "U"], "power": "2", "toughness": "2", "oracle_text": "Shroud"}, 1, true)

	_assert_true(not _MagicRules.is_legal_target(pro_red, "creature", 1, red_src), "Protection from red blocks red targeting")
	_assert_true(not _MagicRules.is_legal_target(hex_c, "creature", 1, red_src), "Hexproof blocks opponent targeting")
	_assert_true(not _MagicRules.is_legal_target(shroud_c, "creature", 1, red_src), "Shroud blocks controller targeting")

	# Affinity & Cost Reduction
	var art1 := _make_card_node(main, {"name": "Sol Ring", "type_line": "Artifact", "oracle_text": "{T}: Add {C}{C}."}, 1, true)
	var art2 := _make_card_node(main, {"name": "Arcane Signet", "type_line": "Artifact", "oracle_text": "{T}: Add one mana of any color in your commander's color identity."}, 1, true)
	var aff_data := {"name": "Thoughtcast", "type_line": "Sorcery", "mana_cost": "{4}{U}", "oracle_text": "Affinity for artifacts\nDraw two cards."}
	var red_amt: int = _ContinuousEffectsEngine.get_cost_reduction(aff_data, 1, main.battlefield_lands, main.battlefield_non_lands)
	var final_c: String = _ContinuousEffectsEngine.apply_cost_reduction("{4}{U}", red_amt)
	_assert_true(red_amt >= 2 and final_c == "{2}{U}", "Affinity for artifacts reduced {4}{U} to %s" % final_c)

	# Non-combat Protection damage prevention
	_AbilityResolver.execute_effect_text("Deal 3 damage to target creature.", red_src, pro_red, main, 1)
	_assert_true(int(pro_red.marked_damage) == 0, "Protection from red prevented non-combat red damage")

	# Fizzle (CR 608.2b) when target leaves battlefield
	var fizz_tgt := _make_card_node(main, {"name": "Llanowar Elves", "type_line": "Creature — Elf Druid", "power": "1", "toughness": "1"}, 2, true)
	main._finalize_push_ability_to_stack(art1, {"effect_raw": "Destroy target creature.", "target_requirement": "creature"}, "Activated", fizz_tgt)
	main.zone_manager.move_to_graveyard(fizz_tgt)
	main.resolve_top_stack_card()
	_assert_true(main.active_stack.is_empty(), "Ability fizzled cleanly when target became illegal (CR 608.2b)")

func _test_triggers_counters_and_mechanics(main: Node) -> void:
	print("\n[3/6] Testing Triggers, Counters, Empower Jace, Day/Night & Monarch...")
	_reset_board(main)
	_seed_library(main, 1, 10)

	# Chasm Skulker DRAW trigger
	var skulker := _make_card_node(main, {
		"name": "Chasm Skulker", "type_line": "Creature — Squid Horror", "power": "1", "toughness": "1",
		"oracle_text": "Whenever you draw a card, put a +1/+1 counter on Chasm Skulker."
	}, 1, true)
	main.zone_manager.draw_card()
	while not main.active_stack.is_empty(): main.resolve_top_stack_card()
	_assert_true(int(skulker.counter_amount) == 1, "Chasm Skulker gained +1/+1 counter on draw")

	# Prowess on noncreature cast
	var prowess_c := _make_card_node(main, {
		"name": "Monastery Swiftspear", "type_line": "Creature — Human Monk", "power": "1", "toughness": "2",
		"oracle_text": "Haste\nProwess"
	}, 1, true)
	var opt_spell := _make_card_node(main, {"name": "Opt", "type_line": "Instant", "colors": ["U"], "oracle_text": "Scry 1. Draw a card."}, 1, false)
	main.check_and_queue_triggers("CAST", opt_spell)
	main.run_state_based_actions()
	_assert_true(int(prowess_c.dynamic_power) == 2 and int(prowess_c.dynamic_toughness) == 3, "Prowess granted +1/+1 on noncreature spell cast")

	# Energy + Proliferate
	_AbilityResolver.execute_effect_text("You get {E}{E}.", null, null, main, 1)
	_AbilityResolver.execute_effect_text("Proliferate.", null, null, main, 1)
	_assert_true(int(main.player_counters.get(1, {}).get("energy", 0)) == 3, "Energy {E}{E} + Proliferate = 3 energy")
	_assert_true(int(skulker.counter_amount) == 2, "Proliferate incremented +1/+1 counter on Chasm Skulker to 2")

	# Empower Jace 3 -> grows to 4 on second Empower Jace 1
	_AbilityResolver.execute_effect_text("Empower Jace 3.", null, null, main, 1)
	_AbilityResolver.execute_effect_text("Empower Jace 1.", null, null, main, 1)
	var jace_tok: Node3D = null
	for p in main.battlefield_non_lands:
		if is_instance_valid(p) and "jace" in str(p.card_data.get("name", "")).to_lower():
			jace_tok = p; break
	_assert_true(jace_tok != null and jace_tok.get_named_counter("loyalty") == 4, "Empower Jace 3 + Empower Jace 1 = 4 loyalty on single Jace token")
	_assert_true(main._has_activatable_nonmana_ability(jace_tok), "Unused Jace token with 4 loyalty has golden sheen")

	# Undying & Persist & Finality
	var undy := _make_card_node(main, {"name": "Strangleroot Geist", "type_line": "Creature — Spirit", "power": "2", "toughness": "1", "oracle_text": "Haste\nUndying"}, 1, true)
	main.zone_manager.move_to_graveyard(undy)
	_assert_true(undy.is_on_battlefield and int(undy.counter_amount) == 1, "Undying returned creature with +1/+1 counter")
	undy.modify_named_counter("finality", 1)
	main.zone_manager.move_to_graveyard(undy)
	_assert_true(not undy.is_on_battlefield and (undy in main.exile_stack), "Finality counter exiled creature instead of graveyard")

	# Stun, Shield, CR 704.5q
	skulker.toggle_tap()
	skulker.modify_named_counter("stun", 1)
	main.zone_manager.untap_single_card(skulker)
	_assert_true(skulker.is_tapped and skulker.get_named_counter("stun") == 0, "Stun counter prevented untap")

	skulker.modify_named_counter("shield", 1)
	_AbilityResolver.execute_effect_text("Destroy all creatures.", null, null, main, 2)
	_assert_true(skulker.is_on_battlefield and skulker.get_named_counter("shield") == 0, "Shield counter saved creature from Destroy")

	skulker.modify_named_counter("+1/+1", 3)
	skulker.modify_named_counter("-1/-1", 2)
	main.run_state_based_actions()
	_assert_true(skulker.get_named_counter("+1/+1") == 1 and skulker.get_named_counter("-1/-1") == 0, "CR 704.5q annihilated +1/+1 and -1/-1 counters")

	# Monarch, Initiative, Ring, Day/Night
	_AbilityResolver.execute_effect_text("You become the monarch.", null, null, main, 1)
	_AbilityResolver.execute_effect_text("You take the initiative.", null, null, main, 1)
	_AbilityResolver.execute_effect_text("The Ring tempts you.", null, null, main, 1)
	_AbilityResolver.execute_effect_text("It becomes Night.", null, null, main, 1)
	_assert_true(main.monarch_player_id == 1 and main.initiative_player_id == 1 and main.battlefield_day_night == "Night", "Monarch, Initiative, and Night state tracked")

	# "If you do" chain
	while main.hand_cards.size() > 1:
		var ex: Node3D = main.hand_cards.pop_back() as Node3D
		main._on_card_to_graveyard(ex)
	_AbilityResolver.execute_effect_text("Discard a card. If you do, draw a card.", null, null, main, 1)
	_assert_true(main.hand_cards.size() == 1, "'If you do' discard-to-draw drew replacement card")

func _test_combat_and_sbas(main: Node) -> void:
	print("\n[4/6] Testing Combat Keywords, Evasion, Animated Lands & SBAs...")
	_reset_board(main)

	# 1. Deathtouch + Trample + Lifelink + Exalted + Menace + Flying + Skulk + Fear
	var dt_trample := _make_card_node(main, {
		"name": "Questing Beast", "type_line": "Creature — Beast", "colors": ["G"], "power": "4", "toughness": "4",
		"oracle_text": "Deathtouch\nTrample\nLifelink"
	}, 1, true)
	dt_trample.has_summoning_sickness = false
	var blk := _make_card_node(main, {"name": "Big Wall", "type_line": "Creature — Treefolk", "colors": ["G"], "power": "0", "toughness": "8"}, 2, true)
	dt_trample.set("is_attacking", true)
	dt_trample.set("attacking_target_player_id", 2)
	blk.set("is_blocking", true)
	blk.set("blocking_target_creature", dt_trample)
	main.combat_manager._resolve_combat_damage()
	_assert_true(int(main.player_life[2]) == 37, "Deathtouch + Trample dealt 1 to 0/8 blocker and 3 trample to P2 (life=37)")
	_assert_true(int(main.player_life[1]) == 44, "Lifelink gained 4 life for P1 (life=44)")
	_assert_true(not blk.is_on_battlefield, "Deathtouch 1 damage killed 0/8 blocker via SBA")

	# 2. First Strike kills blocker before normal damage
	var fs_atk := _make_card_node(main, {"name": "White Knight", "type_line": "Creature — Human Knight", "colors": ["W"], "power": "3", "toughness": "1", "oracle_text": "First strike"}, 1, true)
	var norm_blk := _make_card_node(main, {"name": "Hill Giant", "type_line": "Creature — Giant", "colors": ["R"], "power": "3", "toughness": "3"}, 2, true)
	fs_atk.set("is_attacking", true); fs_atk.set("attacking_target_player_id", 2)
	norm_blk.set("is_blocking", true); norm_blk.set("blocking_target_creature", fs_atk)
	main.combat_manager._resolve_combat_damage()
	_assert_true(fs_atk.is_on_battlefield and not norm_blk.is_on_battlefield, "First Strike killed 3/3 blocker before taking 3 normal damage")

	# 3. Animated Land + Cleanup + Equipment auto-detach (CR 704.5n)
	var tar_pit := _make_card_node(main, {
		"name": "Creeping Tar Pit", "type_line": "Land",
		"oracle_text": "Creeping Tar Pit becomes a 3/2 blue and black Elemental creature until end of turn. It's still a land."
	}, 1, true)
	_AbilityResolver.execute_effect_text("Creeping Tar Pit becomes a 3/2 blue and black Elemental creature until end of turn.", tar_pit, null, main, 1)
	_assert_true(_MagicRules.is_creature(tar_pit.card_data, 0, tar_pit) and int(tar_pit.dynamic_power) == 3, "Animated land is 3/2 Creature")
	var eq := _make_card_node(main, {"name": "Test Sword", "type_line": "Artifact — Equipment", "oracle_text": "Equipped creature gets +1/+1.\nEquip {1}"}, 1, true)
	main.zone_manager.attach_card_to_creature(eq, tar_pit, false)
	tar_pit.toggle_tap()
	_assert_true(tar_pit.is_tapped and not eq.is_tapped, "Attached Equipment stays untapped when host taps")

	# Step through END -> CLEANUP to verify EOT cleanup & CR 704.5n Equipment detach
	main.turn_manager.current_turn_phase = _TurnManager.TurnPhase.END
	main.turn_manager._step_single_phase()
	main.run_state_based_actions()
	_assert_true(not _MagicRules.is_creature(tar_pit.card_data, 0, tar_pit), "Animated land reverted to non-creature at Cleanup")
	_assert_true(eq.get("attached_to") == null, "CR 704.5n detached Equipment when animated land stopped being a creature")

	# 4. Defender cannot attack, Menace requires 2+ blockers, Infect gives poison, Legend rule, 0-defense Battle
	var wall := _make_card_node(main, {"name": "Wall of Omens", "type_line": "Creature — Wall", "power": "0", "toughness": "4", "oracle_text": "Defender"}, 1, true)
	wall.has_summoning_sickness = false
	main.combat_manager.handle_declare_attacker_key(wall, false)
	_assert_true(not bool(wall.get("is_attacking")), "Defender blocked from attacking (CR 702.3)")

	var inf_c := _make_card_node(main, {"name": "Glistener Elf", "type_line": "Creature — Elf", "power": "10", "toughness": "1", "oracle_text": "Infect"}, 1, true)
	inf_c.set("is_attacking", true); inf_c.set("attacking_target_player_id", 3)
	main.combat_manager._resolve_combat_damage()
	_assert_true(int(main.player_counters.get(3, {}).get("poison", 0)) == 10 and main.is_player_eliminated(3), "10 Infect damage eliminated P3 via Poison SBA (CR 704.5c)")

	# Mill opponent & verify milling an empty library does NOT eliminate (only drawing does)
	_seed_library(main, 2, 2)
	_AbilityResolver.execute_effect_text("Target opponent mills 3 cards.", null, 2, main, 1)
	_assert_true(main.player_libraries[2].is_empty() and not main.is_player_eliminated(2), "Opponent milled 2 cards; milling empty library did not eliminate P2")

	# Empty library draw SBA (CR 704.5b)
	main.local_player_id = 1
	main.library_stack.clear()
	main.zone_manager.draw_card()
	_assert_true(main.is_player_eliminated(1), "Drawing from empty library eliminated player via CR 704.5b")

func _test_serializer_and_surfaces(main: Node) -> void:
	print("\n[5/6] Testing GameSerializer Full Fidelity & All 14 Table Surfaces...")
	_reset_board(main)
	var host := _make_card_node(main, {"name": "Commander Test", "type_line": "Legendary Creature — Wizard", "power": "3", "toughness": "3"}, 1, true)
	host.set_meta("is_commander", true)
	var eq := _make_card_node(main, {"name": "Swiftfoot Boots", "type_line": "Artifact — Equipment", "oracle_text": "Equipped creature has hexproof and haste.\nEquip {1}"}, 1, true)
	main.zone_manager.attach_card_to_creature(eq, host, false)
	main.modify_player_counter(1, "energy", 5)
	main.set_monarch(1)

	var snap: Dictionary = _GameSerializer.serialize_state(main)
	_GameSerializer.restore_state(main, snap)
	var found_att := false
	for c in main.battlefield_non_lands:
		if is_instance_valid(c) and "attachments" in c and not c.attachments.is_empty():
			found_att = true; break
	_assert_true(found_att and int(main.player_counters.get(1, {}).get("energy", 0)) == 5 and main.monarch_player_id == 1, "GameSerializer preserved attachments, energy counters, and Monarch")

	var all_surf_ok := true
	var tbl: MeshInstance3D = main.get_node_or_null("tableSurface")
	for s_id in main.TABLE_SURFACES:
		main.apply_playmat_theme(str(s_id))
		if tbl and tbl.get_surface_override_material(0) == null:
			all_surf_ok = false
	_assert_true(all_surf_ok and main.TABLE_SURFACES.size() == 14, "All 14 table surfaces generated valid PBR materials")

func _test_ai_soak_turns(main: Node, target_turns: int) -> void:
	print("\n[6/6] Running %d-Turn Multi-Mechanic 4-AI Commander Soak..." % target_turns)
	_reset_board(main)
	var card_pool := [
		{"name": "Forest", "type_line": "Basic Land — Forest", "oracle_text": "{T}: Add {G}.", "produced_mana": ["G"]},
		{"name": "Island", "type_line": "Basic Land — Island", "oracle_text": "{T}: Add {U}.", "produced_mana": ["U"]},
		{"name": "Grizzly Bears", "type_line": "Creature — Bear", "mana_cost": "{1}{G}", "cmc": 2, "power": "2", "toughness": "2", "oracle_text": ""},
		{"name": "Phantom Warrior", "type_line": "Creature — Illusion Warrior", "mana_cost": "{1}{U}{U}", "cmc": 3, "power": "2", "toughness": "2", "oracle_text": "Phantom Warrior can't be blocked."},
		{"name": "Divination", "type_line": "Sorcery", "mana_cost": "{2}{U}", "cmc": 3, "oracle_text": "Draw two cards."},
		{"name": "Aether Hub", "type_line": "Land", "oracle_text": "When Aether Hub enters the battlefield, you get {E}.\n{T}: Add {C}."}
	]
	for pid in [1, 2, 3, 4]:
		for idx in range(36):
			var c: Node3D = main._instantiate_card()
			c.card_data = card_pool[idx % card_pool.size()].duplicate(true)
			c.set_meta("owner_id", pid)
			main.connect_card_signals(c)
			var anc: Node3D = main.library_anchor if pid == 1 else main.player_stations[pid]["library"]
			anc.add_child(c)
			c.setup_library()
			if pid == 1: main.library_stack.append(c)
			main.player_libraries[pid].append(c)
		for _h in range(7):
			if pid == 1: main.zone_manager.draw_card()
			else: main.zone_manager.draw_opponent_card(pid)

	main.local_player_id = 99
	main.starting_player_id = 1
	main.mulligan_phase_active = false
	main.turn_manager.set_starting_player(1)
	main.turn_manager.advance_turn_phase(false)

	var guard := 0
	var max_steps := target_turns * 150
	while main.turn_manager.turn_number <= target_turns and guard < max_steps:
		guard += 1
		var p_id: int = main.turn_manager.priority_player_id
		if main.ai_controller and main.ai_controller.should_ai_act_on_priority(p_id):
			main.ai_controller._execute_ai_step(p_id)
		else:
			main.turn_manager.pass_priority(true)
		if guard % 15 == 0:
			await process_frame

	_assert_true(main.turn_manager.turn_number > target_turns, "Completed %d full 4-AI turns without stalling (Turn %d in %d steps)" % [target_turns, main.turn_manager.turn_number, guard])
	main.local_player_id = 1


func _test_cached_deck_games(main: Node, num_games: int, turns_per_game: int) -> void:
	print("\n[7/7] Emulating %d Full Games Using Random Cached Decks (%d turns each)..." % [num_games, turns_per_game])
	var cache: Dictionary = main.deck_loader._load_deck_cache()
	var keys: Array = cache.keys()
	if keys.is_empty():
		print("  [SKIP] No cached decks found in user://deck_cache.json — import decks in-game first.")
		return

	print("  Found %d cached deck(s) in deck library." % keys.size())
	for g_idx in range(num_games):
		_reset_board(main)
		var picked := {}
		var shuffled_keys := keys.duplicate()
		shuffled_keys.shuffle()
		var deck_names: Array[String] = []
		for pid in [1, 2, 3, 4]:
			var dk = shuffled_keys[(pid - 1) % shuffled_keys.size()]
			picked[pid] = dk
			deck_names.append("P%d=%s" % [pid, str(cache[dk].get("deckName", str(dk)))])
		print("  Game %d/%d: %s" % [g_idx + 1, num_games, " | ".join(deck_names)])

		main.local_player_id = 99
		main.deck_loader.load_and_spawn_all_decks(picked)

		var wait_frames := 0
		while main.deck_loader._pending_deck_loads > 0 and wait_frames < 1800:
			wait_frames += 1
			await process_frame

		if main.deck_loader._pending_deck_loads > 0:
			_assert_true(false, "Game %d deck loading timed out" % (g_idx + 1))
			continue

		# Dismiss any interactive UI opened by deck load and start Turn 1 under 4-AI control
		for ui_name in ["FirstPlayerChoiceUI", "MulliganUI", "DiceRollBannerUI"]:
			var ui_n := main.get_node_or_null(ui_name)
			if ui_n and is_instance_valid(ui_n): ui_n.queue_free()
		main.mulligan_phase_active = false
		main.starting_player_id = 1
		main.turn_manager.set_starting_player(1)
		main.turn_manager.advance_turn_phase(false)

		var guard := 0
		var max_steps := turns_per_game * 160
		while main.turn_manager.turn_number <= turns_per_game and guard < max_steps:
			guard += 1
			var p_id: int = main.turn_manager.priority_player_id
			if main.ai_controller and main.ai_controller.should_ai_act_on_priority(p_id):
				main.ai_controller._execute_ai_step(p_id)
			else:
				main.turn_manager.pass_priority(true)
			if guard % 15 == 0:
				await process_frame

		if main.turn_manager.turn_number <= turns_per_game:
			var top_nm: String = str(main.active_stack[-1].name) if not main.active_stack.is_empty() else "Empty"
			print("    [STALL DIAG] Turn=%d Phase=%d ActiveP=%d PrioP=%d Stack=%d Top=%s" % [main.turn_manager.turn_number, main.turn_manager.current_turn_phase, main.turn_manager.active_player_id, main.turn_manager.priority_player_id, main.active_stack.size(), top_nm])
		_assert_true(main.turn_manager.turn_number > turns_per_game, "Cached-deck Game %d completed %d turns cleanly (Turn %d in %d steps)" % [g_idx + 1, turns_per_game, main.turn_manager.turn_number, guard])
	main.local_player_id = 1
