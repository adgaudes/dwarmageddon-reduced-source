class_name SfxLibrary
extends RefCounted
## Effetti sonori della run e dell'interfaccia. Dal D-084 ogni id ha un file
## registrato in `SAMPLE_DIR` (mix dal bundle Sonniss GDC 2024, generato da
## `tools/audio/build_sfx.py`); se il file manca resta la sintesi in codice di
## D-048: somma di strati (sinusoide, quadra morbida, triangolare, rumore
## filtrato) con inviluppo e glissando, resa come AudioStreamWAV mono a 16 bit,
## con rumore a seme fisso (stream identici a ogni avvio).

enum Wave { SINE, SOFT_SQUARE, TRIANGLE, NOISE }

const SAMPLE_DIR := "res://assets/audio/sfx/"
const MIX_RATE := 22050
const PEAK := 0.85
const FADE_OUT_SECONDS := 0.004
const NOISE_SEED := 20261006

## Tutti gli id disponibili. Gli ultimi quattro non sono collegati da RunAudio:
## li attiva il codice del boss e del portatore.
const IDS: Array[StringName] = [
	&"nail_shot", &"enemy_death", &"player_hurt", &"player_death", &"dash",
	&"terrain_dig", &"terrain_raise", &"tool_reject", &"xp_pickup",
	&"scrap_pickup", &"scrap_spend", &"level_up", &"upgrade_chosen",
	&"boss_warning", &"victory",
	&"boss_spawn", &"boss_demolish", &"boss_barricade", &"carrier_pickup",
	&"dusk", &"nightfall", &"train_horn", &"driller_charge", &"quake_rumble",
	&"ui_move", &"ui_confirm", &"ui_back", &"ui_open",
	# Armi (piano 5 di D-092): campioni Sonniss, nessuna sintesi di riserva.
	&"w_seismic_stake_fire", &"w_seismic_stake_hit", &"w_scrap_launcher_fire", &"w_scrap_launcher_hit",
	&"w_dig_charge_fire", &"w_dig_charge_hit", &"w_welder_fire", &"w_crane_magnet_fire",
	&"w_crane_magnet_hit", &"w_scythe_hit", &"w_bramble_fire", &"w_bramble_hit",
	&"w_site_blade_fire", &"w_site_blade_hit", &"w_jackhammer_fire", &"w_ram_fire",
	&"w_ram_hit", &"w_cement_mixer_fire", &"w_cement_mixer_hit",
]

static var _cache: Dictionary[StringName, AudioStream] = {}
## Precaricamento (R-40): i file si caricano con le richieste in thread del
## ResourceLoader, la sintesi di riserva nel WorkerThreadPool. Id del task e PCM
## gia codificato per id, scritto dal thread sotto mutex e letto dal thread
## principale solo a task finito.
static var _precache_started := false
static var _precache_task := -1
static var _precache_mutex := Mutex.new()
static var _precache_pcm: Dictionary[StringName, PackedByteArray] = {}
## Percorsi chiesti al ResourceLoader in thread e non ancora ritirati.
static var _requested: Array[String] = []


## Stream per id, costruiti una sola volta per processo (il riavvio della run
## ricarica la scena ma non ricarica nulla). Se `precache_async` e in corso ne
## aspetta la fine e usa il suo lavoro; altrimenti carica e sintetizza qui.
static func build_all() -> Dictionary[StringName, AudioStream]:
	if not _cache.is_empty():
		return _cache
	var pcm: Dictionary[StringName, PackedByteArray] = {}
	if _precache_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_precache_task)
		_precache_task = -1
		_precache_mutex.lock()
		pcm = _precache_pcm
		_precache_pcm = {}
		_precache_mutex.unlock()
	for id in IDS:
		var path := sample_path(id)
		if _requested.has(path):
			_requested.erase(path)
			_cache[id] = ResourceLoader.load_threaded_get(path) as AudioStream
		elif pcm.has(id):
			_cache[id] = _wrap(pcm[id])
		else:
			_cache[id] = build(id)
		if _cache[id] == null:
			_cache[id] = synthesize(id)
	_precache_started = false
	return _cache


