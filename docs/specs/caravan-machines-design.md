# Carovana di macchine e fusione — design

Data: 15 ottobre 2026. Stato: **design approvato a sezioni dal proprietario il 15 ottobre 2026 (Sezioni 1-7); spec scritta da rileggere. Il 16 ottobre 2026 il proprietario ha chiesto di procedere: piano A in `docs/superpowers/plans/2026-10-16-caravan-machines.md`.** **Piano A fatto il 18 ottobre 2026** (macchine, moduli, danni, guasto e riparazione, relitti, HUD, bot, benchmark e catture); ai piani B e C restano `fusion_tests`, `colossus_tests`, il colosso nel benchmark e nei bot, le catture di piazzola, banco, colosso e modulo staccato. **Piano B fatto il 19 ottobre 2026** (`docs/superpowers/plans/2026-10-18-caravan-fusion.md`: piazzola, banco, taglie, travolgere, combinazioni, Ricettario e profilo v3, `fusion_tests`, riga `caravan_colossus` del benchmark, regola di fusione dei bot, catture di piazzola, banco e macchina fusa; scelte e domande eseguite coi default in D-093); al piano C restano `colossus_tests`, il colosso pilotato e la cattura del modulo staccato. **Piano C scritto il 20 ottobre 2026** (`docs/specs/caravan-colossus-plan.md`); **task 1-4 fatti** (valori, basi della carovana, relitti dei moduli, eventi che staccano moduli), task 5-8 da fare.
Decisione: **D-093**. Contesto: D-011 (costruire, fondere, pilotare macchine), D-012 (primo compagno autonomo), D-033 (promessa A; la carovana come struttura, la macchina sempre piu assurda come payoff), D-035 (la build si vede nel mondo), roadmap sezione 2 ("carovana di macchine... agganciarsi e separarsi; fusione in configurazioni crescenti e forma colossale"), D-092 (armi e classi: casse, carte, Officina, ricettario gia esistono).

## Perche

Il proprietario (15 ottobre): "e una meccanica fondamentale del gameplay, che lo fa distinguere da tanti altri". Oggi esiste un solo compagno autonomo (raccoglie e fornisce rottami) con pezzi montabili (Torretta, Calamita, Cassone, Faro); niente seconda macchina, aggancio, fusione o pilotaggio.

## Scelte del proprietario (15 ottobre 2026)

| Domanda | Risposta |
|---|---|
| Momento che rende il gioco diverso | **Entrambi, in sequenza**: la carovana che cresce durante la run, poi la scelta strategica fra tante macchine piccole separate e poche grandi fuse, col colosso come culmine |
| Come si ottiene una macchina | **Relitti sepolti** (si scavano, come le casse), **carte del level-up**, **sblocco in Officina** |
| Regola della fusione | **Moduli che si sommano liberamente**, piu **bonus di combinazione** da scoprire nel ricettario |
| Agganciare e sganciare | **Entrambi costano rottami**; solo su una **piazzola fissa che arriva a meta livello**; **gli eventi (terremoto, treno) possono staccare moduli** |
| Colosso | **Si puo sia pilotare sia lasciare autonomo**, ognuna con pro e contro (definiti nella Sezione 3) |
| Danni | Le macchine **si guastano e si riparano coi rottami** (non si distruggono) |
| Approccio | **Approccio 1, macchine a moduli** (telaio + modulo; fusione = una macchina con piu moduli) |
| Protezione della carovana | **Grappolo attorno al giocatore** (2-4 m, dentro la portata delle armi), **fuse piu robuste**, **ritirata automatica** sotto il 30% di vita, e (aggiunta del proprietario) **rigenerazione lenta della vita dopo un periodo senza danni**. Scartate per ora: "bersaglio solo se isolate", comando di richiamo. I rottamatori inseguono il giocatore come oggi e feriscono le macchine che toccano |

## Approcci valutati

1. **Macchine a moduli (scelto).** Ogni macchina e un telaio con un modulo; separate lavorano ognuna per conto suo; fuse sulla piazzola diventano una macchina con piu moduli, piu forte per taglia e coi bonus di combinazione. Il compagno di oggi diventa la prima macchina (modulo Cassone); i pezzi di oggi diventano moduli.
2. Tipi fissi che salgono di livello fondendosi: piu facile da bilanciare, ma perde la somma libera.
3. Una sola macchina che cresce: la piu economica, ma perde la carovana.

## Sezione 1 — macchine e moduli (APPROVATA dal proprietario il 15 ottobre 2026)

