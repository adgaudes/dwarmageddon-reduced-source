class_name RunTuning
extends Resource
## Parametri della run del prototipo della promessa A (D-038). Unita Godot
## (metri, secondi). I nodi copiano i valori all'avvio e non modificano mai la
## risorsa: gli upgrade cambiano le copie, non il file condiviso.

@export_group("Player")
## Playtest del 14 ottobre 2026 (O-01): a 5 si moriva in circa 3 s a contatto e la vita
## "non si sentiva"; a 10, con la spinta al colpo, c'e il tempo di reagire.
@export var player_max_health := 10
## Invulnerabilita dopo un colpo.
@export var player_invulnerability := 0.8
## Al colpo i nemici entro questo raggio vengono respinti (m) a questa velocita (m/s).
@export var hit_shove_radius := 3.0
@export var hit_shove_speed := 9.0
## Raggio entro cui i frammenti di esperienza volano verso il giocatore.
@export var pickup_radius := 2.5

@export_group("Night")
## Secondi di livello all'inizio del tramonto (D-058). 0 = ciclo spento: il livello resta diurno.
@export var night_start_seconds := 270.0
@export var dusk_seconds := 45.0
## Moltiplicatore di velocita dei rottamatori al buio (fuori da ogni luce) di notte.
@export var night_dark_speed_scale := 1.35
## Danno da contatto in piu al buio di notte.
@export var night_dark_contact_bonus := 1
@export var torch_radius := 6.0
@export var beacon_radius := 11.0
## Crescita per livello delle carte `torch_range` e `beacon_range`.
@export var torch_radius_per_level := 1.5
@export var beacon_radius_per_level := 2.0

@export_group("Lamps")
## Rottami del cassone per un lampione (D-058, tappa 2).
@export var lamp_scrap_cost := 3
@export var lamp_max_count := 6
@export var lamp_light_radius := 5.0

@export_group("Enemies")
@export var enemy_speed := 2.2
@export var enemy_health := 2
## Ogni quanti secondi la vita dei nuovi nemici cresce di 1.
@export var enemy_health_growth_seconds := 150.0
## Distanza planare di contatto col giocatore.
@export var contact_radius := 0.75
@export var contact_damage := 1
@export var max_alive := 70

@export_group("Spawning")
@export var spawn_interval_start := 1.6
@export var spawn_interval_min := 0.3
## Secondi per passare dall'intervallo iniziale al minimo.
@export var spawn_ramp_seconds := 300.0
@export var batch_min := 1
@export var batch_max := 3
## Nessun nemico nasce piu vicino di cosi al giocatore.
@export var spawn_min_player_distance := 11.0
## Anello di comparsa attorno al giocatore (D-039), in metri: oltre il bordo
## dello schermo a 1280x800 (circa 15 m in orizzontale), ma non troppo lontano.
## I punti sono riportati dentro l'area giocabile, quindi in un'arena piccola
## cadono sui bordi come prima.
@export var spawn_ring_min := 17.0
@export var spawn_ring_max := 23.0
## Un nemico piu lontano di cosi dal giocatore viene riportato sull'anello di
## comparsa: in un'arena grande l'orda non si disperde dietro le spalle.
@export var enemy_leash_distance := 40.0

@export_group("Weapon")
@export var fire_interval := 0.5
@export var weapon_range := 9.0
@export var weapon_damage := 1
@export var projectile_speed := 24.0

@export_group("Progression")
@export var xp_per_enemy := 1
## Esperienza per passare dal livello 1 al 2; ogni livello ne chiede xp_growth in piu.
@export var xp_first_level := 5
@export var xp_growth := 3
## Level-up consecutivi senza carte Rare prima della garanzia (regola 4).
@export var pity_level_ups := 4

@export_group("World events")
## Eventi del mondo (D-097): quanti ne arrivano lo decidono le impostazioni di Gameplay
## (`world_events_count` vale quando il servizio manca); istanti e tipi sono casuali fra
## `world_events_start_seconds` e la chiamata del boss meno `world_events_boss_margin`,
## distanziati di almeno `world_events_min_gap` secondi.
@export var world_events_count := 1
@export var world_events_start_seconds := 90.0
@export var world_events_boss_margin := 30.0
@export var world_events_min_gap := 60.0

@export_group("Train")
## Treno della ferrovia (D-066), solo dove la scena ha un nodo TrainEvent: preavviso,
## velocita, vagoni, danno al giocatore e al boss travolti.
@export var train_warning_seconds := 10.0
@export var train_speed := 18.0
@export var train_carriages := 5
@export var train_player_damage := 2
@export var train_boss_damage := 30

@export_group("Quake")
## Terremoto del quartiere (D-075), solo dove la scena ha un nodo QuakeEvent: preavviso, lunghezza della faglia in celle, distanza del suo
## centro dal giocatore, danno a chi sta su una cella della faglia.
@export var quake_warning_seconds := 6.0
@export var quake_length_cells := 18
@export var quake_distance_min := 7.0
@export var quake_distance_max := 13.0
@export var quake_player_damage := 1

