extends Node
## Procedural audio synthesizer and spatialized 3D sound + ambient music manager.
## Generates 16-bit PCM AudioStreamWAV assets at startup so every action, surface,
## mob, weather state and UI interaction has immediate, responsive audio.

const RATE := 22050
var streams: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _rain_player: AudioStreamPlayer
var _music_timer: float = 4.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_generate_all()
	for i in 16:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"SFX"
		p3.max_distance = 36.0
		p3.unit_size = 5.0
		add_child(p3)
		_pool_3d.append(p3)
	for i in 6:
		var p2 := AudioStreamPlayer.new()
		p2.bus = &"SFX"
		add_child(p2)
		_pool_2d.append(p2)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	_music_player.volume_db = -6.0
	add_child(_music_player)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = &"Ambient"
	_rain_player.stream = streams.get("rain_loop")
	_rain_player.volume_db = -80.0
	add_child(_rain_player)

func _process(delta: float) -> void:
	_music_timer -= delta
	if _music_timer <= 0.0 and not _music_player.playing:
		_music_player.stream = _make_music_phrase()
		_music_player.play()
		_music_timer = _rng.randf_range(18.0, 35.0)

func set_rain_intensity(intensity: float) -> void:
	if intensity <= 0.01:
		if _rain_player.playing:
			_rain_player.stop()
	else:
		if not _rain_player.playing:
			_rain_player.play()
		_rain_player.volume_db = linear_to_db(clampf(intensity * 0.45, 0.001, 1.0))

func play_ui(name: String = "click", pitch: float = 1.0, vol_db: float = 0.0) -> void:
	var st: AudioStreamWAV = streams.get(name)
	if st == null:
		return
	for p in _pool_2d:
		if not p.playing:
			p.stream = st
			p.pitch_scale = pitch
			p.volume_db = vol_db
			p.play()
			return

func play_3d(name: String, pos: Vector3, vol_db: float = 0.0, pitch_var: float = 0.12) -> void:
	var st: AudioStreamWAV = streams.get(name)
	if st == null:
		return
	for p in _pool_3d:
		if not p.playing:
			p.global_position = pos
			p.stream = st
			p.volume_db = vol_db
			p.pitch_scale = _rng.randf_range(1.0 - pitch_var, 1.0 + pitch_var)
			p.play()
			return

func play_block(block_id: int, pos: Vector3, kind: String = "break") -> void:
	if block_id <= 0 or block_id >= B.COUNT:
		return
	var snd: String = Registry.b_sound[block_id]
	var pitch := 0.85 if kind == "break" else (1.15 if kind == "step" else 1.0)
	var vol := -8.0 if kind == "step" else (-4.0 if kind == "hit" else 0.0)
	var st: AudioStreamWAV = streams.get("mat_" + snd, streams.get("mat_stone"))
	if st == null:
		return
	for p in _pool_3d:
		if not p.playing:
			p.global_position = pos
			p.stream = st
			p.volume_db = vol
			p.pitch_scale = pitch * _rng.randf_range(0.9, 1.1)
			p.play()
			return

