# Livello 2: la ferrovia — specifica

**Stato:** **implementata il 9 ottobre 2026** (D-066, D-067) e **portata sul rilievo continuo il 12 ottobre 2026** (D-087, tappa B: `docs/superpowers/specs/2026-10-12-continuous-terrain-railway-design.md`): le regole sotto sono scritte in metri e quote, non piu in celle. Differenza dalla prima versione: la Trivella devia dalle rovine seguendo il campo di percorso quando la linea diretta e chiusa (sezione 5). Il proprietario non ha ancora giocato ne il livello 1 ne questo: tutto cio che segue si ritocca dopo il playtest. Valori **non bilanciati**. Per giocarlo: dal menu, Gioca, mappa di campagna (sbloccato dopo una vittoria nel quartiere), oppure `godot --path godot -- --level=railway`; `--boss-at=60` anticipa la Trivella. Catture in `output/railway/` e `output/campaign/`.

## 1. In una frase

Un corridoio ferroviario stretto e lungo (122 x 319 m) dove ogni due minuti e mezzo passa un treno che spiana la fascia dei binari, con un boss, la **Trivella**, che carica in linea retta scavando solchi e che si ferma solo contro un terrapieno.

## 2. Arena: `RailwayDistrict` (`scripts/arena/railway_district.gd`)

Estende `RuinsDistrict`: stessi mattoni (rovine basse, oggetti, perimetro, cortili, depositi, trincee come pennellate), pianta **rettangolare** (`play_half_extents` = 159,6 x 61,2 m; `TerrainField` 319,2 x 122,4 m, regioni Terrain3D 4 x 2, 21 x 9 chunk di collisione; base cotta in `levels/railway/base.bin`). L'asse lungo e X (est-ovest); la camera guarda da sud come nel livello 1.

- **Fascia dei binari**: `abs(z) <= 3,6` per tutta la lunghezza. Nel rilievo di base e piatta a quota zero (il rumore si spegne sui binari con un raccordo di 2 m ai lati), dipinta ad asfalto e tinta ghiaia scura; dopo le pennellate dei cortili e dei depositi torna alla base (`RailwayDistrict.apply_strokes`), cosi nulla vi sbava. Due binari (z = -2,4 e +2,4) con rotaie e traversine come mesh senza collisione; niente rovine ne oggetti sulla fascia.
- **Cortile di partenza** all'origine, a cavallo dei binari: anello di argini (+1,4 m) senza i tratti sulla fascia, cosi i varchi est e ovest coincidono con i binari.
- **Vagoni** (`kind = wagon`): cinque cumuli di raggio 3 m e 1,5 m sulla fascia, tinta ruggine, ognuno con una **vena da 8 rottami**; ricchi e vicini, ma il treno li spiana e azzera la vena senza lasciare rottami: chi li vuole deve scavarli prima del treno. Il marker "ROTTAMI" resta finche la vena ha rottami.
- **Scali e magazzini**: cortili secondari e depositi normali a nord e a sud della fascia; trincee come solchi (-0,8 m) paralleli ai binari (canali di scolo).
- **Perimetro**: torri a nord, bordo basso a sud; alle due estremita est e ovest un portale di galleria da cui il treno entra ed esce.
- **Seme fisso** come il livello 1 (D-065).

## 3. Evento: il treno (`TrainEvent`, `scripts/run/train_event.gd`)

- **Ritmo**: primo passaggio a 90 s, poi ogni 150 s (`train_interval_seconds`), finche il boss non e sconfitto. Direzione alternata (da est, da ovest), binario scelto a caso.
- **Preavviso**: 10 s prima compare "TRENO DA EST" con freccia a bordo schermo e suona il fischio; a 3 s un secondo fischio.
- **Passaggio**: locomotiva piu 5 vagoni (circa 60 m), 18 m/s, attraversa tutta l'arena in circa 18 s. Mentre avanza:
  - il tratto di **fascia** sotto il muso torna alla **quota di base** (`TerrainField.reset_to_base`, anche se protetto): argini, barricate e cumuli dei vagoni spariscono senza rottami, i solchi si riempiono; una zolla ogni 2 m3 spianati; le **vene dei vagoni** si azzerano;
  - i **rottamatori** nella fascia vengono travolti: contano come uccisi dal giocatore (esperienza), cosi attirarli sui binari e una tattica;
  - il **giocatore** nella fascia subisce 2 danni e viene spinto fuori sul primo punto calpestabile (dislivello dalla base sotto 0,5 m, pendenza sotto la soglia) a passi di 1,2 m dal bordo; il **compagno** viene spinto fuori senza danni;
  - i **lampioni** nella fascia cadono; i rottami a terra nella fascia spariscono.
