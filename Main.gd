extends Node3D

const CARD_SCENE_PRELOAD = preload("res://Card3D.tscn")
@export var CardScene: PackedScene = CARD_SCENE_PRELOAD

const BELEREN_FONT = preload("res://Beleren.ttf")
const UI_BACKGROUND = Color(0.1, 0.1, 0.13, 0.9)
const UI_BORDER = Color(0.85, 0.7, 0.35, 0.8)

static var MANA_SYMBOL_REGEX: RegEx
static var MANA_COST_REGEX: RegEx
static var EQUIP_COST_REGEX: RegEx

@export_category("Hand Settings")
@export var hand_start_x: float = -2.0
@export var hand_y: float = -1.0
@export var hand_z: float = 6.0
@export var card_spacing_x: float = 0.8
@export var max_hand_width: float = 1.8

@export_category("Library Settings")
@export var library_x: float = -3.0
@export var library_y: float = 0.01
@export var library_z: float = 4.0
@export var card_thickness: float = 0.003

@export_category("Graveyard Settings")
@export var graveyard_x: float = -3.0
@export var graveyard_y: float = 0.01
@export var graveyard_z: float = 5.2

@export_category("Command Zone Settings")
@export var command_zone_x: float = -3.0
@export var command_zone_y: float = 0.01
@export var command_zone_z: float = 2.8

@export_category("Exile Settings")
@export var exile_x: float = -4.2
@export var exile_y: float = 0.01
@export var exile_z: float = 5.2

@export_category("Battlefield Lands Settings")
@export var battlefield_lands_start_x: float = -1.5
@export var battlefield_lands_y: float = 0.01
@export var battlefield_lands_z: float = 5.2
@export var battlefield_lands_spacing_x: float = 0.7

@export_category("Battlefield Non-Lands Settings")
@export var battlefield_non_lands_start_x: float = -1.5
@export var battlefield_non_lands_y: float = 0.01
@export var battlefield_non_lands_z: float = 4.0
@export var battlefield_non_lands_spacing_x: float = 0.7
@export var max_battlefield_width: float = 5.6
@export var max_stack_group_size: int = 5

const MANA_ICONS = {
	"W": "res://white.png",
	"U": "res://blue.png",
	"B": "res://black.png",
	"R": "res://red.png",
	"G": "res://green.png",
	"C": "res://colorless.png"
}

const COMMON_TOKENS = [
	{"name": "Treasure", "type_line": "Token Artifact — Treasure", "oracle_text": "{T}, Sacrifice this artifact: Add one mana of any color.", "query": "!" + "\"Treasure\" t:token -is:dfc"},
	{"name": "Clue", "type_line": "Token Artifact — Clue", "oracle_text": "{2}, Sacrifice this artifact: Draw a card.", "query": "!" + "\"Clue\" t:token -is:dfc"},
	{"name": "Food", "type_line": "Token Artifact — Food", "oracle_text": "{2}, {T}, Sacrifice this artifact: You gain 3 life.", "query": "!" + "\"Food\" t:token -is:dfc"},
	{"name": "Blood", "type_line": "Token Artifact — Blood", "oracle_text": "{1}, {T}, Discard a card, Sacrifice this artifact: Draw a card.", "query": "!" + "\"Blood\" t:token -is:dfc"},
	{"name": "Map", "type_line": "Token Artifact — Map", "oracle_text": "{1}, {T}, Sacrifice this artifact: Target creature you control explores.", "query": "!" + "\"Map\" t:token -is:dfc"},
	{"name": "Powerstone", "type_line": "Token Artifact — Powerstone", "oracle_text": "{T}: Add {C}. This mana can't be spent to cast a nonartifact spell.", "query": "!" + "\"Powerstone\" t:token -is:dfc"},
	{"name": "1/1 Soldier", "type_line": "Token Creature — Soldier", "power": "1", "toughness": "1", "oracle_text": "", "query": "t:soldier t:token pow=1 tou=1"},
	{"name": "1/1 Spirit", "type_line": "Token Creature — Spirit", "power": "1", "toughness": "1", "oracle_text": "Flying", "query": "t:spirit t:token pow=1 tou=1 o:flying"},
	{"name": "1/1 Goblin", "type_line": "Token Creature — Goblin", "power": "1", "toughness": "1", "oracle_text": "", "query": "t:goblin t:token pow=1 tou=1"},
	{"name": "2/2 Zombie", "type_line": "Token Creature — Zombie", "power": "2", "toughness": "2", "oracle_text": "", "query": "t:zombie t:token pow=2 tou=2"},
	{"name": "1/1 Saproling", "type_line": "Token Creature — Saproling", "power": "1", "toughness": "1", "oracle_text": "", "query": "t:saproling t:token pow=1 tou=1"},
	{"name": "1/1 Thopter", "type_line": "Token Artifact Creature — Thopter", "power": "1", "toughness": "1", "oracle_text": "Flying", "query": "t:thopter t:token pow=1 tou=1 o:flying"},
	{"name": "1/1 Servo", "type_line": "Token Artifact Creature — Servo", "power": "1", "toughness": "1", "oracle_text": "", "query": "t:servo t:token pow=1 tou=1"},
	{"name": "3/3 Beast", "type_line": "Token Creature — Beast", "power": "3", "toughness": "3", "oracle_text": "", "query": "t:beast t:token pow=3 tou=3"},
	{"name": "4/4 Angel", "type_line": "Token Creature — Angel", "power": "4", "toughness": "4", "oracle_text": "Flying, vigilance", "query": "t:angel t:token pow=4 tou=4 o:flying"},
	{"name": "4/4 Dragon", "type_line": "Token Creature — Dragon", "power": "4", "toughness": "4", "oracle_text": "Flying", "query": "t:dragon t:token pow=4 tou=4 o:flying"}
]

# Modular Managers
var event_ledger: GameEventLedger
var turn_manager: TurnManager
var combat_manager: CombatManager
var hud_manager: HUDManager
var zone_manager: ZoneManager
var deck_loader: DeckLoader
var ai_controller: AIController
var sound_manager: SoundManager

