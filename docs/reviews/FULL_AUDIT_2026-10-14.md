# Audit generale con performance — 14 ottobre 2026

**Oggetto:** tutto il branch `feature/arena-run` al commit `e77cfbe`: 81 script (17.600 righe), 36 suite (12.600 righe), scene principali, 17 shader, `project.godot`, `export_presets.cfg`, gate, strumenti (`tools/`), documenti operativi e igiene del repository. Il restyling dell'Ingegnere (D-088, branch `feature/engineer-restyle`) non e incluso.

**Metodo.** Cinque letture indipendenti e complete per area (terreno, navigazione e nemici; run, boss, compagno e progressione; giocatore, input, servizi e audio; interfaccia, resa e shader; test, gate, strumenti e documenti), **statiche e senza Godot**, cosi da non falsare le misure. In parallelo, **misure con Godot** (matrice di benchmark, sonde temporanee poi rimosse) e verifica a mano, sul codice o con Godot, delle voci di gravita A e delle principali M. Colonna "Verifica": **misurata** = numero preso con Godot oggi; **confermata** = riletta sul codice (o sul sorgente del motore) da chi ha scritto questo documento; **lettura** = solo il revisore d'area, non ripresa.

**Stato delle correzioni** (aggiornato a ogni commit): **14 ottobre, chiuse con test:** S-01, S-02, S-03 (`ConfigIO` con `.bak`, `.tmp` conservato, recupero e copia `.corrupt`; profilo e impostazioni; chiavi e versione conservate), K-05 (allowlist per suite), K-11 (file di prova nella cartella utente), D-02; E-11 (spinta della Trivella), R-02 (cresta del terremoto), R-01 (annuncio con priorita), U-02 (Esci con conferma e incasso), I-01 e I-03 (pennello dopo Alt-Tab, echo), G-01 (zainetto), P-01 (frammenti sul rilievo); **N-01** (cache per chunk e precalcolo a rate: ricentro da 51-64 ms a 0,5-1,4 ms, suite `path_cache_tests`) e PF-02 (fase di corsa nel benchmark); E-12 (martello: da 557 a 18 aggiornamenti del terreno al secondo, `begin_batch`/`end_batch`), T-03 e T-05 (pennellata senza cambiamenti silenziosa, raggio zero), N-02 (ricombinazione solo del rettangolo), E-13 (solco a rate: da 11 a 3,2 aggiornamenti per metro), R-03 (cime dei cortili in cache), E-14, E-15, E-16; **V-01** (prato in porzioni da 32 m: primitive 2,06 M -> 0,78 M, frame Alto 6,83 -> 4,79 ms, Deck 5,42 -> 4,33 ms), R-04 (prato costruito una volta, solo nei quartieri delle run), PF-03 in parte (pennellate e pittura a lotti: primo frame da circa 3,1 s a 2,7 s; restano prato sul rilievo 850 ms e pittura 460 ms), PF-04 e X-02 (exe da 246 a 196 MB), K-01, K-02, K-06, H-02, D-01; V-04 e PF-05 (preset bassi senza PCSS: Deck 337 -> 304 draw call, 4,33 -> 4,05 ms), V-05, Q-02, B-01, B-02, R-06, C-01, R-05, G-02, G-03, K-03 (passo con finestra nel gate), D-04 e D-06 (MIGRATION_STATUS da 65 a 6 KB e stato della roadmap da 26 a 4 KB, il resto in `docs/archive/`). Rimandate di proposito a dopo la misura sul Deck: V-02, V-03, V-06, Q-01, Q-03, Q-04 (V-02 riporterebbe passaggi a gradini fra gli strati del terreno). Gate verde dopo ogni gruppo. Resta per S-02 un avviso nel menu quando il profilo e stato recuperato o era illeggibile (oggi solo i marker `PROTOTYPE01_PROFILE_RECOVERED` e `PROTOTYPE01_PROFILE_CORRUPT`).

Gravita: **A** = puo rovinare una run, perdere dati o rendere ingiocabile il Deck; **M** = comportamento sbagliato o costo evitabile; **B** = debito, incoerenza, caso raro.

## Esito in breve