- **Boss**: la Trivella nella fascia subisce 30 danni (60 se stordita) e viene spinta fuori.
- Marker: `PROTOTYPE01_TRAIN_WARNING`, `PROTOTYPE01_TRAIN_PASS`, `PROTOTYPE01_TRAIN_HIT`, `PROTOTYPE01_TRAIN_PASSED passes= volume= wagons= enemies= player_hits=`.

## 4. Nemico nuovo: il saltatore

Rottamatore verde, piu leggero (vita x0,5), stessa velocita dell'orda, pendenza massima di marcia **1,2 m/m** (gli altri 0,8): sale argini piu ripidi e nel rallentamento in salita (`EnemyDirector.uphill_speed_scale`) perde meno velocita a parita di pendenza; un solco della Trivella non lo rallenta in modo sensibile. Compare dal minuto 2 con quota crescente fino al 25 % delle nascite. Toglie valore ai fossati, che la Trivella regala in abbondanza: il giocatore deve usare anche gli argini, che la Trivella consuma. Variante nel direttore (`spawn_kind(&"hopper")`): colore, `speed_scale`, `health_share`, `max_grade`.

## 5. Boss: la Trivella (`scripts/enemies/driller.gd`)

Regola col terreno, leggibile al primo incontro: **carica in linea retta e scava un solco; un argine la ferma**.

- **Carica**: mira al giocatore, telegraph di 2 s (la punta accelera, striscia a terra fino al bersaglio), poi avanza a 6 m/s per al massimo 30 m ignorando il campo di percorso. La punta porta il terreno a **0,8 m sotto la base** (raggio 1,2 m, `driller_furrow_depth_m`), mai oltre: una seconda carica sullo stesso solco non scava di piu. Il giocatore colpito subisce 2 danni e viene spinto di lato.
- **Argine sul percorso**: un punto che sporge dalla base di almeno 0,8 m (`driller_wall_min_delta_m`), cercato davanti al pennello del solco con `bump_along`, ferma la carica: il varco si apre sulla cresta (`level` a raggio 2,4 verso la base; la terra si polverizza, **nessun rottame** salvo quelli di una vena sotto), la Trivella resta **stordita 3 s** con la punta scoperta e subisce danno doppio. E l'unico modo per fermarla prima dei 30 m. Un rialzo sotto 0,8 m lo supera.
- **Riposo**: dopo ogni carica si ferma 3 s (si gira lentamente verso il giocatore), poi ricomincia.
- **Solchi**: non la rallentano (`max_grade` 10). Barricate: non ne costruisce. Lampioni: li abbatte a contatto. Rovine: devia via campo di percorso.
- **Soluzioni che il campo offre**: un argine a sacrificio (terra dello zainetto) la stordisce dove la chiodatrice la colpisce; i suoi solchi sono fossati gratis contro l'orda, ma rallentano anche te e il compagno; attirarla sui binari prima del treno.
- Valori iniziali: 180 punti vita, contatto 2, carica 6 m/s, 30 m, stordimento 3 s, riposo 3 s. Chiamata a 12 minuti, come il Demolitore.

## 6. Campagna: catalogo, mappa, sblocco

- `LevelCatalog` (`scripts/run/level_catalog.gd`): elenco ordinato dei livelli (`id`, titolo, scena, boss). Oggi: `district` (Quartiere in rovina), `railway` (Ferrovia). Il terzo (Cantiere, Gru) e nel catalogo come "in costruzione", non giocabile.
- `ArenaRun.level_id` dice quale livello e; una vittoria sblocca il successivo nel profilo (`levels_unlocked`).
- **Mappa di campagna** (`CampaignMapPanel`): dal menu iniziale "Gioca" apre la mappa con i livelli in fila; si sceglie fra quelli sbloccati, A conferma, B torna. Dalla schermata di fine livello, in caso di vittoria, il pulsante **Prossimo livello**.
- Riga di comando: `--level=railway` avvia subito quel livello (fa saltare il menu come `--autostart`).

