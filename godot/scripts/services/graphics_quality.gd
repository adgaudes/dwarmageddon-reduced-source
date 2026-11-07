class_name GraphicsQuality
extends RefCounted
## Tabella dei preset grafici (restyling 2026-10-11, spec §5.2) e loro applicazione a
## Environment e sole. I campi corrispondono alle proprieta di GameSettingsService; un
## preset le imposta tutte, toccarne una porta il preset a Personalizzato.

## Preset -> valori dei campi di GameSettingsService.
const PRESETS: Dictionary = {
	GameSettingsService.Preset.STEAM_DECK: {
		"msaa_3d": Viewport.MSAA_DISABLED, "screen_aa": 1, "shadow_quality": 1, "ssao_quality": 1,
		"gi_mode": 0, "glow_quality": 1, "volumetric_fog": false, "texture_quality": 1,
		"vegetation_density": 1, "render_scale": 0.85, "fsr_upscaling": true,
	},
	GameSettingsService.Preset.LOW: {
		"msaa_3d": Viewport.MSAA_DISABLED, "screen_aa": 1, "shadow_quality": 1, "ssao_quality": 0,
		"gi_mode": 0, "glow_quality": 0, "volumetric_fog": false, "texture_quality": 0,
		"vegetation_density": 0, "render_scale": 0.75, "fsr_upscaling": true,
	},
	GameSettingsService.Preset.MEDIUM: {
		"msaa_3d": Viewport.MSAA_2X, "screen_aa": 0, "shadow_quality": 2, "ssao_quality": 1,
		"gi_mode": 0, "glow_quality": 1, "volumetric_fog": false, "texture_quality": 1,
		"vegetation_density": 1, "render_scale": 1.0, "fsr_upscaling": false,
	},
	GameSettingsService.Preset.HIGH: {
		"msaa_3d": Viewport.MSAA_4X, "screen_aa": 0, "shadow_quality": 2, "ssao_quality": 2,
		"gi_mode": 1, "glow_quality": 2, "volumetric_fog": false, "texture_quality": 1,
		"vegetation_density": 2, "render_scale": 1.0, "fsr_upscaling": false,
	},
	GameSettingsService.Preset.MAX: {
		"msaa_3d": Viewport.MSAA_4X, "screen_aa": 1, "shadow_quality": 3, "ssao_quality": 2,
		"gi_mode": 2, "glow_quality": 2, "volumetric_fog": true, "texture_quality": 1,
		"vegetation_density": 2, "render_scale": 1.0, "fsr_upscaling": false,
	},
}
## Dimensione dell'atlante delle ombre direzionali per qualita (0 = ombre spente).
const SHADOW_SIZES: Array[int] = [1024, 1024, 2048, 4096]
const SHADOW_MODES: Array[int] = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_ORTHOGONAL,
	DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS]
## Sole: diametro angolare e distanza d'ombra dei preset alti e dei bassi (audit V-04).
const SUN_ANGULAR_DISTANCE := 1.5
const SHADOW_DISTANCE := 90.0
const LOW_SHADOW_DISTANCE := 55.0
## Moltiplicatore delle istanze di erba, fiori e detriti per densita.
const VEGETATION: Array[float] = [0.35, 0.65, 1.0]


## Applica le opzioni di qualita a un Environment e al sole dell'arena.
static func apply(s: GameSettingsService, environment: Environment, sun: DirectionalLight3D) -> void:
	if sun != null:
		sun.shadow_enabled = s.shadow_quality > 0
		sun.directional_shadow_mode = SHADOW_MODES[s.shadow_quality]
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[s.shadow_quality], true)
		# Audit V-04: con il diametro angolare il sole usa le ombre PCSS (ricerca dei
		# bloccanti e filtro) in ogni pixel illuminato; nei preset bassi niente PCSS, il
		# bordo morbido lo da lo sfocato, e l'ombra copre i 55 m che la camera vede invece di
		# 90 (meno oggetti nella passata d'ombra).
		var low := s.shadow_quality <= 1
		sun.light_angular_distance = 0.0 if low else SUN_ANGULAR_DISTANCE
		sun.directional_shadow_max_distance = LOW_SHADOW_DISTANCE if low else SHADOW_DISTANCE
		sun.shadow_blur = 1.6 if low else 1.2
		RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW if low else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	if environment == null:
		return
	environment.ssao_enabled = s.ssao_quality > 0
	environment.ssao_intensity = 1.6 if s.ssao_quality == 1 else 2.4
	# La qualita dell'SSAO e globale del renderer: bassa = pochi campioni a meta risoluzione.
	if s.ssao_quality == 1:
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, true, 0.5, 2, 50.0, 300.0)
	elif s.ssao_quality == 2:
		RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
	environment.ssil_enabled = s.gi_mode == 1
	environment.sdfgi_enabled = s.gi_mode == 2
	if s.gi_mode == 2:
		environment.sdfgi_cascades = 4
		environment.sdfgi_min_cell_size = 0.3
		environment.sdfgi_use_occlusion = true
		# Playtest del 14 ottobre (O-07): a energia piena il rimbalzo del cielo azzurro
		# riempiva le ombre di blu e le schiariva.
		environment.sdfgi_energy = 0.6
	environment.glow_enabled = s.glow_quality > 0
	environment.glow_intensity = 0.3 if s.glow_quality == 1 else 0.55
	# Basso: un solo livello (meno passate di sfocatura); alto: tre livelli come l'arena.
	for level in 7:
		environment.set_glow_level(level, 0.0)
	if s.glow_quality == 1:
		environment.set_glow_level(2, 0.8)
	elif s.glow_quality == 2:
		environment.set_glow_level(1, 0.6)
		environment.set_glow_level(3, 0.8)
		environment.set_glow_level(5, 0.4)
	environment.volumetric_fog_enabled = s.volumetric_fog
	if s.volumetric_fog:
		# Playtest del 14 ottobre (O-07): a 0,012 la nebbia velava di latte tutto il campo
		# visto dalla camera (15-25 m d'aria) e schiariva le ombre; ora resta una foschia.
		environment.volumetric_fog_density = 0.003
		environment.volumetric_fog_albedo = Color(0.95, 0.85, 0.7)
		environment.volumetric_fog_anisotropy = 0.6