- **Prestazioni su PC buone in media, con due picchi gravi e un rischio Steam Deck alto.** Frame medio 5,6-6,8 ms (Alto, 70 nemici). Ma **ogni ricentro del campo di percorso costa 51-64 ms** (correndo, uno ogni 1,4 s circa: scatto visibile anche su PC) e il **direttore dei nemici e salito a 2,8-3,0 ms per passo** (1,20 ms il 9 ottobre), per due terzi in `move_and_slide` contro il rilievo. Sul Deck la GPU e il vincolo: 1,4 M triangoli di erba mai scartati, shader del terreno sempre nel ramo pesante, ombre PCSS in tutti i preset; il preset Deck **ha piu draw call del preset Alto**.
- **Dati del giocatore a rischio:** un salvataggio fallito su Windows cancella il profilo (rinomina di Godot verificata nel sorgente 4.7.2), un profilo illeggibile viene sovrascritto da uno vuoto.
- **Gameplay:** la spinta della Trivella puo mandare il giocatore sotto il terreno; l'avviso unico dell'HUD nasconde treno e terremoto durante l'estrazione; "Esci" dalla pausa perde i rottami della run.
- **Gate e documenti:** il seme della run non e fissato ne stampato quando una suite fallisce (radice dell'instabilita di `quake_tests`); il gate e tutto headless e non esercita ne Terrain3D ne gli shader; i documenti "da leggere per primi" pesano 63 KB e contengono prossimi passi superati.

## 0. Misure (PC del proprietario: i7-13620H, RTX 4050 Laptop; Windows; commit `e77cfbe`)

Matrice `benchmark_arena.gd` con finestra 1280x800, limite fps tolto, una misura alla volta. Il Deck ha una CPU circa 2,5-3 volte piu lenta e una GPU circa 6-8 volte piu debole: **nessuna misura sul Deck esiste**.

| Misura | Quartiere | Ferrovia | Note |
|---|---|---|---|
| Frame medio, Alto / Deck / Basso / Massimo (70 nemici) | 6,83 / 5,42 / 3,89 / 8,55 ms | 5,77 / 5,60 / 3,73 / 8,09 ms | |
| Draw call, Alto / Deck / Basso / Massimo | 279 / **316** / 313 / 458 | 319 / **355** / 361 / 473 | i preset bassi hanno **piu** draw call e oggetti dell'Alto (PF-05) |
| Primitive, Alto / Deck / Basso / Massimo | 2,06 M / 1,49 M / 1,08 M / 2,62 M | 2,07 M / 1,51 M / 1,08 M / 2,66 M | circa meta e erba (V-01) |
| VRAM, Alto / Deck / Massimo | 463 / 431 / 865 MB | 466 / 435 / 868 MB | |
| Notte, Alto / Deck | 7,12 / 5,43 ms | — | la notte costa poco |
| Direttore per passo fisico, 70 / 150 / 250 nemici | **2,8-3,05** / 6,05 / 9,79 ms | 2,8-3,0 ms (70) | lineare, circa 0,04 ms per nemico; il 9 ottobre era 1,20 ms |
| Frame con 150 / 250 nemici (Alto) | 19,2 ms (52 fps) / 29,8 ms (33 fps) | — | la fisica a 120 Hz domina |
| Scomposizione del direttore (sonda, 64 nemici) | `move_and_slide` **2,40 ms**, separazione 0,25, campo 0,16, salita 0,15, visuali 0,14, rosicchio 0,14, contatti 0,08 | — | sfera al posto della capsula: 1,92 ms (−20 %); `max_slides = 2`: nessun effetto |
| Movimento procedurale A/B | +4,9 % | — | nel rumore |
| Pennellata media / massima | 1,05-1,22 / 2,3-4,0 ms | 0,79-0,98 / 2,3-3,5 ms | dopo `44185ea`; soglie 1,5 / 4 |
| Campo di percorso: soluzione | 2,9-3,3 ms | 2,9-3,2 ms | soglia 6 |
| **Campo di percorso: ricentro** (sonda, corsa a 7 m/s) | **52-64 ms**, 6 ricentri su 1200 passi | **51-58 ms** | il benchmark non lo misurava (giocatore fermo); N-01 |
| Caricamento reale di un livello (sonda, con finestra) | **3,6-3,8 s**, di cui un primo frame da 3,1 s | 3,6 s | stima Deck 9-11 s; PF-03 |
| Ricostruzione: rovine e verde / base / pennellate | 0,84 / 0,60 / 1,5 s | 0,88 / 0,41 / 1,47 s | le pennellate si riapplicano a ogni avvio |
| Memoria statica dopo il caricamento | 185 MB | 189 MB | |
| Exe Windows | 246 MB | | 132 MB di risorse importate, di cui 48 MB inutili (PF-04) |

`avg_physics_ms` del benchmark non e interpretabile (supera il frame): valgono le righe `step` (L-05).

## 1. Ordine di correzione proposto

1. **Dati del giocatore:** S-01, S-02, poi S-03 (= F-06 del 10 ottobre).
2. **Gameplay che puo rovinare la run:** E-11 (Trivella), R-02 (terremoto sotto giocatore e compagno), R-01 (avviso unico), U-02 ("Esci"), I-01 (pennello bloccato dopo Alt-Tab), G-01 (zainetto), P-01 (frammenti nel terreno).
3. **Picchi CPU:** N-01 (ricentro, cache di pendenze per chunk), E-12 (martello), poi la catena della pennellata (T-01 con T-02, T-03, N-02), E-13, R-03.
4. **Direttore dei nemici (PF-01):** scelta da fare sul metodo (sfera −20 %; nemici a 60 Hz −50 %; movimento cinematico sul campo di quote senza `move_and_slide`, il guadagno maggiore ma un cambio di architettura). Da decidere prima di alzare `max_alive` oltre 70.
5. **Steam Deck, GPU:** V-01 (erba a tile), V-02 (terreno economico nei preset bassi), V-04 (PCSS), PF-05 (draw call dei preset bassi), Q-01 (`frame_queue_size`), Q-02-Q-04; **poi la misura sul Deck** (proprietario, con il Debug Menu F3).
6. **Caricamento:** R-04 (prato costruito due volte), cottura delle pennellate nella base (PF-03).
7. **Gate e test:** K-01 + K-02 (seme fisso e stampato), K-03 (passo con finestra), K-06, K-05, K-07, K-08, K-09.
8. **Documenti:** D-04 + D-06 (MIGRATION_STATUS e ROADMAP corti), D-05, D-01, D-02, D-03.
9. **Dimensione della build e pubblicazione:** PF-04, X-02, H-01, X-03, X-01.

Decisioni del proprietario necessarie: P-02 (regola di Scorta), G-04 (campo visivo sugli schermi larghi), PF-01 (metodo del direttore), Q-03/Q-04 (contenuto del preset Deck, dopo la misura), rimozione degli spike (copertura K).

## 2. Segnalazioni

### 2a. Misure di performance (PF, da questo audit)

| ID | Grav. | Dove | Problema | Correzione | Verifica |
|---|---|---|---|---|---|
| PF-01 | **M** (A sul Deck) | `enemy_director.gd` (ciclo per nemico), `enemy.gd:97-104` | Il direttore costa 2,8-3,0 ms a passo con 70 nemici, di cui 2,4 ms di `move_and_slide` (capsula su `HeightMapShape3D` e rovine, Jolt). A 60 fps sono due passi per frame: sul Deck circa 15 ms solo di nemici. | Sfera (−20 %), nemici a 60 Hz con delta doppio, o movimento cinematico sul campo di quote (ostacoli dal campo di percorso). | **misurata** |
| PF-02 | M | `benchmark_arena.gd` | Il benchmark non muove il giocatore: il ricentro del campo (il passo piu caro del gioco, N-01) non e mai stato misurato. | Fase di corsa nel benchmark con `recenter_ms` massimo. | **misurata** (sonda) |
| PF-03 | M | `arena_run.gd:584-599`, `ruins_district.gd`, `overgrown_arena.gd` | Caricamento 3,6-3,8 s su PC: rovine e verde ricostruiti, prato fatto due volte (R-04), pennellate del livello riapplicate a ogni avvio (1,2-1,5 s) anche con `base.bin`. | R-04; cuocere nella base anche le pennellate (con le vene in un file a parte); misurare il Deck. | **misurata** |
| PF-04 | M | `godot/assets/textures/surfaces/ground_{albedo,normal,orm}.png` | I tre fogli `ground_*` diventano array da 16 MB l'uno nel pacchetto, ma li legge solo lo strumento `pack_terrain_tiles.gd` con `Image.load_from_file` (dopo D-085 il suolo e Terrain3D). 48 MB dei 132 importati. | Import "Skip" per i tre file (lo strumento legge il PNG grezzo) o esclusione dall'export. | **confermata** |
| PF-05 | M | `graphics_quality.gd`, costruzione del quartiere | I preset Deck e Basso hanno piu draw call e oggetti dell'Alto (316 e 313 contro 279; 1853-1904 oggetti contro 1531). Causa non individuata. | Capire quale opzione dei preset bassi spezza il batching (ombre? LOD? vegetazione?) prima di toccare V-06. | **misurata** |

### 2b. Terreno, navigazione, nemici, combattimento (T, N, E)

| ID | Grav. | Dove | Problema | Scenario | Correzione minima | Verifica |
|---|---|---|---|---|---|---|
| N-01 | **A** perf | `path_field.gd:300,321,375-416` | Ogni ricentro ricalcola pendenza e passi di tutte le 4096 celle (circa 82k `height_at`). | Ogni 9,6 m di corsa: 51-64 ms su PC, 130-190 ms stimati sul Deck. | Cache per chunk dei bit di pendenza e passo invalidata da `region_changed`; il ricentro copia. | **misurata** |
| E-11 | **A** | `driller.gd:343-352` | La spinta laterale della Trivella sposta il corpo di 2,6 m tenendo la vecchia quota, senza controllare terreno, bordo o rovine. | Giocatore accanto a un argine o a un cumulo di 1-1,5 m: finisce sotto la heightfield (una faccia sola) e cade o resta incastrato. | La logica di `train_event._push_out` (quota + lift, punto calpestabile, altro lato, altrimenti niente spinta). | **confermata** |
| E-12 | **A** perf | `demolisher.gd:370-381` | Il martello fa a ogni passo una `level` (r 3,6) e 8 `sculpt` (r 3), ognuna con specchio, `update_maps`, chunk e `region_changed`. | Ogni muro: 0,5-1 s a 9 pennellate per passo, stimati ≥ 9 ms a passo su PC. | Martello a 10 Hz; terra smossa in un'unica operazione. | **confermata** (costo stimato) |
| T-01 | M perf | `terrain_collision.gd:65-76` | `_refresh_chunk` ricampiona con `height_at` 1089 vertici per chunk invece di copiarli da `_heights`. | Ogni pennellata di chiunque; all'avvio circa 85 ms. | Copia diretta delle righe (richiede T-02). | lettura |
| T-02 | M | `railway_run.tscn:42`, `terrain_field.gd:48-50`, `terrain_collision.gd:37,68` | Ferrovia 319,2 x 122,4 m: vertici a z ≡ 0,25 (mod 0,5), chunk campionati a meta fra due vertici; collisione fino a circa 0,2 m sotto le creste. | Livello 2, argini e vagoni. | `size_m = (320, 123)`, ricuocere la base, `assert` sull'allineamento. | lettura |
| N-02 | M perf | `path_field.gd:375-385` | `_refresh_blocked` scorre 4096 celle a ogni `region_changed`. | Ogni passo con il tool, la Trivella o il martello: 0,4-0,8 ms. | Solo il rettangolo toccato. | lettura |
| T-03 | M perf | `terrain_field.gd:495-519` | `_brush` specchia ed emette anche se nessun vertice cambia. | Scavo fermo al fondo, alzata al massimo, disco protetto: circa 1 ms a passo per niente. | Contare i vertici cambiati, uscire se zero. | lettura |
| E-13 | M perf | `driller.gd:308-313` | In carica: uno scavo e un `CPUParticles3D` nuovo a ogni passo (120 nodi/s, circa 54 vivi). | Ogni carica da 5 s. | Scavo ogni 0,3 m, schizzo ogni 0,15 s. | lettura |
| E-14 | M perf | `enemy_director.gd:241-249` | I secchi di separazione non si rimuovono mai (fino a 4096 chiavi); il `clear()` sopra 4096 toglie la separazione in quel passo. | Run lunga: circa 0,2 ms a passo. | Lista dei secchi attivi. | lettura |
| E-15 | M perf | `auto_weapon.gd:115-153` | Per chiodo e per passo: nuova query di raggio e distanza dal segmento su tutti i nemici. | 20 chiodi x 70 nemici: circa 0,5 ms a passo. | Scarto per distanza² e query riusata. | lettura |
| E-16 | M perf | `demolisher.gd:613-625` | `_nearest_wall_point` riscansiona 4 dischi annidati (4564 iterazioni). | Ogni 0,4 s senza muro vicino: 1-1,5 ms. | Una passata unica. | lettura |
| N-03 | B | `flow_preview.gd:243-259` | Con il pennello tenuto premuto le scie si ritracciano a ogni soluzione e non svaniscono. | Tool premuto. | Non riarmare se gia visibili. | lettura |
| E-17 | B perf | `demolisher.gd:426-435` | `_reachable` prima del confronto di distanza. | Rottami ogni 0,4 s. | Invertire l'ordine. | lettura |
| T-04 | B | `terrain_collision.gd:56-57` | Il vertice di bordo fra due chunk non aggiorna il chunk precedente. | Treno verso −X, reset isolati. | `floor((pos − 0,001)/16)`. | lettura |
| T-05 | B | `terrain_field.gd:231,291,375,506` | Raggio 0: NaN nelle quote. | Solo da tuning. | Uscire con raggio ≤ 0. | lettura |
| T-06 | B | `terrain_field.gd:404-405` | Rinomina del `base.bin` non controllata; header di 36 byte, non 32. | Solo nello strumento di cottura. | Controllare l'errore. | lettura |
| E-18 | B | vari (elenco nel rapporto d'area) | Commenti dell'epoca della griglia, codice morto (`_refresh_terrain`, `DIAGONAL_COST`, wrapper vuoti), duplicazioni. | — | Pulizia. | lettura |

Da verificare con Godot: danno da spine sugli argini dolci (normale del contatto non filtrata, `enemy_director.gd:353`); barricata che alza 1,5 m sotto un nemico a 1,9 m (`demolisher.gd:693`); resa della ferrovia sfasata di 0,25 m (T-02); tre `update_maps` per passo del treno sui vagoni (`train_event.gd:211-215`).

### 2c. Run, boss, compagno, progressione (R, B, C, P)

| ID | Grav. | Dove | Problema | Scenario | Correzione minima | Verifica |
|---|---|---|---|---|---|---|
| R-01 | M | `run_hud.gd:207-226`, `arena_run.gd:190-197`, `extraction_pad.gd:74-80`, `train_event.gd:148-152`, `quake_event.gd:167-170` | Un solo avviso nell'HUD, scritto a ogni passo da boss, treno, terremoto e piazzola: vince l'ultimo (la piazzola, senza freccia). | Ferrovia, piazzola sulla fascia dei binari: il treno non viene annunciato, colpisce il giocatore. Uguale col terremoto. | Priorita (treno/terremoto > boss > piazzola) o due righe. | lettura (due revisori indipendenti) |
| R-02 | M (A se confermato) | `quake_event.gd:221-257` | Giocatore e compagno sono risparmiati solo entro 1,2 m, la cresta ha raggio 2,4 m e `_lift_bodies` riappoggia solo i nemici. | Compagno a 1,3-1,7 m dalla faglia: il suolo gli sale sopra il centro. | Riappoggiare anche giocatore e compagno. | lettura |
| P-01 | M | `xp_field.gd:50,73-81` | Frammenti di esperienza a y = 0,35 assoluta; nessun riferimento al terreno. | Nemico ucciso su un argine o un cumulo: frammento invisibile dentro il terreno. | `height_at + 0,35` alla posa e in volo. | **confermata** |
| P-02 | M | `arena_run.gd:548-553`, `companion.gd:234-238` | Scorta liv. 2 non aggiunge nulla senza Cassone (rottami tagliati alla capienza). | 7 rottami di Officina spesi a vuoto. | Regola da decidere (proprietario). | lettura |
| C-01 | M | `companion.gd:149-152,170-181` | Verso un rottame raggiungibile il compagno va dritto, anche contro un argine. | Rottami dietro l'argine con varco lontano: compagno bloccato. | Accettare il rottame solo con linea percorribile. | lettura |
| R-03 | M perf | `arena_run.gd:208-235` | Ogni secondo `highest_bump` su dischi di 9-14 m per ogni cortile (circa 20.000 iterazioni con allocazioni). | Picco di qualche ms al secondo. | Solo i punti delle pennellate, o su `region_changed`. | lettura |
| R-04 | M perf | `overgrown_arena.gd:905,994-1022`, `ruins_district.gd:195`, `railway_district.gd:131` | Il prato si costruisce due volte a ogni avvio (a quota 0, poi sul rilievo). | Ogni "Gioca" e riavvio. | Saltare la prima costruzione col rilievo non pronto. | lettura (coerente con PF-03) |
| R-05 | M visivo | `ruins_district.gd:659-660,700-725` | Corone e tondini delle rovine (MultiMesh) non seguono il riappoggio dei blocchi sul rilievo. | Corone che galleggiano o affondano. | Comporle dopo il riappoggio. | lettura |
| B-01 | B | `arena_run.gd:483-488,797-800` | Con l'estrazione il boss e gia liberato a fine livello: la mappa perde le barricate. | Ogni vittoria nel quartiere. | Copiare i punti in `_on_boss_died`. | lettura |
| B-02 | B | `arena_run.gd:185-200` | Dopo treno, terremoto e piazzola non si ricontrolla `is_over`. | Morte nel passo della chiamata del boss. | `if is_over: return` dopo ogni evento. | lettura |
| R-06 | B | `quake_event.gd:149-204` | Faglia vuota (tutta fuori campo o protetta) ma preavviso e rombo partono. | Giocatore al bordo. | Nuova estrazione o salto del ciclo. | lettura |
| P-03 | B perf | `upgrade_catalog.gd:24-86` | `value()` ricostruisce il catalogo a ogni chiamata, a ogni passo di scavo con Scavo esplosivo. | 120 ricostruzioni al secondo. | Cache. | lettura |
| P-04 | B perf | `xp_field.gd:64-91` | Ogni frammento ruota e cerca l'attrattore a ogni passo. | Fino a 250 frammenti x 120 Hz. | Rotazione nello shader, attrattore ogni N passi. | lettura |
| R-10 | B perf | vari | Allocazioni per passo residue (indicatori, stringhe d'avviso, `duplicate()` del treno, mesh nuove dell'esplosione). | Continuo, piccolo. | Riuso. | lettura |
| P-05 | B | `arena_run.gd:539-559,883-890`, cataloghi | R-15 a meta: Torcia e Faro leggono il tuning, il testo il catalogo; valori permanenti cablati. | Un ritocco rende falso il testo. | Valori solo nei cataloghi. | lettura |
| R-07 | B | `run_tuning.gd:100-105`, `extraction_pad.gd:29-32` | `extraction_pad_radius` morto; raggio e tolleranza cablati nel nodo. | — | In `RunTuning`. | lettura |
| R-09 | B | `arena_run.gd:580-589`, `terrain_field.gd:408-419` | `base.bin` accettato se coincide il seme anche con parametri di composizione cambiati. | Ritocco del quartiere dall'Inspector. | Hash dei parametri nell'header. | lettura |
| R-08 | B | vari | Commenti orfani, variabili e segnali morti (`wall_ring_radius`, `cells_filled`, "Hazard assist"). | — | Pulizia. | lettura |

Da verificare con Godot: `quake_event.boss` mai azzerato dopo la liberazione del boss (`boss != null` con un oggetto liberato: errore e scossa nulla durante l'estrazione; correzione `is_instance_valid` comunque utile); costo GPU del tramonto (parametri del cielo riscritti a ogni passo per 45 s); istanza dei 6 vagoni del treno a ogni passaggio (GLB da 8,4 MB).

### 2d. Giocatore, input, servizi, audio, configurazione (G, I, S, A, X)

| ID | Grav. | Dove | Problema | Scenario | Correzione minima | Verifica |
|---|---|---|---|---|---|---|
| S-01 | **A** | `config_io.gd:15-17` | Su Windows `DirAccess.rename` di Godot 4.7.2 **cancella la destinazione e poi chiama `MoveFileW`** (`drivers/windows/dir_access_windows.cpp:340-346`); se `MoveFileW` fallisce, `save_atomic` cancella anche il `.tmp`: profilo e impostazioni spariscono. Nessuno recupera il `.tmp` al caricamento. | Antivirus che tiene aperto il `.tmp` a fine run: al riavvio profilo vuoto. | Vecchio → `.bak`, `.tmp` → finale; non cancellare il `.tmp` se la rinomina fallisce; al caricamento ripiegare su `.tmp`/`.bak`. | **confermata** (sorgente del motore) |
| S-02 | **A** | `player_profile.gd:115-123`, `game_settings.gd:139-144` | Un profilo che non si analizza lascia i valori azzerati da `reset()`; il primo salvataggio sovrascrive l'originale. | Riga troncata: tutti i rottami e gli upgrade persi senza avviso. | Copia `profile.cfg.corrupt-<data>` prima di salvare, tentare `.bak`, avviso nel menu. | **confermata** |
| G-01 | M | `player_character.gd:402-407` | In Alza lo zainetto paga il volume teorico, non quello posato (protezioni, quota massima, bordo). | Alzare vicino a una rovina: la terra sparisce. | Pagare il volume restituito da `player_sculpt`. | lettura |
| G-02 | M | `player_character.gd:372-384` | Mira col mouse: intersezione con il piano alla quota del giocatore, non con il terreno sotto il cursore. | In una buca da 2,5 m l'anello sta 1,75 m oltre il cursore. | Due o tre iterazioni a punto fisso con `height_at`. | lettura |
| G-03 | M | `player_character.gd:419-420`, `character_animator.gd:194-199` | `play_dig()` a ogni passo mentre il tool e premuto (120 richieste al secondo al OneShot). | Affondo forse congelato sui primi fotogrammi. | Solo all'inizio e poi ogni `DIG_SECONDS`. | lettura, da verificare |
| I-01 | M | `player_character.gd:197-224,274-275` | Lo stato premuto si azzera solo all'uscita dalla pausa; la perdita di focus non genera il rilascio. | Alt-Tab mentre si scava: al ritorno il pennello scava da solo. | Reset su `NOTIFICATION_APPLICATION_FOCUS_OUT` e autocorrezione con `Input.is_action_pressed`. | lettura |
| I-02 | M | nessun `Input.mouse_mode` | Cursore di sistema mai nascosto ne confinato. | Col controller il puntatore resta sopra l'arena; con due monitor si clicca fuori finestra. | `CONFINED` in run, `CONFINED_HIDDEN` col controller, `VISIBLE` nei menu. | lettura |
| S-03 | B | `player_profile.gd:12-14,124,139-152` | Chiavi sconosciute di `[profile]` perse; versione riscritta a 1 (= F-06 del 10 ottobre, aperta). | Rollback a una build vecchia. | Conservare le chiavi, scrivere `maxi(VERSION, loaded)`. | lettura |
| A-01 | B | `sfx_library.gd:127-134`, `boot_intro.gd:51,150-153` | `build()` non ripiega sulla sintesi se il file e corrotto e ricarica in sincrono un file gia chiesto in thread. | OGG danneggiato: intro muta. | Usare `load_threaded_get` se richiesto, sintesi se null. | lettura |
| I-03 | B | `player_character.gd:204-212` | Un echo di tastiera finisce nel ramo di rilascio (P-02 del 9 ottobre, residuo). | Raro. | Saltare gli echo. | lettura |
| G-04 | B | `isometric_camera_rig.gd:132` | `KEEP_WIDTH` con 90° orizzontali: su 21:9 si vede il 31 % in meno in verticale. | Ultrawide. | `KEEP_HEIGHT` a 64° (decisione). | lettura |
| G-05 | B perf | `player_character.gd`, `soil_pack.gd:25-30` | Piccoli costi per passo (`_brush_blocked` doppio, `get_node` delle impostazioni, segnale dello zainetto pieno a 120 Hz). | — | Cache e emissione solo se cambia. | lettura |
| G-06 | B | `hip_twist_modifier.gd:33` | `_process_modification()` deprecato dal 4.4. | Rimozione futura. | `_process_modification_with_delta`. | lettura |
| I-04 | B | `tuning_switcher.gd:63,76` | Etichette con tasti del pad che non esistono piu. | `ruins_arena`. | Correggere il testo. | lettura |
| S-04 | B | `run_launch_options.gd:40-54` | Opzioni non numeriche diventano 0 (`--boss-at=abc` chiama il boss subito). | Errore di battitura. | Validare. | lettura |
| X-01 | B | `project.godot:29`, `debug_menu.gd:129-138` | Debug Menu e misura del tempo GPU attivi anche nella build release. | Va tolto prima di Steam. | Preset di export "perf" separato. | lettura |
| X-02 | B | `export_presets.cfg:10,41` | Pennelli e icone dell'editor di Terrain3D (12 MB) nel pacchetto. | Dimensione. | Escluderli. | lettura |
| X-03 | B | `export_presets.cfg:11,28-30` | Exe e proprieta "Prototype01", icona di Godot. | Proprieta del file. | Nome, `.ico`, `modify_resources`. | lettura |

Da verificare con Godot: `frame_queue_size=1` sul Deck (vedi Q-01); FSR 2 + FXAA nel preset Deck (Q-03); scatto in discesa con `floor_snap_length` di 0,1 m (a 29 m/s ci si stacca sopra pendenza 0,4); OGG contro WAV per i suoni frequenti sul Deck; richieste in thread mai ritirate uscendo dal menu senza giocare.

### 2e. Interfaccia, resa, preset (U, V, Q)

| ID | Grav. | Dove | Problema | Scenario | Correzione minima | Verifica |
|---|---|---|---|---|---|---|
| V-01 | **A** (Deck) | `overgrown_arena.gd:985-987,1050-1064`, `ruins_district.gd:143-158` | Erba, fiori e detriti sono tre MultiMesh grandi come la mappa, senza `visibility_range` ne tile: sempre nel frustum. Circa 1,38 M triangoli su due passate (prepass e colore) per vedere il 2-4 % dell'area. | Sempre, sul Deck. | Tile da 32 m (un `MultiMeshInstance3D` per tile) e `visibility_range_end`. | **confermata** (assenza di culling); costo sul Deck stimato |
| V-02 | M | `terrain_relief.gdshader:372-519` | Con 0,5 m per vertice e circa 3 cm per pixel il ramo `bilerp` e attivo su tutto lo schermo: fino a 16 `textureGrad` e circa 25 letture per pixel. | Costo GPU fisso sul Deck. | `low_quality` dai preset Deck e Basso. | lettura |
| V-03 | M | `ruin_overgrown.gdshader:41-109` | 6 `fbm` (circa 120 hash) e 9 letture anisotrope per pixel sulle rovine. | Rovine e torri in camera. | Variante economica nei preset bassi o rumore in texture. | lettura |
| V-04 | M | `overgrown_arena.gd:1158-1161`, `graphics_quality.gd:44-48` | `light_angular_distance = 1,5` attiva le ombre PCSS in tutti i preset; distanza d'ombra 90 m contro 45-60 visibili. | Ogni pixel illuminato sul Deck. | Nei preset bassi: angolo 0, 55 m, filtro piu basso. | lettura |
| V-05 | M | `overgrown_arena.gd:1101-1110` | Fiori come sfere da 48 triangoli per 4 px. | 192 k triangoli. | Ottaedro o due quad. | lettura |
| V-06 | M | `ruins_district.gd:632-695`, `overgrown_arena.gd:673-687` | Circa 20 `MeshInstance3D` per rovina e 2-4 per cespuglio, tutti con ombra. | CPU di resa sul Deck. | MultiMesh per rovina o tile. | lettura |
| Q-01 | M | `project.godot:180` | `frame_queue_size=1`: CPU e GPU non si sovrappongono, il frame vale la loro somma. Non registrato in DECISIONS. | Deck. | 2 (latenza col limite di fps) e decisione registrata. | lettura |
| Q-02 | M | `terrain_field.gd:557-563` | Il LOD ridotto del terreno vale solo per i preset Deck e Basso esatti: toccare un'opzione (Personalizzato) lo toglie. | Utente Deck che spegne l'SSAO. | Campo `terrain_detail` nei preset. | lettura |
| Q-03 | M | `graphics_quality.gd:9-13` | Preset Deck con FSR 2 a 0,85 (scie su erba mossa nel vertex shader, senza vettori di movimento) e FXAA sopra. | Deck in movimento. | FSR 1 o bilineare + FXAA, dopo misura. | lettura |
| Q-04 | M | `graphics_quality.gd:9-18` | Il preset Deck accende SSAO e glow e non tocca V-01-V-04. | Deck. | Partire da Basso, decidere con una misura. | lettura |
| U-02 | M | `pause_menu.gd:29` | "Esci" chiama `get_tree().quit` senza `abandon_run()` (che "Torna al menu" fa); nessuna conferma. | Esce a meta run: quota di rottami persa, run non contata. | `abandon_run` prima di uscire, conferma. | **confermata** |
| U-03 | B perf | `run_hud.gd:231-280,363` | Override di colore e stringhe rifatti a ogni passo per gli indicatori. | 5 indicatori x 60/s. | Solo se cambiano. | lettura |
| U-04 | B | `settings_menu.gd:35,103,191-199` | Scale 0,85 e 0,75 mostrate come 80 % e 70 %. | Menu sul Deck. | Voci 75 % e 85 %. | lettura |
| U-05 | B | `run_hud.gd:183,249,272` | Indicatori a sud-ovest sopra la colonna dei comandi. | 1280x800. | Margine. | lettura |
| V-07 | B | `env_baked.gdshader:50,54`, `rusted_metal.gdshader:29,33` | `fbm` calcolati anche dove pesano zero. | Prop in camera. | Rami coerenti. | lettura |
| V-08 | B | vari | Commenti falsi, materiale e mesh del carico creati per nemico. | — | Pulizia, risorse condivise. | lettura |
| Q-05 | B | `Invoke-GodotChecks.ps1:47-50` | Allowlist di P-09 rimasta dopo la rimozione di `terrain_grid.gd` (vedi K-05). | Gate. | Togliere e rilanciare. | lettura |

R-01 di 2c e U-01 del rapporto d'area sono lo stesso difetto (avviso unico): una voce sola.

Da verificare con Godot: costo per passata sul Deck (vegetazione, terreno, rovine, SSAO, ombre, glow, spenti uno alla volta); radiance del cielo ricalcolata durante il tramonto; ordine di `_input` durante le transizioni di `UiFx`; riallocazioni grafiche a ogni `changed` delle impostazioni (anche per il volume); larghezza delle righe del pannello Impostazioni a 1280x800.

### 2f. Test, gate, strumenti, documenti, repository (K, L, D, H)

| ID | Grav. | Dove | Problema | Scenario | Correzione minima | Verifica |
|---|---|---|---|---|---|---|
| K-01 | M | `Invoke-GodotChecks.ps1:118`, `run_launch_options.gd:30-35` | Il gate non passa `--seed`: 16 suite di run cambiano seme a ogni esecuzione; dipendono dal seme almeno `boss_tests.gd:127-155` e `district_tests.gd:225-231`. | Rossi intermittenti come `quake_tests` (corretta in `e77cfbe`). | Seme fisso per suite piu `-SeedSweep N`. | lettura (lo schema e stato **misurato** su `quake_tests`) |
| K-02 | M | `Invoke-GodotChecks.ps1:79-80,125` | Una suite fallita perde seme e log. | Il seme di quake e stato ritrovato a mano. | Filtro su `RUN_START` e copia del log in `output/gate/`. | lettura |
| K-03 | M | gate, `restyle_tests.gd:73-86`, 17 shader | Gate tutto headless: ramo Terrain3D (compreso il test di `44185ea`) e compilazione degli shader mai eseguiti. | Uno shader rotto o lo smarcamento tolto: gate verde. | Passo con finestra a 320x200 e smoke con finestra che conta `SHADER ERROR`. | lettura (il test di `44185ea` gira solo con finestra: **misurata**) |
| K-05 | M | `Invoke-GodotChecks.ps1:45-58` | Allowlist globale, anche per gli smoke test. | Mesh senza materiale nascosta ovunque. | Allowlist per suite. | lettura |
| K-06 | M | `Invoke-GodotChecks.ps1:97-98,133-134` | Lo smoke test ignora exit code e timeout. | Crash all'uscita o blocco dopo i marker: PASS. | Contare il codice d'uscita. | lettura |
| K-07 | M | `path_field_tests.gd:343,349`, `audio_tests.gd:116-125` | Soglie a tempo reale nelle suite funzionali. | Rosso per carico della macchina. | Budget nei benchmark o soglie larghe. | lettura |
| L-01 | M | comandi Blender in `GODOT_WORKFLOW.md`, `tools/blender/*.py` | Nessun comando usa `--python-exit-code 1`: Blender esce con 0 anche su eccezione. | Export parziale dichiarato fatto. | Aggiungere l'opzione, validare i nomi. | lettura |
| D-01 | M | `GODOT_WORKFLOW.md:98` | "`--fixed-fps 60` … risultati deterministici": falso senza `--seed`. | Radice dell'instabilita di quake. | Riscrivere. | lettura |
| D-02 | M | `GODOT_WORKFLOW.md:94` | Allowlist "vuota dal 12 ottobre", ma ha una voce. | — | Allineare. | lettura |
| D-03 | M | `MIGRATION_STATUS.md:5` | Minori della review dell'Ingegnere nel registro in `.superpowers/`, ignorato da Git. | Nuova sessione o clone non li vede. | Spostarli in `docs/REVIEWS/` (all'integrazione di D-088). | lettura |
| D-04 | M | `MIGRATION_STATUS.md:256-260`, `PROJECT_ROADMAP.md:75,82,87` | Prossimi passi gia fatti (giorno/notte, migrazione del terreno, audio); 14 voci di "Prossimo passo". | Una sessione nuova non sa cosa fare. | Al massimo 5 voci correnti; il resto in storia. | lettura |
| D-05 | M | `DECISIONS.md:36,58,64`, `INDEX.md:63-64` | D-042 (griglia), D-048 (nessun file audio), D-020 (nessun MCP) non segnate come superate; D-088 citata ma assente su questo branch; INDEX cita `sculpt.py` e `build_engineer.py`, che qui non esistono. | Decisioni superate prese per buone. | Segnare gli stati; rimandi a D-088 come "su branch non integrato". | lettura |
| D-06 | M | dimensioni | MIGRATION_STATUS 63 KB, ROADMAP 61 KB, DECISIONS 106 KB, WORKFLOW 49 KB: circa 16.000 token prima del prossimo passo. | Costo e confusione a ogni sessione. | MIGRATION_STATUS sotto 8 KB con archivio a parte; ROADMAP corta; DECISIONS con righe brevi e dettagli separati. | lettura |
| L-05 | B | `benchmark_arena.gd:161` | `avg_physics_ms` non interpretabile (piu del frame). | Misure fuorvianti. | Togliere o calcolare dal tempo di `_physics_process`. | **misurata** |
| K-04 | B | `Invoke-GodotChecks.ps1:55` | Le righe `WARNING:` non contano. | Regressioni segnalate solo da warning. | Contarle almeno negli smoke test. | lettura |
| K-08 | B | `terrain_field_tests.gd:241`, `district_tests.gd:286`, `restyle_tests.gd:256`, `lamp_tests.gd:101`, `terrain_horde_tests.gd:92` | Controlli tautologici o deboli (`_check(true)`, `>= 0` con `INF`, `or` che assorbe). | Difetti non rilevati. | Controlli espliciti. | lettura |
| K-09 | B | `Invoke-GodotChecks.ps1:104,116` | Il gate legge anche i file non tracciati e non controlla i puntatori LFS. | Verde in locale, commit rotto. | Avviso sui non tracciati, stop sui puntatori LFS. | lettura |
| K-11 | B | `terrain_field_tests.gd:70,86`, `menu_tests.gd:197` | I test lasciano file in `user://` del gioco vero (`rect_base_*.bin`, `maps/`). | Accumulo. | Pulizia a fine suite. | lettura |
| K-12 | B | gate | Il Python degli strumenti non e mai compilato. | Errore scoperto alla prossima cottura. | `py_compile` nel gate. | lettura |
| K-13 | B | gate | Export Linux mai verificato; build in `LocalBuilds/` non confrontate con HEAD. | Build Deck rotta e "riesportata". | Smoke Linux via WSL, data della build. | lettura |
| L-02 | B | `build_sfx.py:11,251-253` | `--only id` (con lo spazio) rigenera tutto; id sconosciuto dà PASS. | Ritocco di un suono che riscrive tutto. | Entrambe le forme, exit 1 su id sconosciuto. | lettura |
| L-03 | B | `build_sfx.py:28-29`, `TOOLS_AND_LICENSES.md` | ffmpeg non registrato fra gli strumenti; percorso del bundle fisso. | Nuova macchina. | Riga in TOOLS, variabile `SONNISS_DIR`. | lettura |
| L-04 | B | `tools/ai/Invoke-CodexDelegate.ps1`, `.codex/config.toml`, `.mcp.json` | Configurazioni ancora puntate a `unreal-mcp`. | Tentativi di connessione a un server morto. | Togliere o documentare. | lettura |
| D-07 | B | `GODOT_WORKFLOW.md:72-92,150,303-307`, `TOOLS_AND_LICENSES.md:55-57` | `--import` "non verificato" ma in uso; elenco suite a 20 su 36; binari Terrain3D descritti male. | — | Correggere. | lettura |
| H-01 | B | `godot/addons/terrain_3d/bin/` | 13,6 MB di binari per piattaforme non bersaglio (macOS, iOS, web) in Git normale. | Ogni aggiornamento ne aggiunge altri. | Toglierli (come per Debug Draw 3D) o regole LFS. | lettura |
| H-02 | B | `godot/tests/{slice_b,terrain,terrain_tool}_tests.gd.uid` | Tre `.uid` orfani. | — | `git rm`. | lettura |

Script senza copertura significativa nel gate: ramo Terrain3D di `terrain_field.gd` e `terrain_surface.gd` (solo con finestra), i 17 shader, `unreal_space.gd` (solo indiretta), `skeleton_probe.gd` (solo marker), i 30 strumenti di `godot/tests/tools/` (solo check-only), `tools/*.py`. Gli spike (`scripts/spikes/`) sono coperti ma obsoleti dopo D-085/D-087: rimozione da decidere col proprietario.

## 3. Voci delle review precedenti

- **9 ottobre (`FULL_CODE_2026-10-09.md`):** chiuse e riconfermate sul codice E-01, E-03-E-08, T-06 (debris), R-35, P-06, P-07, P-10, U-02, U-04, U-07, U-08, U-13, T-01, T-05, E-09, P-03-P-05, R-38. **Obsolete** con D-087 (file rimossi): T-03, T-04, T-07, T-09, T-10, T-11, P-09 (ma la sua allowlist resta: Q-05/K-05), U-11 (superata da Terrain3D; il nuovo costo per pixel e V-02). **Residui:** E-02 superata da N-01; E-10 non verificata a video; P-01 (mouse sul Deck) non provata sul Deck; P-02 (echo, I-03); U-05 (vsync di ripiego) da verificare; U-06 parziale (U-03); U-09 senza cattura; U-12 etichette (I-04); U-14 icona dell'exe (X-03); T-08 regge solo senza estrazione (B-01); **R-12 da riaprire** per Windows (S-01). La conclusione di T-07 sul contatore delle primitive e smentita da D-083: il contatore conta le istanze.
- **7 ottobre (`ARENA_RUN_LEVEL_2026-10-07.md`):** chiuse R-09, R-14, R-16 (D-065), R-20, R-27; parziali R-05 (C-01), R-15 (P-05), R-22 (R-10).
- **10 ottobre (`RAILWAY_CAMPAIGN_2026-10-10.md`):** chiuse F-01 (sul rilievo), F-03, F-04, F-07 (superata), F-08; F-05 scelta di design; **F-06 aperta** (S-03).

## 4. Cosa e verificato e cosa no

- **Misurato con Godot oggi:** tutta la sezione 0, N-01, PF-01-PF-05, L-05; lo schema "seme casuale" su `quake_tests` (corretto in `e77cfbe`).
- **Riletto sul codice da chi scrive:** S-01 (anche sul sorgente di Godot 4.7.2), S-02, E-11, E-12, P-01, U-02, V-01, PF-04.
- **Solo lettura dei revisori d'area:** tutto il resto, con file e righe citati; le voci "da verificare con Godot" restano ipotesi.
- **Mai misurato:** Steam Deck (CPU, GPU, caricamento, FSR, `frame_queue_size`), build Linux, costo GPU per passata.