- **Macchina = telaio + moduli.** Telaio con vita (6 PV) e un modulo. Al massimo **6 moduli in tutta la carovana** (sei piccole separate, o qualunque fusione fino a una sola da 6).
- **Otto moduli:** Cassone (raccoglie e fornisce rottami: il compagno di oggi), Torretta (chiodatrice), Calamita (frammenti d'esperienza), Faro (luce di notte), Trivella (scava buche attorno al grappolo; su una vena estrae rottami), Pala (alza un piccolo argine davanti al nemico piu vicino coi rottami del Cassone), Saldatore (ripara le altre macchine, 1 PV ogni 3 s), Sirena (attira i rottamatori vicini su di se).
- **Taglie della macchina fusa:** 1 modulo piccola, 2-3 media, 4-5 grande, 6 colosso. Ogni modulo oltre il primo rende gli altri del 15% piu forti; vita = somma dei telai + 25% per taglia sopra la piccola; velocita -10% per taglia; da media in su travolge i rottamatori piccoli (1 danno al contatto quando si muove).
- **Sei combinazioni di partenza** (bonus quando i due moduli stanno nella stessa macchina): Estrattore (Trivella + Calamita: le buche risucchiano i rottami vicini nel Cassone), Riflettore (Torretta + Faro: i nemici illuminati prendono doppio danno dalla Torretta), Betoniera mobile (Pala + Cassone: argini della Pala gratis), Esca blindata (Saldatore + Sirena: mentre attira subisce meta danno), Ruspa (Trivella + Pala: fossato con argine a lato dove passa), Trappola (Torretta + Sirena: chi e attirato prende doppio danno dalla Torretta).
- Valori di partenza, non bilanciati.

## Sezione 2 — piazzola di fusione (APPROVATA dal proprietario il 15 ottobre 2026, opzione A: gioco in pausa)

- **Arrivo:** a meta della chiamata del boss (oggi 6:00 su 12:00), annunciata 15 s prima con scritta, freccia e conto alla rovescia come il boss. Atterra su un tratto piano a 20-30 m dal giocatore: pedana 4x4 celle con gru e faro, visibile di notte da lontano.
- **Durata:** resta ferma fino alla chiamata del boss, poi si richiude; il boss si affronta con la carovana che si ha. Prima dell'arrivo la carovana cresce solo con macchine piccole separate; dopo, la scelta strategica.
- **Uso:** giocatore sulla pedana, col grappolo al seguito, tasto azione: si apre il **banco di fusione** e **il gioco va in pausa** come al level-up (il rischio sta nell'arrivarci con l'orda addosso).
  - **Fondere:** scegliere una macchina, poi una seconda; anteprima di taglia, PV, velocita e combinazioni (quelle mai scoperte come "???"; alla prima scoperta entrano nel ricettario).
  - **Sganciare:** scegliere una macchina e un modulo; il modulo diventa una macchina piccola con telaio nuovo.
  - **Costi:** fondere 1 rottame per modulo della macchina assorbita; sganciare 1 rottame per modulo. Sei macchine in un colosso costano 5 rottami (un Cassone pieno). Si paga dai Cassoni della carovana.
- Le macchine ottenute dopo l'arrivo (relitti, carte) arrivano piccole; si torna alla piazzola quante volte si vuole fino al boss.

## Sezione 3 — colosso pilotato o autonomo (APPROVATA dal proprietario il 15 ottobre 2026)

- **Salire e scendere:** vicino al colosso, tasto azione tenuto circa 0,5 s; lo stesso per scendere. **Solo il colosso** (6 moduli) si pilota; le altre taglie restano autonome.
- **Pilotato, pro:** il corpo del giocatore non prende danni (li prende il colosso); moduli **+50%**; il giocatore decide dove scavano e alzano Trivella, Pala e Ruspa (il terreno in grande); travolge anche i rottamatori medi.
- **Pilotato, contro:** armi del giocatore spente (restano quelle del colosso), niente attrezzo, niente scatto, velocita -30% rispetto al giocatore a piedi.
- **Carburante:** 1 rottame ogni 10 s dai Cassoni; senza rottami, o sotto il 30% di vita, il giocatore viene sbalzato fuori e il colosso va in ritirata.
- **Autonomo:** segue nel grappolo alla forza normale, nessun consumo; il giocatore tiene armi, attrezzo e scatto.

## Sezione 4 — danni, guasti ed eventi (APPROVATA dal proprietario il 15 ottobre 2026)

- **Guasto:** a 0 PV la macchina si ferma e fuma, i moduli si spengono, i nemici la ignorano. **Riparazione:** giocatore entro 2 m, tasto azione tenuto 1,5 s, **2 rottami**, riparte a meta vita. Il **Saldatore** ripara gratis anche le guaste, in 6 s. Rischio della fusione: il colosso guasto ferma tutto insieme.
- **Ritirata:** sotto il 30% di vita la macchina va dietro al giocatore, dal lato opposto al nemico piu vicino, a 4-6 m; i moduli continuano a lavorare; torna al posto sopra il 50%.
- **Rigenerazione:** dopo 8 s senza danni, 1 PV ogni 4 s fino al pieno.
- **Eventi** (D-097: casuali, quanti ne sceglie il giocatore nella scheda Gameplay; un evento spento non stacca moduli; solo macchine fuse; le piccole non perdono moduli): **terremoto**, se la crepa attraversa la macchina, stacca 1 modulo a caso; **treno**, guasta subito la macchina investita e, se fusa, stacca 1 modulo scagliandolo a 6-8 m.
- **Modulo staccato:** relitto luccicante a terra come le casse; col tasto azione torna una macchina piccola, gratis; per rifonderlo si torna alla piazzola.
- Boss e rottamatori non staccano moduli: fanno solo danno (rottamatori 1 al contatto, come oggi).

## Sezione 5 — come si ottengono le macchine; classi e Officina (APPROVATA dal proprietario il 15 ottobre 2026)

- **Partenza:** tutti con una macchina (Cassone, il compagno di oggi); il **Meccanico** con due (Cassone e Torretta).
- **Relitti sepolti:** due per livello sotto cumuli e vagoni, distinti dalle casse (telaio arrugginito che spunta, luccichio arancione invece che turchese); allo scavo scelta fra due moduli sbloccati; a carovana piena valgono 3 rottami; il treno che spiana un vagone porta via il relitto come la cassa.
- **Carte:** le carte dei pezzi del compagno di oggi (Torretta sul cassone, Calamita, Faro) diventano "Nuova macchina: <modulo>" (Rare nel mazzo comune, Non comuni in quello del Meccanico); al massimo una carta macchina per level-up, solo se c'e posto. Le carte che oggi potenziano un pezzo (livelli di Torretta, Faro, Cassone rinforzato) potenziano tutti i moduli di quel tipo; Motore truccato e Saldatura al volo valgono per tutte le macchine.
- **Officina:** sbloccati da subito Cassone, Torretta, Calamita, Faro; nuova scheda "Macchine" per sbloccare Trivella, Pala, Saldatore, Sirena (15-25 rottami l'uno); Cassone saldato, Scorta e Torretta fissa (Meccanico) restano. Il Ricettario ha la sezione "Combinazioni" (6 voci a "???" fino alla prima fusione); profilo versione 3, un profilo v2 si carica intatto.
- **Meccanico, "carovana potenziata":** parte con due macchine; carta di classe "Officina mobile" che porta il limite a 7 moduli (un colosso piu una piccola); le sue armi che usano il compagno (Calamita da gru) usano la macchina col Cassone piu vicina.

## Sezione 6 — comandi, HUD, prestazioni, bot (APPROVATA dal proprietario il 15 ottobre 2026)

- **Comandi:** una sola azione nuova, **Interagisci** (`interact`: X del controller, R della tastiera, entrambi liberi oggi; correzione dell'agente dopo l'approvazione: il gioco non aveva un tasto azione, le casse si aprono scavando). Secondo il contesto ripara la macchina guasta vicina (tenuto), apre il banco sulla piazzola, fa salire e scendere dal colosso; controller e tastiera equivalenti. Le macchine sono autonome, niente ordini. Nelle Sezioni 2-4 "tasto azione" significa Interagisci.
- **HUD:** striscia di icone sopra la barra delle armi, una per macchina, con taglia, vita e segno di guasto. Nel mondo un anello colorato a terra sotto ogni macchina per staccarla dall'orda; la guasta fuma e ha un'icona sopra.
- **Prestazioni:** al piu 6 corpi; budget 0,5 ms per passo sul preset Deck, misurato col benchmark come le armi; se si sfora si riducono prima gli effetti.
- **Bot:** il simulatore raccoglie i relitti, fonde sulla piazzola e ripara, per bilanciare i numeri.

## Sezione 7 — ordine dei piani e verifica (APPROVATA dal proprietario il 15 ottobre 2026)

1. **Piano 5 delle armi** (effetti e suoni, D-092), gia pronto: prima della carovana.
2. **Piano A, macchine:** catalogo dei moduli, `Machine` e `Caravan`, il compagno di oggi diventa la prima macchina (Cassone), grappolo attorno al giocatore, danni dai rottamatori, guasto, riparazione, ritirata, rigenerazione, Saldatore, azione Interagisci, relitti sepolti, carte "Nuova macchina", HUD della carovana. Moduli: Cassone, Torretta, Calamita, Faro, Trivella, Pala, Saldatore, Sirena.
3. **Piano B, fusione:** piazzola di fusione, banco in pausa, taglie, travolgere, combinazioni, ricettario, profilo v3.
4. **Piano C, colosso e resto:** colosso pilotato, eventi che staccano moduli e relitto del modulo, Meccanico (partenza a due, Officina mobile, armi che usano la macchina col Cassone), scheda Macchine in Officina.
5. **Bilanciamento coi bot**, poi playtest del proprietario.

Ogni piano si chiude con gate verde, suite nuove, benchmark Deck della carovana e catture.

## Architettura del codice

Nuova cartella `godot/scripts/caravan/`. `ArenaRun` e gia lungo (circa 1400 righe): la carovana vive nei suoi nodi e `ArenaRun` la collega soltanto.

| Unita | File | Compito | Dipende da |
|---|---|---|---|
| `MachineCatalog` | `caravan/machine_catalog.gd` | dati dei moduli (id, nome, colore, icona, valori, sbloccato di serie) e delle combinazioni; logica pura | niente |
| `MachineModule` | `caravan/modules/*.gd` | un nodo per modulo dentro la macchina (`cargo`, `turret`, `magnet`, `beacon`, `drill`, `shovel`, `welder`, `siren`); `power` impostato dalla macchina; `tick(delta)`; spento quando la macchina e guasta | servizi passati dalla carovana (come `WeaponLoadout.give_services`) |
| `Machine` | `caravan/machine.gd` (`CharacterBody3D`) | telaio: PV, moduli, taglia, stato (`OK`, `RETREAT`, `BROKEN`), posto nel grappolo, movimento su `PathField` come il compagno, rigenerazione, modello (carretto di oggi + pezzi impilati per modulo), anello a terra | `MachineCatalog`, `PathField`, `TerrainField` |
| `Caravan` | `caravan/caravan.gd` (`Node3D`) | elenco delle macchine, limite moduli (6, 7 con Officina mobile), posti del grappolo (2-4 m), rottami totali dei Cassoni, `add_machine(module)`, `fuse(a, b)`, `detach(machine, module)`, `repair(machine)`, `detach_random(machine)`, segnali per HUD e audio; espone `can_supply()`/`spend()`/`can_supply_count()`/`spend_count()` con la firma del `Companion` di oggi, cosi tool, lampioni e armi non cambiano chiamata | `Machine` |
| `MachineWrecks` | `caravan/machine_wrecks.gd` | relitti sepolti (due per livello, sotto cumuli e vagoni, luccichio arancione) e moduli staccati a terra; sul modello di `BuriedCaches` | `TerrainField`, `RuinsDistrict` |
| `FusionPad` | `caravan/fusion_pad.gd` | arrivo a meta della chiamata del boss, annuncio, pedana 4x4 con gru e faro, chiusura alla chiamata | `RunHud`, `TerrainField` |
| `FusionBench` | `ui/fusion_bench.gd` | banco in pausa: scegliere, anteprima, costi, "???", conferma; controller prima | `Caravan`, `MachineCatalog`, profilo |
| `CaravanStrip` | `ui/caravan_strip.gd` | icone delle macchine sopra la barra delle armi | `Caravan` |
| Pilotaggio | `Caravan` + `PlayerCharacter` | salire e scendere, armi e attrezzo spenti, carburante, sbalzo fuori | `WeaponLoadout`, `PlayerCharacter` |

**Il compagno di oggi.** `Companion` (`scripts/companion/companion.gd`) diventa `Machine` col modulo Cassone; la raccolta dei rottami passa nel modulo `cargo`. I 18 file che leggono `companion` (soprattutto `arena_run.gd`, `upgrade_catalog.gd`, `welder.gd`, `class_perks.gd`, `crane_magnet.gd`, eventi, lampioni) passano a `caravan`, o alla macchina col Cassone piu vicina per le armi del Meccanico. Le scene `arena_run.tscn` e `railway_run.tscn` cambiano il nodo `Companion` in `Caravan` (da dire al proprietario prima di toccarle).

**Danni.** Oggi il compagno non prende danni. Il direttore dei nemici (`EnemyDirector`) controlla gia il contatto col giocatore: si aggiunge il contatto con le macchine (1 danno, ricarica 0,8 s per macchina), senza un secondo giro sui nemici (si riusa la griglia spaziale del direttore). I nemici non scelgono le macchine come bersaglio: inseguono il giocatore come oggi.

**Profilo v3.** Sezione `[machines]`: moduli sbloccati e combinazioni scoperte. Un profilo v2 si carica intatto (stessa via di v1 → v2 del piano 4 delle armi).

## Valori di partenza (non bilanciati, in `CaravanTuning`)

| Valore | Partenza |
|---|---|
| Telaio | 6 PV; limite 6 moduli (7 con Officina mobile) |
| Taglie | 1 piccola, 2-3 media, 4-5 grande, 6 colosso |
| Forza per modulo oltre il primo | +15% a tutti i moduli della macchina |
| Vita della fusa | somma dei telai +25% per taglia sopra la piccola |
| Velocita | quella del compagno di oggi, -10% per taglia |
| Travolgere | da media in su, 1 danno al contatto in movimento (colosso pilotato anche i medi) |
| Cassone | 5 rottami (come oggi) |
| Torretta | chiodatrice del compagno di oggi (0,9 s, 8 m) |
| Calamita | raggio 2,5 m (come oggi) |
| Faro | raggio del faro di oggi |
| Trivella | buca di 1,2 m ogni 4 s entro 5 m dal grappolo; su una vena estrae 1 rottame |
| Pala | argine di 1 m davanti al nemico piu vicino ogni 5 s, 1 rottame |
| Saldatore | 1 PV ogni 3 s entro 4 m; guaste in 6 s |
| Sirena | attira i rottamatori entro 8 m per 3 s ogni 6 s |
| Combinazioni | doppio danno o meta danno o costo zero come nella Sezione 1 |
| Guasto e riparazione | 2 rottami, 1,5 s tenendo Interagisci entro 2 m, riparte a meta vita |
| Ritirata | sotto 30%, torna sopra 50%; 4-6 m dietro al giocatore |
| Rigenerazione | dopo 8 s senza danni, 1 PV ogni 4 s |
| Piazzola | a meta della chiamata del boss, preavviso 15 s, 20-30 m dal giocatore, fino alla chiamata |
| Costi di fusione | 1 rottame per modulo assorbito; sgancio 1 per modulo |
| Colosso pilotato | moduli +50%, velocita -30% del giocatore, 1 rottame ogni 10 s, sbalzo sotto 30% |
| Relitti | 2 per livello; scelta fra 2 moduli; a carovana piena 3 rottami |
| Officina | Trivella, Pala, Saldatore, Sirena: 15-25 rottami l'uno |

## Verifica

- **Suite nuove:** `caravan_tests` (aggiunta, limite, grappolo, rottami condivisi, firma `can_supply`/`spend`), `machine_modules_tests` (un controllo per modulo e per combinazione), `machine_damage_tests` (contatto, guasto, riparazione, ritirata, rigenerazione, Saldatore), `fusion_tests` (piazzola, banco, costi, taglie, anteprima, ricettario, profilo v3 e caricamento di un v2), `colossus_tests` (salire, scendere, armi spente, carburante, sbalzo, eventi che staccano moduli). Le suite di oggi che usano `companion` vanno adattate, non indebolite.
- **Benchmark:** riga `caravan` in `benchmark_arena.gd` col preset Deck, sei macchine piccole e un colosso, 70 nemici; budget 0,5 ms per passo.
- **Bot:** `simulate_runs.gd` raccoglie i relitti, ripara e fonde (una regola semplice: colosso se ci sono 6 moduli e rottami).
- **Catture:** grappolo con l'orda di giorno e di notte, piazzola, banco, colosso pilotato, relitto e modulo staccato; `output/caravan/`.
- **Controller:** banco, riparazione e pilotaggio provati a controller nei test (eventi di input), come le Impostazioni.

## Rischi

- **Costo sul Deck:** sei corpi che si muovono e sparano piu l'orda; mitigazione: moduli senza fisica propria, un solo `move_and_slide` per macchina, effetti ridotti per primi.
- **Migrazione del compagno:** 18 file e due scene; si fa nel piano A con le suite di oggi come rete.
- **Leggibilita:** grappolo e orda si confondono; anello a terra e striscia nel HUD, da giudicare sulle catture.
- **Bilanciamento:** tutti i valori sono di partenza; i bot non sanno tenere la piazzola di estrazione (D-076) e per ora non sapranno pilotare il colosso.

## Domande per il playtest

- La piazzola a meta livello arriva troppo presto o troppo tardi?
- Il colosso pilotato vale i rottami che consuma?
- Sei moduli bastano? Il grappolo resta leggibile con 70 nemici sul Deck?
- La riparazione a 2 rottami e il guasto del colosso sono una punizione giusta?
