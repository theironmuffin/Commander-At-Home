extends Node

# Trigger Event Bus Signals
signal card_entered_battlefield(card: Node3D, zone_from: String)
signal card_left_battlefield(card: Node3D, zone_to: String)
signal card_died(card: Node3D)
signal phase_changed(new_phase: int)
signal turn_changed(active_player_id: int, turn_number: int)
signal priority_changed(priority_player_id: int, passes_count: int)
signal stack_changed(stack_size: int)
signal mana_pool_changed(mana_pool: Dictionary)
signal life_total_changed(player_id: int, new_total: int, change_amount: int)
signal damage_dealt(source: Node3D, target: Variant, amount: int)
signal combat_declared(attacker: Node3D, target_player_id: int)
signal blocker_declared(blocker: Node3D, attacker: Node3D)
signal sfx_requested(sfx_name: String)

func notify_etb(card: Node3D, zone_from: String) -> void:
	card_entered_battlefield.emit(card, zone_from)

func notify_die(card: Node3D) -> void:
	card_died.emit(card)
	card_left_battlefield.emit(card, "Graveyard")

func notify_phase(new_phase: int) -> void:
	phase_changed.emit(new_phase)

func notify_turn(active_pid: int, turn_num: int) -> void:
	turn_changed.emit(active_pid, turn_num)

func notify_priority(priority_pid: int, passes: int) -> void:
	priority_changed.emit(priority_pid, passes)

func notify_stack(stack_size: int) -> void:
	stack_changed.emit(stack_size)

func notify_mana(pool: Dictionary) -> void:
	mana_pool_changed.emit(pool)

func notify_life_change(player_id: int, new_total: int, amount: int) -> void:
	life_total_changed.emit(player_id, new_total, amount)

func play_sfx(sfx_name: String) -> void:
	sfx_requested.emit(sfx_name)
