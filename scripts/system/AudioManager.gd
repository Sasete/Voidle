extends Node

const SAMPLE_RATE := 22050
const MAX_PLAYERS := 8
const CREDITS_THROTTLE := 0.25   # min seconds between cash sounds

var _players: Array[AudioStreamPlayer] = []
var _ambient_player: AudioStreamPlayer = null
var _construct_loop_player: AudioStreamPlayer = null
var _music_player: AudioStreamPlayer = null
var _cache: Dictionary = {}
var _credits_timer: float = 0.0
var _construct_active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in MAX_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.volume_db = -28.0
	add_child(_ambient_player)

	_construct_loop_player = AudioStreamPlayer.new()
	_construct_loop_player.volume_db = -20.0
	add_child(_construct_loop_player)

	_cache["hover"]         = _gen_hover()
	_cache["click"]         = _gen_click()
	_cache["skill_buy"]     = _gen_skill_buy()
	_cache["error"]         = _gen_error()
	_cache["level_up"]      = _gen_level_up()
	_cache["survey"]        = _gen_survey()
	_cache["clink"]         = _gen_clink()
	_cache["poi_hover"]     = _gen_poi_hover()
	_cache["district_hover"]= _gen_district_hover()
	_cache["construct"]     = _gen_construct()
	_cache["rocket"]        = _gen_rocket()
	_cache["building_done"] = _gen_building_done()
	_cache["poi_ping"]      = _gen_poi_ping()
	_cache["poi_select"]    = _gen_poi_select()
	_cache["cash"]          = _gen_cash()
	_cache["achievement"]   = _gen_achievement()
	_cache["tick"]          = _gen_tick()
	_cache["terrain_earth"] = _gen_terrain_earth()
	_cache["terrain_water"] = _gen_terrain_water()
	_cache["terrain_sand"]  = _gen_terrain_sand()
	_cache["terrain_ice"]   = _gen_terrain_ice()
	_cache["terrain_fire"]  = _gen_terrain_fire()
	_cache["terrain_dust"]  = _gen_terrain_dust()
	_cache["terrain_gas"]   = _gen_terrain_gas()

	_construct_loop_player.stream = _gen_construct_loop()

	_play_ambient()
	_play_music()

	GameState.credits_changed.connect(func(_v: float) -> void:
		if _credits_timer <= 0.0:
			play("cash", -4.0)
			_credits_timer = CREDITS_THROTTLE)

func _process(delta: float) -> void:
	if _credits_timer > 0.0:
		_credits_timer -= delta

func set_construction_active(active: bool) -> void:
	if active == _construct_active:
		return
	_construct_active = active
	if active:
		_construct_loop_player.play()
	else:
		_construct_loop_player.stop()

func play(sound: String, vol_db: float = 0.0) -> void:
	var stream: AudioStreamWAV = _cache.get(sound)
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream  = stream
			p.volume_db = -6.0 + vol_db
			p.play()
			return
	# all busy → steal oldest (first)
	_players[0].stop()
	_players[0].stream  = stream
	_players[0].volume_db = -6.0 + vol_db
	_players[0].play()

# ── synthesis helpers ──────────────────────────────────────────────────

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format    = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate  = SAMPLE_RATE
	wav.stereo    = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var s := int(clamp(samples[i], -1.0, 1.0) * 32767.0)
		bytes[i * 2]     = s & 0xFF
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	wav.data = bytes
	return wav

func _envelope(t: float, attack: float, decay: float, sustain: float, release: float, total: float) -> float:  ## adsr
	if t < attack:
		return t / attack
	elif t < attack + decay:
		return 1.0 - (1.0 - sustain) * (t - attack) / decay
	elif t < total - release:
		return sustain
	else:
		return sustain * (1.0 - (t - (total - release)) / release)

func _sine(phase: float) -> float:
	return sin(phase)

