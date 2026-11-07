# Progressione nella run — specifica proposta

> **Stato: APPROVATA** (D-035). Forma decisa dal proprietario il 4 ottobre 2026; logica di estrazione proposta dall'agente e **confermata dal proprietario il 5 ottobre 2026**. Valori e categorie restano rivedibili dopo il primo playtest.

## 1. Cosa e deciso

- Ogni nemico sconfitto rilascia esperienza.
- A ogni livello il giocatore sceglie **uno fra tre upgrade**.
- Categorie: **armi aggiuntive**, **pezzi per costruire i compagni**, altre da definire insieme.
- Gli upgrade hanno **rarita diverse**.

## 2. Vincolo dalla promessa (D-033)

La build non deve vivere solo nel menu (`VISION_PROPOSAL_2026-10-03.md`, "Differenza riconoscibile"). Ogni upgrade deve vedersi o sentirsi **nel mondo**: un pezzo montato sul compagno, una cella modificata in modo diverso, un'arma con un effetto sul terreno. Un upgrade puramente numerico (+10% danno) e ammesso solo come riempitivo comune.

## 3. Logica proposta: casuale pesato con regole

Ne totalmente casuale (troppe scelte inutili, run decise dalla fortuna) ne deterministico (niente sorpresa, rigiocabilita bassa). Cinque regole:

1. **Rarita pesate.** Comune 60, Non comune 27, Raro 10, Leggendario 3. La rarita aumenta l'effetto; i **leggendari portano anche un costo** leggibile (piu forti ma con un pericolo, come vuole la promessa A).
2. **Pool filtrato dallo stato.** Non compaiono upgrade gia al massimo, pezzi per compagni che non hai, armi oltre il limite di slot (proposta: 4). A slot pieni compaiono solo potenziamenti di cio che possiedi.
3. **Categorie diverse nelle tre carte**, quando il pool lo permette: di norma un'arma, un pezzo compagno e un jolly. La scelta resta sempre fra direzioni diverse.
4. **Garanzia anti-sfortuna.** Se negli ultimi 4 level-up non e uscito nulla di Raro o superiore, la scelta successiva ne contiene almeno uno.
5. **Peso di sinergia.** Gli upgrade collegati a cio che possiedi pesano il doppio: la build tende a prendere una forma senza essere imposta.

Ogni run usa un **seed** registrato nel log: la stessa sequenza e riproducibile per test e debug.

Rimandati, da valutare dopo il primo playtest: ritira le carte, scarta un upgrade per sempre, statistica fortuna.

## 4. Esperienza

- I nemici lasciano **frammenti** a terra; il giocatore li raccoglie entrando in un raggio di attrazione.
- Proposta di sinergia: il compagno, che gia raccoglie rottami (D-032), puo ricevere un pezzo "Calamita" che gli fa raccogliere anche i frammenti.
- Curva: tutti i valori in un `.tres` di tuning (D-024). Obiettivo indicativo: 20-30 livelli in una run da 25 minuti.

## 5. Esempi di upgrade (da discutere)

| Categoria | Esempi | Effetto nel mondo |
|---|---|---|
| Armi | chiodatrice automatica, lanciarottami, mina a scavo | proiettili visibili; la mina abbassa una cella |
| Pezzi compagno | cingoli, pala, torretta, calamita | il pezzo appare sul modello; cambia cosa fa il compagno |
| Tool terreno | scavo su due celle, rialzo piu alto, cella rinforzata | la griglia cambia in modo diverso |
| Personaggio | dash piu lungo, velocita, raggio di raccolta | — (riempitivo comune) |

## 6. Primo prototipo

Una sola arma automatica di base, 6-8 upgrade, tre rarita (Comune, Non comune, Raro), le regole 1-4. La sinergia (regola 5) e i leggendari entrano quando il pool e abbastanza grande da renderli visibili.

## 7. Rilievo continuo (12 ottobre 2026, D-085)

Col terreno continuo il tool non lavora piu a celle: il pennello ha un raggio (2,4 m) e un volume. Cambiano:

- **Prolunga** (Officina): +1,2 m di portata del tool per livello (era una cella);
- **Zainetto largo** (Officina, nuovo, costi 12/20/30): +20 m3 di capacita dello zainetto di terra per livello;
- **Pala larga** (carta comune, nuova, tre livelli): +0,4 m di raggio del pennello per livello;
- **Scavo esplosivo**: scatta ogni 0,5 s di scavo continuo, non a ogni cella;
- **Argini spinati** (era "Terrapieni spinati"): i rottamatori che spingono contro un argine (delta oltre 0,3 m dalla base) si fanno male;
- i rottami vengono solo dalle vene sepolte nei cumuli (uno ogni 0,8 m3 scavati sotto la base), mai dal suolo nudo: il reddito per livello resta quello di D-056.

Valori provvisori, da bilanciare con le run simulate e il playtest.
