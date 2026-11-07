class_name CaravanTuning
extends Resource
## Parametri della carovana di macchine (spec D-093, "Valori di partenza"; piano A). Unita
## Godot (metri, secondi), valori di partenza non bilanciati. I nodi copiano i valori e non
## modificano mai la risorsa: le carte cambiano le copie, non il file condiviso (come RunTuning).

@export_group("Movement")
## Velocita e accelerazione del compagno di oggi (D-032).
@export var max_speed := 5.0
@export var acceleration := 25.0
## Entro questa distanza dal punto di destinazione la macchina si ferma.
@export var arrive_radius := 0.4
## Piu lontana dal giocatore del raggio del suo posto piu questo margine, la macchina segue
## il campo di percorso invece di puntare dritta.
@export var path_margin := 1.5
## Posti del grappolo attorno al giocatore, uno per macchina: x = gradi dalla direzione
## "dietro al giocatore", y = distanza in metri. Il settimo serve all'Officina mobile.
@export var cluster_slots := PackedVector2Array([
	Vector2(0.0, 2.5), Vector2(60.0, 3.0), Vector2(-60.0, 3.0), Vector2(120.0, 3.5),
	Vector2(-120.0, 3.5), Vector2(180.0, 3.0), Vector2(30.0, 3.5),
])

@export_group("Cargo")
## Rottami nel primo Cassone all'avvio.
@export var starting_scrap := 3
## Rottami che porta ogni Cassone.
@export var cargo_capacity := 5
## Un Cassone raccoglie solo i rottami entro questa distanza dal giocatore.
@export var pickup_radius_from_player := 6.0
## Distanza a cui un rottame viene caricato.
@export var collect_radius := 0.9
## Un lampione si paga solo coi Cassoni entro questa distanza dal punto.
@export var supply_radius := 5.0
## Un Cassone ricerca il rottame da raccogliere al piu ogni tanti secondi (prima ricerca
## subito; la meta si riperde se il rottame sparisce, il Cassone e pieno o il percorso cambia).
@export var cargo_search_interval := 0.2

@export_group("Chassis")
## Punti vita del telaio di una macchina.
@export var chassis_health := 6
## Moduli in tutta la carovana (7 con l'Officina mobile del Meccanico, piano C).
@export var module_limit := 6
## Un rottamatore entro questa distanza planare da una macchina la colpisce.
@export var contact_radius := 0.8
@export var contact_damage := 1
## Immunita di una macchina dopo un colpo.
@export var hit_cooldown := 0.8

@export_group("Repair")
## Rottami e secondi tenendo Interagisci entro `repair_range` da una macchina guasta.
@export var repair_cost := 2
@export var repair_seconds := 1.5
## Con meno di `repair_cost` rottami nella carovana si ripara gratis, ma ci vuole di piu.
@export var repair_seconds_without_scrap := 4.5
@export var repair_range := 2.0
## Vita alla ripartenza, in frazione del massimo.
@export var repair_health_fraction := 0.5

@export_group("Retreat and regen")
## Sotto questa frazione di vita la macchina si ritira; sopra `retreat_until` torna al posto.
@export var retreat_below := 0.3
@export var retreat_until := 0.5
## La ritirata porta a questa distanza dal giocatore, dal lato opposto al nemico piu vicino
## entro `retreat_enemy_range`.
@export var retreat_distance := 5.0
@export var retreat_enemy_range := 12.0
## Secondi senza colpi prima che la vita risalga, poi 1 PV ogni `regen_interval` secondi.
@export var regen_delay := 8.0
@export var regen_interval := 4.0
## Una macchina non guasta piu lontana di cosi dal giocatore torna al suo posto.
@export var leash_distance := 20.0
## Ferma per tanti secondi a piu di 2 m dalla meta, una macchina non guasta torna al suo posto.
@export var stuck_seconds := 3.0

@export_group("Modules")
## Torretta: la chiodatrice del compagno di oggi; ogni livello divide l'intervallo per
## `turret_rate_per_level`.
@export var turret_interval := 0.9
@export var turret_range := 8.0
@export var turret_rate_per_level := 1.35
## Calamita: raggio d'attrazione dei frammenti, piu `magnet_radius_per_level` per livello.
@export var magnet_radius := 2.5
@export var magnet_radius_per_level := 1.5
## Trivella: una buca ogni `drill_interval` secondi entro `drill_reach` dalla macchina.
@export var drill_interval := 4.0
@export var drill_reach := 5.0
@export var drill_radius := 1.2
@export var drill_depth := 0.6
## Fuori da una vena la Trivella scava solo dove il suolo e entro tanti metri dalla base.
@export var drill_flat_tolerance := 0.2
## Pala: ogni `shovel_interval` secondi un argine alto `shovel_height` sulla base, a
## `shovel_gap` dal nemico piu vicino entro `shovel_reach`, per `shovel_cost` rottami.
@export var shovel_interval := 5.0
@export var shovel_reach := 8.0
@export var shovel_radius := 1.0
@export var shovel_height := 1.0
@export var shovel_gap := 1.5
@export var shovel_cost := 1
## Saldatore: 1 PV ogni `welder_interval` secondi alla macchina piu danneggiata entro
## `welder_range`; una guasta in raggio riparte dopo `welder_broken_seconds`.
@export var welder_interval := 3.0
@export var welder_range := 4.0
@export var welder_broken_seconds := 6.0
## Sirena: ogni `siren_period` secondi attira per `siren_active` secondi i rottamatori entro
## `siren_range`, a `siren_pull_speed` m/s.
@export var siren_period := 6.0
@export var siren_active := 3.0
@export var siren_range := 8.0
@export var siren_pull_speed := 4.0
## Trivella e Pala non scrivono il terreno entro questa distanza dal giocatore o da una macchina.
@export var keep_clear := 1.5

