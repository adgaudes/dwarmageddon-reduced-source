class_name RunLaunchOptions
extends RefCounted
## Opzioni della riga di comando dopo `--`, lette in un solo posto (R-23): menu
## iniziale, run e sonda di smoke test leggono tutte da qui. Una nuova opzione va
## aggiunta qui e, se deve saltare il menu, in AUTOSTART_PREFIXES.

## Opzioni che fanno saltare il menu iniziale e avviano subito il livello.
const AUTOSTART_PREFIXES: Array[String] = ["--autostart", "--seed=", "--boss-at=", "--night-at=", "--quake-at=", "--capture=", "--level=",
	"--class="]


static func wants_autostart(args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	for arg in args:
		for prefix in AUTOSTART_PREFIXES:
			if arg.begins_with(prefix):
				return true
	return false


## `--intro-test`: l'intro all'avvio (BootIntro) gira anche in headless (suite intro_tests).
static func wants_intro_test(args: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	return args.has("--intro-test")


## Livello da avviare subito: `--level=<id>` (D-066: `district`, `railway`), altrimenti vuoto.
static func level_id(args: PackedStringArray = OS.get_cmdline_user_args()) -> StringName:
	return StringName(_value_of("--level=", args))


## Classe del giocatore (D-092): `--class=<id>` (`engineer`, `sapper`, `mechanic`, `weeder`), altrimenti vuoto.
static func class_id(args: PackedStringArray = OS.get_cmdline_user_args()) -> StringName:
	return StringName(_value_of("--class=", args))


## Seme della run: `--seed=N`, altrimenti la variabile d'ambiente `PROTOTYPE01_SEED` (il gate
## la imposta per tutte le suite: audit K-01, risultati riproducibili senza toccare la riga
## di comando, che il menu legge per l'avvio diretto), altrimenti casuale.
static func run_seed(args: PackedStringArray = OS.get_cmdline_user_args()) -> int:
	var value := _value_of("--seed=", args)
	if not value.is_empty():
		return value.to_int()
	var from_env := OS.get_environment("PROTOTYPE01_SEED")
	if from_env.is_valid_int():
		return from_env.to_int()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7fffffff


## Secondi alla chiamata del boss: `--boss-at=S`, altrimenti il tuning.
static func boss_call_seconds(default_seconds: float, args: PackedStringArray = OS.get_cmdline_user_args()) -> float:
	var value := _value_of("--boss-at=", args)
	return value.to_float() if not value.is_empty() else default_seconds


## Secondi all'inizio del tramonto: `--night-at=S` (0 = niente notte), altrimenti il tuning.
static func night_start_seconds(default_seconds: float, args: PackedStringArray = OS.get_cmdline_user_args()) -> float:
	var value := _value_of("--night-at=", args)
	return value.to_float() if not value.is_empty() else default_seconds


## Terremoto forzato per prove e catture: `--quake-at=S` lo mette a S secondi al posto della
## scelta casuale (0 = nessun terremoto); senza opzione -1, cioe decide il pianificatore (D-097).
static func quake_seconds(args: PackedStringArray = OS.get_cmdline_user_args()) -> float:
	var value := _value_of("--quake-at=", args)
	return value.to_float() if not value.is_empty() else -1.0


## Percorso del PNG da salvare al primo frame utile (`--capture=<file>`), o vuoto.
static func capture_path(args: PackedStringArray = OS.get_cmdline_user_args()) -> String:
	return _value_of("--capture=", args)


static func _value_of(prefix: String, args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""