## Avvia il caricamento dei file e la sintesi dei suoni senza file in thread (dal
## menu iniziale, cosi "Gioca" non li paga). Solo buffer puri nel thread di sintesi;
## gli AudioStreamWAV nascono sul thread principale in `build_all`. Innocuo se ripetuto.
static func precache_async() -> void:
	if not _cache.is_empty() or _precache_started:
		return
	_precache_started = true
	var to_synthesize: Array[StringName] = []
	for id in IDS:
		if has_sample(id):
			var path := sample_path(id)
			if ResourceLoader.load_threaded_request(path, "AudioStream", false, ResourceLoader.CACHE_MODE_IGNORE) == OK:
				_requested.append(path)
		else:
			to_synthesize.append(id)
	if not to_synthesize.is_empty():
		_precache_task = WorkerThreadPool.add_task(SfxLibrary._precache_in_thread.bind(to_synthesize), false, "SfxLibrary.precache")


## Vero quando `build_all` non deve piu caricare, sintetizzare ne aspettare.
static func is_precached() -> bool:
	if not _cache.is_empty():
		return true
	if not _precache_started:
		return false
	if _precache_task >= 0 and not WorkerThreadPool.is_task_completed(_precache_task):
		return false
	for path in _requested:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
	return true


static func _precache_in_thread(ids: Array[StringName]) -> void:
	var pcm: Dictionary[StringName, PackedByteArray] = {}
	for id in ids:
		pcm[id] = _encode(_synthesize(id))
	_precache_mutex.lock()
	_precache_pcm = pcm
	_precache_mutex.unlock()


static func sample_path(id: StringName) -> String:
	return SAMPLE_DIR + String(id) + ".ogg"


static func has_sample(id: StringName) -> bool:
	return ResourceLoader.exists(sample_path(id))


