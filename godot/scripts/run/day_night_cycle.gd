class_name DayNightCycle
extends Node
## Ciclo giorno/notte, tappa 1 (D-058, `docs/DAY_NIGHT_PLAN.md`): dal tempo del livello
## ricava la fase (giorno, tramonto, notte) e un fattore 0..1, e con quello interpola
## sole, luce ambiente, cielo e nebbia del distretto fra il profilo di giorno (letto dai
## nodi cosi come li costruisce `OvergrownArena`) e quello di notte (costanti qui).
## Non ha un passo fisico proprio: `ArenaRun` lo fa avanzare. Non conosce nemici, HUD
## ne `LightField`.

signal phase_changed(phase: Phase)

enum Phase { DAY, DUSK, NIGHT }

const PHASE_NAMES: Array[String] = ["DAY", "DUSK", "NIGHT"]

## Profilo di notte: energie sopra zero, cosi sagome e rilievo del terreno restano leggibili.
## Luna blu e ambiente viola (D-094): con AgX i valori di prima (0,12 e 0,16) davano nero
## pieno fuori dalla torcia; ora il campo si legge in blu e la torcia conta ancora.
const NIGHT_SUN_ENERGY := 0.9
const NIGHT_SUN_COLOR := Color(0.5, 0.6, 1.0)
const NIGHT_AMBIENT_ENERGY := 0.5
const NIGHT_AMBIENT_COLOR := Color(0.35, 0.3, 0.7)
## Notte blu-violacea (direzione artistica: mai monocromo freddo).
const NIGHT_SKY_TOP := Color(0.04, 0.03, 0.10)
const NIGHT_SKY_HORIZON := Color(0.16, 0.10, 0.22)
const NIGHT_FOG_COLOR := Color(0.10, 0.08, 0.16)

## Il distretto (OvergrownArena / RuinsDistrict) che possiede `SunLight` e `WorldEnvironment`.
@export var district: Node3D

var phase := Phase.DAY
## 0 di giorno, 1 a notte piena, in mezzo durante il tramonto.
var night_factor := 0.0
## Secondi di livello all'inizio del tramonto; 0 = ciclo spento, sempre giorno.
var night_start_seconds := 0.0
var dusk_seconds := 45.0

var _sun: DirectionalLight3D
var _environment: Environment
var _day_sun_energy := 1.4
var _day_sun_color := Color.WHITE
var _day_ambient_energy := 0.5
var _day_ambient_color := Color.WHITE
var _day_sky_top := Color.WHITE
var _day_sky_horizon := Color.WHITE
var _day_fog_color := Color.WHITE
var _applied_factor := -1.0


func is_enabled() -> bool:
	return night_start_seconds > 0.0


## Secondi che mancano al tramonto; INF a ciclo spento.
func seconds_to_dusk(elapsed: float) -> float:
	if not is_enabled():
		return INF
	return maxf(night_start_seconds - elapsed, 0.0)


## Da chiamare a ogni passo con il tempo del livello.
func advance(elapsed: float) -> void:
	var new_phase := Phase.DAY
	var factor := 0.0
	if is_enabled() and elapsed >= night_start_seconds:
		factor = clampf((elapsed - night_start_seconds) / maxf(dusk_seconds, 0.001), 0.0, 1.0)
		new_phase = Phase.NIGHT if factor >= 1.0 else Phase.DUSK
	night_factor = factor
	if new_phase != phase:
		phase = new_phase
		print("PROTOTYPE01_NIGHT_PHASE %s time=%.1f" % [PHASE_NAMES[phase], elapsed])
		phase_changed.emit(phase)
	_apply_rendering()


# Interpola i parametri di resa solo quando il fattore cambia o i nodi sono stati ricreati.
func _apply_rendering() -> void:
	if district == null:
		return
	if not is_instance_valid(_sun) or not is_instance_valid(_environment) or _sun == null:
		if not _find_rendering_nodes():
			return
		_applied_factor = -1.0
	if is_equal_approx(_applied_factor, night_factor):
		return
	_applied_factor = night_factor
	var t := night_factor
	_sun.light_energy = lerpf(_day_sun_energy, NIGHT_SUN_ENERGY, t)
	_sun.light_color = _day_sun_color.lerp(NIGHT_SUN_COLOR, t)
	_environment.ambient_light_energy = lerpf(_day_ambient_energy, NIGHT_AMBIENT_ENERGY, t)
	_environment.ambient_light_color = _day_ambient_color.lerp(NIGHT_AMBIENT_COLOR, t)
	_environment.fog_light_color = _day_fog_color.lerp(NIGHT_FOG_COLOR, t)
	var sky_material := _environment.sky.sky_material if _environment.sky != null else null
	if sky_material is ProceduralSkyMaterial:
		sky_material.sky_top_color = _day_sky_top.lerp(NIGHT_SKY_TOP, t)
		sky_material.sky_horizon_color = _day_sky_horizon.lerp(NIGHT_SKY_HORIZON, t)
	elif sky_material is ShaderMaterial:
		# Cielo dipinto (restyling 2026-10-11): stessi due colori come uniform.
		sky_material.set_shader_parameter(&"top_color", _day_sky_top.lerp(NIGHT_SKY_TOP, t))
		sky_material.set_shader_parameter(&"horizon_color", _day_sky_horizon.lerp(NIGHT_SKY_HORIZON, t))


# Cerca sole e ambiente nel distretto e legge da loro il profilo di giorno.
func _find_rendering_nodes() -> bool:
	_sun = district.get_node_or_null(^"SunLight") as DirectionalLight3D
	var world_environment := district.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if _sun == null or world_environment == null or world_environment.environment == null:
		return false
	_environment = world_environment.environment
	_day_sun_energy = _sun.light_energy
	_day_sun_color = _sun.light_color
	_day_ambient_energy = _environment.ambient_light_energy
	_day_ambient_color = _environment.ambient_light_color
	_day_fog_color = _environment.fog_light_color
	var sky_material := _environment.sky.sky_material if _environment.sky != null else null
	if sky_material is ProceduralSkyMaterial:
		_day_sky_top = sky_material.sky_top_color
		_day_sky_horizon = sky_material.sky_horizon_color
	elif sky_material is ShaderMaterial:
		_day_sky_top = sky_material.get_shader_parameter(&"top_color")
		_day_sky_horizon = sky_material.get_shader_parameter(&"horizon_color")
	return true


func sun_energy() -> float:
	return _sun.light_energy if is_instance_valid(_sun) else -1.0


func ambient_energy() -> float:
	return _environment.ambient_light_energy if _environment != null else -1.0