func _noise(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(-1.0, 1.0)

# ── sound generators ───────────────────────────────────────────────────

func _gen_hover() -> AudioStreamWAV:
	# Short high-frequency tick: sine chirp 900→1400 Hz, 40ms
	var dur  := 0.040
	var n    := int(SAMPLE_RATE * dur)
	var buf  := PackedFloat32Array(); buf.resize(n)
	var ph   := 0.0
	for i in n:
		var t    := float(i) / SAMPLE_RATE
		var freq: float = lerp(900.0, 1400.0, t / dur)
		ph      += TAU * freq / SAMPLE_RATE
		var env: float  = _envelope(t, 0.002, 0.010, 0.0, 0.028, dur)
		buf[i]   = _sine(ph) * env * 0.35
	return _make_wav(buf)

func _gen_click() -> AudioStreamWAV:
	# Punchy click: low thud (80Hz sine) + noise burst, 60ms
	var dur := 0.060
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1337
	var ph  := 0.0
	for i in n:
		var t   := float(i) / SAMPLE_RATE
		ph     += TAU * 120.0 / SAMPLE_RATE
		var env: float   = _envelope(t, 0.001, 0.015, 0.0, 0.044, dur)
		var thud: float  = _sine(ph) * 0.5
		var noise: float = _noise(rng) * 0.25 * exp(-t * 60.0)
		buf[i]   = (thud + noise) * env
	return _make_wav(buf)

func _gen_skill_buy() -> AudioStreamWAV:
	# Ascending arpeggio: C5 → E5 → G5, each 80ms, total ~280ms
	var notes: Array[float] = [523.25, 659.25, 783.99]
	var note_dur := 0.080
	var gap      := 0.014
	var total    := notes.size() * (note_dur + gap)
	var n        := int(SAMPLE_RATE * total)
	var buf      := PackedFloat32Array(); buf.resize(n)
	var t_offset := 0.0
	for freq in notes:
		var start := int(t_offset * SAMPLE_RATE)
		var count := int(note_dur * SAMPLE_RATE)
		var ph    := 0.0
		for j in count:
			var idx := start + j
			if idx >= n: break
			var t   := float(j) / SAMPLE_RATE
			var env: float = _envelope(t, 0.003, 0.020, 0.4, 0.030, note_dur)
			ph     += TAU * freq / SAMPLE_RATE
			# Sine + slight harmonic
			buf[idx] += (_sine(ph) * 0.6 + _sine(ph * 2.0) * 0.15) * env * 0.55
		t_offset += note_dur + gap
	return _make_wav(buf)

func _gen_error() -> AudioStreamWAV:
	# Descending buzz: 320→160 Hz square-ish, 120ms
	var dur := 0.120
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph  := 0.0
	for i in n:
		var t    := float(i) / SAMPLE_RATE
		var freq: float = lerp(320.0, 140.0, t / dur)
		ph      += TAU * freq / SAMPLE_RATE
		var env: float  = _envelope(t, 0.001, 0.010, 0.6, 0.040, dur)
		# Clipped sine → square-ish buzz
		buf[i]   = clamp(_sine(ph) * 3.0, -1.0, 1.0) * env * 0.30
	return _make_wav(buf)

func _gen_level_up() -> AudioStreamWAV:
	# Sweep 300→900Hz + shimmer harmonics, 500ms
	var dur := 0.500
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph1 := 0.0; var ph2 := 0.0; var ph3 := 0.0
	for i in n:
		var t    := float(i) / SAMPLE_RATE
		var frac: float = t / dur
		var f1: float = lerp(280.0, 840.0, pow(frac, 0.6))
		var f2: float = f1 * 2.0
		var f3: float = f1 * 3.0
		ph1 += TAU * f1 / SAMPLE_RATE
		ph2 += TAU * f2 / SAMPLE_RATE
		ph3 += TAU * f3 / SAMPLE_RATE
		var env: float  = _envelope(t, 0.010, 0.060, 0.5, 0.200, dur)
		buf[i]   = (_sine(ph1) * 0.55 + _sine(ph2) * 0.25 + _sine(ph3) * 0.10) * env * 0.60
	return _make_wav(buf)

func _gen_survey() -> AudioStreamWAV:
	# Chord reveal: 3 frequencies fade in together, shimmer, 700ms
	var dur   := 0.700
	var freqs: Array[float] = [440.0, 554.37, 659.25, 880.0]  # A4 chord
	var n     := int(SAMPLE_RATE * dur)
	var buf   := PackedFloat32Array(); buf.resize(n)
	var phases: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for i in n:
		var t   := float(i) / SAMPLE_RATE
		var env: float = _envelope(t, 0.040, 0.100, 0.5, 0.300, dur)
		var s: float   = 0.0
		for j in freqs.size():
			phases[j] += TAU * freqs[j] / SAMPLE_RATE
			s += _sine(phases[j]) * (0.35 if j == 0 else 0.20)
		buf[i] = s * env * 0.55
	return _make_wav(buf)

func _gen_clink() -> AudioStreamWAV:
	# Soft metallic clink: high sine 1800Hz, very short, 35ms
	var dur := 0.035
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph  := 0.0; var ph2 := 0.0
	for i in n:
		var t   := float(i) / SAMPLE_RATE
		ph     += TAU * 1800.0 / SAMPLE_RATE
		ph2    += TAU * 2700.0 / SAMPLE_RATE
		var env: float = exp(-t * 80.0)
		buf[i]  = (_sine(ph) * 0.5 + _sine(ph2) * 0.3) * env * 0.30
	return _make_wav(buf)

func _play_music() -> void:
	var path := "res://resources/The Void.mp3"
	if not ResourceLoader.exists(path):
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -22.0
	var stream = load(path)
	stream.loop = true
	_music_player.stream = stream
	add_child(_music_player)
	_music_player.play()

func _play_ambient() -> void:
	# Deep space drone: two detuned low sines + slow LFO, looping
	var dur := 4.0
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph1 := 0.0; var ph2 := 0.0; var ph_lfo := 0.0
	for i in n:
		var t    := float(i) / SAMPLE_RATE
		ph1     += TAU * 55.0  / SAMPLE_RATE
		ph2     += TAU * 57.2  / SAMPLE_RATE
		ph_lfo  += TAU * 0.18  / SAMPLE_RATE
		var lfo  := 0.7 + 0.3 * sin(ph_lfo)
		buf[i]   = (_sine(ph1) * 0.5 + _sine(ph2) * 0.5) * lfo * 0.5
	var wav := _make_wav(buf)
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = n - 1
	_ambient_player.stream = wav
	_ambient_player.play()

# ── new sounds ─────────────────────────────────────────────────────────

func _gen_poi_hover() -> AudioStreamWAV:
	# Thin techno beep: two-tone blip, very short, 28ms
	var dur := 0.028
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph1 := 0.0; var ph2 := 0.0
	for i in n:
		var t: float    = float(i) / SAMPLE_RATE
		var frac: float = t / dur
		ph1 += TAU * 2200.0 / SAMPLE_RATE
		ph2 += TAU * 3100.0 / SAMPLE_RATE
		var env: float = (1.0 - frac) * exp(-frac * 6.0)
		buf[i] = (_sine(ph1) * 0.55 + _sine(ph2) * 0.30) * env * 0.28
	return _make_wav(buf)

func _gen_district_hover() -> AudioStreamWAV:
	# Slightly lower, warmer blip: 1400→1800 Hz chirp, 35ms
	var dur := 0.035
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph  := 0.0
	for i in n:
		var t: float    = float(i) / SAMPLE_RATE
		var freq: float = lerp(1400.0, 1800.0, t / dur)
		ph += TAU * freq / SAMPLE_RATE
		var env: float = exp(-t * 55.0)
		buf[i] = _sine(ph) * env * 0.32
	return _make_wav(buf)

func _gen_construct() -> AudioStreamWAV:
	# Industrial start: low thud + rising metallic whirr, 320ms
	var dur := 0.320
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 0xBEEF
	var ph1 := 0.0; var ph2 := 0.0
	for i in n:
		var t: float    = float(i) / SAMPLE_RATE
		var frac: float = t / dur
		# Low thud punch (80Hz, fast decay)
		ph1 += TAU * 80.0 / SAMPLE_RATE
		var thud: float = _sine(ph1) * exp(-t * 18.0) * 0.55
		# Rising metallic whirr (400→1200Hz)
		var freq: float = lerp(400.0, 1200.0, pow(frac, 0.5))
		ph2 += TAU * freq / SAMPLE_RATE
		var whirr_env: float = frac * exp(-frac * 3.5)
		var whirr: float = (_sine(ph2) * 0.4 + _noise(rng) * 0.08) * whirr_env
		var env: float = _envelope(t, 0.005, 0.060, 0.3, 0.120, dur)
		buf[i] = (thud + whirr) * env
	return _make_wav(buf)

func _gen_rocket() -> AudioStreamWAV:
	# Rocket launch: low rumble burst + whoosh sweep, 900ms
	var dur := 0.900
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 0xF00D
	var ph1 := 0.0; var ph2 := 0.0
	for i in n:
		var t: float    = float(i) / SAMPLE_RATE
		var frac: float = t / dur
		# Deep rumble (60Hz + harmonics)
		ph1 += TAU * 60.0 / SAMPLE_RATE
		var rumble_env: float = exp(-frac * 2.8) * min(frac * 12.0, 1.0)
		var rumble: float = (_sine(ph1) * 0.5 + _sine(ph1 * 2.1) * 0.25 + _noise(rng) * 0.25) * rumble_env
		# Whoosh sweep (200→3000Hz noise band)
		var wfreq: float = lerp(200.0, 3000.0, pow(frac, 0.4))
		ph2 += TAU * wfreq / SAMPLE_RATE
		var whoosh_env: float = frac * exp(-frac * 1.8)
		var whoosh: float = (_sine(ph2) * 0.3 + _noise(rng) * 0.35) * whoosh_env
		buf[i] = clamp((rumble * 0.55 + whoosh * 0.45), -1.0, 1.0)
	return _make_wav(buf)

func _gen_building_done() -> AudioStreamWAV:
	# Construction complete: quick two-note confirm ding, 280ms
	var dur     := 0.280
	var n       := int(SAMPLE_RATE * dur)
	var buf     := PackedFloat32Array(); buf.resize(n)
	var freqs: Array[float] = [880.0, 1318.5]   # A5 → E6
	var offsets: Array[float] = [0.0, 0.12]
	for fi in 2:
		var start := int(offsets[fi] * SAMPLE_RATE)
		var count := int(0.16 * SAMPLE_RATE)
		var ph    := 0.0
		for j in count:
			var idx := start + j
			if idx >= n: break
			var t: float   = float(j) / SAMPLE_RATE
			var env: float = _envelope(t, 0.002, 0.020, 0.4, 0.060, 0.16)
			ph += TAU * freqs[fi] / SAMPLE_RATE
			buf[idx] += (_sine(ph) * 0.55 + _sine(ph * 2.0) * 0.15) * env * 0.50
	return _make_wav(buf)

func _gen_poi_ping() -> AudioStreamWAV:
	# "pink" — clean metallic ping, 45ms
	var dur := 0.045
	var n   := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph1 := 0.0; var ph2 := 0.0; var ph3 := 0.0
	for i in n:
		var t: float   = float(i) / SAMPLE_RATE
		ph1 += TAU * 2400.0 / SAMPLE_RATE
		ph2 += TAU * 3600.0 / SAMPLE_RATE
		ph3 += TAU * 4800.0 / SAMPLE_RATE
		var env: float = exp(-t * 65.0)
		buf[i] = (_sine(ph1) * 0.50 + _sine(ph2) * 0.28 + _sine(ph3) * 0.12) * env * 0.32
	return _make_wav(buf)

func _gen_poi_select() -> AudioStreamWAV:
	# "piripipink" — fast 3-note ascending blip, 90ms total
	var freqs: Array[float]   = [2000.0, 2800.0, 3800.0]
	var offsets: Array[float] = [0.0,    0.030,  0.060]
	var note_dur := 0.030
	var total    := 0.090
	var n        := int(SAMPLE_RATE * total)
	var buf      := PackedFloat32Array(); buf.resize(n)
	for fi in 3:
		var start := int(offsets[fi] * SAMPLE_RATE)
		var count := int(note_dur * SAMPLE_RATE)
		var ph    := 0.0
		for j in count:
			var idx := start + j
			if idx >= n: break
			var t: float   = float(j) / SAMPLE_RATE
			var env: float = exp(-t * 90.0)
			ph += TAU * freqs[fi] / SAMPLE_RATE
			buf[idx] += (_sine(ph) * 0.55 + _sine(ph * 2.0) * 0.20) * env * 0.30
	return _make_wav(buf)

func _gen_cash() -> AudioStreamWAV:
	# Soft coin clink — two quick tones, 55ms, pleasant and repeatable
	var dur  := 0.055
	var n    := int(SAMPLE_RATE * dur)
	var buf  := PackedFloat32Array(); buf.resize(n)
	var ph1  := 0.0; var ph2 := 0.0
	for i in n:
		var t: float   = float(i) / SAMPLE_RATE
		ph1 += TAU * 1600.0 / SAMPLE_RATE
		ph2 += TAU * 2400.0 / SAMPLE_RATE
		# Second tone delayed by 18ms for the double-clink feel
		var env1: float = exp(-t * 70.0)
		var t2: float   = maxf(t - 0.018, 0.0)
		var env2: float = exp(-t2 * 70.0) * float(t >= 0.018)
		buf[i] = (_sine(ph1) * env1 * 0.40 + _sine(ph2) * env2 * 0.30) * 0.38
	return _make_wav(buf)

func _gen_construct_loop() -> AudioStreamWAV:
	# Rhythmic construction ambience: 2-beat hammer+saw loop, ~1.6s
	var bpm    := 92.0
	var beat   := 60.0 / bpm
	var beats  := 4
	var dur    := beat * beats   # ~2.6s
	var n      := int(SAMPLE_RATE * dur)
	var buf    := PackedFloat32Array(); buf.resize(n)
	var rng    := RandomNumberGenerator.new(); rng.seed = 0xC0DE

	# Hammer hits on beats 1 and 3
	var hit_times: Array[float] = [0.0, beat, beat * 2.0, beat * 3.0]
	for ht: float in hit_times:
		var start := int(ht * SAMPLE_RATE)
		var hit_len := int(0.08 * SAMPLE_RATE)
		var ph := 0.0
		for j in hit_len:
			var idx := start + j
			if idx >= n: break
			var t: float   = float(j) / SAMPLE_RATE
			ph += TAU * 180.0 / SAMPLE_RATE
			var env: float = exp(-t * 35.0)
			buf[idx] += (_sine(ph) * 0.45 + _noise(rng) * 0.25) * env * 0.55

	# Saw whirr between beats (offset by half-beat)
	var saw_times: Array[float] = [beat * 0.5, beat * 1.5, beat * 2.5]
	for st: float in saw_times:
		var start := int(st * SAMPLE_RATE)
		var saw_len := int(0.18 * SAMPLE_RATE)
		var ph := 0.0
		for j in saw_len:
			var idx := start + j
			if idx >= n: break
			var t: float    = float(j) / SAMPLE_RATE
			var frac: float = t / 0.18
			var freq: float = lerp(600.0, 1400.0, frac)
			ph += TAU * freq / SAMPLE_RATE
			var env: float  = frac * (1.0 - frac) * 4.0 * 0.30
			buf[idx] += (_sine(ph) * 0.5 + _noise(rng) * 0.15) * env * 0.40

	var wav := _make_wav(buf)
	wav.loop_mode  = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end   = n - 1
	return wav

func _gen_achievement() -> AudioStreamWAV:
	# Triumphant 4-note fanfare: ascending + final sustained chord shimmer, 700ms
	var notes: Array[float]   = [523.25, 659.25, 783.99, 1046.50]  # C5 E5 G5 C6
	var offsets: Array[float] = [0.0,    0.100,  0.200,  0.340]
	var total := 0.700
	var n     := int(SAMPLE_RATE * total)
	var buf   := PackedFloat32Array(); buf.resize(n)
	for fi in 4:
		var note_dur := 0.36 if fi == 3 else 0.14
		var start    := int(offsets[fi] * SAMPLE_RATE)
		var count    := int(note_dur * SAMPLE_RATE)
		var ph       := 0.0; var ph2 := 0.0
		for j in count:
			var idx := start + j
			if idx >= n: break
			var t: float   = float(j) / SAMPLE_RATE
			var env: float = _envelope(t, 0.004, 0.030, 0.55, 0.12, note_dur)
			ph  += TAU * notes[fi]       / SAMPLE_RATE
			ph2 += TAU * notes[fi] * 2.0 / SAMPLE_RATE
			buf[idx] += (_sine(ph) * 0.55 + _sine(ph2) * 0.18) * env * 0.55
	return _make_wav(buf)

# ── terrain hit sounds ────────────────────────────────────────────────────────

func _gen_terrain_earth() -> AudioStreamWAV:
	# Damp thud: low-pass filtered noise burst, 110ms
	var dur := 0.110; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1001
	var prev := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 28.0)
		var raw: float = rng.randf_range(-1.0, 1.0)
		# Low-pass (IIR): cutoff ~300 Hz
		prev = prev * 0.94 + raw * 0.06
		buf[i] = prev * env * 0.9
	return _make_wav(buf)

