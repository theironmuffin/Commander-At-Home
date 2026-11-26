class_name SoundManager
extends Node

const SAMPLE_RATE: int = 22050
const POOL_SIZE: int = 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0
var _muted: bool = false
var _last_stack_size: int = 0
var master_volume: float = 0.85
var sfx_volume: float = 0.85
const AUDIO_SETTINGS_PATH := "user://audio_settings.json"

func _ready() -> void:
	name = "SoundManager"
	_load_audio_settings()
	_bake_all_streams()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_apply_volumes()

	var eb := get_node_or_null("/root/EventBus")
	if eb:
		if eb.has_signal("sfx_requested") and not eb.sfx_requested.is_connected(play_sfx):
			eb.sfx_requested.connect(play_sfx)
		if eb.has_signal("damage_dealt") and not eb.damage_dealt.is_connected(_on_damage_dealt):
			eb.damage_dealt.connect(_on_damage_dealt)
		if eb.has_signal("card_entered_battlefield") and not eb.card_entered_battlefield.is_connected(_on_etb):
			eb.card_entered_battlefield.connect(_on_etb)
		if eb.has_signal("card_died") and not eb.card_died.is_connected(_on_card_died):
			eb.card_died.connect(_on_card_died)
		if eb.has_signal("turn_changed") and not eb.turn_changed.is_connected(_on_turn_changed):
			eb.turn_changed.connect(_on_turn_changed)
		if eb.has_signal("life_total_changed") and not eb.life_total_changed.is_connected(_on_life_changed):
			eb.life_total_changed.connect(_on_life_changed)
		if eb.has_signal("combat_declared") and not eb.combat_declared.is_connected(_on_combat_declared):
			eb.combat_declared.connect(_on_combat_declared)
		if eb.has_signal("blocker_declared") and not eb.blocker_declared.is_connected(_on_blocker_declared):
			eb.blocker_declared.connect(_on_blocker_declared)
		if eb.has_signal("stack_changed") and not eb.stack_changed.is_connected(_on_stack_changed):
			eb.stack_changed.connect(_on_stack_changed)
		if eb.has_signal("phase_changed") and not eb.phase_changed.is_connected(_on_phase_changed):
			eb.phase_changed.connect(_on_phase_changed)

func _on_damage_dealt(_source: Node3D, target: Variant, amount: int) -> void:
	if amount <= 0: return
	play_sfx("hit")
	if target is Node3D and is_instance_valid(target) and target.has_method("play_damage_flash"):
		target.play_damage_flash()

func _on_etb(card: Node3D, _zone_from: String) -> void:
	if card and is_instance_valid(card) and "card_data" in card:
		if card.has_meta("is_commander") and bool(card.get_meta("is_commander")):
			play_sfx("commander_etb")
		elif MagicRules.is_land(card.card_data):
			play_sfx("land")

func _on_phase_changed(new_phase: int) -> void:
	if new_phase == 4: # COMBAT_DECLARE_ATTACKERS
		play_sfx("declare_attackers")
	else:
		play_sfx("phase_tick")

func _on_card_died(_card: Node3D) -> void:
	play_sfx("die")

func _on_turn_changed(_active_pid: int, _turn_num: int) -> void:
	play_sfx("turn")

func _on_life_changed(_pid: int, _new_total: int, amount: int) -> void:
	if amount > 0: play_sfx("life_gain")
	elif amount < 0: play_sfx("life_loss")

func _on_combat_declared(_attacker: Node3D, _target_pid: int) -> void:
	play_sfx("attack")

func _on_blocker_declared(_blocker: Node3D, _attacker: Node3D) -> void:
	play_sfx("block")

func _on_stack_changed(stack_size: int) -> void:
	if stack_size > _last_stack_size:
		play_sfx("cast")
	_last_stack_size = stack_size

func _load_audio_settings() -> void:
	if FileAccess.file_exists(AUDIO_SETTINGS_PATH):
		var f := FileAccess.open(AUDIO_SETTINGS_PATH, FileAccess.READ)
		if f:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK and j.get_data() is Dictionary:
				var d: Dictionary = j.get_data()
				master_volume = clampf(float(d.get("master_volume", 0.85)), 0.0, 1.0)
				sfx_volume = clampf(float(d.get("sfx_volume", 0.85)), 0.0, 1.0)
				_muted = bool(d.get("muted", false))

func _save_audio_settings() -> void:
	var f := FileAccess.open(AUDIO_SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"master_volume": master_volume, "sfx_volume": sfx_volume, "muted": _muted}))

func _apply_volumes() -> void:
	var combined: float = master_volume * sfx_volume
	var db: float = -80.0 if (_muted or combined <= 0.001) else linear_to_db(combined) - 4.0
	for p in _players:
		if is_instance_valid(p):
			p.volume_db = db