@export_group("Wrecks")
## Relitti sepolti per livello, moduli fra cui scegliere e rottami di un relitto a carovana piena.
@export var wrecks_per_level := 2
@export var wreck_choices := 2
@export var wreck_full_scrap := 3

@export_group("Fusion")
## Moduli minimi di ogni taglia (Piccola, Media, Grande, Colosso) e massimo per macchina (piano B).
@export var size_min_modules := PackedInt32Array([1, 2, 4, 6])
@export var max_modules_per_machine := 6
## Forza dei moduli: +`power_per_extra_module` per ogni modulo oltre il primo (scelta 4 di D-093).
@export var power_per_extra_module := 0.15
## Per taglia: vita +`health_bonus_per_size` del totale dei telai, velocita -`speed_malus_per_size`.
@export var health_bonus_per_size := 0.25
@export var speed_malus_per_size := 0.10
## Scala di modello, pezzi, anello a terra e raggio di contatto per taglia.
@export var size_model_scale := PackedFloat32Array([1.0, 1.25, 1.5, 1.8])
## Travolgere: da `trample_min_size` in su, in moto a piu di `trample_min_speed` m/s,
## `trample_damage` a ogni rottamatore in contatto al piu ogni `trample_interval` secondi.
@export var trample_min_size := 1
@export var trample_damage := 1
@export var trample_interval := 0.5
@export var trample_min_speed := 1.0
## Rottami per modulo assorbito in una fusione, e per uno sgancio.
@export var fuse_cost_per_module := 1
@export var detach_cost_per_module := 1

@export_group("Fusion pad")
## La piazzola si annuncia a `pad_boss_fraction` del livello, atterra dopo `pad_warning_seconds`
## fra `pad_distance_min` e `pad_distance_max` dal giocatore: `pad_cells` x `pad_cells` celle
## da `pad_cell_m`, piana entro `pad_flat_tolerance`.
@export var pad_boss_fraction := 0.5
@export var pad_warning_seconds := 15.0
@export var pad_distance_min := 20.0
@export var pad_distance_max := 30.0
@export var pad_cells := 4
@export var pad_cell_m := 1.5
@export var pad_flat_tolerance := 0.35
## Ricerca del punto: candidati per passo e secondi d'anticipo sull'atterraggio.
@export var pad_candidates_per_step := 10
@export var pad_search_lead_seconds := 1.0
## Raggio della luce visiva della piazzola (non e una sorgente di LightField).
@export var pad_light_radius := 9.0

@export_group("Combinations")
## Riflettore e Trappola: danno della Torretta x `combo_damage_scale`; Esca blindata: danno
## subito x `combo_hit_scale`; Estrattore: rottami entro `extractor_radius` dalla buca.
@export var combo_damage_scale := 2.0
@export var combo_hit_scale := 0.5
@export var extractor_radius := 3.0
## Ruspa: ogni `dozer_spacing` metri un fossato dietro la macchina e un argine a lato.
@export var dozer_spacing := 1.5
@export var dozer_ditch_radius := 0.8
@export var dozer_ditch_depth := 0.4
@export var dozer_bank_offset := 1.6
@export var dozer_bank_radius := 0.8
@export var dozer_bank_height := 0.6

@export_group("Colossus")
## Salita e discesa: secondi di pressione di `interact` e portata dal colosso.
@export var pilot_hold_seconds := 0.5
@export var pilot_mount_range := 2.5
## Pilotato: forza dei moduli +`pilot_power_bonus` e velocita del giocatore x `pilot_speed_factor`.
@export var pilot_power_bonus := 0.5
@export var pilot_speed_factor := 0.7
## Carburante: ogni `pilot_fuel_interval` secondi a bordo costa `pilot_fuel_cost` unita.
@export var pilot_fuel_interval := 10.0
@export var pilot_fuel_cost := 1
## Sotto questa frazione di vita il colosso sbalza il pilota; poi ritirata forzata per i secondi indicati.
@export var pilot_eject_below := 0.3
@export var pilot_forced_retreat_seconds := 6.0
## Travolgere: danno per contatto; portata della mira del punto di scavo a bordo.
@export var pilot_trample_damage := 2
@export var pilot_aim_reach := 3.0

@export_group("Events")
## Moduli staccati da terremoto e treno; il treno li lancia a una distanza tra min e max (m).
@export var quake_detach_count := 1
@export var train_detach_count := 1
@export var train_throw_min := 6.0
@export var train_throw_max := 8.0
## Portata per riprendere un modulo staccato (relitto).
@export var relic_pickup_range := 2.0
