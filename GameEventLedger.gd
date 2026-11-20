class_name GameEventLedger
extends Node

signal event_logged(event_payload: Dictionary)

enum EventType {
	PHASE_CHANGED,
	PRIORITY_PASSED,
	CARD_MOVED,
	CARD_TAPPED,
	CARD_UNTAPPED,
	DAMAGE_DEALT,
	LIFE_CHANGED,
	MANA_ADDED,
	MANA_EMPTIED,
	STACK_PUSHED,
	STACK_RESOLVED,
	COUNTERS_MODIFIED
}

var event_history: Array[Dictionary] = []

func log_event(type: EventType, payload: Dictionary) -> Dictionary:
	payload["type"] = type
	payload["timestamp"] = Time.get_ticks_msec()
	payload["event_id"] = event_history.size()
	
	event_history.append(payload)
	event_logged.emit(payload)
	return payload

func clear_history() -> void:
	event_history.clear()