func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	_apply_volumes()
	_save_audio_settings()

func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	_apply_volumes()
	_save_audio_settings()

func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_volumes()
	_save_audio_settings()

func play_sfx(sfx_name: String) -> void:
	if _muted or _players.is_empty() or (master_volume * sfx_volume) <= 0.001: return
	var stream: AudioStreamWAV = _streams.get(sfx_name, null)
	if stream == null: return
	var p := _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % _players.size()
	p.stream = stream
	if sfx_name in ["tap", "draw", "hit", "land", "shuffle"]:
		p.pitch_scale = randf_range(0.91, 1.09)
	else:
		p.pitch_scale = randf_range(0.96, 1.04)
	p.play()

func _bake_all_streams() -> void:
	_streams["draw"] = _make_wav(0.09, func(t: float, dur: float) -> float:
		var env := exp(-t * 36.0) * minf(1.0, t / 0.008)
		var noise := randf_range(-1.0, 1.0) * 0.45
		var tone := sin(TAU * lerpf(620.0, 280.0, t / dur) * t) * 0.35
		return (noise + tone) * env * 0.55
	)

	_streams["tap"] = _make_wav(0.055, func(t: float, dur: float) -> float:
		var env := exp(-t * 58.0) * minf(1.0, t / 0.003)
		var freq := lerpf(360.0, 130.0, t / dur)
		return (sin(TAU * freq * t) * 0.7 + randf_range(-1.0, 1.0) * 0.18) * env * 0.65
	)

	_streams["hit"] = _make_wav(0.13, func(t: float, dur: float) -> float:
		var env := exp(-t * 24.0) * minf(1.0, t / 0.004)
		var freq := lerpf(165.0, 52.0, t / dur)
		var thud := sin(TAU * freq * t) * 0.75
		var crunch := randf_range(-1.0, 1.0) * exp(-t * 50.0) * 0.45
		return clampf((thud + crunch) * env * 0.85, -1.0, 1.0)
	)

	_streams["resolve"] = _make_wav(0.24, func(t: float, _dur: float) -> float:
		var env := exp(-t * 11.0) * minf(1.0, t / 0.012)
		var f1 := sin(TAU * 523.25 * t) * 0.45
		var f2 := sin(TAU * 659.25 * t) * 0.35 * clampf((t - 0.03) * 20.0, 0.0, 1.0)
		var f3 := sin(TAU * 783.99 * t) * 0.25 * clampf((t - 0.06) * 20.0, 0.0, 1.0)
		return (f1 + f2 + f3) * env * 0.48
	)

	_streams["fizzle"] = _make_wav(0.19, func(t: float, dur: float) -> float:
		var env := exp(-t * 16.0) * minf(1.0, t / 0.008)
		var freq := lerpf(330.0, 145.0, t / dur)
		return (sin(TAU * freq * t) * 0.65 + sin(TAU * freq * 1.5 * t) * 0.15) * env * 0.55
	)

	_streams["shuffle"] = _make_wav(0.28, func(t: float, dur: float) -> float:
		var pulse := absf(sin(TAU * 14.0 * t))
		var env := sin(PI * (t / dur))
		return randf_range(-1.0, 1.0) * (0.25 + 0.75 * pulse) * env * 0.38
	)

	_streams["cast"] = _make_wav(0.16, func(t: float, dur: float) -> float:
		var env := exp(-t * 15.0) * minf(1.0, t / 0.015)
		var freq := lerpf(320.0, 610.0, t / dur)
		return (sin(TAU * freq * t) * 0.55 + sin(TAU * freq * 2.0 * t) * 0.20) * env * 0.45
	)

	_streams["land"] = _make_wav(0.11, func(t: float, dur: float) -> float:
		var env := exp(-t * 28.0) * minf(1.0, t / 0.004)
		var freq := lerpf(190.0, 82.0, t / dur)
		return sin(TAU * freq * t) * env * 0.68
	)

	_streams["attack"] = _make_wav(0.13, func(t: float, dur: float) -> float:
		var env := exp(-t * 22.0) * minf(1.0, t / 0.006)
		var freq := lerpf(420.0, 940.0, t / dur)
		var sheen := sin(TAU * freq * t) * 0.45 + randf_range(-1.0, 1.0) * 0.25
		return sheen * env * 0.48
	)

	_streams["block"] = _make_wav(0.10, func(t: float, dur: float) -> float:
		var env := exp(-t * 32.0) * minf(1.0, t / 0.004)
		var freq := lerpf(270.0, 115.0, t / dur)
		return (sin(TAU * freq * t) * 0.65 + sin(TAU * freq * 1.41 * t) * 0.25) * env * 0.62
	)

	_streams["die"] = _make_wav(0.22, func(t: float, dur: float) -> float:
		var env := exp(-t * 12.0) * minf(1.0, t / 0.01)
		var freq := lerpf(250.0, 105.0, t / dur)
		return (sin(TAU * freq * t) * 0.6 + sin(TAU * freq * 0.5 * t) * 0.3) * env * 0.52
	)

	_streams["exile"] = _make_wav(0.20, func(t: float, dur: float) -> float:
		var env := exp(-t * 13.0) * minf(1.0, t / 0.012)
		var freq := lerpf(740.0, 1280.0, t / dur)
		return (sin(TAU * freq * t) * 0.45 + sin(TAU * freq * 1.5 * t) * 0.20) * env * 0.36
	)

	_streams["life_gain"] = _make_wav(0.18, func(t: float, _dur: float) -> float:
		var env := exp(-t * 14.0) * minf(1.0, t / 0.008)
		var freq := 587.33 if t < 0.06 else 880.0
		return sin(TAU * freq * t) * env * 0.38
	)

	_streams["life_loss"] = _make_wav(0.16, func(t: float, dur: float) -> float:
		var env := exp(-t * 16.0) * minf(1.0, t / 0.006)
		var freq := lerpf(185.0, 125.0, t / dur)
		return sin(TAU * freq * t) * env * 0.45
	)

	_streams["counter_up"] = _make_wav(0.07, func(t: float, dur: float) -> float:
		var env := exp(-t * 42.0) * minf(1.0, t / 0.004)
		return sin(TAU * lerpf(640.0, 920.0, t / dur) * t) * env * 0.35
	)

	_streams["counter_down"] = _make_wav(0.07, func(t: float, dur: float) -> float:
		var env := exp(-t * 42.0) * minf(1.0, t / 0.004)
		return sin(TAU * lerpf(460.0, 300.0, t / dur) * t) * env * 0.35
	)

	_streams["token"] = _make_wav(0.14, func(t: float, _dur: float) -> float:
		var env := exp(-t * 18.0) * minf(1.0, t / 0.005)
		var freq := 440.0 if t < 0.04 else (659.25 if t < 0.08 else 880.0)
		return sin(TAU * freq * t) * env * 0.40
	)

	_streams["turn"] = _make_wav(0.28, func(t: float, _dur: float) -> float:
		var env := exp(-t * 9.0) * minf(1.0, t / 0.015)
		return (sin(TAU * 392.0 * t) * 0.55 + sin(TAU * 587.33 * t) * 0.35) * env * 0.42
	)

	_streams["declare_attackers"] = _make_wav(0.16, func(t: float, dur: float) -> float:
		var env := exp(-t * 14.0) * minf(1.0, t / 0.008)
		var f := lerpf(330.0, 495.0, t / dur)
		return (sin(TAU * f * t) * 0.6 + sin(TAU * f * 1.5 * t) * 0.3) * env * 0.36
	)

	_streams["combat_damage"] = _make_wav(0.15, func(t: float, _dur: float) -> float:
		var env := exp(-t * 20.0) * minf(1.0, t / 0.004)
		return (sin(TAU * 92.0 * t) * 0.7 + randf_range(-0.25, 0.25)) * env * 0.45
	)

	_streams["loyalty"] = _make_wav(0.18, func(t: float, _dur: float) -> float:
		var env := exp(-t * 14.0) * minf(1.0, t / 0.006)
		return (sin(TAU * 783.99 * t) * 0.5 + sin(TAU * 1174.66 * t) * 0.35) * env * 0.32
	)

	_streams["commander_etb"] = _make_wav(0.28, func(t: float, _dur: float) -> float:
		var env := exp(-t * 8.0) * minf(1.0, t / 0.012)
		return (sin(TAU * 293.66 * t) * 0.45 + sin(TAU * 440.0 * t) * 0.35 + sin(TAU * 587.33 * t) * 0.28) * env * 0.42
	)

	_streams["phase_tick"] = _make_wav(0.04, func(t: float, _dur: float) -> float:
		var env := exp(-t * 65.0) * minf(1.0, t / 0.002)
		return sin(TAU * 680.0 * t) * env * 0.16
	)

	_streams["dice"] = _make_wav(0.12, func(t: float, _dur: float) -> float:
		var env := exp(-t * 24.0) * minf(1.0, t / 0.003)
		return (sin(TAU * 520.0 * t) * 0.4 + randf_range(-0.3, 0.3)) * env * 0.30
	)

func _make_wav(duration: float, sample_fn: Callable) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(SAMPLE_RATE)
		var s: float = clampf(float(sample_fn.call(t, duration)), -1.0, 1.0)
		var val := int(s * 32767.0)
		data.encode_s16(i * 2, val)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
