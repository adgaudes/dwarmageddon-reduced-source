# Ciclo giorno/notte e luce — specifica

**Stato:** design approvato dal proprietario il 6 ottobre 2026 ("per il momento"), D-058. Non implementato. Tutti i valori sono un primo tentativo, da bilanciare con simulatore e playtest.

## 1. Scopo

Dare al livello due tempi: un giorno in cui si scava e si prepara, una notte molto piu dura in cui la preparazione viene messa alla prova. Di notte la luce del giocatore, della carovana e dei lampioni e un territorio: dentro si combatte ad armi pari, fuori si rischia.

Cosa ha chiesto il proprietario: ciclo giorno/notte, notte molto piu difficile, luce di giocatore e carovana come aiuto; una sola notte per livello; nemici piu forti al buio e visibilita ridotta ma non azzerata; luce fissa che cresce con gli upgrade; lampioni piazzabili.

Criterio di successo: al playtest la notte si sente come un cambio di fase (piu tensione, scelte diverse), la luce si legge a colpo d'occhio come zona di vantaggio, e nessuno perde perche "non si vedeva niente".

## 2. Fuori scope in questa versione

- Piu cicli per livello, alba, livelli solo notturni.
- Luce che consuma rottami o carburante.
- Effetti aggiuntivi della luce (rallentare, danneggiare), pezzi dell'Officina legati alla luce.
- Rottamatori che attaccano i lampioni; nemici solo notturni.
- Effetto del buio sul Demolitore.
- Cursore di luminosita della notte nelle impostazioni (si aggiunge solo se il playtest lo chiede, vedi rischi).

## 3. Ciclo

Una sola notte per livello, guidata dall'orologio di `ArenaRun` (`elapsed`).

| Fase | Da | A | Note |
|---|---|---|---|
| `DAY` | 0:00 | 4:30 | gioco identico a oggi |
| `DUSK` | 4:30 | 5:15 | transizione visiva di 45 s; nessun effetto sui nemici |
| `NIGHT` | 5:15 | morte del boss | il boss e chiamato a 12:00 (`boss_call_seconds`) |

- `night_factor` va da 0 (giorno) a 1 (notte) lungo il tramonto e guida solo la resa visiva.
- Gli effetti di gioco scattano all'ingresso in `NIGHT`, non gradualmente: una soglia sola, annunciata.
- Avvio rapido: `-- --night-at=N` sposta l'inizio del tramonto a N secondi. `night_start_seconds = 0` spegne il ciclo (il livello resta diurno): serve ai test esistenti e alle scene che non lo vogliono.

## 4. Luce di gioco

