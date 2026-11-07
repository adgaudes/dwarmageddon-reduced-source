class_name TerrainTuning
extends Resource
## Parametri del pennello del terreno continuo (D-082, spec tappa A sezione 2.7).
## La griglia a celle e i suoi campi sono stati rimossi con la tappa B (D-087).

@export_group("Brush")
## Pennello del giocatore: raggio, velocita al centro, livella.
@export var brush_radius_m := 2.4
@export var sculpt_rate_m_s := 2.2
@export var level_rate := 5.0
## Pendenza massima di marcia (metri di quota per metro).
@export var max_grade := 0.8
## Zainetto di terra (m3): capacita e quantita all'avvio del livello.
@export var pack_capacity_m3 := 60.0
@export var pack_start_m3 := 20.0
## Distanza del bersaglio del tool davanti al giocatore, metri.
@export var tool_range_m := 3.6
## Dischi non scolpibili attorno alle fondamenta e al cortile di partenza (primi 10 s).
@export var protected_radius_m := 1.5
@export var start_protected_radius_m := 6.0
@export var start_protected_seconds := 10.0