# Engine State
var local_player_id: int = 1
var starting_player_id: int = 1
var player_life: Dictionary = {1: 40, 2: 40, 3: 40, 4: 40}
var player_display_names: Dictionary = {1: "Player 1", 2: "Player 2", 3: "Player 3", 4: "Player 4"}
var player_sleeves: Dictionary = {1: "", 2: "", 3: "", 4: ""}
var player_sleeve_textures: Dictionary = {}
const SLEEVES_SAVE_PATH = "user://player_sleeves.json"
var commander_damage: Dictionary = {1: {}, 2: {}, 3: {}, 4: {}}
var mana_pool: Dictionary = {"W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0}
var restricted_mana: Array[Dictionary] = []
var land_played_this_turn: bool = false
var mulligan_phase_active: bool = false
var mulligan_count: int = 0
var mulligan_bottom_remaining: int = 0
var hovered_card: Node3D = null
var _last_upkeep_trigger_key: String = ""
var _legend_rule_pending: bool = false
var eliminated_players: Dictionary = {}
var game_over_shown: bool = false
var player_counters: Dictionary = {1: {}, 2: {}, 3: {}, 4: {}}
var player_statuses: Dictionary = {1: [], 2: [], 3: [], 4: []}
var monarch_player_id: int = 0
var initiative_player_id: int = 0
var battlefield_day_night: String = ""
var player_dungeons: Dictionary = {1: {}, 2: {}, 3: {}, 4: {}}
@export var controller_cursor_speed: float = 950.0
var _popup_nav_cooldown: float = 0.0
var targeting_arcs_mesh: ImmediateMesh = null
var targeting_arcs_instance: MeshInstance3D = null

@onready var hand_container: Node3D = $Camera3D/HandContainer

var hand_cards: Array[Node3D] = []
var library_stack: Array[Node3D] = []
var graveyard_stack: Array[Node3D] = []
var exile_stack: Array[Node3D] = []
var battlefield_lands: Array[Node3D] = []
var battlefield_non_lands: Array[Node3D] = []
var command_zone_cards: Array[Node3D] = []
var commander_cast_counts: Dictionary = {}
var active_stack: Array = []

var central_stack_anchor: Node3D
var exile_anchor: Node3D
var library_anchor: Node3D
var graveyard_anchor: Node3D
var command_zone_anchor: Node3D

var stack_count_label: Label3D
var library_count_label: Label3D
var graveyard_count_label: Label3D
var commander_count_label: Label3D
var exile_count_label: Label3D

var player_stations: Dictionary = {}
var player_libraries: Dictionary = {}
var player_graveyards: Dictionary = {}
var player_exile: Dictionary = {}
var player_hands: Dictionary = {}
var player_command_zones: Dictionary = {}
var player_battlefield_lands: Dictionary = {}
var player_battlefield_non_lands: Dictionary = {}
var player_hand_containers: Dictionary = {}
var player_cameras: Dictionary = {}
var player_zone_labels: Dictionary = {}
var command_info_stations: Dictionary = {}

class StackObject extends RefCounted:
	var name: String = ""
	var effect_text: String = ""
	var source_card: Node3D = null
	var controller_id: int = 1
	var target_ref = null
	var target_requirement: String = "" 

func _ready() -> void:
	_initialize_regex_cache()

	event_ledger = GameEventLedger.new(); add_child(event_ledger)
	turn_manager = TurnManager.new(); add_child(turn_manager); turn_manager.setup(self)
	combat_manager = CombatManager.new(); add_child(combat_manager); combat_manager.setup(self)
	zone_manager = ZoneManager.new(); add_child(zone_manager); zone_manager.setup(self)
	hud_manager = HUDManager.new(); add_child(hud_manager); hud_manager.setup(self)
	deck_loader = DeckLoader.new(); add_child(deck_loader); deck_loader.setup(self)
	ai_controller = AIController.new(); add_child(ai_controller); ai_controller.setup(self)
	sound_manager = SoundManager.new(); add_child(sound_manager)

	setup_tabletop_layout()
	var table_mesh: MeshInstance3D = $tableSurface
	if table_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("res://tableSurface.jpg")
		mat.roughness = 0.6
		table_mesh.set_surface_override_material(0, mat)

	_load_player_sleeves()
	_setup_zone_anchors()
	_setup_targeting_arcs()
	EventBus.phase_changed.connect(_on_phase_changed_triggers)
	EventBus.combat_declared.connect(_on_combat_declared_triggers)
	EventBus.blocker_declared.connect(_on_blocker_declared_triggers)
	EventBus.damage_dealt.connect(_on_damage_dealt_triggers)
	EventBus.life_total_changed.connect(func(_p, _n, _a): refresh_command_info_stations())
	EventBus.damage_dealt.connect(func(_s, _t, _a): refresh_command_info_stations())
	deck_loader.show_deck_selector_ui()

static func _initialize_regex_cache() -> void:
	if MANA_SYMBOL_REGEX == null:
		MANA_SYMBOL_REGEX = RegEx.new()
		MANA_SYMBOL_REGEX.compile("\\{([WUBRG2C])\\}")
	if MANA_COST_REGEX == null:
		MANA_COST_REGEX = RegEx.new()
		MANA_COST_REGEX.compile("\\{([^\\}]+)\\}")
	if EQUIP_COST_REGEX == null:
		EQUIP_COST_REGEX = RegEx.new()
		EQUIP_COST_REGEX.compile("Equip\\s*(\\{[^\\}]+\\}+)")

func _instantiate_card() -> Node3D:
	var scene_to_spawn: PackedScene = CardScene if CardScene != null else CARD_SCENE_PRELOAD
	return scene_to_spawn.instantiate()

func reset_game_and_reselect_decks() -> void:
	if hud_manager:
		hud_manager.hide_mulligan_ui()
		hud_manager.hide_card_preview()
	get_tree().reload_current_scene()

func is_player_eliminated(pid: int) -> bool:
	return bool(eliminated_players.get(pid, false))

func _eliminate_player(pid: int) -> void:
	eliminated_players[pid] = true
	player_life[pid] = mini(0, int(player_life.get(pid, 0)))
	for perm in (battlefield_lands + battlefield_non_lands).duplicate():
		if is_instance_valid(perm) and get_card_owner_id(perm) == pid:
			zone_manager.remove_from_battlefield(perm)
			perm.visible = false
	for s_item in active_stack.duplicate():
		if s_item is Node3D and is_instance_valid(s_item) and get_card_owner_id(s_item) == pid:
			active_stack.erase(s_item)
			s_item.visible = false
		elif not (s_item is Node3D) and int(s_item.controller_id) == pid:
			active_stack.erase(s_item)
	zone_manager.update_battlefield_positions(true)
	refresh_command_info_stations()
	EventBus.notify_stack(active_stack.size())

	var alive: Array[int] = []
	for p in [1, 2, 3, 4]:
		if not is_player_eliminated(p): alive.append(p)
	if alive.size() <= 1 and not game_over_shown:
		game_over_shown = true
		var winner_pid: int = alive[0] if not alive.is_empty() else -1
		hud_manager.show_game_over_banner(winner_pid)

func modify_player_counter(pid: int, counter_name: String, delta: int) -> void:
	var key := counter_name.strip_edges().to_lower()
	if not player_counters.has(pid): player_counters[pid] = {}
	var next_val: int = maxi(0, int(player_counters[pid].get(key, 0)) + delta)
	if next_val == 0: player_counters[pid].erase(key)
	else: player_counters[pid][key] = next_val
	refresh_command_info_stations()
	run_state_based_actions()

func toggle_player_status(pid: int, status_name: String) -> void:
	if not player_statuses.has(pid): player_statuses[pid] = []
	var arr: Array = player_statuses[pid]
	if status_name in arr: arr.erase(status_name)
	else: arr.append(status_name)
	refresh_command_info_stations()
	if hud_manager: hud_manager.update_phase_ui()

func set_monarch(pid: int) -> void:
	monarch_player_id = pid
	refresh_command_info_stations()
	if hud_manager: hud_manager.update_phase_ui()

func set_initiative(pid: int) -> void:
	initiative_player_id = pid
	refresh_command_info_stations()
	if hud_manager: hud_manager.update_phase_ui()

func set_day_night(state_str: String) -> void:
	battlefield_day_night = state_str
	if hud_manager: hud_manager.update_phase_ui()

func set_player_dungeon(pid: int, dungeon_name: String, room_num: int) -> void:
	if dungeon_name.is_empty():
		player_dungeons[pid] = {}
	else:
		player_dungeons[pid] = {"name": dungeon_name, "room": room_num}
	refresh_command_info_stations()

func get_player_display_name(pid: int) -> String:
	return str(player_display_names.get(pid, "Player %d" % pid))

func _load_player_sleeves() -> void:
	if not FileAccess.file_exists(SLEEVES_SAVE_PATH): return
	var f := FileAccess.open(SLEEVES_SAVE_PATH, FileAccess.READ)
	if not f: return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.get_data() is Dictionary:
		var d: Dictionary = json.get_data()
		for k in d.keys():
			var pid := int(k)
			var p := str(d[k])
			if not p.is_empty() and FileAccess.file_exists(p):
				set_player_sleeve(pid, p, false)

func _save_player_sleeves() -> void:
	var f := FileAccess.open(SLEEVES_SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(player_sleeves))

func get_player_sleeve_texture(pid: int) -> Texture2D:
	return player_sleeve_textures.get(pid, null)

func set_player_sleeve(pid: int, file_path: String, save_to_disk: bool = true) -> Texture2D:
	var tex: Texture2D = null
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		player_sleeves[pid] = ""
		player_sleeve_textures.erase(pid)
	else:
		var img := Image.load_from_file(file_path)
		if img and not img.is_empty():
			# Cap very large images while keeping stretchable UV aspect
			if img.get_width() > 1024 or img.get_height() > 1024:
				img.resize(mini(img.get_width(), 1024), mini(img.get_height(), 1024), Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
			player_sleeves[pid] = file_path
			player_sleeve_textures[pid] = tex
		else:
			player_sleeves[pid] = ""
			player_sleeve_textures.erase(pid)
	if save_to_disk:
		_save_player_sleeves()
	return tex

func get_card_owner_id(card_node: Node3D) -> int:
	if card_node and card_node.has_meta("owner_id"):
		return int(card_node.get_meta("owner_id"))
	return 1

func get_card_controller_id(card_node: Node3D) -> int:
	if not card_node or not is_instance_valid(card_node): return 1
	if card_node.is_on_battlefield:
		if card_node.has_meta("control_override_player_id"):
			return int(card_node.get_meta("control_override_player_id"))
		if "layer_controller_id" in card_node and int(card_node.layer_controller_id) > 0:
			return int(card_node.layer_controller_id)
	return get_card_owner_id(card_node)


func _setup_targeting_arcs() -> void:
	targeting_arcs_mesh = ImmediateMesh.new()
	targeting_arcs_instance = MeshInstance3D.new()
	targeting_arcs_instance.name = "TargetingArcs3D"
	targeting_arcs_instance.mesh = targeting_arcs_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	targeting_arcs_instance.material_override = mat
	add_child(targeting_arcs_instance)

func _process(delta: float) -> void:
	_update_controller_cursor(delta)
	_update_targeting_arcs()

func _update_targeting_arcs() -> void:
	if not targeting_arcs_mesh: return
	targeting_arcs_mesh.clear_surfaces()

	var arcs: Array = []

	# 1. Stack Spells & Abilities -> Targets
	for item in active_stack:
		var src_node: Node3D = null
		var tgt_val: Variant = null
		if item is Node3D and is_instance_valid(item):
			src_node = item
			if item.has_meta("chosen_target"): tgt_val = item.get_meta("chosen_target")
		else:
			src_node = item.source_card if is_instance_valid(item.source_card) else null
			tgt_val = item.target_ref

		if src_node and is_instance_valid(src_node) and tgt_val != null:
			var end_pos: Variant = _resolve_target_world_pos(tgt_val)
			if end_pos is Vector3:
				arcs.append({"start": src_node.global_position, "end": end_pos, "color": Color(0.3, 0.88, 1.0, 0.95), "height": 0.9})

	# 2. Attacking & Blocking Creatures -> Combat Targets
	for card in battlefield_non_lands:
		if not is_instance_valid(card) or not card.is_on_battlefield: continue
		if bool(card.get("is_attacking")):
			var pid: int = int(card.get("attacking_target_player_id"))
			var end_pos: Variant = _resolve_target_world_pos(pid)
			if end_pos is Vector3:
				arcs.append({"start": card.global_position, "end": end_pos, "color": Color(1.0, 0.28, 0.25, 0.9), "height": 0.75})
		if bool(card.get("is_blocking")) and card.get("blocking_target_creature") != null:
			var atk: Node3D = card.get("blocking_target_creature")
			if is_instance_valid(atk):
				arcs.append({"start": card.global_position, "end": atk.global_position, "color": Color(0.35, 0.65, 1.0, 0.9), "height": 0.55})

	if arcs.is_empty(): return

	targeting_arcs_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 18
	const HALF_WIDTH := 0.042
	for arc in arcs:
		var p0: Vector3 = arc["start"] + Vector3(0.0, 0.05, 0.0)
		var p1: Vector3 = arc["end"] + Vector3(0.0, 0.05, 0.0)
		var col: Color = arc["color"]
		var h: float = arc["height"]
		for s in range(SEGMENTS):
			var t0 := float(s) / float(SEGMENTS)
			var t1 := float(s + 1) / float(SEGMENTS)
			var a := p0.lerp(p1, t0) + Vector3(0.0, sin(t0 * PI) * h, 0.0)
			var b := p0.lerp(p1, t1) + Vector3(0.0, sin(t1 * PI) * h, 0.0)
			var dir := (b - a)
			if dir.length_squared() < 0.00001: continue
			var side := dir.normalized().cross(Vector3.UP)
			if side.length_squared() < 0.001: side = Vector3.RIGHT
			side = side.normalized() * HALF_WIDTH
			var a0 := a - side
			var a1 := a + side
			var b0 := b - side
			var b1 := b + side
			for v in [a0, a1, b0, a1, b1, b0]:
				targeting_arcs_mesh.surface_set_color(col)
				targeting_arcs_mesh.surface_add_vertex(v)
	targeting_arcs_mesh.surface_end()

func _resolve_target_world_pos(target_val: Variant) -> Variant:
	if target_val is Node3D and is_instance_valid(target_val):
		return target_val.global_position
	elif target_val is int:
		var pid: int = int(target_val)
		if command_info_stations.has(pid):
			var cis_root: Node3D = command_info_stations[pid].get("root", null)
			if is_instance_valid(cis_root): return cis_root.global_position
		if player_stations.has(pid):
			var st: Node3D = player_stations[pid].get("non_lands_anchor", player_stations[pid].get("station", null))
			if is_instance_valid(st): return st.global_position
	return null

func counter_stack_item(index: int) -> void:
	if index < 0 or index >= active_stack.size(): return
	var item = active_stack[index]
	active_stack.remove_at(index)
	EventBus.notify_stack(active_stack.size())

	if item is Node3D and is_instance_valid(item):
		if item.has_method("set_highlight"): item.set_highlight(false)
		if item.has_meta("chosen_target"): item.remove_meta("chosen_target")
		zone_manager.move_to_graveyard(item)
	else:
		zone_manager.update_zone_counters()
	run_state_based_actions()

func _setup_zone_anchors() -> void:
	library_anchor = _create_anchor("LibraryAnchor", Vector3(library_x, library_y, library_z))
	graveyard_anchor = _create_anchor("GraveyardAnchor", Vector3(graveyard_x, graveyard_y, graveyard_z))
	command_zone_anchor = _create_anchor("CommandZoneAnchor", Vector3(command_zone_x, command_zone_y, command_zone_z))
	exile_anchor = _create_anchor("ExileAnchor", Vector3(exile_x, exile_y, exile_z))

	library_count_label = _create_3d_label("LibraryCountLabel", library_anchor, Color(1, 0.9, 0.6, 1))
	graveyard_count_label = _create_3d_label("GraveyardCountLabel", graveyard_anchor, Color(1, 1, 1, 1))
	commander_count_label = _create_3d_label("CommanderTaxCountLabel", command_zone_anchor, Color(1, 0.85, 0.4, 1))
	exile_count_label = _create_3d_label("ExileCountLabel", exile_anchor, Color(0.7, 0.7, 0.8, 1))
	_create_zone_click_area(graveyard_anchor, local_player_id, "graveyard")
	_create_zone_click_area(exile_anchor, local_player_id, "exile")
	stack_count_label = _create_3d_label("StackCountLabel", central_stack_anchor, Color(0.9, 0.4, 0.4, 1), Vector3(-1.0, 0.4, 0.0))


func _create_zone_click_area(anchor: Node3D, pid: int, zone_kind: String) -> void:
	var area := Area3D.new()
	area.name = "%s_ClickArea_%d" % [zone_kind.capitalize(), pid]
	area.input_ray_pickable = true
	area.set_meta("zone_pid", pid)
	area.set_meta("zone_kind", zone_kind)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 0.35, 1.0)
	col.shape = box
	col.position = Vector3(0, 0.15, 0)
	area.add_child(col)
	anchor.add_child(area)
	area.input_event.connect(func(_cam, event, _pos, _norm, _shape):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if zone_kind == "graveyard":
				var cards: Array = graveyard_stack if pid == local_player_id else player_graveyards.get(pid, [])
				hud_manager.open_zone_viewer("%s's Graveyard" % get_player_display_name(pid), cards, pid)
			else:
				var cards: Array = exile_stack if pid == local_player_id else player_exile.get(pid, [])
				hud_manager.open_zone_viewer("%s's Exile" % get_player_display_name(pid), cards, pid)
	)

func cast_from_graveyard(card_node: Node3D, mode: String, alt_cost: String, exile_other_count: int) -> void:
	if not turn_manager.holds_priority(local_player_id): return
	var is_instant := MagicRules.can_cast_at_instant_speed(card_node.card_data, 0, local_player_id, self)
	if mode == "unearth" or not is_instant:
		if not turn_manager.can_act_sorcery_speed(local_player_id): return

	if mode == "escape":
		if graveyard_stack.size() - 1 < exile_other_count: return

	var finalize_gy = func(chosen_tgt: Variant):
		if not can_pay_and_drain_cost(alt_cost): return
		if mode == "escape":
			var exiled := 0
			for c in graveyard_stack.duplicate():
				if c == card_node: continue
				graveyard_stack.erase(c)
				zone_manager.move_to_exile(c)
				exiled += 1
				if exiled >= exile_other_count: break

		graveyard_stack.erase(card_node)
		if mode == "unearth":
			card_node.set_meta("unearthed", true)
			card_node.grant_layer_keyword("haste")
			card_node.has_summoning_sickness = false
			var gt := card_node.global_transform
			card_node.reparent(self, true)
			card_node.global_transform = gt
			card_node.is_on_battlefield = true
			battlefield_non_lands.append(card_node)
			EventBus.notify_etb(card_node, "Graveyard")
			check_and_queue_triggers("ETB", card_node)
			zone_manager.update_battlefield_positions(true)
			zone_manager.update_zone_counters()
			run_state_based_actions()
		else:
			if mode == "flashback": card_node.set_meta("cast_via_flashback", true)
			if chosen_tgt != null: card_node.set_meta("chosen_target", chosen_tgt)
			zone_manager.move_to_stack(card_node)
			zone_manager.update_zone_counters()

	var oracle_lower: String = str(card_node.get_active_oracle_text()).to_lower()
	if mode != "unearth" and "target" in oracle_lower:
		var req := OracleParser.extract_target_requirement(oracle_lower)
		hud_manager.start_generic_targeting("SELECT TARGET FOR %s" % str(card_node.card_data.get("name", "SPELL")), func(tgt):
			card_node.set_meta("target_requirement", req)
			finalize_gy.call(tgt)
		, req, card_node)
	else:
		finalize_gy.call(null)

func _create_anchor(node_name: String, pos: Vector3) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = node_name
	anchor.position = pos
	add_child(anchor)
	return anchor

func _create_anchor_child(node_name: String, pos: Vector3, parent: Node) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = node_name
	anchor.position = pos
	parent.add_child(anchor)
	return anchor

func _create_3d_label(label_name: String, parent_node: Node3D, modulate_color: Color, offset := Vector3(0.0, 0.4, 0.0)) -> Label3D:
	var lbl := Label3D.new()
	if BELEREN_FONT: lbl.font = BELEREN_FONT
	lbl.name = label_name
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.pixel_size = 0.003
	lbl.modulate = modulate_color
	lbl.position = offset
	parent_node.add_child(lbl)
	return lbl

func _setup_command_info_stations() -> void:
	var station_cfgs := [
		{"id": 1, "pos": Vector3(0.0, 0.025, 1.05), "rot_y": 0.0},
		{"id": 2, "pos": Vector3(-1.15, 0.025, 0.0), "rot_y": -PI / 2.0},
		{"id": 3, "pos": Vector3(0.0, 0.025, -1.05), "rot_y": PI},
		{"id": 4, "pos": Vector3(1.15, 0.025, 0.0), "rot_y": PI / 2.0}
	]
	for sc in station_cfgs:
		var pid: int = sc["id"]
		var root := Node3D.new()
		root.name = "CommandInfoStation_%d" % pid
		root.position = sc["pos"]
		root.rotation.y = sc["rot_y"]
		add_child(root)

		# Gold trim frame matching UI_BORDER
		var border_mesh := MeshInstance3D.new()
		var b_box := BoxMesh.new()
		b_box.size = Vector3(1.26, 0.014, 0.56)
		border_mesh.mesh = b_box
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = UI_BORDER
		b_mat.metallic = 0.35
		b_mat.roughness = 0.4
		border_mesh.material_override = b_mat
		root.add_child(border_mesh)

		# Dark slate inner plate matching UI_BACKGROUND
		var bg_mesh := MeshInstance3D.new()
		var bg_box := BoxMesh.new()
		bg_box.size = Vector3(1.20, 0.018, 0.50)
		bg_mesh.mesh = bg_box
		var bg_mat := StandardMaterial3D.new()
		bg_mat.albedo_color = Color(UI_BACKGROUND.r, UI_BACKGROUND.g, UI_BACKGROUND.b, 1.0)
		bg_mat.roughness = 0.7
		bg_mesh.material_override = bg_mat
		root.add_child(bg_mesh)

		var name_lbl := Label3D.new()
		if BELEREN_FONT: name_lbl.font = BELEREN_FONT
		name_lbl.text = get_player_display_name(pid)
		name_lbl.position = Vector3(0.0, 0.015, -0.15)
		name_lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		name_lbl.font_size = 28
		name_lbl.outline_size = 10
		name_lbl.pixel_size = 0.0022
		name_lbl.modulate = Color(0.45, 0.95, 0.45, 1.0) if pid == local_player_id else Color(0.95, 0.85, 0.55, 1.0)
		root.add_child(name_lbl)

		var life_lbl := Label3D.new()
		if BELEREN_FONT: life_lbl.font = BELEREN_FONT
		life_lbl.text = str(player_life.get(pid, 40))
		life_lbl.position = Vector3(0.0, 0.015, 0.01)
		life_lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		life_lbl.font_size = 56
		life_lbl.outline_size = 14
		life_lbl.pixel_size = 0.0028
		life_lbl.modulate = Color(0.45, 0.95, 0.45, 1.0) if pid == local_player_id else Color(1.0, 1.0, 1.0, 1.0)
		root.add_child(life_lbl)

		var cmd_lbl := Label3D.new()
		if BELEREN_FONT: cmd_lbl.font = BELEREN_FONT
		cmd_lbl.text = ""
		cmd_lbl.position = Vector3(0.0, 0.015, 0.13)
		cmd_lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		cmd_lbl.font_size = 20
		cmd_lbl.outline_size = 8
		cmd_lbl.pixel_size = 0.0020
		cmd_lbl.modulate = Color(1.0, 0.55, 0.45, 1.0)
		root.add_child(cmd_lbl)

		var st_lbl := Label3D.new()
		if BELEREN_FONT: st_lbl.font = BELEREN_FONT
		st_lbl.text = ""
		st_lbl.position = Vector3(0.0, 0.015, 0.21)
		st_lbl.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		st_lbl.font_size = 16
		st_lbl.outline_size = 7
		st_lbl.pixel_size = 0.0019
		st_lbl.modulate = Color(0.55, 0.90, 1.0, 1.0)
		root.add_child(st_lbl)
		command_info_stations[pid] = {"root": root, "name": name_lbl, "life": life_lbl, "cmd": cmd_lbl, "status": st_lbl}

func refresh_command_info_stations() -> void:
	for pid in command_info_stations.keys():
		var st: Dictionary = command_info_stations[pid]
		var name_lbl: Label3D = st["name"]
		var life_lbl: Label3D = st["life"]
		var cmd_lbl: Label3D = st["cmd"]
		if is_instance_valid(name_lbl):
			name_lbl.text = get_player_display_name(pid)
		var cur_life: int = int(player_life.get(pid, 40))
		if is_instance_valid(life_lbl):
			life_lbl.text = "DEAD" if cur_life <= 0 else str(cur_life)
			if cur_life <= 0:
				life_lbl.modulate = Color(0.95, 0.3, 0.3, 1.0)
			else:
				life_lbl.modulate = Color(0.45, 0.95, 0.45, 1.0) if pid == local_player_id else Color(1.0, 1.0, 1.0, 1.0)
		if is_instance_valid(cmd_lbl):
			var cmd_map: Dictionary = commander_damage.get(pid, {})
			var parts: Array[String] = []
			for cmd_card in cmd_map.keys():
				var amt := int(cmd_map[cmd_card])
				if amt > 0 and is_instance_valid(cmd_card):
					parts.append("%s %d" % [str(cmd_card.card_data.get("name", "Cmd")).split(" ")[0], amt])
			cmd_lbl.text = ("Cmd: " + " · ".join(parts)) if not parts.is_empty() else ""
		var st_lbl: Label3D = st.get("status", null)
		if st_lbl and is_instance_valid(st_lbl):
			var s_parts: Array[String] = []
			if monarch_player_id == pid: s_parts.append("Monarch")
			if initiative_player_id == pid: s_parts.append("Initiative")
			for ps in player_statuses.get(pid, []):
				s_parts.append(str(ps))
			var p_cnts: Dictionary = player_counters.get(pid, {})
			for ck in p_cnts.keys():
				var cv: int = int(p_cnts[ck])
				if cv > 0: s_parts.append("%s: %d" % [str(ck).capitalize(), cv])
			var d_info: Dictionary = player_dungeons.get(pid, {})
			if not d_info.is_empty():
				s_parts.append("%s (Rm %d)" % [str(d_info.get("name", "Dungeon")).left(12), int(d_info.get("room", 1))])
			st_lbl.text = " · ".join(s_parts)

func setup_tabletop_layout() -> void:
	central_stack_anchor = _create_anchor("CentralStack", Vector3(0.0, 0.55, 0.0))
	_setup_command_info_stations()
	var configs := [
		{"id": 1, "station_pos": Vector3(0.0, 0.0, 5.5), "rotation_y": 0.0, "lib": Vector3(-3.0, 0.01, 4.0), "gy": Vector3(-3.0, 0.01, 5.0), "cmd": Vector3(-3.0, 0.01, 3.0), "hand_pos": Vector3(0.0, -1.0, 6.8)},
		{"id": 2, "station_pos": Vector3(5.5, 0.0, 0.0), "rotation_y": -PI / 2.0, "lib": Vector3(-3.0, 0.01, 9.6), "gy": Vector3(-3.0, 0.01, 10.6), "cmd": Vector3(-3.0, 0.01, 8.6), "hand_pos": Vector3(6.8, -1.0, 0.0)},
		{"id": 3, "station_pos": Vector3(0.0, 0.0, -5.5), "rotation_y": PI, "lib": Vector3(-3.0, 0.01, -1.4), "gy": Vector3(-3.0, 0.01, -0.4), "cmd": Vector3(-3.0, 0.01, -2.4), "hand_pos": Vector3(0.0, -1.0, -6.8)},
		{"id": 4, "station_pos": Vector3(-5.5, 0.0, 0.0), "rotation_y": PI / 2.0, "lib": Vector3(-2.8, 0.01, 9.6), "gy": Vector3(-2.8, 0.01, 10.6), "cmd": Vector3(-2.8, 0.01, 8.6), "hand_pos": Vector3(-6.8, -1.0, 0.0)}
	]
	for cfg in configs:
		var pid: int = cfg["id"]
		var station := Node3D.new()
		station.name = "Player_%d_Station" % pid
		station.position = cfg["station_pos"]
		station.rotation.y = cfg["rotation_y"]
		add_child(station)

		var lib_anchor := _create_anchor_child("LibraryAnchor", cfg["lib"], station)
		var gy_anchor := _create_anchor_child("GraveyardAnchor", cfg["gy"], station)
		var cmd_anchor := _create_anchor_child("CommandZoneAnchor", cfg["cmd"], station)
		var exile_anc := _create_anchor_child("ExileAnchor", cfg["gy"] + Vector3(-1.2, 0.0, 0.0), station)
		var lands_anc := _create_anchor_child("BattlefieldLandsAnchor", Vector3(0.0, 0.01, cfg["gy"].z), station)
		var non_lands_anc := _create_anchor_child("BattlefieldNonLandsAnchor", Vector3(0.0, 0.01, cfg["lib"].z), station)

		var hand_cont: Node3D = null
		if pid == local_player_id:
			hand_cont = _create_anchor_child("HandContainer", cfg["hand_pos"], station)
		else:
			# Instantiate placeholder Camera3D + HandContainer for opponent stations
			var opp_cam := Camera3D.new()
			opp_cam.name = "Player_%d_Camera" % pid
			opp_cam.current = false
			opp_cam.position = Vector3(0.0, 2.6, cfg["gy"].z + 2.2)
			opp_cam.rotation = Vector3(deg_to_rad(-51.0), 0.0, 0.0)
			station.add_child(opp_cam)
			player_cameras[pid] = opp_cam
			hand_cont = _create_anchor_child("HandContainer", Vector3(0.0, -0.9, -1.5), opp_cam)

		var lib_lbl: Label3D = null
		var gy_lbl: Label3D = null
		var ex_lbl: Label3D = null
		if pid != local_player_id:
			lib_lbl = _create_3d_label("LibraryCountLabel", lib_anchor, Color(1, 0.9, 0.6, 1))
			gy_lbl = _create_3d_label("GraveyardCountLabel", gy_anchor, Color(1, 1, 1, 1))
			ex_lbl = _create_3d_label("ExileCountLabel", exile_anc, Color(0.7, 0.7, 0.8, 1))
			_create_zone_click_area(gy_anchor, pid, "graveyard")
			_create_zone_click_area(exile_anc, pid, "exile")

		player_stations[pid] = {
			"station": station, "library": lib_anchor, "graveyard": gy_anchor,
			"command_zone": cmd_anchor, "exile": exile_anc,
			"lands_anchor": lands_anc, "non_lands_anchor": non_lands_anc,
			"hand_container": hand_cont, "config": cfg
		}
		player_zone_labels[pid] = {"library": lib_lbl, "graveyard": gy_lbl, "exile": ex_lbl}
		player_libraries[pid] = []; player_graveyards[pid] = []; player_exile[pid] = []; player_hands[pid] = []
		player_command_zones[pid] = []; player_battlefield_lands[pid] = []; player_battlefield_non_lands[pid] = []
		player_hand_containers[pid] = hand_cont

func connect_card_signals(card_node: Node3D) -> void:
	if card_node.has_signal("card_played") and not card_node.card_played.is_connected(_on_card_played):
		card_node.card_played.connect(_on_card_played)
	if card_node.has_signal("card_clicked_on_battlefield") and not card_node.card_clicked_on_battlefield.is_connected(_on_card_clicked_on_battlefield):
		card_node.card_clicked_on_battlefield.connect(_on_card_clicked_on_battlefield)
	if card_node.has_signal("card_hovered") and not card_node.card_hovered.is_connected(_on_card_hovered):
		card_node.card_hovered.connect(_on_card_hovered)
	if card_node.has_signal("card_unhovered") and not card_node.card_unhovered.is_connected(_on_card_unhovered):
		card_node.card_unhovered.connect(_on_card_unhovered)

func _get_card_texture(card: Node3D) -> Texture2D:
	if card.has_method("get_active_texture"):
		var active_tex: Texture2D = card.get_active_texture()
		if active_tex != null: return active_tex
	if "stored_front_texture" in card and card.stored_front_texture != null:
		return card.stored_front_texture
	var front_face_node := card.get_node_or_null("FrontFace")
	if front_face_node and front_face_node is MeshInstance3D:
		var mat := front_face_node.material_override as ShaderMaterial
		if mat:
			var shader_tex = mat.get_shader_parameter("front_tex")
			if shader_tex is Texture2D and shader_tex != card.get("LOCAL_CARD_BACK"):
				return shader_tex
	var front_url: String = card.card_data.get("image_url", "")
	if front_url.is_empty() and card.card_data.get("card_faces") is Array and not card.card_data["card_faces"].is_empty():
		var face: Dictionary = card.card_data["card_faces"][0]
		var uris: Dictionary = face.get("image_uris", {})
		front_url = uris.get("normal", uris.get("small", ""))
	if not front_url.is_empty():
		return CardManager.get_cached_image_texture(front_url)
	return null

# --- PROXY METHODS FOR MANAGERS & ABILITY RESOLVER ---

func draw_card() -> void: zone_manager.draw_card()
func _draw_opponent_card(pid: int) -> void: zone_manager.draw_opponent_card(pid)
func _on_card_to_graveyard(card_node: Node3D) -> void: zone_manager.move_to_graveyard(card_node)
func _on_card_to_exile(card_node: Node3D) -> void: zone_manager.move_to_exile(card_node)
func _on_card_returned_to_hand(card_node: Node3D) -> void: zone_manager.move_to_hand(card_node)
func update_hand_positions(anim: bool = false) -> void: zone_manager.update_hand_positions(anim)
func update_mana_ui() -> void: hud_manager.update_mana_ui()
func show_mana_choice_popup(card_node: Node3D, colors: Array) -> void: hud_manager.show_mana_choice_popup(card_node, colors)

func modify_life(player_id: int, amount: int) -> void:
	player_life[player_id] += amount
	event_ledger.log_event(GameEventLedger.EventType.LIFE_CHANGED, {"player_id": player_id, "delta": amount, "new_life": player_life[player_id]})
	EventBus.notify_life_change(player_id, player_life[player_id], amount)
	run_state_based_actions()

func empty_mana_pool() -> void:
	for color in mana_pool.keys():
		mana_pool[color] = 0
	restricted_mana.clear()
	event_ledger.log_event(GameEventLedger.EventType.MANA_EMPTIED, {})
	EventBus.notify_mana(mana_pool)

func parse_equip_cost(oracle_text: String) -> String:
	var result := EQUIP_COST_REGEX.search(oracle_text)
	return result.get_string(1) if result else ""

func get_taxed_mana_cost(card_node: Node3D) -> String:
	var base_cost: String = card_node.card_data.get("mana_cost", card_node.card_data.get("manaCost", ""))
	var casts: int = int(commander_cast_counts.get(card_node, 0))
	return base_cost if casts == 0 else base_cost + "{2}".repeat(casts)

# --- STATE-BASED ACTIONS & TRIGGERS ---

func run_state_based_actions() -> void:
	ContinuousEffectsEngine.recalculate_layers(battlefield_lands, battlefield_non_lands, self)

	var dead_creatures: Array[Node3D] = []
	var unattached_auras: Array[Node3D] = []

	for card in battlefield_non_lands:
		if not is_instance_valid(card): continue
		var type_line := MagicRules.get_card_type_line(card.card_data).to_lower()
		if "aura" in type_line:
			var host: Node3D = card.get("attached_to")
			var enchant_req: String = str(card.parsed_abilities.get("enchant_target", ""))
			if host == null or not is_instance_valid(host) or not host.is_on_battlefield:
				unattached_auras.append(card)
				continue
			elif not enchant_req.is_empty() and not MagicRules.is_legal_target(host, enchant_req, get_card_owner_id(card), card):
				zone_manager.detach_card(card)
				continue
		if "creature" in type_line:
			var tou: int = card.dynamic_toughness
			var dmg: int = card.marked_damage
			var is_indestructible: bool = card.has_method("has_keyword") and bool(card.has_keyword("indestructible"))
			var lethal_damage: bool = (dmg >= tou and tou > 0) or bool(card.get("has_deathtouch_damage"))
			if tou <= 0 or (lethal_damage and not is_indestructible):
				dead_creatures.append(card)
		if "planeswalker" in type_line:
			var loy: int = card.get_named_counter("loyalty") if card.has_method("get_named_counter") else 0
			if loy <= 0:
				dead_creatures.append(card)

	for aura in unattached_auras:
		zone_manager.move_to_graveyard(aura)

	for dead in dead_creatures:
		EventBus.notify_die(dead)
		check_and_queue_triggers("DIE", dead)
		zone_manager.move_to_graveyard(dead)

	# Legend Rule (CR 704.5j)
	if not _legend_rule_pending:
		var leg_groups: Dictionary = {}
		for perm in battlefield_lands + battlefield_non_lands:
			if not is_instance_valid(perm) or not perm.is_on_battlefield: continue
			var tl := MagicRules.get_card_type_line(perm.card_data).to_lower()
			if "legendary" in tl:
				var key := "%d|%s" % [get_card_owner_id(perm), str(perm.card_data.get("name", ""))]
				if not leg_groups.has(key): leg_groups[key] = []
				leg_groups[key].append(perm)
		for key in leg_groups.keys():
			var grp: Array = leg_groups[key]
			if grp.size() > 1:
				var grp_owner := get_card_owner_id(grp[0])
				if grp_owner != local_player_id:
					for k in range(1, grp.size()):
						zone_manager.move_to_graveyard(grp[k])
				else:
					_legend_rule_pending = true
					var labels: Array = []
					for idx in range(grp.size()):
						labels.append("Keep %s #%d" % [str(grp[idx].card_data.get("name", "Legend")), idx + 1])
					hud_manager.open_choice_popup("LEGEND RULE — KEEP ONE", labels, func(keep_idx: int):
						_legend_rule_pending = false
						for idx in range(grp.size()):
							if idx != keep_idx and is_instance_valid(grp[idx]):
								zone_manager.move_to_graveyard(grp[idx])
					)
					break

	for pid in player_life.keys():
		var lost_by_cmd := false
		var cmd_map: Dictionary = commander_damage.get(pid, {})
		for cmd_card in cmd_map.keys():
			if int(cmd_map[cmd_card]) >= 21:
				lost_by_cmd = true
				break
		var lost_by_poison: bool = int(player_counters.get(pid, {}).get("poison", 0)) >= 10
		if player_life[pid] <= 0 or lost_by_cmd or lost_by_poison:
			if hud_manager.life_labels.has(pid):
				hud_manager.life_labels[pid].text = "DEAD"
			if not is_player_eliminated(pid):
				_eliminate_player(pid)

	for t in graveyard_stack.duplicate():
		if is_instance_valid(t) and t.get("is_token"):
			graveyard_stack.erase(t)
			t.queue_free()

	zone_manager.update_zone_counters()

func _on_phase_changed_triggers(new_phase: int) -> void:
	if new_phase == TurnManager.TurnPhase.UPKEEP:
		var turn_key := "%d_%d" % [turn_manager.turn_number, turn_manager.active_player_id]
		if turn_key != _last_upkeep_trigger_key:
			_last_upkeep_trigger_key = turn_key
			check_and_queue_triggers("UPKEEP", null)
	elif new_phase == TurnManager.TurnPhase.END:
		check_and_queue_triggers("END_STEP", null)

func _on_combat_declared_triggers(attacker: Node3D, _target_pid: int) -> void:
	check_and_queue_triggers("ATTACK", attacker)

func _on_blocker_declared_triggers(blocker: Node3D, _attacker: Node3D) -> void:
	check_and_queue_triggers("BLOCK", blocker)

func _on_damage_dealt_triggers(source: Node3D, target: Variant, amount: int) -> void:
	if amount > 0 and target is int and is_instance_valid(source):
		check_and_queue_triggers("COMBAT_DAMAGE_PLAYER", source)

func advance_sagas_for_player(pid: int) -> void:
	for perm in battlefield_non_lands.duplicate():
		if not is_instance_valid(perm) or not perm.is_on_battlefield: continue
		if get_card_owner_id(perm) != pid: continue
		if not MagicRules.is_saga(perm.card_data): continue
		if perm.has_method("modify_named_counter"):
			perm.modify_named_counter("lore", 1)
		var cur_lore: int = perm.get_named_counter("lore") if perm.has_method("get_named_counter") else 1
		var pa: Dictionary = perm.parsed_abilities
		var chapters: Array = pa.get("saga_chapters", [])
		for ch_data in chapters:
			var ch_nums: Array = ch_data.get("chapters", [])
			if cur_lore in ch_nums:
				_push_ability_to_stack(perm, ch_data, "Saga Ch.%d" % cur_lore)
		var max_ch: int = int(pa.get("saga_max_chapter", 0))
		if max_ch > 0 and cur_lore >= max_ch:
			zone_manager.move_to_graveyard(perm)

func check_and_queue_triggers(event_name: String, source_card: Node3D = null) -> void:
	var all_permanents := battlefield_lands + battlefield_non_lands
	var src_valid := source_card != null and is_instance_valid(source_card)
	var src_type := MagicRules.get_card_type_line(source_card.card_data).to_lower() if src_valid else ""
	var src_owner := get_card_owner_id(source_card) if src_valid else -1

	for perm in all_permanents:
		if not is_instance_valid(perm) or not perm.has_method("get_triggered_abilities"): continue
		var perm_name := str(perm.card_data.get("name", "")).to_lower()
		var perm_owner := get_card_owner_id(perm)

		for trig in perm.get_triggered_abilities():
			var event_raw: String = str(trig.get("trigger_event_raw", "")).to_lower()

			if event_name == "ETB" and src_valid and ("enters the battlefield" in event_raw or "enters" in event_raw):
				if "enters tapped" in event_raw or "enters with" in event_raw: continue
				var is_self: bool = ("this " in event_raw or "~" in event_raw or (not perm_name.is_empty() and perm_name in event_raw)) and not ("another" in event_raw)
				if is_self:
					if perm == source_card: _push_ability_to_stack(perm, trig, "Triggered")
					continue
				if "another" in event_raw and perm == source_card: continue
				if "you control" in event_raw and src_owner != perm_owner: continue
				if "creature" in event_raw and not ("creature" in src_type): continue
				if "land" in event_raw and not ("land" in src_type): continue
				if "artifact" in event_raw and not ("artifact" in src_type): continue
				if "enchantment" in event_raw and not ("enchantment" in src_type): continue
				_push_ability_to_stack(perm, trig, "Triggered")

			elif event_name == "DIE" and src_valid and ("dies" in event_raw or "put into a graveyard" in event_raw):
				if source_card == perm or ("another" in event_raw and source_card != perm) or ("a creature" in event_raw and "creature" in src_type):
					_push_ability_to_stack(perm, trig, "Triggered")

			elif event_name == "UPKEEP" and "beginning of" in event_raw and "upkeep" in event_raw:
				if "your upkeep" in event_raw and perm_owner != turn_manager.active_player_id: continue
				_push_ability_to_stack(perm, trig, "Triggered")

			elif event_name == "END_STEP" and "beginning of" in event_raw and "end step" in event_raw:
				if "your end step" in event_raw and perm_owner != turn_manager.active_player_id: continue
				_push_ability_to_stack(perm, trig, "Triggered")

			elif (event_name == "ATTACK" and src_valid and "attacks" in event_raw) or (event_name == "BLOCK" and src_valid and "blocks" in event_raw):
				var is_ctrl_trigger: bool = ("creature you control" in event_raw and src_owner == perm_owner)
				if perm == source_card or is_ctrl_trigger:
					var eff_l: String = str(trig.get("effect_raw", "")).to_lower()
					var def_tgt: Variant = source_card if (not ("target" in eff_l)) else null
					_push_ability_to_stack(perm, trig, "Triggered", def_tgt)

			elif event_name == "COMBAT_DAMAGE_PLAYER" and src_valid and "combat damage" in event_raw and "player" in event_raw:
				if perm == source_card or ("creature you control deals combat damage" in event_raw and src_owner == perm_owner):
					_push_ability_to_stack(perm, trig, "Triggered")

			elif event_name == "CAST" and src_valid and "you cast" in event_raw and src_owner == perm_owner:
				if "instant or sorcery" in event_raw and not ("instant" in src_type or "sorcery" in src_type): continue
				if "creature spell" in event_raw and not ("creature" in src_type): continue
				if "noncreature" in event_raw and ("creature" in src_type): continue
				_push_ability_to_stack(perm, trig, "Triggered")

func _push_ability_to_stack(source_card: Node3D, ability_data: Dictionary, ability_type: String, default_target: Variant = null) -> void:
	var effect_raw: String = str(ability_data.get("effect_raw", ""))
	var ctrl_id: int = get_card_owner_id(source_card)
	if ability_type == "Triggered" and "target" in effect_raw.to_lower():
		if ctrl_id == local_player_id:
			hud_manager.start_generic_targeting("SELECT TARGET FOR %s TRIGGER" % str(source_card.card_data.get("name", "Card")), func(chosen_target):
				_finalize_push_ability_to_stack(source_card, ability_data, ability_type, chosen_target)
			)
			return
		elif ai_controller:
			var ai_tgt = ai_controller.pick_ai_target(ctrl_id, effect_raw.to_lower())
			_finalize_push_ability_to_stack(source_card, ability_data, ability_type, ai_tgt)
			return
	_finalize_push_ability_to_stack(source_card, ability_data, ability_type, default_target)

func _finalize_push_ability_to_stack(source_card: Node3D, ability_data: Dictionary, ability_type: String, target_ref: Variant) -> void:
	var stack_obj := StackObject.new()
	stack_obj.name = "%s [%s Ability]" % [source_card.card_data.get("name", "Card"), ability_type]
	stack_obj.effect_text = ability_data.get("effect_raw", "")
	stack_obj.source_card = source_card
	stack_obj.controller_id = get_card_owner_id(source_card)
	stack_obj.target_ref = target_ref
	stack_obj.target_requirement = str(ability_data.get("target_requirement", ""))

	var eff_lower := stack_obj.effect_text.to_lower()
	if target_ref == null and "target" in eff_lower:
		var req := str(stack_obj.target_requirement)
		if stack_obj.controller_id != local_player_id:
			stack_obj.target_ref = ai_controller.pick_ai_target(stack_obj.controller_id, eff_lower)
		else:
			hud_manager.start_generic_targeting("TRIGGER TARGET (%s) — %s" % [req.to_upper() if not req.is_empty() else "ANY", stack_obj.name], func(chosen_tgt):
				stack_obj.target_ref = chosen_tgt
				active_stack.append(stack_obj)
				turn_manager.priority_passes_count = 0
				event_ledger.log_event(GameEventLedger.EventType.STACK_PUSHED, {"card_name": stack_obj.name})
				zone_manager.update_zone_counters()
				EventBus.notify_stack(active_stack.size())
			, req, source_card)
			return
	active_stack.append(stack_obj)
	turn_manager.priority_passes_count = 0
	event_ledger.log_event(GameEventLedger.EventType.STACK_PUSHED, {"card_name": stack_obj.name})
	zone_manager.update_zone_counters()
	EventBus.notify_stack(active_stack.size())

func resolve_top_stack_card() -> void:
	if active_stack.is_empty(): return
	var stack_item = active_stack.pop_back()
	EventBus.notify_stack(active_stack.size())

	if stack_item is StackObject:
		var valid_src: Node3D = stack_item.source_card if is_instance_valid(stack_item.source_card) else null
		var tgt_req: String = str(stack_item.target_requirement)
		if stack_item.target_ref != null and stack_item.target_ref is Node3D and not tgt_req.is_empty():
			if not MagicRules.is_legal_target(stack_item.target_ref, tgt_req, stack_item.controller_id, valid_src):
				EventBus.play_sfx("fizzle")
				event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": stack_item.name + " (Fizzled)"})
				run_state_based_actions()
				return
		AbilityResolver.execute_effect_text(stack_item.effect_text, valid_src, stack_item.target_ref, self, stack_item.controller_id)
		EventBus.play_sfx("resolve")
		event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": stack_item.name})
		run_state_based_actions()
		return

	var card_node: Node3D = stack_item
	if card_node.has_method("set_highlight"): card_node.set_highlight(false)

	var face_idx: int = int(card_node.get("active_face_index")) if "active_face_index" in card_node else 0
	var type_line := MagicRules.get_card_type_line(card_node.card_data, face_idx).to_lower()
	var oracle_text: String = str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", face_idx))
	var is_instant_or_sorcery := ("instant" in type_line or "sorcery" in type_line) and not ("creature" in type_line or "artifact" in type_line or "enchantment" in type_line or "planeswalker" in type_line or "battle" in type_line)

	var chosen_target: Variant = card_node.get_meta("chosen_target") if card_node.has_meta("chosen_target") else null
	var target_req: String = str(card_node.get_meta("target_requirement")) if card_node.has_meta("target_requirement") else ""

	if is_instant_or_sorcery:
		if chosen_target != null and chosen_target is Node3D:
			var tgt_n := chosen_target as Node3D
			if is_instance_valid(tgt_n) and "parsed_abilities" in tgt_n:
				var w_cost: String = str(tgt_n.parsed_abilities.get("ward_cost", ""))
				var caster_id: int = get_card_owner_id(card_node)
				if not w_cost.is_empty() and get_card_owner_id(tgt_n) != caster_id and not card_node.has_meta("ward_paid"):
					if caster_id == local_player_id:
						hud_manager.open_choice_popup("WARD %s — PAY OR COUNTER" % w_cost, ["Pay Ward (%s)" % w_cost, "Decline (Counter Spell)"], func(w_idx: int):
							if w_idx == 0 and can_pay_and_drain_cost(w_cost, caster_id):
								card_node.set_meta("ward_paid", true)
								active_stack.append(card_node)
								resolve_top_stack_card()
							else:
								zone_manager.move_to_graveyard(card_node)
								EventBus.play_sfx("fizzle")
								event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": card_node.card_data.get("name", "") + " (Countered by Ward)"})
						)
						return
					elif not can_pay_and_drain_cost(w_cost, caster_id):
						zone_manager.move_to_graveyard(card_node)
						EventBus.play_sfx("fizzle")
						event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": card_node.card_data.get("name", "") + " (Countered by Ward)"})
						return
		if chosen_target != null and chosen_target is Node3D and not target_req.is_empty():
			if not MagicRules.is_legal_target(chosen_target, target_req, get_card_owner_id(card_node), card_node):
				if card_node.has_meta("chosen_target"): card_node.remove_meta("chosen_target")
				if card_node.has_meta("target_requirement"): card_node.remove_meta("target_requirement")
				zone_manager.move_to_graveyard(card_node)
				EventBus.play_sfx("fizzle")
				event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": card_node.card_data.get("name", "") + " (Fizzled)"})
				run_state_based_actions()
				return
		var eff_text := str(card_node.get_meta("chosen_modal_text")) if card_node.has_meta("chosen_modal_text") else oracle_text
		if card_node.has_meta("chosen_modal_text"): card_node.remove_meta("chosen_modal_text")
		if card_node.has_meta("chosen_x"):
			eff_text = OracleParser.substitute_x_in_text(eff_text, int(card_node.get_meta("chosen_x")))
			card_node.remove_meta("chosen_x")
		if bool(card_node.get("is_fused_cast")) and MagicRules.has_multiple_faces(card_node.card_data):
			var f0_text := str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", 0))
			var f1_text := str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", 1))
			AbilityResolver.execute_effect_text(f0_text, card_node, chosen_target, self, get_card_owner_id(card_node))
			AbilityResolver.execute_effect_text(f1_text, card_node, chosen_target, self, get_card_owner_id(card_node))
			card_node.is_fused_cast = false
		else:
			AbilityResolver.execute_effect_text(eff_text, card_node, chosen_target, self, get_card_owner_id(card_node))
		if card_node.has_meta("chosen_target"): card_node.remove_meta("chosen_target")

		# Omen spells shuffle back into library; Adventure spells exile themselves "On an Adventure"
		if MagicRules.is_adventure(card_node.card_data) and face_idx == 1:
			card_node.active_face_index = 0
			if MagicRules.is_omen(card_node.card_data):
				card_node.is_on_adventure = false
				zone_manager.move_to_bottom_library(card_node)
				zone_manager.shuffle_library()
			else:
				card_node.is_on_adventure = true
				zone_manager.move_to_exile(card_node)
		elif card_node.has_meta("cast_via_flashback") and bool(card_node.get_meta("cast_via_flashback")):
			card_node.remove_meta("cast_via_flashback")
			card_node.active_face_index = 0
			zone_manager.move_to_exile(card_node)
		else:
			card_node.active_face_index = 0
			zone_manager.move_to_graveyard(card_node)
	else:
		card_node.is_on_adventure = false
		if MagicRules.is_aura(card_node.card_data, face_idx):
			var enchant_req: String = str(card_node.parsed_abilities.get("enchant_target", "creature"))
			if not MagicRules.is_legal_target(chosen_target, enchant_req, get_card_owner_id(card_node), card_node):
				if card_node.has_meta("chosen_target"): card_node.remove_meta("chosen_target")
				zone_manager.move_to_graveyard(card_node)
				EventBus.play_sfx("fizzle")
				event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": card_node.card_data.get("name", "") + " (Aura Fizzled)"})
				run_state_based_actions()
				return
			zone_manager.attach_card_to_creature(card_node, chosen_target, false)
			if card_node.has_meta("chosen_target"): card_node.remove_meta("chosen_target")
			EventBus.notify_etb(card_node, "Stack")
			check_and_queue_triggers("ETB", card_node)
			EventBus.play_sfx("resolve")
			event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": card_node.card_data.get("name", "")})
			run_state_based_actions()
			return

		var global_trans := card_node.global_transform
		card_node.reparent(self, true)
		card_node.global_transform = global_trans
		card_node.is_on_battlefield = true
		var face_lower := oracle_text.to_lower()
		if card_node.has_meta("chosen_x"):
			var x_etb: int = int(card_node.get_meta("chosen_x"))
			card_node.remove_meta("chosen_x")
			if x_etb > 0 and "x +1/+1 counter" in face_lower and card_node.has_method("modify_counters"):
				card_node.modify_counters(x_etb)
		_apply_etb_tapped_replacement(card_node, face_idx)
		_apply_etb_choice_replacements(card_node, face_idx)
		if "land" in type_line: battlefield_lands.append(card_node)
		else: battlefield_non_lands.append(card_node)

		if MagicRules.is_room(card_node.card_data):
			card_node.unlocked_rooms = [face_idx]
			AbilityResolver.execute_effect_text(oracle_text, card_node, null, self)

		if MagicRules.is_planeswalker(card_node.card_data, face_idx) and card_node.has_method("modify_named_counter"):
			var start_loy: int = str(MagicRules.get_card_attribute(card_node.card_data, "loyalty", "0", face_idx)).to_int()
			if start_loy > 0:
				card_node.modify_named_counter("loyalty", start_loy)

		if "enters as a copy of" in face_lower or "enters the battlefield as a copy of" in face_lower:
			var p_owner := get_card_owner_id(card_node)
			if p_owner != local_player_id:
				var best_c = ai_controller.pick_ai_target(p_owner, "creature")
				if best_c is Node3D and is_instance_valid(best_c):
					card_node.set_meta("copy_of_card_data", best_c.card_data.duplicate(true))
			else:
				hud_manager.start_generic_targeting("CHOOSE CREATURE TO COPY", func(copy_tgt):
					if copy_tgt is Node3D and is_instance_valid(copy_tgt):
						card_node.set_meta("copy_of_card_data", copy_tgt.card_data.duplicate(true))
						run_state_based_actions()
				, "creature", card_node)

		EventBus.notify_etb(card_node, "Stack")
		check_and_queue_triggers("ETB", card_node)
		zone_manager.update_battlefield_positions(true)

	EventBus.play_sfx("resolve")
	event_ledger.log_event(GameEventLedger.EventType.STACK_RESOLVED, {"card_name": card_node.card_data.get("name", "")})
	run_state_based_actions()

# --- INPUT & INTERACTION ---

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var open_popup := _find_visible_popup_menu(get_tree().root)
		if open_popup != null:
			var vp := get_viewport()
			if event.button_index == JOY_BUTTON_A:
				var p_idx: int = open_popup.get_focused_item()
				if p_idx < 0 and open_popup.item_count > 0:
					var mp: Vector2 = open_popup.get_mouse_position()
					var row_h: float = maxf(1.0, float(open_popup.size.y) / float(open_popup.item_count))
					p_idx = clampi(int(mp.y / row_h), 0, open_popup.item_count - 1)
				if p_idx >= 0 and p_idx < open_popup.item_count:
					var ob := open_popup.get_parent() as OptionButton
					if ob:
						ob.select(p_idx)
						ob.item_selected.emit(p_idx)
					else:
						open_popup.index_pressed.emit(p_idx)
						open_popup.id_pressed.emit(open_popup.get_item_id(p_idx))
					open_popup.hide()
				vp.set_input_as_handled()
			elif event.button_index == JOY_BUTTON_B:
				open_popup.hide()
				vp.set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_handle_joypad_button(event.button_index)
		return
	if not (event is InputEventKey and event.pressed): return
	var k: int = event.keycode

	match k:
		KEY_SPACE:
			if hud_manager.phase_ui_label:
				turn_manager.request_primary_action()
				get_viewport().set_input_as_handled()
			return
		KEY_TAB:
			if turn_manager.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS and turn_manager.is_local_player_turn():
				combat_manager.cycle_next_attacker()
				get_viewport().set_input_as_handled()
			return
		KEY_P:
			turn_manager.pass_until_end_step = false
			turn_manager.advance_turn_phase(true)
			get_viewport().set_input_as_handled()
			return
		KEY_BACKSPACE:
			empty_mana_pool()
			get_viewport().set_input_as_handled()
			return
		KEY_F:
			hud_manager.open_zone_viewer("Library (Tutor)", library_stack)
			get_viewport().set_input_as_handled()
			return
		KEY_G:
			if hovered_card == null:
				hud_manager.open_zone_viewer("Graveyard", graveyard_stack)
				get_viewport().set_input_as_handled()
				return
		KEY_E:
			if hovered_card == null:
				hud_manager.open_zone_viewer("Exile", exile_stack)
				get_viewport().set_input_as_handled()
				return
		KEY_ENTER:
			resolve_top_stack_card()
			get_viewport().set_input_as_handled()
			return
		KEY_ESCAPE:
			var act_popup := get_node_or_null("ActivatedAbilitiesUI")
			if act_popup:
				act_popup.queue_free()
				get_viewport().set_input_as_handled()
			elif hud_manager.search_canvas and hud_manager.search_canvas.is_inside_tree():
				hud_manager.search_canvas.queue_free(); hud_manager.search_canvas = null
				get_viewport().set_input_as_handled()
			elif hud_manager.targeting_attachment != null or hud_manager.active_target_callback.is_valid():
				hud_manager.cancel_attachment_targeting()
				get_viewport().set_input_as_handled()
			return

	match k:
		KEY_D:
			if turn_manager.is_local_player_turn(): zone_manager.draw_card(); get_viewport().set_input_as_handled()
		KEY_U:
			if turn_manager.is_local_player_turn():
				if hovered_card and hovered_card.is_on_battlefield: zone_manager.untap_single_card(hovered_card)
				else: zone_manager.untap_all(local_player_id)
				get_viewport().set_input_as_handled()
		KEY_S:
			if turn_manager.is_local_player_turn(): zone_manager.shuffle_library(); get_viewport().set_input_as_handled()
		KEY_T:
			if not hovered_card and turn_manager.is_local_player_turn():
				hud_manager.open_token_spawner(); get_viewport().set_input_as_handled()
			elif hovered_card and hovered_card.is_on_battlefield:
				_on_card_clicked_on_battlefield(hovered_card, MOUSE_BUTTON_LEFT); get_viewport().set_input_as_handled()

	if hovered_card:
		match k:
			KEY_E: zone_manager.move_to_exile(hovered_card); get_viewport().set_input_as_handled()
			KEY_Y:
				if turn_manager.is_local_player_turn(): spawn_token_copy(hovered_card); get_viewport().set_input_as_handled()
			KEY_EQUAL:
				if hovered_card.has_method("modify_counters"):
					hovered_card.modify_counters(5 if event.shift_pressed else 1); run_state_based_actions(); get_viewport().set_input_as_handled()
			KEY_MINUS:
				if hovered_card.has_method("modify_counters"):
					hovered_card.modify_counters(-5 if event.shift_pressed else -1); run_state_based_actions(); get_viewport().set_input_as_handled()
			KEY_DELETE:
				if event.shift_pressed and hovered_card.has_method("clear_counters"):
					hovered_card.clear_counters(); run_state_based_actions(); get_viewport().set_input_as_handled()
			KEY_C:
				if hovered_card in command_zone_cards or hovered_card.is_on_battlefield or hovered_card in graveyard_stack or hovered_card in hand_cards:
					zone_manager.move_to_command_zone(hovered_card); get_viewport().set_input_as_handled()
			KEY_H:
				if hovered_card.is_on_battlefield or hovered_card in graveyard_stack:
					zone_manager.move_to_hand(hovered_card); get_viewport().set_input_as_handled()
			KEY_L:
				if hovered_card.is_on_battlefield: zone_manager.remove_from_battlefield(hovered_card)
				elif hovered_card in hand_cards: hand_cards.erase(hovered_card); zone_manager.update_hand_positions(true)
				elif hovered_card in graveyard_stack: graveyard_stack.erase(hovered_card)
				if event.shift_pressed: zone_manager.move_to_bottom_library(hovered_card)
				else: zone_manager.move_to_top_library(hovered_card)
				get_viewport().set_input_as_handled()
			KEY_G:
				if not hovered_card in graveyard_stack:
					if hovered_card in hand_cards: hand_cards.erase(hovered_card); zone_manager.update_hand_positions(true)
					zone_manager.move_to_graveyard(hovered_card); get_viewport().set_input_as_handled()
			KEY_A:
				if turn_manager.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS and turn_manager.is_local_player_turn():
					combat_manager.handle_declare_attacker_key(hovered_card, event.shift_pressed)
				elif hud_manager.targeting_attachment != null:
					if hovered_card != hud_manager.targeting_attachment and hovered_card.is_on_battlefield:
						zone_manager.attach_card_to_creature(hud_manager.targeting_attachment, hovered_card)
					else: hud_manager.cancel_attachment_targeting()
				else:
					if event.shift_pressed and hovered_card.get("attached_to") != null: zone_manager.detach_card(hovered_card)
					else: hud_manager.start_attachment_targeting(hovered_card)
				get_viewport().set_input_as_handled()

func _on_card_hovered(card: Node3D) -> void:
	hovered_card = card
	hud_manager.show_card_preview(card)

func _on_card_unhovered(card: Node3D) -> void:
	if hovered_card == card:
		hovered_card = null
		hud_manager.hide_card_preview()

func put_library_card_onto_battlefield(card_node: Node3D, pid: int = local_player_id, enter_tapped: bool = false) -> void:
	if not card_node or not is_instance_valid(card_node): return
	if pid == local_player_id:
		library_stack.erase(card_node)
		for c in library_stack:
			if c.has_method("setup_library"): c.setup_library()
	else:
		var opp_lib: Array = player_libraries.get(pid, [])
		opp_lib.erase(card_node)
		opp_lib.shuffle()
		EventBus.play_sfx("shuffle")

	var is_land_card := MagicRules.is_land(card_node.card_data)
	var target_parent: Node3D = self
	if pid != local_player_id and player_stations.has(pid):
		target_parent = player_stations[pid]["lands_anchor"] if is_land_card else player_stations[pid]["non_lands_anchor"]

	var gt := card_node.global_transform
	card_node.reparent(target_parent, true)
	card_node.global_transform = gt
	card_node.rotation = Vector3.ZERO
	connect_card_signals(card_node)
	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	card_node.is_on_battlefield = true
	if card_node.collision_shape: card_node.collision_shape.disabled = false

	if enter_tapped:
		if not card_node.is_tapped: card_node.toggle_tap()
	elif is_land_card:
		_apply_etb_tapped_replacement(card_node, 0)
		_apply_etb_choice_replacements(card_node, 0)

	if is_land_card: battlefield_lands.append(card_node)
	else: battlefield_non_lands.append(card_node)

	EventBus.notify_etb(card_node, "Library")
	check_and_queue_triggers("ETB", card_node)
	zone_manager.update_battlefield_positions(true)
	zone_manager.update_zone_counters()
	if pid == local_player_id:
		zone_manager.shuffle_library()
	run_state_based_actions()

func _on_tutor_card_selected(card_node: Node3D) -> void:
	if hud_manager.search_canvas and is_instance_valid(hud_manager.search_canvas):
		hud_manager.search_canvas.queue_free(); hud_manager.search_canvas = null
	library_stack.erase(card_node)
	for c in library_stack:
		if c.has_method("setup_library"): c.setup_library()
	var global_trans := card_node.global_transform
	card_node.reparent(hand_container, true)
	card_node.global_transform = global_trans
	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	connect_card_signals(card_node)
	hand_cards.append(card_node)
	zone_manager.update_hand_positions(true)
	zone_manager.update_zone_counters()
	zone_manager.shuffle_library()

func _on_card_clicked_on_battlefield(card_node: Node3D, button_index: int = MOUSE_BUTTON_LEFT) -> void:
	if hud_manager.active_target_callback.is_valid():
		hud_manager.select_target(card_node)
		return

	if turn_manager.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_BLOCKERS and button_index == MOUSE_BUTTON_LEFT:
		if combat_manager.handle_declare_blocker_click(card_node):
			return

	if button_index == MOUSE_BUTTON_RIGHT or (Input.is_key_pressed(KEY_SHIFT) and button_index == MOUSE_BUTTON_LEFT):
		hud_manager.open_activated_abilities_menu(card_node)
		return

	if not turn_manager.holds_priority() and hud_manager.targeting_attachment == null:
		return

	if hud_manager.targeting_attachment != null:
		zone_manager.attach_card_to_creature(hud_manager.targeting_attachment, card_node)
		return

	var mana_abilities := OracleParser.parse_mana_abilities(card_node.card_data, card_node)
	if not mana_abilities.is_empty():
		if card_node.is_tapped: return
		if mana_abilities.size() == 1:
			var ab: Dictionary = mana_abilities[0]
			var cols: Array = ab.get("colors", [])
			var combo: Array = ab.get("fixed_combo", [])
			var is_simple: bool = (cols.size() == 1 or not combo.is_empty()) and int(ab.get("life_cost", 0)) == 0 and str(ab.get("mana_cost", "")).is_empty() and not bool(ab.get("sac_cost", false)) and str(ab.get("restriction", "")).is_empty()
			if is_simple:
				add_mana_from_ability(card_node, ab, str(cols[0]) if not cols.is_empty() else "")
				return
		hud_manager.show_mana_ability_popup(card_node, mana_abilities)
	else:
		card_node.toggle_tap()


func start_mulligan_phase() -> void:
	mulligan_phase_active = true
	mulligan_count = 0
	mulligan_bottom_remaining = 0
	hud_manager.show_mulligan_ui()

func perform_mulligan() -> void:
	if not mulligan_phase_active: return
	mulligan_count += 1
	for c in hand_cards.duplicate():
		if is_instance_valid(c):
			hand_cards.erase(c)
			zone_manager.move_to_top_library(c)
	zone_manager.shuffle_library()
	for i in range(min(7, library_stack.size())):
		zone_manager.draw_card()
	hud_manager.update_mulligan_ui()

func confirm_keep_hand() -> void:
	if not mulligan_phase_active: return
	# Commander rules: first mulligan is free; subsequent mulligans bottom (mulligan_count - 1) cards
	var to_bottom: int = max(0, mulligan_count - 1)
	if to_bottom == 0:
		finish_mulligan_phase()
	else:
		mulligan_bottom_remaining = to_bottom
		hud_manager.update_mulligan_ui()

func finish_mulligan_phase() -> void:
	mulligan_phase_active = false
	mulligan_bottom_remaining = 0
	hud_manager.hide_mulligan_ui()
	turn_manager.set_starting_player(starting_player_id)
	turn_manager.advance_turn_phase(false)

func _on_card_played(card_node: Node3D) -> void:
	if hud_manager.active_target_callback.is_valid() and card_node in active_stack:
		hud_manager.select_target(card_node)
		return
	if mulligan_phase_active:
		if mulligan_bottom_remaining > 0 and card_node in hand_cards:
			hand_cards.erase(card_node)
			zone_manager.move_to_bottom_library(card_node)
			zone_manager.update_hand_positions(true)
			mulligan_bottom_remaining -= 1
			if mulligan_bottom_remaining <= 0:
				finish_mulligan_phase()
			else:
				hud_manager.update_mulligan_ui()
		return
	if card_node in graveyard_stack:
		hud_manager.open_zone_viewer("%s's Graveyard" % get_player_display_name(local_player_id), graveyard_stack, local_player_id)
		return
	if card_node in exile_stack:
		hud_manager.open_zone_viewer("%s's Exile" % get_player_display_name(local_player_id), exile_stack, local_player_id)
		return
	for pid in player_graveyards.keys():
		var gy_arr: Array = player_graveyards[pid]
		if card_node in gy_arr:
			hud_manager.open_zone_viewer("%s's Graveyard" % get_player_display_name(int(pid)), gy_arr, int(pid))
			return
	for pid in player_exile.keys():
		var ex_arr: Array = player_exile[pid]
		if card_node in ex_arr:
			hud_manager.open_zone_viewer("%s's Exile" % get_player_display_name(int(pid)), ex_arr, int(pid))
			return

	if not turn_manager.holds_priority(local_player_id): return

	# Multi-face chooser for MDFCs, Split cards (incl. Fuse), Rooms, and Adventures
	if MagicRules.has_multiple_faces(card_node.card_data) and (MagicRules.is_modal_dfc(card_node.card_data) or MagicRules.is_split(card_node.card_data) or MagicRules.is_room(card_node.card_data) or MagicRules.is_adventure(card_node.card_data)):
		var f0 := MagicRules.get_face_data(card_node.card_data, 0)
		var f1 := MagicRules.get_face_data(card_node.card_data, 1)
		var options: Array = [
			{"label": "%s (%s)" % [f0.get("name", "Front"), f0.get("mana_cost", "Land" if MagicRules.is_land(card_node.card_data, 0) else "")], "face_index": 0, "fuse": false},
			{"label": "%s (%s)" % [f1.get("name", "Back"), f1.get("mana_cost", "Land" if MagicRules.is_land(card_node.card_data, 1) else "")], "face_index": 1, "fuse": false}
		]
		if MagicRules.is_split(card_node.card_data) and "fuse" in MagicRules.get_card_combined_text(card_node.card_data):
			options.append({"label": "FUSE: %s + %s (%s%s)" % [f0.get("name", ""), f1.get("name", ""), f0.get("mana_cost", ""), f1.get("mana_cost", "")], "face_index": 0, "fuse": true})
		hud_manager.open_face_choice_popup(card_node, "CHOOSE SIDE TO PLAY", options, func(chosen):
			_cast_card_face(card_node, int(chosen["face_index"]), bool(chosen["fuse"]))
		)
		return

	_cast_card_face(card_node, 0, false)


func _does_mana_match_context(restriction: String, chosen_type: String, spell_context: Dictionary) -> bool:
	if restriction.is_empty(): return true
	var tl := str(spell_context.get("type_line", "")).to_lower()
	var is_act := bool(spell_context.get("is_activated", false))
	match restriction:
		"activated": return is_act
		"creature": return (not is_act) and ("creature" in tl)
		"artifact": return (not is_act) and ("artifact" in tl)
		"enchantment": return (not is_act) and ("enchantment" in tl)
		"planeswalker": return (not is_act) and ("planeswalker" in tl)
		"instant_or_sorcery": return (not is_act) and ("instant" in tl or "sorcery" in tl)
		"commander": return (not is_act) and bool(spell_context.get("is_commander", false))
		"chosen_type":
			if is_act or not ("creature" in tl): return false
			if chosen_type.is_empty(): return true
			return chosen_type.to_lower() in tl
	return true

func add_mana_from_ability(card_node: Node3D, ab: Dictionary, chosen_color: String = "") -> void:
	if not is_instance_valid(card_node): return
	var tap_cost: bool = bool(ab.get("tap_cost", true))
	if tap_cost and card_node.is_tapped: return
	var mana_cost: String = str(ab.get("mana_cost", ""))
	var life_cost: int = int(ab.get("life_cost", 0))
	var sac_cost: bool = bool(ab.get("sac_cost", false))
	var owner_id: int = get_card_owner_id(card_node)
	if life_cost > 0 and int(player_life.get(owner_id, 0)) <= life_cost:
		return
	if not mana_cost.is_empty():
		if not can_pay_and_drain_cost(mana_cost, owner_id, {"is_activated": true}):
			return
	if tap_cost and not card_node.is_tapped:
		card_node.toggle_tap()
		event_ledger.log_event(GameEventLedger.EventType.CARD_TAPPED, {"card_name": card_node.card_data.get("name", "")})
	if life_cost > 0:
		modify_life(owner_id, -life_cost)

	var fixed_combo: Array = ab.get("fixed_combo", [])
	var cols: Array = ab.get("colors", [])
	var amt: int = int(ab.get("amount", 1))
	var restriction: String = str(ab.get("restriction", ""))
	var chosen_type: String = str(ab.get("chosen_type", ""))
	var spawned_cols: Array = []

	if not fixed_combo.is_empty():
		for fc in fixed_combo:
			var c_s := str(fc)
			if restriction.is_empty():
				mana_pool[c_s] += 1
			else:
				restricted_mana.append({"color": c_s, "restriction": restriction, "chosen_type": chosen_type})
			spawned_cols.append(c_s)
	else:
		var c_pick := chosen_color if not chosen_color.is_empty() else (str(cols[0]) if not cols.is_empty() else "C")
		for _i in range(amt):
			if restriction.is_empty():
				mana_pool[c_pick] += 1
			else:
				restricted_mana.append({"color": c_pick, "restriction": restriction, "chosen_type": chosen_type})
			spawned_cols.append(c_pick)

	if not spawned_cols.is_empty():
		spawn_mana_produced_animation(card_node, spawned_cols)
	if sac_cost and is_instance_valid(card_node):
		zone_manager.move_to_graveyard(card_node)
	EventBus.notify_mana(mana_pool)

func _collect_deck_creature_types(pid: int) -> Array[String]:
	var counts := {}
	var pools: Array = []
	if pid == local_player_id:
		pools.append_array(hand_cards)
		pools.append_array(library_stack)
	else:
		pools.append_array(player_hands.get(pid, []))
		pools.append_array(player_libraries.get(pid, []))
	for c in battlefield_non_lands:
		if is_instance_valid(c) and get_card_owner_id(c) == pid: pools.append(c)
	for c in pools:
		if not is_instance_valid(c): continue
		var tl := MagicRules.get_card_type_line(c.card_data)
		if "—" in tl and "creature" in tl.to_lower():
			var sub_part := tl.split("—")[1].strip_edges()
			for t in sub_part.split(" "):
				var clean_t := t.strip_edges()
				if not clean_t.is_empty():
					counts[clean_t] = int(counts.get(clean_t, 0)) + 1
	var sorted_types: Array[String] = []
	for k in counts.keys(): sorted_types.append(str(k))
	sorted_types.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	for common in ["Human", "Elf", "Goblin", "Zombie", "Wizard", "Dragon", "Soldier", "Spirit", "Vampire", "Angel", "Warrior", "Beast"]:
		if not (common in sorted_types): sorted_types.append(common)
	return sorted_types

func _apply_etb_choice_replacements(card_node: Node3D, face_index: int = 0) -> void:
	if not is_instance_valid(card_node): return
	var oracle_lower := str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", face_index)).to_lower()
	var owner_id: int = get_card_owner_id(card_node)
	if "enters" in oracle_lower and "choose a creature type" in oracle_lower:
		var types := _collect_deck_creature_types(owner_id)
		if owner_id == local_player_id and hud_manager and hud_manager.has_method("open_etb_creature_type_popup"):
			hud_manager.open_etb_creature_type_popup(card_node, types, func(chosen_t: String):
				if is_instance_valid(card_node):
					card_node.set_meta("chosen_creature_type", chosen_t)
			)
		elif not types.is_empty():
			card_node.set_meta("chosen_creature_type", types[0])
	if "enters" in oracle_lower and "choose a color" in oracle_lower:
		if owner_id == local_player_id and hud_manager and hud_manager.has_method("open_choice_popup"):
			hud_manager.open_choice_popup("CHOOSE A COLOR (%s)" % str(card_node.card_data.get("name", "Card")).to_upper(), ["White (W)", "Blue (U)", "Black (B)", "Red (R)", "Green (G)"], func(idx: int):
				var cols := ["W", "U", "B", "R", "G"]
				if is_instance_valid(card_node) and idx >= 0 and idx < cols.size():
					card_node.set_meta("chosen_color", cols[idx])
			)
		else:
			card_node.set_meta("chosen_color", "W")

func _apply_etb_tapped_replacement(card_node: Node3D, face_index: int = 0) -> void:
	var oracle_text := str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", face_index))
	var parsed := OracleParser.parse_oracle_text(oracle_text)
	var etb_info: Dictionary = parsed.get("etb_tapped", {})
	var mode: String = str(etb_info.get("mode", "none"))
	var owner_id: int = get_card_owner_id(card_node)

	match mode:
		"always":
			card_node.is_tapped = true
		"unless":
			var cond: String = str(etb_info.get("condition", ""))
			card_node.is_tapped = not AbilityResolver.evaluate_condition(cond, card_node, self, owner_id)
		"shock_pay_life":
			var life_cost: int = int(etb_info.get("pay_life", 2))
			card_node.is_tapped = true
			if owner_id == local_player_id and int(player_life.get(owner_id, 0)) > life_cost:
				var c_id := card_node.get_instance_id()
				hud_manager.open_choice_popup(
					"%s — ENTER UNTAPPED?" % str(card_node.card_data.get("name", "Land")).to_upper(),
					["Pay %d Life (Enter Untapped)" % life_cost, "Enter Tapped"],
					func(choice_idx: int):
						var c_ref := instance_from_id(c_id) as Node3D
						if choice_idx == 0 and c_ref and is_instance_valid(c_ref):
							c_ref.is_tapped = false
							modify_life(owner_id, -life_cost)
							zone_manager.update_battlefield_positions(true)
				)
		_:
			card_node.is_tapped = false

func cast_revealed_spell_immediately(card_node: Node3D, caster_id: int, without_paying_mana: bool = true) -> void:
	if not card_node or not is_instance_valid(card_node): return
	# Resolution-time casts (Cascade, Discover, impulse-cast) bypass sorcery-speed timing (CR 608.2g)
	if card_node.has_method("make_active"): card_node.make_active(card_node.card_data)
	connect_card_signals(card_node)
	card_node.set_meta("owner_id", caster_id)
	if without_paying_mana:
		var ol := str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "")).to_lower()
		if "target" in ol:
			var req := OracleParser.extract_target_requirement(ol)
			if caster_id != local_player_id:
				var tgt = ai_controller.pick_ai_target(caster_id, ol)
				if tgt == null: return
				card_node.set_meta("chosen_target", tgt)
				card_node.set_meta("target_requirement", req)
				zone_manager.move_to_stack(card_node)
			else:
				hud_manager.start_generic_targeting("SELECT TARGET FOR %s" % str(card_node.card_data.get("name", "SPELL")), func(chosen_tgt):
					card_node.set_meta("chosen_target", chosen_tgt)
					card_node.set_meta("target_requirement", req)
					zone_manager.move_to_stack(card_node)
				, req, card_node)
		else:
			zone_manager.move_to_stack(card_node)
	else:
		_cast_card_face(card_node, 0, false)