func _gen_terrain_water() -> AudioStreamWAV:
	# Wet splash: band-pass noise + rising sine bubble, 140ms
	var dur := 0.140; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1002
	var lp := 0.0; var hp := 0.0; var ph := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 18.0)
		var raw: float = rng.randf_range(-1.0, 1.0)
		lp = lp * 0.88 + raw * 0.12      # LP ~800 Hz
		hp = raw - lp                      # HP residual
		var band: float = lp * 0.6 + hp * 0.3
		var freq: float = lerp(280.0, 560.0, t / dur)
		ph += TAU * freq / SAMPLE_RATE
		buf[i] = (band * 0.5 + _sine(ph) * 0.25) * env * 0.8
	return _make_wav(buf)

func _gen_terrain_sand() -> AudioStreamWAV:
	# Gritty hiss: high-freq noise with slight pitch curve, 90ms
	var dur := 0.090; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1003
	var hp := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 30.0) * (1.0 + t * 4.0)
		var raw: float = rng.randf_range(-1.0, 1.0)
		hp = raw * 0.55 + hp * 0.45      # HP ~5kHz band
		buf[i] = hp * env * 0.55
	return _make_wav(buf)

func _gen_terrain_ice() -> AudioStreamWAV:
	# Crystalline tink: sharp click + high resonance decay, 120ms
	var dur := 0.120; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph1 := 0.0; var ph2 := 0.0; var ph3 := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 22.0)
		ph1 += TAU * 3800.0 / SAMPLE_RATE
		ph2 += TAU * 5400.0 / SAMPLE_RATE
		ph3 += TAU * 7200.0 / SAMPLE_RATE
		buf[i] = (_sine(ph1) * 0.50 + _sine(ph2) * 0.30 + _sine(ph3) * 0.15) * env * 0.65
	return _make_wav(buf)