func _make_wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := clampi(int(samples[i] * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	return wav

func _generate_all() -> void:
	# Surface material sounds (thuds, crunches, clicks)
	streams["mat_stone"] = _synth_impact(0.14, 180.0, 60.0, 0.7, 0.35)
	streams["mat_wood"] = _synth_impact(0.15, 240.0, 110.0, 0.45, 0.55)
	streams["mat_grass"] = _synth_impact(0.16, 120.0, 80.0, 0.9, 0.15)
	streams["mat_gravel"] = _synth_impact(0.18, 220.0, 90.0, 0.92, 0.2)
	streams["mat_sand"] = _synth_impact(0.16, 300.0, 140.0, 0.95, 0.1)
	streams["mat_snow"] = _synth_impact(0.15, 420.0, 180.0, 0.95, 0.12)
	streams["mat_glass"] = _synth_impact(0.20, 1400.0, 750.0, 0.55, 0.65)
	streams["mat_metal"] = _synth_impact(0.24, 880.0, 520.0, 0.3, 0.8)
	streams["mat_wool"] = _synth_impact(0.13, 140.0, 70.0, 0.65, 0.25)
	streams["mat_water"] = _synth_impact(0.28, 320.0, 120.0, 0.85, 0.3)
	streams["mat_fire"] = _synth_impact(0.22, 260.0, 90.0, 0.95, 0.15)

	# UI & gameplay sounds
	streams["click"] = _synth_tone(0.05, 720.0, 980.0, 0.1)
	streams["swing"] = _synth_impact(0.12, 260.0, 90.0, 0.9, 0.1)
	streams["hit"] = _synth_impact(0.16, 190.0, 65.0, 0.75, 0.45)
	streams["hurt"] = _synth_tone(0.22, 340.0, 150.0, 0.45)
	streams["eat"] = _synth_impact(0.14, 210.0, 130.0, 0.85, 0.3)
	streams["splash"] = _synth_impact(0.35, 360.0, 90.0, 0.9, 0.25)
	streams["bow"] = _synth_tone(0.16, 520.0, 220.0, 0.25)
	streams["explosion"] = _synth_impact(0.65, 95.0, 28.0, 0.92, 0.4)
	streams["portal"] = _synth_tone(0.55, 220.0, 660.0, 0.3)
	streams["pickup"] = _synth_tone(0.08, 520.0, 880.0, 0.05)

	# Creature vocalizations
	streams["mob_cow"] = _synth_voice(0.45, 135.0, 110.0, 0.15)
	streams["mob_sheep"] = _synth_voice(0.35, 260.0, 230.0, 0.25)
	streams["mob_pig"] = _synth_voice(0.22, 190.0, 240.0, 0.35)
	streams["mob_chicken"] = _synth_voice(0.18, 540.0, 680.0, 0.2)
	streams["mob_wolf"] = _synth_voice(0.28, 220.0, 160.0, 0.4)
	streams["mob_zombie"] = _synth_voice(0.48, 105.0, 78.0, 0.55)
	streams["mob_skeleton"] = _synth_impact(0.18, 920.0, 480.0, 0.65, 0.5)
	streams["mob_spider"] = _synth_impact(0.22, 480.0, 200.0, 0.92, 0.2)
	streams["mob_creeper"] = _synth_impact(0.45, 900.0, 400.0, 0.98, 0.05)
	streams["mob_boss"] = _synth_voice(0.65, 82.0, 52.0, 0.6)

	# Rain loop (1.5 seconds of filtered pink noise)
	var rlen := int(RATE * 1.5)
	var rbuf := PackedFloat32Array()
	rbuf.resize(rlen)
	var prev := 0.0
	for i in rlen:
		var w := _rng.randf_range(-1.0, 1.0)
		prev = prev * 0.82 + w * 0.18
		rbuf[i] = prev * 0.35
	streams["rain_loop"] = _make_wav(rbuf, true)

func _synth_impact(dur: float, f0: float, f1: float, noise_mix: float, tone_mix: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := pow(1.0 - t, 2.2)
		var freq := lerpf(f0, f1, t)
		phase += freq / RATE
		var tone := sin(phase * TAU) + 0.35 * sin(phase * TAU * 2.3)
		var raw := _rng.randf_range(-1.0, 1.0)
		lp = lp * 0.65 + raw * 0.35
		buf[i] = (lp * noise_mix + tone * tone_mix) * env * 0.55
	return _make_wav(buf)

func _synth_tone(dur: float, f0: float, f1: float, noise_amt: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := sin(t * PI) * (1.0 - t * 0.5)
		var freq := lerpf(f0, f1, t)
		phase += freq / RATE
		var s := sin(phase * TAU) * (1.0 - noise_amt) + _rng.randf_range(-1.0, 1.0) * noise_amt
		buf[i] = s * env * 0.45
	return _make_wav(buf)

func _synth_voice(dur: float, f0: float, f1: float, growl: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var env := sin(minf(t * 4.0, 1.0) * PI * 0.5) * pow(1.0 - t, 1.2)
		var vib := sin(t * 28.0) * 0.04
		var freq := lerpf(f0, f1, t) * (1.0 + vib)
		phase += freq / RATE
		var wave := sin(phase * TAU) + 0.5 * sin(phase * TAU * 2.0) + 0.25 * sin(phase * TAU * 3.0)
		var grit := _rng.randf_range(-1.0, 1.0) * growl
		buf[i] = (wave * 0.45 + grit) * env * 0.45
	return _make_wav(buf)

func _make_music_phrase() -> AudioStreamWAV:
	# Gentle pentatonic ambient piano chord progression
	const NOTES := [261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33, 659.25]
	var dur := 8.0
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for note_idx in 4:
		var start := int(note_idx * 1.8 * RATE)
		var f: float = NOTES[_rng.randi() % NOTES.size()]
		var f_fifth := f * 1.5
		var len := mini(int(3.2 * RATE), n - start)
		for j in len:
			var t := float(j) / float(len)
			var env := minf(t * 12.0, 1.0) * pow(1.0 - t, 2.0)
			var tm := float(j) / RATE
			var v := (sin(tm * f * TAU) * 0.6 + sin(tm * f_fifth * TAU) * 0.25 + sin(tm * f * 0.5 * TAU) * 0.3) * env * 0.14
			buf[start + j] += v
	return _make_wav(buf)