## Un singolo suono: il file registrato se c'e, altrimenti la sintesi; null per un
## id sconosciuto. Se la libreria e gia pronta restituisce la sua risorsa.
## I file si caricano fuori dalla cache del ResourceLoader: la cache statica di
## questa classe li tiene vivi fino all'uscita e il motore li segnalerebbe come
## risorse ancora in uso.
static func build(id: StringName) -> AudioStream:
	if not IDS.has(id):
		return null
	if _cache.has(id):
		return _cache[id]
	if has_sample(id):
		return ResourceLoader.load(sample_path(id), "AudioStream", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	return synthesize(id)


## Sintesi di riserva (D-048) di un singolo suono; null per un id sconosciuto.
static func synthesize(id: StringName) -> AudioStreamWAV:
	var samples := _synthesize(id)
	if samples.is_empty():
		return null
	return _wrap(_encode(samples))


static func duration_of(stream: AudioStream) -> float:
	return stream.get_length()


static func _synthesize(id: StringName) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED + hash(id)
	var b := PackedFloat32Array()
	match id:
		&"ui_move":
			# Tic di metallo: il cursore a chiodo si sposta (D-081).
			b = _buffer(0.05)
			_layer(b, rng, Wave.SINE, 0.0, 0.045, 1900.0, 1500.0, 0.5, 0.001, 3.0)
			_layer(b, rng, Wave.NOISE, 0.0, 0.02, 4000.0, 2500.0, 0.25, 0.001, 3.0)
		&"ui_confirm":
			# Clink di rame: due parziali che salgono.
			b = _buffer(0.16)
			_clink(b, rng, 0.0, 0.12, 1320.0, 0.5)
			_clink(b, rng, 0.05, 0.11, 1760.0, 0.4)
		&"ui_back":
			# Tock piu basso e sordo.
			b = _buffer(0.1)
			_layer(b, rng, Wave.SINE, 0.0, 0.09, 520.0, 360.0, 0.6, 0.001, 2.5)
			_layer(b, rng, Wave.NOISE, 0.0, 0.03, 1500.0, 800.0, 0.2, 0.001, 3.0)
		&"ui_open":
			# Lamiera che scorre: soffio di rumore filtrato con un leggero clink finale.
			b = _buffer(0.22)
			_layer(b, rng, Wave.NOISE, 0.0, 0.18, 900.0, 2600.0, 0.35, 0.03, 1.6)
			_clink(b, rng, 0.14, 0.08, 1100.0, 0.25)
		&"nail_shot":
			# Colpo secco di chiodatrice pneumatica: sbuffo d'aria e scatto.
			b = _buffer(0.075)
			_layer(b, rng, Wave.NOISE, 0.0, 0.07, 5200.0, 1400.0, 0.7, 0.001, 2.5)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.035, 820.0, 260.0, 0.45, 0.001, 2.0)
		&"enemy_death":
			# Tonfo sordo e breve, come un sacco che cede.
			b = _buffer(0.14)
			_layer(b, rng, Wave.SINE, 0.0, 0.14, 210.0, 70.0, 0.9, 0.002, 2.0)
			_layer(b, rng, Wave.NOISE, 0.0, 0.09, 1300.0, 300.0, 0.4, 0.001, 2.5)
		&"player_hurt":
			# Botta sulla lamiera: ronzio basso che cala e un graffio.
			b = _buffer(0.22)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.2, 190.0, 85.0, 0.55, 0.002, 1.6)
			_layer(b, rng, Wave.NOISE, 0.0, 0.12, 2200.0, 400.0, 0.5, 0.001, 2.2)
		&"player_death":
			# Tre note che scendono e un motore che si spegne.
			b = _buffer(1.0)
			_layer(b, rng, Wave.TRIANGLE, 0.0, 0.32, 330.0, 320.0, 0.6, 0.005, 1.5)
			_layer(b, rng, Wave.TRIANGLE, 0.24, 0.32, 247.0, 240.0, 0.6, 0.005, 1.5)
			_layer(b, rng, Wave.TRIANGLE, 0.48, 0.5, 165.0, 150.0, 0.65, 0.005, 1.4)
			_layer(b, rng, Wave.SINE, 0.3, 0.7, 110.0, 45.0, 0.5, 0.05, 1.2)
		&"dash":
			# Soffio d'aria che sale.
			b = _buffer(0.18)
			_layer(b, rng, Wave.NOISE, 0.0, 0.18, 500.0, 3600.0, 0.8, 0.05, 1.6)
			_layer(b, rng, Wave.SINE, 0.0, 0.12, 160.0, 320.0, 0.25, 0.02, 1.5)
		&"terrain_dig":
			# Badilata: terra che frana su un colpo basso.
			b = _buffer(0.2)
			_layer(b, rng, Wave.NOISE, 0.0, 0.2, 950.0, 240.0, 0.75, 0.002, 1.8)
			_layer(b, rng, Wave.SINE, 0.0, 0.14, 125.0, 58.0, 0.7, 0.002, 2.0)
		&"terrain_raise":
			# Il terrapieno sale e si assesta con un colpo di lamiera.
			b = _buffer(0.28)
			_layer(b, rng, Wave.SINE, 0.0, 0.2, 68.0, 165.0, 0.7, 0.02, 1.0)
			_layer(b, rng, Wave.NOISE, 0.0, 0.2, 450.0, 1500.0, 0.35, 0.03, 1.2)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.19, 0.08, 230.0, 150.0, 0.5, 0.001, 2.2)
		&"tool_reject":
			# Due ronzii sordi: "non si puo".
			b = _buffer(0.17)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.065, 150.0, 138.0, 0.6, 0.003, 0.8)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.09, 0.075, 132.0, 118.0, 0.6, 0.003, 0.8)
		&"xp_pickup":
			# Blip morbido che sale.
			b = _buffer(0.09)
			_layer(b, rng, Wave.TRIANGLE, 0.0, 0.09, 880.0, 1320.0, 0.6, 0.004, 1.6)
		&"scrap_pickup":
			# Tintinnio di ferraglia: parziali non armoniche.
			b = _buffer(0.13)
			_clink(b, rng, 0.0, 0.13, 1400.0, 0.6)
		&"scrap_spend":
			# Clangore piu grave: un pezzo lascia il cassone.
			b = _buffer(0.15)
			_clink(b, rng, 0.0, 0.15, 520.0, 0.65)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.04, 210.0, 120.0, 0.35, 0.001, 2.0)
		&"level_up":
			# Arpeggio ascendente di quattro note.
			b = _buffer(0.62)
			var notes: Array[float] = [392.0, 494.0, 587.0, 784.0]
			for i in notes.size():
				_layer(b, rng, Wave.TRIANGLE, 0.09 * i, 0.3, notes[i], notes[i], 0.55, 0.004, 2.0)
				_layer(b, rng, Wave.SINE, 0.09 * i, 0.2, notes[i] * 2.0, notes[i] * 2.0, 0.12, 0.004, 2.5)
		&"upgrade_chosen":
			# Il pezzo scatta in sede, poi due note di conferma.
			b = _buffer(0.28)
			_layer(b, rng, Wave.NOISE, 0.0, 0.04, 3000.0, 900.0, 0.5, 0.001, 2.0)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.05, 190.0, 120.0, 0.45, 0.001, 2.0)
			_layer(b, rng, Wave.TRIANGLE, 0.05, 0.1, 523.0, 523.0, 0.5, 0.004, 1.5)
			_layer(b, rng, Wave.TRIANGLE, 0.13, 0.15, 784.0, 784.0, 0.5, 0.004, 1.8)
		&"dusk":
			# Campana lontana: fondamentale e armonica con decadimento lungo.
			b = _buffer(1.6)
			_layer(b, rng, Wave.SINE, 0.0, 1.6, 220.0, 218.0, 0.6, 0.01, 0.7)
			_layer(b, rng, Wave.SINE, 0.0, 1.1, 440.0, 438.0, 0.25, 0.01, 0.9)
		&"nightfall":
			# Colpo secco grave e un soffio breve.
			b = _buffer(0.4)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.35, 70.0, 52.0, 0.8, 0.005, 1.4)
			_layer(b, rng, Wave.NOISE, 0.0, 0.12, 900.0, 300.0, 0.3, 0.002, 2.0)
		&"train_horn":
			# Fischio di locomotiva: due note tenute, bicordo, con un soffio di vapore.
			b = _buffer(1.1)
			for start: float in [0.0, 0.5]:
				_layer(b, rng, Wave.SOFT_SQUARE, start, 0.5, 311.0, 305.0, 0.5, 0.03, 0.5)
				_layer(b, rng, Wave.SOFT_SQUARE, start, 0.5, 370.0, 364.0, 0.4, 0.03, 0.5)
				_layer(b, rng, Wave.SINE, start, 0.5, 155.5, 152.0, 0.3, 0.03, 0.6)
			_layer(b, rng, Wave.NOISE, 0.0, 1.1, 2200.0, 800.0, 0.12, 0.05, 1.2)
		&"driller_charge":
			# La punta che accelera: ronzio che sale, poi un colpo di cingoli.
			b = _buffer(0.9)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.7, 60.0, 240.0, 0.5, 0.05, 0.4)
			_layer(b, rng, Wave.NOISE, 0.0, 0.8, 600.0, 2400.0, 0.2, 0.05, 0.6)
			_layer(b, rng, Wave.SINE, 0.65, 0.25, 80.0, 50.0, 0.8, 0.003, 1.6)
		&"quake_rumble":
			# Terremoto: brontolio grave che sale e scende, con due schiocchi di roccia.
			b = _buffer(1.6)
			_layer(b, rng, Wave.NOISE, 0.0, 1.6, 140.0, 45.0, 0.45, 0.12, 0.7)
			_layer(b, rng, Wave.SINE, 0.0, 1.4, 38.0, 52.0, 0.7, 0.08, 0.8)
			_layer(b, rng, Wave.TRIANGLE, 0.1, 1.2, 76.0, 60.0, 0.25, 0.1, 0.9)
			for start: float in [0.45, 0.95]:
				_layer(b, rng, Wave.SOFT_SQUARE, start, 0.1, 110.0, 70.0, 0.5, 0.002, 2.2)
		&"boss_warning":
			# Due colpi di sirena grave, da cantiere.
			b = _buffer(1.25)
			for start: float in [0.0, 0.62]:
				_layer(b, rng, Wave.SINE, start, 0.55, 98.0, 94.0, 0.7, 0.04, 0.6)
				_layer(b, rng, Wave.TRIANGLE, start, 0.55, 196.5, 188.0, 0.4, 0.04, 0.7)
				_layer(b, rng, Wave.SOFT_SQUARE, start, 0.55, 147.0, 141.0, 0.18, 0.06, 0.8)
		&"victory":
			# Fanfara corta: salita e accordo tenuto.
			b = _buffer(1.35)
			var rise: Array[float] = [392.0, 523.0, 659.0]
			for i in rise.size():
				_layer(b, rng, Wave.TRIANGLE, 0.14 * i, 0.26, rise[i], rise[i], 0.5, 0.005, 1.6)
			for note: float in [523.0, 659.0, 784.0]:
				_layer(b, rng, Wave.TRIANGLE, 0.44, 0.9, note, note, 0.4, 0.008, 1.3)
			_layer(b, rng, Wave.SINE, 0.44, 0.9, 130.8, 130.8, 0.35, 0.01, 1.2)
		&"boss_spawn":
			# Impatto pesante con coda di macerie.
			b = _buffer(0.95)
			_layer(b, rng, Wave.SINE, 0.0, 0.9, 92.0, 34.0, 1.0, 0.004, 1.6)
			_layer(b, rng, Wave.NOISE, 0.0, 0.8, 850.0, 140.0, 0.55, 0.003, 1.8)
			_layer(b, rng, Wave.SOFT_SQUARE, 0.0, 0.12, 120.0, 60.0, 0.3, 0.002, 2.0)
		&"boss_demolish":
			# Tre colpi di mazza su un muro che si sbriciola.
			b = _buffer(0.48)
			_layer(b, rng, Wave.NOISE, 0.0, 0.48, 1500.0, 280.0, 0.55, 0.004, 1.3)
			for start: float in [0.0, 0.13, 0.27]:
				_layer(b, rng, Wave.SINE, start, 0.14, 105.0, 50.0, 0.7, 0.002, 2.0)
		&"boss_barricade":
			# Lamiere tirate su e sbattute in posizione.
			b = _buffer(0.4)
			_layer(b, rng, Wave.SINE, 0.0, 0.17, 60.0, 115.0, 0.6, 0.02, 1.0)
			_layer(b, rng, Wave.NOISE, 0.15, 0.06, 2600.0, 700.0, 0.45, 0.001, 2.0)
			_clink(b, rng, 0.15, 0.25, 310.0, 0.7)
		&"carrier_pickup":
			# Due tintinnii in salita: il carico e a bordo.
			b = _buffer(0.24)
			_clink(b, rng, 0.0, 0.12, 900.0, 0.55)
			_clink(b, rng, 0.1, 0.14, 1200.0, 0.55)
	return b