func _cast_card_face(card_node: Node3D, face_index: int, is_fuse: bool) -> void:
	card_node.active_face_index = face_index
	card_node.is_fused_cast = is_fuse
	if card_node.has_method("_apply_face_texture"): card_node._apply_face_texture()
	if card_node.has_method("refresh_visual_status"): card_node.refresh_visual_status()

	var type_line := MagicRules.get_card_type_line(card_node.card_data, face_index).to_lower()
	var oracle_lower := str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", face_index)).to_lower()
	var is_land := "land" in type_line
	var is_instant := MagicRules.can_cast_at_instant_speed(card_node.card_data, face_index, local_player_id, self)

	if is_land:
		if not turn_manager.can_act_sorcery_speed(local_player_id) or land_played_this_turn: return
		land_played_this_turn = true
		graveyard_stack.erase(card_node); exile_stack.erase(card_node); hand_cards.erase(card_node)
		zone_manager.update_hand_positions(true)

		var global_trans := card_node.global_transform
		card_node.reparent(self, true)
		card_node.global_transform = global_trans
		connect_card_signals(card_node)
		card_node.is_on_battlefield = true
		if card_node.collision_shape: card_node.collision_shape.disabled = false
		_apply_etb_tapped_replacement(card_node, face_index)
		_apply_etb_choice_replacements(card_node, face_index)

		battlefield_lands.append(card_node)
		EventBus.notify_etb(card_node, "Hand")
		check_and_queue_triggers("ETB", card_node)
		zone_manager.update_battlefield_positions(true)
		run_state_based_actions()
	else:
		if not is_instant and not turn_manager.can_act_sorcery_speed(local_player_id): return
		if is_instant and not turn_manager.holds_priority(local_player_id): return
		var mana_cost := ""
		if is_fuse and MagicRules.has_multiple_faces(card_node.card_data):
			mana_cost = str(MagicRules.get_card_attribute(card_node.card_data, "mana_cost", "", 0)) + str(MagicRules.get_card_attribute(card_node.card_data, "mana_cost", "", 1))
		elif card_node in command_zone_cards:
			mana_cost = get_taxed_mana_cost(card_node)
		else:
			mana_cost = str(MagicRules.get_card_attribute(card_node.card_data, "mana_cost", "", face_index))

		var parsed_face: Dictionary = OracleParser.parse_oracle_text(str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", face_index)))
		var face_name := str(MagicRules.get_card_attribute(card_node.card_data, "name", "SPELL", face_index))
		var modal_info: Dictionary = parsed_face.get("modal", {})
		var add_cost: Dictionary = parsed_face.get("additional_cost", {})

		var step_pay_and_push = func(raw_mana_cost: String, sac_node: Node3D, add_discard_amt: int, add_life_amt: int):
			if not is_instant and not turn_manager.can_act_sorcery_speed(local_player_id): return
			var red := ContinuousEffectsEngine.get_cost_reduction(card_node.card_data, local_player_id, battlefield_lands, battlefield_non_lands)
			var final_mana_cost := ContinuousEffectsEngine.apply_cost_reduction(raw_mana_cost, red)
			if add_life_amt > 0 and int(player_life.get(local_player_id, 0)) <= add_life_amt:
				return
			if not can_pay_and_drain_cost(final_mana_cost, local_player_id, {"type_line": type_line, "is_commander": card_node in command_zone_cards, "is_activated": false}):
				if card_node.has_meta("chosen_target"): card_node.remove_meta("chosen_target")
				return
			if sac_node != null and is_instance_valid(sac_node):
				zone_manager.move_to_graveyard(sac_node)
			if add_life_amt > 0:
				modify_life(local_player_id, -add_life_amt)
			if card_node in command_zone_cards:
				commander_cast_counts[card_node] = int(commander_cast_counts.get(card_node, 0)) + 1
				zone_manager.update_commander_tax_counter()
			exile_stack.erase(card_node)
			zone_manager.move_to_stack(card_node)
			if add_discard_amt > 0:
				hud_manager.open_discard_choice(add_discard_amt)

		var step_targeting = func(final_mana_cost: String, effect_scope_lower: String, sac_node: Node3D, add_discard_amt: int, add_life_amt: int):
			var is_aura_spell := MagicRules.is_aura(card_node.card_data, face_index)
			var is_inst_or_sorc := ("instant" in type_line or "sorcery" in type_line)
			var needs_spell_target := is_aura_spell or (is_inst_or_sorc and ("target" in effect_scope_lower or (is_fuse and "target" in str(MagicRules.get_card_attribute(card_node.card_data, "oracle_text", "", 1)).to_lower())))
			if needs_spell_target:
				var req: String = str(card_node.parsed_abilities.get("enchant_target", "creature")) if is_aura_spell else OracleParser.extract_target_requirement(effect_scope_lower)
				hud_manager.start_generic_targeting("SELECT TARGET (%s) FOR %s" % [req.to_upper() if not req.is_empty() else "ANY", face_name], func(chosen_target):
					card_node.set_meta("chosen_target", chosen_target)
					card_node.set_meta("target_requirement", req)
					step_pay_and_push.call(final_mana_cost, sac_node, add_discard_amt, add_life_amt)
				, req, card_node)
			else:
				step_pay_and_push.call(final_mana_cost, sac_node, add_discard_amt, add_life_amt)

		var step_additional_cost = func(final_mana_cost: String, effect_scope_lower: String):
			var ac_type := str(add_cost.get("type", ""))
			var ac_tgt := str(add_cost.get("target", ""))
			var ac_amt := int(add_cost.get("amount", 0))
			if ac_type == "sacrifice":
				var sac_req := "%s you control" % ac_tgt
				var has_sac := false
				for p in battlefield_lands + battlefield_non_lands:
					if MagicRules.is_legal_target(p, sac_req, local_player_id, card_node):
						has_sac = true; break
				if not has_sac: return
				hud_manager.start_generic_targeting("SACRIFICE A %s (Additional Cost)" % ac_tgt.to_upper(), func(sac_target):
					step_targeting.call(final_mana_cost, effect_scope_lower, sac_target, 0, 0)
				, sac_req, card_node)
			elif ac_type == "discard":
				var avail_hand := hand_cards.size() - (1 if card_node in hand_cards else 0)
				if avail_hand < ac_amt: return
				step_targeting.call(final_mana_cost, effect_scope_lower, null, ac_amt, 0)
			elif ac_type == "pay_life":
				step_targeting.call(final_mana_cost, effect_scope_lower, null, 0, ac_amt)
			else:
				step_targeting.call(final_mana_cost, effect_scope_lower, null, 0, 0)

		var step_x_cost = func(effect_scope_lower: String):
			var x_count := OracleParser.count_x_in_mana_cost(mana_cost)
			if x_count > 0:
				var max_x := get_max_available_x(mana_cost, local_player_id)
				hud_manager.open_x_stepper_popup(face_name, mana_cost, max_x, func(chosen_x: int):
					card_node.set_meta("chosen_x", chosen_x)
					var resolved_cost := mana_cost.replace("{X}", "").replace("{x}", "")
					if chosen_x * x_count > 0:
						resolved_cost = "{%d}%s" % [chosen_x * x_count, resolved_cost]
					step_additional_cost.call(resolved_cost, effect_scope_lower)
				)
			else:
				step_additional_cost.call(mana_cost, effect_scope_lower)

		var modes_arr: Array = modal_info.get("modes", [])
		var modal_cnt: int = int(modal_info.get("count", 0))
		if modal_cnt > 0 and not modes_arr.is_empty():
			hud_manager.open_modal_choice_popup(face_name, modal_cnt, bool(modal_info.get("allow_repeat", false)), modes_arr, func(chosen_modal_text: String):
				card_node.set_meta("chosen_modal_text", chosen_modal_text)
				step_x_cost.call(chosen_modal_text.to_lower())
			)
		else:
			step_x_cost.call(oracle_lower)

# --- MANA PAYMENT & TOKENS ---

func get_max_available_x(mana_cost_str: String, payer_id: int = local_player_id) -> int:
	var x_count := maxi(1, OracleParser.count_x_in_mana_cost(mana_cost_str))
	var non_x_cost := 0
	for result in MANA_COST_REGEX.search_all(mana_cost_str):
		var sym := result.get_string(1).to_upper()
		if sym == "X": continue
		if sym.is_valid_int(): non_x_cost += sym.to_int()
		else: non_x_cost += 1
	var total_avail := 0
	if payer_id == local_player_id:
		for c in mana_pool.keys(): total_avail += int(mana_pool[c])
	for card in battlefield_lands + battlefield_non_lands:
		if not is_instance_valid(card) or card.is_tapped: continue
		if get_card_owner_id(card) != payer_id: continue
		var tl := MagicRules.get_card_type_line(card.card_data).to_lower()
		var has_haste: bool = card.has_method("has_keyword") and bool(card.has_keyword("haste"))
		if "creature" in tl and card.has_summoning_sickness and not has_haste: continue
		var o_up := str(MagicRules.get_card_attribute(card.card_data, "oracle_text", "")).to_upper()
		if "land" in tl or "{T}: ADD" in o_up or "ADD ONE MANA" in o_up:
			total_avail += 1
	return maxi(0, (total_avail - non_x_cost) / x_count)

func can_pay_and_drain_cost(mana_cost_str: String, payer_id: int = local_player_id, spell_context: Dictionary = {}) -> bool:
	if mana_cost_str.is_empty() or mana_cost_str == "{}" or mana_cost_str == "0": return true

	var colored_required := {"W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0}
	var generic_required := 0
	var hybrid_requirements := []

	for result in MANA_COST_REGEX.search_all(mana_cost_str):
		var symbol := result.get_string(1).to_upper()
		if symbol.is_valid_int():
			generic_required += symbol.to_int()
		elif "/" in symbol:
			var options := []
			for part in symbol.split("/"):
				part = part.strip_edges()
				if part.is_valid_int(): generic_required += part.to_int()
				elif part in colored_required: options.append(part)
			if not options.is_empty(): hybrid_requirements.append(options)
		elif symbol in colored_required:
			colored_required[symbol] += 1

	var active_pool: Dictionary = mana_pool if payer_id == local_player_id else {"W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0}
	var temp_pool := active_pool.duplicate()
	var used_restricted_indices: Array[int] = []

	# First try matching restricted mana in pool for colored/colorless requirements
	var missing_colored := colored_required.duplicate()
	if payer_id == local_player_id:
		for ri in range(restricted_mana.size()):
			var rm: Dictionary = restricted_mana[ri]
			if not _does_mana_match_context(str(rm.get("restriction", "")), str(rm.get("chosen_type", "")), spell_context):
				continue
			var rcol: String = str(rm.get("color", "C"))
			if int(missing_colored.get(rcol, 0)) > 0:
				missing_colored[rcol] -= 1
				used_restricted_indices.append(ri)

	for color in missing_colored.keys():
		var available: int = min(int(missing_colored[color]), int(temp_pool[color]))
		missing_colored[color] -= available
		temp_pool[color] -= available

	var missing_hybrid := []
	for options in hybrid_requirements:
		var paid := false
		if payer_id == local_player_id:
			for ri in range(restricted_mana.size()):
				if ri in used_restricted_indices: continue
				var rm: Dictionary = restricted_mana[ri]
				if not _does_mana_match_context(str(rm.get("restriction", "")), str(rm.get("chosen_type", "")), spell_context): continue
				if str(rm.get("color", "")) in options:
					used_restricted_indices.append(ri); paid = true; break
		if not paid:
			for opt in options:
				if temp_pool[opt] > 0:
					temp_pool[opt] -= 1; paid = true; break
		if not paid: missing_hybrid.append(options)

	var remaining_generic := generic_required
	if payer_id == local_player_id:
		for ri in range(restricted_mana.size()):
			if remaining_generic <= 0: break
			if ri in used_restricted_indices: continue
			var rm: Dictionary = restricted_mana[ri]
			if _does_mana_match_context(str(rm.get("restriction", "")), str(rm.get("chosen_type", "")), spell_context):
				used_restricted_indices.append(ri)
				remaining_generic -= 1

	var total_temp_remaining := 0
	for color in temp_pool.keys(): total_temp_remaining += int(temp_pool[color])

	var missing_generic: int = remaining_generic - int(min(remaining_generic, total_temp_remaining))
	var total_missing: int = missing_hybrid.size() + missing_generic
	for color in missing_colored.keys(): total_missing += int(missing_colored[color])

	var cards_to_tap: Array[Node3D] = []
	var tapped_card_colors := {}
	var generated_mana_to_add := {"W": 0, "U": 0, "B": 0, "R": 0, "G": 0, "C": 0}
	var total_life_cost := 0

	if total_missing > 0:
		var available_options := []
		var cur_life: int = int(player_life.get(payer_id, 40))
		for card in battlefield_lands + battlefield_non_lands:
			if not is_instance_valid(card) or card.is_tapped: continue
			if get_card_controller_id(card) != payer_id: continue
			var type_line := MagicRules.get_card_type_line(card.card_data).to_lower()
			var has_haste: bool = card.has_method("has_keyword") and bool(card.has_keyword("haste"))
			if "creature" in type_line and card.has_summoning_sickness and not has_haste: continue
			for ab in OracleParser.parse_mana_abilities(card.card_data, card):
				if bool(ab.get("sac_cost", false)): continue
				if not str(ab.get("mana_cost", "")).is_empty(): continue
				var l_cost: int = int(ab.get("life_cost", 0))
				if l_cost >= cur_life: continue
				if not _does_mana_match_context(str(ab.get("restriction", "")), str(ab.get("chosen_type", "")), spell_context):
					continue
				var score: int = l_cost * 100 + ab.get("colors", []).size() * 10
				if not str(ab.get("restriction", "")).is_empty(): score -= 5
				available_options.append({"card": card, "ab": ab, "colors": ab.get("colors", []), "score": score})

		available_options.sort_custom(func(a, b): return int(a["score"]) < int(b["score"]))

		var consume_source = func(valid_colors: Array) -> bool:
			for i in range(available_options.size()):
				var opt_d: Dictionary = available_options[i]
				var src_card: Node3D = opt_d["card"]
				if src_card in cards_to_tap: continue
				var ab: Dictionary = opt_d["ab"]
				var ab_cols: Array = opt_d["colors"]
				var chosen_color := ""
				if valid_colors.is_empty(): chosen_color = str(ab_cols[0])
				else:
					for c in valid_colors:
						if c in ab_cols: chosen_color = c; break
				if not chosen_color.is_empty():
					var l_c: int = int(ab.get("life_cost", 0))
					if total_life_cost + l_c >= cur_life: continue
					total_life_cost += l_c
					cards_to_tap.append(src_card)
					var combo: Array = ab.get("fixed_combo", [])
					var amt: int = int(ab.get("amount", 1))
					if not combo.is_empty():
						tapped_card_colors[src_card] = combo.duplicate()
						for fc in combo: generated_mana_to_add[str(fc)] += 1
					else:
						tapped_card_colors[src_card] = [chosen_color]
						generated_mana_to_add[chosen_color] += amt
					return true
			return false

		for color in missing_colored.keys():
			while missing_colored[color] > 0:
				if generated_mana_to_add[color] > colored_required[color] and int(temp_pool[color]) + generated_mana_to_add[color] > colored_required[color]:
					missing_colored[color] -= 1
				elif consume_source.call([color]):
					missing_colored[color] -= 1
				else: return false
		for options in missing_hybrid:
			if not consume_source.call(options): return false
		var any_colors := ["C", "W", "U", "B", "R", "G"]
		while missing_generic > 0:
			# Check if excess multi-mana from an already-tapped source (like Sol Ring) covers it
			var surplus := 0
			for c in generated_mana_to_add.keys():
				surplus += maxi(0, generated_mana_to_add[c] - colored_required[c])
			if surplus >= missing_generic:
				missing_generic = 0
				break
			if consume_source.call(any_colors): missing_generic -= 1
			else: return false

	# Commit payments
	if payer_id == local_player_id and not used_restricted_indices.is_empty():
		used_restricted_indices.sort()
		used_restricted_indices.reverse()
		for ri in used_restricted_indices:
			if ri >= 0 and ri < restricted_mana.size():
				restricted_mana.remove_at(ri)

	for card in cards_to_tap:
		card.toggle_tap()
		if tapped_card_colors.has(card): spawn_mana_produced_animation(card, tapped_card_colors[card])
	if total_life_cost > 0:
		modify_life(payer_id, -total_life_cost)
	for color in generated_mana_to_add.keys(): active_pool[color] += generated_mana_to_add[color]
	if not cards_to_tap.is_empty(): zone_manager.update_battlefield_positions(true)

	# Drain remaining colored/hybrid/generic from active_pool (restricted already accounted for above)
	for color in colored_required:
		var need: int = mini(int(colored_required[color]), int(active_pool[color]))
		active_pool[color] -= need
	for options in hybrid_requirements:
		for opt in options:
			if active_pool[opt] > 0: active_pool[opt] -= 1; break
	var remaining_to_pay := remaining_generic
	for color in ["C", "W", "U", "B", "R", "G"]:
		while remaining_to_pay > 0 and active_pool[color] > 0:
			active_pool[color] -= 1; remaining_to_pay -= 1

	if payer_id == local_player_id:
		EventBus.notify_mana(mana_pool)
	return true

func spawn_mana_produced_animation(card_node: Variant, colors: Array) -> void:
	var unique_colors := []
	for c in colors:
		if not c in unique_colors: unique_colors.append(c)
	var total := unique_colors.size()
	for i in range(total):
		var c: String = unique_colors[i]
		if not MANA_ICONS.has(c): continue
		var tex: Texture2D = load(MANA_ICONS[c])
		if not tex: continue

		var sprite := Sprite3D.new()
		sprite.texture = tex
		sprite.pixel_size = 0.0006
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.transparent = true; sprite.no_depth_test = true
		add_child(sprite)
		if card_node is Node3D and is_instance_valid(card_node): sprite.global_transform = card_node.global_transform
		elif card_node is Vector3: sprite.global_position = card_node
		else: sprite.global_position = central_stack_anchor.global_position
		sprite.position.y += 0.25
		if total > 1: sprite.position.x += (float(i) - float(total - 1) / 2.0) * 0.15

		var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(sprite, "position:y", sprite.position.y + 0.8, 1.2)
		tween.tween_property(sprite, "modulate:a", 0.0, 1.2)
		tween.chain().tween_callback(func(): sprite.queue_free())

func _spawn_new_token(token_data: Dictionary) -> void:
	EventBus.play_sfx("token")
	var token: Node3D = _instantiate_card()
	token.card_data = token_data.duplicate(true)
	token.set_meta("owner_id", turn_manager.active_player_id)
	connect_card_signals(token)
	add_child(token)

	token.position = central_stack_anchor.position + Vector3(0, 0.5, 0)
	token.rotation = Vector3.ZERO
	token.is_on_battlefield = true
	if token.has_method("mark_as_token"): token.mark_as_token()
	if token.has_method("setup"): token.setup(token.card_data)

	var token_id := token.get_instance_id()
	var http := HTTPRequest.new()
	add_child(http)
	var http_id := http.get_instance_id()
	http.request_completed.connect(func(_result, response_code, _headers, body):
		var req_node := instance_from_id(http_id)
		if req_node and is_instance_valid(req_node): req_node.queue_free()
		var token_ref := instance_from_id(token_id) as Node3D
		if token_ref == null or not is_instance_valid(token_ref): return
		if response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data: Dictionary = json.get_data()
				if data.get("data") is Array and not data["data"].is_empty():
					var scry: Dictionary = data["data"][0]
					var face_data: Dictionary = scry["card_faces"][0] if (scry.get("card_faces") is Array and not scry["card_faces"].is_empty()) else scry
					var uris: Dictionary = face_data.get("image_uris", scry.get("image_uris", {}))
					var img_url: String = uris.get("normal", uris.get("small", ""))
					if not img_url.is_empty(): token_ref.card_data["image_url"] = img_url
					if face_data.has("oracle_text") and str(token_ref.card_data.get("oracle_text", "")).is_empty():
						token_ref.card_data["oracle_text"] = str(face_data["oracle_text"])
					if str(token_ref.card_data.get("type_line", "")) == "Token" and face_data.has("type_line"):
						token_ref.card_data["type_line"] = str(face_data["type_line"])
					if face_data.has("power"): token_ref.card_data["power"] = str(face_data["power"])
					if face_data.has("toughness"): token_ref.card_data["toughness"] = str(face_data["toughness"])
					if token_ref.has_method("setup"): token_ref.setup(token_ref.card_data)
					run_state_based_actions()
	)

	var search_url: String = "https://api.scryfall.com/cards/search?q=" + String(token_data.get("query", "")).uri_encode()
	http.request(search_url, ["User-Agent: MTGBrawlSim/1.0", "Accept: */*"])

	var type_line: String = String(token_data.get("type_line", "")).to_lower()
	if "land" in type_line: battlefield_lands.append(token)
	else: battlefield_non_lands.append(token)
	EventBus.notify_etb(token, "TokenSpawner")
	check_and_queue_triggers("ETB", token)
	zone_manager.update_battlefield_positions(true)
	run_state_based_actions()

func spawn_token_copy(original_card: Node3D) -> void:
	EventBus.play_sfx("token")
	var token: Node3D = _instantiate_card()
	token.card_data = original_card.card_data.duplicate(true)
	token.set_meta("owner_id", get_card_owner_id(original_card))
	connect_card_signals(token)
	add_child(token)
	if "stored_front_texture" in original_card and original_card.stored_front_texture:
		token.stored_front_texture = original_card.stored_front_texture
	token.global_transform = original_card.global_transform
	if token.has_method("mark_as_token"): token.mark_as_token()
	if token.has_method("setup"): token.setup(token.card_data)
	token.is_on_battlefield = true; token.is_tapped = original_card.is_tapped

	var type_line := MagicRules.get_card_type_line(token.card_data).to_lower()
	if "land" in type_line: battlefield_lands.append(token)
	else: battlefield_non_lands.append(token)
	EventBus.notify_etb(token, "Copy")
	check_and_queue_triggers("ETB", token)
	zone_manager.update_battlefield_positions(true)
	run_state_based_actions()

func is_modal_ui_open() -> bool:
	if hud_manager:
		if hud_manager.search_canvas and is_instance_valid(hud_manager.search_canvas): return true
		if hud_manager.settings_canvas and is_instance_valid(hud_manager.settings_canvas): return true
		if hud_manager.match_log_canvas and is_instance_valid(hud_manager.match_log_canvas): return true
		if hud_manager.controller_help_canvas and is_instance_valid(hud_manager.controller_help_canvas): return true
		if hud_manager.tracker_canvas and is_instance_valid(hud_manager.tracker_canvas): return true
	for n_name in ["DeckSelectorUI", "ActivatedAbilitiesUI", "XStepperUI", "ModalChoiceUI", "ScrySurveilUI", "ManaPopupUI", "GenericChoiceUI", "FaceChoiceUI"]:
		var n := get_node_or_null(n_name)
		if n and is_instance_valid(n): return true
	return false

func _find_visible_scroll_container(root: Node) -> ScrollContainer:
	if root is ScrollContainer and (root as ScrollContainer).is_visible_in_tree():
		return root as ScrollContainer
	for ch in root.get_children():
		var found := _find_visible_scroll_container(ch)
		if found != null: return found
	return null

func _update_controller_cursor(delta: float) -> void:
	if Input.get_connected_joypads().is_empty(): return
	var lx: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly: float = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if _popup_nav_cooldown > 0.0:
		_popup_nav_cooldown -= delta
	var open_popup := _find_visible_popup_menu(get_tree().root)
	if open_popup != null and open_popup.item_count > 0:
		if absf(ly) > 0.45 and _popup_nav_cooldown <= 0.0:
			var cur_idx: int = open_popup.get_focused_item()
			if cur_idx < 0:
				var ob := open_popup.get_parent() as OptionButton
				cur_idx = ob.selected if (ob and ob.selected >= 0) else 0
			var step: int = 1 if ly > 0.0 else -1
			var next_idx: int = (cur_idx + step + open_popup.item_count) % open_popup.item_count
			open_popup.set_focused_item(next_idx)
			_popup_nav_cooldown = 0.18
		return
	var stick_vec := Vector2(lx, ly)
	if stick_vec.length() > 0.18:
		var vp := get_viewport()
		var cur := vp.get_mouse_position()
		var vp_size := vp.get_visible_rect().size
		var next_pos := (cur + stick_vec * controller_cursor_speed * delta).clamp(Vector2.ZERO, vp_size)
		vp.warp_mouse(next_pos)

		# Sync 3D card hover when cursor is over the 3D tabletop (not a UI panel)
		if vp.gui_get_hovered_control() == null:
			var hit_obj := _raycast_3d_at_screen_pos(next_pos)
			var hit_card := _find_card_node_from_collider(hit_obj)
			if hit_card != hovered_card:
				if hovered_card != null and is_instance_valid(hovered_card):
					_on_card_unhovered(hovered_card)
				if hit_card != null:
					_on_card_hovered(hit_card)

	if is_modal_ui_open():
		var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
		if absf(ry) > 0.18:
			var sc := _find_visible_scroll_container(self)
			if sc != null:
				sc.scroll_vertical += int(ry * 750.0 * delta)

func _raycast_3d_at_screen_pos(screen_pos: Vector2) -> Object:
	var cam := $Camera3D as Camera3D
	if not cam: return null
	var world := cam.get_world_3d()
	if not world: return null
	var origin := cam.project_ray_origin(screen_pos)
	var target := origin + cam.project_ray_normal(screen_pos) * 120.0
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty(): return null
	return result.get("collider", null)

func _find_card_node_from_collider(obj: Object) -> Node3D:
	var cur: Node = obj as Node
	while cur != null:
		if cur.has_method("get_active_oracle_text"):
			return cur as Node3D
		cur = cur.get_parent()
	return null

func _synthesize_mouse_left_click() -> void:
	var pos := get_viewport().get_mouse_position()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	call_deferred("_synthesize_mouse_left_release", pos)

func _synthesize_mouse_left_release(pos: Vector2) -> void:
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)

func _find_visible_popup_menu(root: Node) -> PopupMenu:
	for ch in root.get_children():
		if ch is PopupMenu and (ch as PopupMenu).visible:
			return ch as PopupMenu
		var found := _find_visible_popup_menu(ch)
		if found != null:
			return found
	return null

func _activate_ui_control(ctrl: Control) -> bool:
	if ctrl == null or not is_instance_valid(ctrl): return false
	if ctrl is OptionButton:
		var ob := ctrl as OptionButton
		if not ob.disabled:
			ob.show_popup()
			return true
	if ctrl is CheckBox or ctrl is CheckButton:
		var cb := ctrl as BaseButton
		if not cb.disabled:
			cb.button_pressed = not cb.button_pressed
			cb.emit_signal("toggled", cb.button_pressed)
			cb.emit_signal("pressed")
			return true
	if ctrl is BaseButton:
		var bb := ctrl as BaseButton
		if not bb.disabled:
			bb.emit_signal("pressed")
			return true
	return false

func _handle_joypad_button(btn_idx: int) -> void:
	var vp := get_viewport()
	match btn_idx:
		JOY_BUTTON_BACK:
			hud_manager.toggle_controller_help()
			vp.set_input_as_handled()
		JOY_BUTTON_Y:
			if hud_manager.phase_ui_label:
				turn_manager.request_primary_action()
				vp.set_input_as_handled()
		JOY_BUTTON_B:
			var open_popup := _find_visible_popup_menu(get_tree().root)
			if open_popup != null:
				open_popup.hide()
				vp.set_input_as_handled()
				return
			if hud_manager.settings_canvas and is_instance_valid(hud_manager.settings_canvas):
				hud_manager.toggle_settings_menu()
				vp.set_input_as_handled()
				return
			if hud_manager.tracker_canvas and is_instance_valid(hud_manager.tracker_canvas):
				hud_manager.toggle_table_trackers()
				vp.set_input_as_handled()
				return
			if hud_manager.match_log_canvas and is_instance_valid(hud_manager.match_log_canvas):
				hud_manager.toggle_match_log()
				vp.set_input_as_handled()
				return
			if hud_manager.controller_help_canvas and is_instance_valid(hud_manager.controller_help_canvas):
				hud_manager.toggle_controller_help()
				vp.set_input_as_handled()
				return
			var act_popup := get_node_or_null("ActivatedAbilitiesUI")
			if act_popup:
				act_popup.queue_free()
			elif hud_manager.search_canvas and hud_manager.search_canvas.is_inside_tree():
				hud_manager.search_canvas.queue_free(); hud_manager.search_canvas = null
			elif hud_manager.targeting_attachment != null or hud_manager.active_target_callback.is_valid():
				hud_manager.cancel_attachment_targeting()
			elif combat_manager.selected_blocker != null:
				if is_instance_valid(combat_manager.selected_blocker) and combat_manager.selected_blocker.has_method("set_highlight"):
					combat_manager.selected_blocker.set_highlight(false)
				combat_manager.selected_blocker = null
			vp.set_input_as_handled()
		JOY_BUTTON_A:
			var open_popup := _find_visible_popup_menu(get_tree().root)
			if open_popup != null:
				var p_idx: int = open_popup.get_focused_item()
				if p_idx < 0 and open_popup.item_count > 0:
					var mp: Vector2 = open_popup.get_mouse_position()
					var row_h: float = maxf(1.0, float(open_popup.size.y) / float(open_popup.item_count))
					p_idx = clampi(int(mp.y / row_h), 0, open_popup.item_count - 1)
				if p_idx >= 0 and p_idx < open_popup.item_count:
					var item_id: int = open_popup.get_item_id(p_idx)
					open_popup.index_pressed.emit(p_idx)
					open_popup.id_pressed.emit(item_id)
					open_popup.hide()
				vp.set_input_as_handled()
				return
			var hovered_ctrl := vp.gui_get_hovered_control()
			if _activate_ui_control(hovered_ctrl):
				vp.set_input_as_handled()
				return
			if hovered_ctrl != null:
				_synthesize_mouse_left_click()
				vp.set_input_as_handled()
				return
			var hit_obj := _raycast_3d_at_screen_pos(vp.get_mouse_position())
			var target_card := hovered_card if (hovered_card != null and is_instance_valid(hovered_card)) else _find_card_node_from_collider(hit_obj)
			if target_card != null and is_instance_valid(target_card):
				if target_card.is_on_battlefield:
					_on_card_clicked_on_battlefield(target_card, MOUSE_BUTTON_LEFT)
				else:
					_on_card_played(target_card)
			elif hit_obj is Node and (hit_obj as Node).has_meta("zone_kind"):
				var zn := hit_obj as Node
				var pid: int = int(zn.get_meta("zone_pid"))
				var zkind: String = str(zn.get_meta("zone_kind"))
				if zkind == "graveyard":
					var cards: Array = graveyard_stack if pid == local_player_id else player_graveyards.get(pid, [])
					hud_manager.open_zone_viewer("%s's Graveyard" % get_player_display_name(pid), cards, pid)
				else:
					var cards: Array = exile_stack if pid == local_player_id else player_exile.get(pid, [])
					hud_manager.open_zone_viewer("%s's Exile" % get_player_display_name(pid), cards, pid)
			else:
				_synthesize_mouse_left_click()
			vp.set_input_as_handled()
		JOY_BUTTON_X:
			var target_card := hovered_card if (hovered_card != null and is_instance_valid(hovered_card)) else _find_card_node_from_collider(_raycast_3d_at_screen_pos(vp.get_mouse_position()))
			if target_card != null and is_instance_valid(target_card) and target_card.is_on_battlefield:
				if turn_manager.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS and turn_manager.is_local_player_turn() and get_card_owner_id(target_card) == local_player_id:
					combat_manager.handle_declare_attacker_key(target_card, false)
				else:
					hud_manager.open_activated_abilities_menu(target_card)
				vp.set_input_as_handled()
		JOY_BUTTON_LEFT_SHOULDER:
			if turn_manager.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS and turn_manager.is_local_player_turn():
				var target_card := hovered_card if (hovered_card != null and is_instance_valid(hovered_card)) else _find_card_node_from_collider(_raycast_3d_at_screen_pos(vp.get_mouse_position()))
				if target_card != null and is_instance_valid(target_card) and target_card.is_on_battlefield and get_card_owner_id(target_card) == local_player_id:
					combat_manager.handle_declare_attacker_key(target_card, true)
				else:
					for c in battlefield_non_lands:
						if is_instance_valid(c) and bool(c.get("is_attacking")) and get_card_owner_id(c) == local_player_id:
							combat_manager.handle_declare_attacker_key(c, true)
			elif hud_manager.search_canvas and hud_manager.search_canvas.is_inside_tree():
				hud_manager.search_canvas.queue_free(); hud_manager.search_canvas = null
			else:
				hud_manager.open_zone_viewer("%s's Graveyard" % get_player_display_name(local_player_id), graveyard_stack, local_player_id)
			vp.set_input_as_handled()
		JOY_BUTTON_RIGHT_SHOULDER:
			if turn_manager.current_turn_phase == TurnManager.TurnPhase.COMBAT_DECLARE_ATTACKERS and turn_manager.is_local_player_turn():
				combat_manager.cycle_next_attacker()
			elif hud_manager.search_canvas and hud_manager.search_canvas.is_inside_tree():
				hud_manager.search_canvas.queue_free(); hud_manager.search_canvas = null
			else:
				hud_manager.open_zone_viewer("%s's Exile" % get_player_display_name(local_player_id), exile_stack, local_player_id)
			vp.set_input_as_handled()
		JOY_BUTTON_LEFT_STICK:
			if turn_manager.is_local_player_turn():
				if hovered_card and hovered_card.is_on_battlefield:
					zone_manager.untap_single_card(hovered_card)
				else:
					zone_manager.untap_all(local_player_id)
				vp.set_input_as_handled()