La luce che conta per le regole e logica, non grafica: un elenco di sorgenti, ciascuna con posizione e raggio planare. Un punto e illuminato se cade entro il raggio di almeno una sorgente. Nessuna occlusione: mura e rovine non fanno ombra alle regole (fanno ombra solo all'occhio, e solo dove una luce proietta ombre).

| Sorgente | Raggio iniziale | Riferimento |
|---|---|---|
| Torcia del giocatore | 6 m | la chiodatrice arriva a 9 m: si spara nel buio |
| Faro della carovana | 11 m | le mura del cortile sono a circa 9,6 m dal centro |
| Lampione | 5 m | vedi sezione 7 |

Le luci visive sono regolate perche il bordo percepito coincida con il raggio logico. Se al playtest il bordo non si legge, si aggiunge un anello sottile a terra.

## 5. Nemici al buio

In fase `NIGHT`, un rottamatore (normale o veloce) fuori dalla luce ha:

- velocita x1,35 (`night_dark_speed_scale`);
- +1 al danno da contatto (`night_dark_contact_bonus`).

Dentro la luce torna ai valori normali, subito. Lo stato si valuta a ogni passo sulla posizione del nemico. Esclusi: il Demolitore (`self_driven`) e i rottamatori in commissione per lui restano come sono per la velocita di commissione, ma il danno da contatto segue la regola generale.

Riferimenti: il giocatore va a 6 m/s; rottamatore normale 2,2 → 2,97 m/s al buio; veloce 4,2 → 5,67 m/s al buio, appena sotto il giocatore.

## 6. Visibilita

- Di notte sole e luce ambiente scendono molto ma non a zero: fuori dalla luce si distinguono sagome e forma del terreno.
- I rottamatori hanno due occhi emissivi, visibili anche nel buio pieno; quelli veloci mantengono la loro tinta blu negli occhi.
- Rottami, frammenti di esperienza, impronte dell'orda (D-053) e anteprima del tool mantengono un bagliore leggero: restano leggibili al buio.
- Gli indicatori a bordo schermo (D-044) non cambiano.

## 7. Lampioni

Terza modalita del tool del terreno: `DIG → RAISE → LAMP → DIG`, stesso tasto per ciclare, stesso comando per applicare, stessa anteprima sulla cella (bianco caldo se possibile, rosso se no). Nessuna azione di input nuova: controller e tastiera/mouse restano equivalenti.

Regole:

- si piazza su una cella `Normal` o `Raised` (in cima al terrapieno); non su `Lowered`, non sulla cella protetta, non su una cella che ha gia un lampione;
- costa 3 rottami (`lamp_scrap_cost`), di giorno e di notte; senza rottami il comando e rifiutato con il suono di rifiuto esistente;
- al massimo 6 lampioni in piedi (`lamp_max_count`); oltre, rifiutato;
- raggio di luce 5 m (`lamp_light_radius`), acceso sempre (di giorno non ha effetto);
- non blocca il passaggio ne del giocatore ne dell'orda: `PathField` non cambia;
- se la cella cambia stato (scavo, rialzo, demolizione, esplosione), il lampione e perso senza rimborso;
- i rottamatori lo ignorano; il Demolitore lo abbatte quando entra nel suo raggio di contatto.

I lampioni compaiono sulla mappa di fine run (D-052).

## 8. Upgrade

Due carte di level-up nuove in `UpgradeCatalog`:

| id | Nome | Categoria | Rarita | Livelli | Effetto |
|---|---|---|---|---|---|
| `beacon_range` | Faro | Pezzo compagno | Non comune | 3 | +2 m al raggio del faro per livello |
| `torch_range` | Torcia | Personaggio | Comune | 3 | +1,5 m al raggio della torcia per livello |

Sono offerte anche di giorno. `beacon_range` richiede il compagno, come le altre carte compagno.

## 9. Interfaccia e audio

- HUD: indicatore sole/luna con il tempo che manca al tramonto; di notte mostra la luna.
- All'inizio del tramonto: avviso "Cala la notte" e suono sintetizzato dedicato in `SfxLibrary`. All'ingresso in `NIGHT`: secondo segnale, piu secco.
- Modalita `LAMP` nell'indicatore di modalita del tool, con costo e contatore (es. 2/6).

## 10. Architettura

Unita nuove, ognuna con un solo compito:

- **`DayNightCycle`** (`scripts/run/day_night_cycle.gd`, nodo in `arena_run.tscn`). Riceve il tempo da `ArenaRun`, espone `phase`, `night_factor`, `seconds_to_dusk()`, segnale `phase_changed(phase)`. Anima sole, cielo, luce ambiente e nebbia che `OvergrownArena` ha gia creato (nodi `Sun` e `WorldEnvironment`), interpolando fra un profilo giorno (i valori attuali, letti all'avvio) e un profilo notte. Non conosce nemici ne luci di gioco.
- **`LightField`** (`scripts/run/light_field.gd`, `RefCounted`). Logica pura: `add_source(node, radius) -> id`, `set_radius(id, r)`, `remove_source(id)`, `is_lit(world) -> bool`. Nessuna dipendenza dalla grafica: testabile in headless.
- **`LampField`** (`scripts/terrain/lamp_field.gd`, nodo in `arena_run.tscn`). Possiede i lampioni: regole di piazzamento, limite, rimozione quando la cella cambia (`TerrainGrid.cell_changed`), nodo visivo e luce di ciascuno, registrazione in `LightField`.

Modifiche a unita esistenti:

- `RunTuning`: gruppo `Night` (`night_start_seconds` 270, `dusk_seconds` 45, `night_dark_speed_scale` 1,35, `night_dark_contact_bonus` 1, `torch_radius` 6, `beacon_radius` 11) e gruppo `Lamps` (`lamp_scrap_cost` 3, `lamp_max_count` 6, `lamp_light_radius` 5).
- `ArenaRun`: crea `LightField`, registra torcia e faro, fa avanzare `DayNightCycle`, applica i due upgrade, legge `--night-at`.
- `EnemyDirector`: riceve `light_field` e una bandiera `night_active`; in `_move_enemies` e `_apply_contacts` applica moltiplicatore e bonus ai nemici non `self_driven` fuori dalla luce. Con `light_field` nullo si comporta come oggi.
- `TerrainState.ToolMode`: nuova voce `LAMP`; `PlayerCharacter` cicla su tre modalita e instrada il comando `LAMP` a `LampField`; `TerrainGrid.update_preview()` riceve il colore per la terza modalita.
- `Demolisher`: abbatte i lampioni entro il raggio di contatto tramite `LampField`.
- `Enemy` / `EnemyDirector`: occhi emissivi (materiale condiviso, due per tipo di rottamatore).
- `PlayerCharacter` e `Companion`: una luce visiva ciascuno, accesa da `DayNightCycle.night_factor`.
- `RunHud`, `SfxLibrary`/`RunAudio`, `RunMap`, `UpgradeCatalog`: come nelle sezioni 8 e 9.

Resa: luci vere, poche. Sole e ambiente calano; torcia e faro sono `OmniLight3D`; solo il faro puo proiettare ombre, e solo se la misura lo consente. I lampioni non proiettano mai ombre. Nessuno shader esistente va riscritto per il buio.

## 11. Tappe

1. **Notte giocabile:** `DayNightCycle`, `LightField`, torcia e faro, nemici al buio, occhi e bagliori, HUD e audio, due carte upgrade, test, catture, simulatore. Consegnabile e verificabile da sola.
2. **Lampioni:** `LampField`, terza modalita del tool, Demolitore, mappa, test, bot del simulatore che li compra.

**Stato (9 ottobre 2026):** entrambe le tappe implementate (D-058; come, in `DAY_NIGHT_PLAN.md`). Valori non bilanciati: domande della sezione 14 al playtest.

## 12. Verifica

- Nuova suite `tests/day_night_tests.gd`: tempi delle fasi e `--night-at`; `night_start_seconds = 0` lascia tutto diurno; `LightField` (dentro, fuori, bordo, sorgente che si muove, rimozione); velocita e danno di un nemico al buio e alla luce, di giorno e di notte; Demolitore invariato; i due upgrade cambiano i raggi.
- Tappa 2, suite `tests/lamp_tests.gd`: piazzamento valido e rifiuti (stato cella, rottami, limite, doppione), costo scalato, perdita al cambio di cella, abbattimento dal Demolitore, nessun effetto su `PathField`, ciclo delle tre modalita.
- Regressione: le 20 suite esistenti restano verdi; prima del tramonto il comportamento e identico a oggi.
- Visivo: catture a giorno, tramonto e notte, dentro e fuori dalla luce, con lampioni.
- Bilanciamento: `simulate_runs.gd` con e senza notte, stessi semi; in tappa 2 un bot che compra lampioni.
- Prestazioni: `benchmark_arena.gd` di notte con 70 nemici e 6 lampioni, su PC. Steam Deck non misurato.

## 13. Rischi

- **Bilanciamento:** la notte copre oltre meta del livello e arriva insieme ai rottamatori veloci; il primo tentativo potrebbe essere troppo duro. Si tara con il simulatore prima del playtest.
- **Economia riaperta:** i lampioni competono con la torretta per i rottami appena ribilanciati (D-055, D-056).
- **Leggibilita su Steam Deck:** schermo piccolo e poco luminoso; se la notte e troppo scura si aggiunge un cursore di luminosita.
- **Tre modalita su un tasto:** tornare da `RAISE` a `DIG` richiede due pressioni; da valutare al playtest.
- **Prestazioni:** fino a 8 luci dinamiche; i lampioni senza ombre dovrebbero bastare, ma va misurato.
- **Coerenza col mondo:** `WORLD_PREMISE.md` parla di rotazione e meteo; la notte va raccordata a quella premessa quando si scrive la campagna.

## 14. Domande per il playtest

1. Il tramonto si nota in tempo per prepararsi?
2. Il bordo della luce si capisce senza spiegazioni?
3. Uscire dalla luce di notte e una scelta tesa o un errore da non ripetere?
4. I lampioni cambiano dove combatti, o li ignori?
5. La notte e leggibile sul tuo schermo e sul Deck?