static func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * MIX_RATE))
	return b


## Tre parziali non armoniche con decadimento rapido: suono di metallo piccolo.
static func _clink(b: PackedFloat32Array, rng: RandomNumberGenerator, start: float, seconds: float, base: float, amp: float) -> void:
	_layer(b, rng, Wave.SINE, start, seconds, base, base, amp, 0.001, 2.2)
	_layer(b, rng, Wave.SINE, start, seconds * 0.8, base * 1.52, base * 1.52, amp * 0.6, 0.001, 2.6)
	_layer(b, rng, Wave.SINE, start, seconds * 0.6, base * 2.26, base * 2.26, amp * 0.35, 0.001, 3.0)
	_layer(b, rng, Wave.NOISE, start, 0.012, 4000.0, 2000.0, amp * 0.4, 0.001, 2.0)


## Somma uno strato al buffer. Frequenza con glissando esponenziale da
## [param from_hz] a [param to_hz] (per il rumore: taglio del passa-basso);
## inviluppo con attacco lineare e decadimento (1 - t)^[param decay_power].
static func _layer(b: PackedFloat32Array, rng: RandomNumberGenerator, wave: Wave, start: float, seconds: float,
		from_hz: float, to_hz: float, amp: float, attack: float, decay_power: float) -> void:
	var first := int(start * MIX_RATE)
	var count := mini(int(seconds * MIX_RATE), b.size() - first)
	if count <= 0:
		return
	var attack_samples := maxf(attack * MIX_RATE, 1.0)
	var ratio := to_hz / from_hz
	var phase := 0.0
	var low := 0.0
	for i in count:
		var t := float(i) / float(count)
		var hz := from_hz * pow(ratio, t)
		var value := 0.0
		match wave:
			Wave.SINE:
				value = sin(phase * TAU)
			Wave.SOFT_SQUARE:
				value = tanh(3.0 * sin(phase * TAU))
			Wave.TRIANGLE:
				value = 1.0 - 4.0 * absf(fposmod(phase, 1.0) - 0.5)
			Wave.NOISE:
				var alpha := clampf(TAU * hz / MIX_RATE, 0.0, 1.0)
				low += alpha * (rng.randf_range(-1.0, 1.0) - low)
				value = low * 1.8
		phase += hz / MIX_RATE
		var envelope := minf(float(i) / attack_samples, 1.0) * pow(1.0 - t, decay_power)
		b[first + i] += value * amp * envelope
	return


## Normalizza al picco, arrotonda le creste, sfuma la coda e codifica PCM 16 bit.
## Solo buffer: puo girare in un thread.
static func _encode(samples: PackedFloat32Array) -> PackedByteArray:
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	var gain := 1.0 / peak if peak > 0.0001 else 0.0
	var count := samples.size()
	var fade := int(FADE_OUT_SECONDS * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		# tanh(1.5x)/tanh(1.5): saturazione dolce che lascia il picco a 1.
		var value := tanh(samples[i] * gain * 1.5) / 0.9051 * PEAK
		if i >= count - fade:
			value *= float(count - 1 - i) / float(fade)
		data.encode_s16(i * 2, clampi(roundi(value * 32767.0), -32768, 32767))
	return data


## Risorsa audio dal PCM: sul thread principale.
static func _wrap(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