## 7. Verifica

Suite: `railway_tests.gd` (pianta rettangolare, fascia piatta e libera, vagoni come cumuli con vena, cortile a cavallo, saltatori), `train_tests.gd` (preavviso, fascia riportata alla base, vene azzerate, nemici travolti, giocatore spinto su un punto calpestabile, lampioni, vagone scavato a meta), `driller_tests.gd` (carica dritta, solco idempotente, argine che ferma e stordisce senza rottami, vena sotto l'argine, rialzo basso, rovina aggirata, treno, sconfitta che chiude il livello), `campaign_tests.gd` (catalogo, sblocco, mappa, prossimo livello, `--level=`). Catture: `capture_railway.gd` (panoramica, treno in arrivo, Trivella in carica). Simulazioni: `simulate_runs.gd -- --level=railway`.

## 8. Simulazioni

### 8.1 Sul rilievo continuo (12 ottobre 2026, D-087, `--level=railway --bots=scrapper`)

| Seme | Esito | Fine run (s) | Livello | Rottami fuori | Note |
|---|---|---|---|---|---|
| 1 | morte | 1155 | 22 | 8 | Trivella raggiunta a 720 s con 6 punti vita, portata a 27 punti vita; 200 pennellate (vene dei vagoni, lampioni di notte) |
| 2 | morte | 734 | 19 | 8 | morto all'arrivo della Trivella (1 punto vita a 720 s), boss intatto a 180; 93 pennellate |
| 3 | morte | 644 | 18 | 5 | morto prima della chiamata del boss; 84 pennellate |

Lettura provvisoria (3 run, 3 morti, 0 vittorie, 6,5 rottami fuori in media): la ferrovia sul rilievo e piu dura di prima (sulla griglia lo scrapper vinceva 3 run su 3): il cortile aperto sui binari e l'orda lasciano il bot con 1-6 punti vita all'arrivo della Trivella, o lo uccidono prima; la Trivella non viene piu battuta con i soli chiodi; il bot alza argini sulla sua rotta solo con 8 m3 nello zaino e a portata. Valori da bilanciare dopo il playtest (vita della Trivella, orda prima del boss, zainetto iniziale).

### 8.2 Sulla griglia a celle (9 ottobre 2026, superate da D-087, conservate per confronto)

| Bot | Esito | Fine run (s) | Rottami fuori | Note |
|---|---|---|---|---|
| passive (fermo nel cortile) | 3 morti | 24-36 | 1 | nel quartiere resisteva molto di piu: qui i varchi est e ovest sono larghi tre celle (la fascia dei binari) e l'orda entra subito |
| novice | 1 vittoria, 2 morti | 473-1118 | 2-18 | una morte prima della Trivella, una durante |
| kiter | 2 vittorie, 1 morte | 778-912 | 7-32 | Trivella battuta in 60-190 s dall'arrivo, con 3-4 punti vita |
| scrapper | 3 vittorie | 798-882 | 14-16 | Trivella battuta in 80-160 s, mai sotto 5 punti vita; 6-9 lampioni piazzati (il treno ne abbatte) |

Letture: (1) la **Trivella e debole**: cade in uno o tre minuti senza che i bot usino muri per stordirla (non sanno farlo), quindi per un giocatore che li usa sara ancora piu rapida: alzare vita o ridurre la finestra di stordimento dopo il playtest; (2) il **cortile di partenza aperto sui binari** cambia l'inizio del livello: chi resta fermo muore in mezzo minuto; e voluto (il livello 2 non e un tutorial) ma va visto a mano; (3) i rottami portati fuori sono simili al quartiere per kiter e scrapper (D-055: 1-3 run per upgrade). Il treno non ha mai ucciso un bot (si muovono fuori dalla fascia); quante volte abbia travolto l'orda non e nei marker di riepilogo. Simulazioni fatte con la build di questa sera, 4 processi in parallelo, circa 6 minuti.