@export_group("Extraction")
## Piazzola di estrazione (D-076): dopo il boss, un 3x3 (raggio 1) di celle Normal attorno
## al giocatore tenuto integro e occupato per questi secondi; spenta = vittoria subito.
@export var extraction_enabled := true
@export var extraction_hold_seconds := 8.0
@export var extraction_pad_radius := 1

@export_group("Boss")
## Quale boss chiude il livello: `demolisher` (D-043) o `driller` (la Trivella, D-066).
@export var boss_kind: StringName = &"demolisher"
## Secondi di livello prima della chiamata del boss (CAMPAIGN_STRUCTURE_SPEC: livello di 12-15 minuti).
## 0 = nessun boss. `-- --boss-at=N` sulla riga di comando lo anticipa.
@export var boss_call_seconds := 720.0
## Preavviso fra l'annuncio della direzione e l'arrivo.
@export var boss_warning_seconds := 12.0
## Distanza dal giocatore a cui il boss entra in campo, nella direzione annunciata.
@export var boss_spawn_distance := 30.0
@export var boss_health := 150
@export var boss_speed := 1.7
@export var boss_contact_damage := 2
@export var boss_contact_radius := 1.5
## Secondi per smontare una cella Raised.
@export var boss_demolish_seconds := 1.2
## Entro questo raggio un terrapieno lo attira piu del giocatore.
@export var boss_wall_attraction_radius := 12.0
## Mura smontate per costruire una barricata, e barricate in piedi al massimo.
@export var boss_walls_per_barricade := 2
@export var boss_max_barricades := 8
## Rottamatori che lavorano per lui allo stesso tempo (D-045): raccolgono i rottami
## entro `boss_carrier_scrap_radius` da lui e li portano al cantiere della barricata.
@export var boss_max_carriers := 3
@export var boss_carrier_scrap_radius := 10.0
## Un rottamatore e reclutabile se e entro questa distanza dal rottame.
@export var boss_carrier_recruit_radius := 14.0
## Secondi dopo i quali un rottamatore bloccato lascia la commissione (e il rottame).
@export var boss_carrier_timeout := 10.0
## Rottami in piu portati fuori dal livello battendo il boss.
@export var boss_scrap_bonus := 5
## Quota dei rottami che si salva morendo (proposta della specifica di campagna).
@export_range(0.0, 1.0) var death_scrap_share := 0.5
## Rottami di recupero a tempo: uno ogni tanti secondi di livello. 0 = regola spenta
## (D-056: spenta, premiava chi si mura e aspetta).
@export var survival_scrap_seconds := 0.0
## Rottami di recupero per esperienza: uno ogni tanti livelli guadagnati nel livello,
## contati col cassone a fine livello (e ridotti come il cassone se si muore).
## L'esperienza va raccolta fuori dalle mura: chi si chiude dentro non ne matura. 0 = spenta.
@export var recovery_scrap_levels := 0.0

@export_group("Driller")
## La Trivella (D-066): vita, velocita e lunghezza della carica, secondi di mira, di
## riposo e di stordimento dopo un terrapieno, moltiplicatore del danno da stordita.
@export var driller_health := 180
@export var driller_charge_speed := 6.0
@export var driller_charge_length := 30.0
@export var driller_aim_seconds := 2.0
@export var driller_rest_seconds := 3.0
@export var driller_stun_seconds := 3.0
@export var driller_stun_damage_multiplier := 2.0
## Profondita del solco sotto la base e sporgenza minima di un argine che la ferma (metri).
@export var driller_furrow_depth_m := 0.8
@export var driller_wall_min_delta_m := 0.8

@export_group("Runners")
## Rottamatori veloci (D-056): compaiono da `runner_start_seconds` e crescono fino a
## `runner_share_max` dei nuovi nati in `runner_ramp_seconds`. Meno vita, piu velocita:
## non si seminano camminando, ma fossati e mura li fermano come gli altri.
@export var runner_speed := 4.2
@export var runner_start_seconds := 150.0
@export var runner_ramp_seconds := 450.0
@export_range(0.0, 1.0) var runner_share_max := 0.3
## Quota della vita di un rottamatore normale (minimo 1).
@export_range(0.1, 1.0) var runner_health_share := 0.5

@export_group("Hoppers")
## Saltatori (D-066, livello 2): rottamatori leggeri che **non vengono rallentati dalle
## celle Lowered** (le saltano). Compaiono da `hopper_start_seconds` fino a
## `hopper_share_max` dei nuovi nati in `hopper_ramp_seconds`; 0 = nessuno (livello 1).
@export var hopper_start_seconds := 120.0
@export var hopper_ramp_seconds := 300.0
@export_range(0.0, 1.0) var hopper_share_max := 0.0
@export_range(0.1, 1.0) var hopper_health_share := 0.5

@export_group("Terrain")
## Rilievo continuo: un rottamatore fermo contro il terreno per questi secondi rosicchia l'argine.
@export var gnaw_delay_s := 2.0
@export var gnaw_depth_m := 0.6
@export var gnaw_radius_m := 1.2
## Frazione di velocita rimasta sulla pendenza massima del nemico.
@export var uphill_min_speed := 0.5

@export_group("Courtyard")
## Mura iniziali del cortile: anello di celle Raised a questa distanza dal centro
## della griglia, con un varco al centro di ogni lato. 0 = nessuna mura.
@export var wall_ring_radius := 4