func _gen_terrain_fire() -> AudioStreamWAV:
	# Crackle-pop: random impulses riding a low rumble, 160ms
	var dur := 0.160; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1004
	var lp1 := 0.0; var lp2 := 0.0; var ph := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 14.0)
		var raw: float = rng.randf_range(-1.0, 1.0)
		lp1 = lp1 * 0.90 + raw * 0.10   # ~1.1kHz
		lp2 = lp2 * 0.97 + raw * 0.03   # rumble ~200Hz
		ph += TAU * 120.0 / SAMPLE_RATE
		var crackle: float = lp1 if abs(raw) > 0.75 else lp2 * 0.4
		buf[i] = (crackle * 0.55 + _sine(ph) * 0.12) * env * 0.85
	return _make_wav(buf)

func _gen_terrain_dust() -> AudioStreamWAV:
	# Dry scrape: very short mid noise burst, 70ms
	var dur := 0.070; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1005
	var lp := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 35.0)
		var raw: float = rng.randf_range(-1.0, 1.0)
		lp = lp * 0.80 + raw * 0.20     # ~1.8kHz mid band
		buf[i] = lp * env * 0.6
	return _make_wav(buf)

func _gen_terrain_gas() -> AudioStreamWAV:
	# Atmospheric whoosh: sweeping band noise, 180ms
	var dur := 0.180; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var rng := RandomNumberGenerator.new(); rng.seed = 1006
	var lp := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = t / dur * exp(-t * 12.0) * 2.2
		var raw: float = rng.randf_range(-1.0, 1.0)
		var alpha: float = lerp(0.04, 0.14, t / dur)
		lp = lp * (1.0 - alpha) + raw * alpha
		buf[i] = lp * env * 0.75
	return _make_wav(buf)

func _gen_tick() -> AudioStreamWAV:
	# Crisp typewriter key click: sharp transient at ~3kHz, 10ms
	var dur := 0.010; var n := int(SAMPLE_RATE * dur)
	var buf := PackedFloat32Array(); buf.resize(n)
	var ph := 0.0
	for i in n:
		var t: float   = float(i) / SAMPLE_RATE
		var env: float = exp(-t * 380.0)
		ph += TAU * 2800.0 / SAMPLE_RATE
		buf[i] = _sine(ph) * env * 0.55
	return _make_wav(buf)
