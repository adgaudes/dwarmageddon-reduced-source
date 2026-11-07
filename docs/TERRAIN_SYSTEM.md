# Sistema di trasformazione del terreno

## Stato

- Pilastro centrale del concept, approvato come direzione modificabile.
- **Implementazione tecnica scelta e fatta per il quartiere (tappa A, 12 ottobre 2026, D-085): strategia D ibrida con rilievo continuo** (campo di quote a 0,5 m, Terrain3D per la resa, collisione a chunk nostra, Jolt), pennello continuo con zainetto di terra, pendenza massima di marcia; dettagli nella sezione "Rilievo continuo" qui sotto, spec in `docs/superpowers/specs/2026-10-12-continuous-terrain-design.md`.
- **Dal 12 ottobre 2026 (tappa B, D-087) il rilievo continuo e l'unico sistema**: anche la ferrovia e le scene minori stanno su `TerrainField`; `TerrainGrid` e `TerrainState` non esistono piu.
- Il prototipo deve dimostrare profondita sistemica prima di adottare tecnologia voxel.

## Promessa

Il terreno non e uno sfondo passivo. Il giocatore lo osserva, lo modifica con strumenti personali e lo trasforma su scala maggiore con le macchine. Le modifiche cambiano combattimento, movimento, risorse, luce e configurazione della carovana.

La profondita non viene misurata soltanto dalla liberta geometrica. Una modifica e significativa quando produce conseguenze comprensibili e permette piu soluzioni valide.

## Riferimento di interazione: Astroneer

*Astroneer* e il riferimento dichiarato per la profondita e la sensazione tattile della modifica del terreno:

- rimuovere materiale;
- aggiungere materiale;
- livellare o regolarizzare una superficie;
- creare percorsi e rampe;
- raggiungere risorse attraverso il terreno;
- usare la trasformazione come parte continua dell'esplorazione e della risoluzione dei problemi.

Il riferimento non autorizza a copiare stile grafico, forma del tool, interfaccia, animazioni, risorse o struttura del gioco. Il nostro sistema deve essere adattato a visuale isometrica/top-down, pressione delle orde, macchine, carovana, luce/buio e inondazioni.

Obiettivo esperienziale candidato: il giocatore deve poter guardare un'area, immaginare una configurazione migliore e scolpirla abbastanza liberamente da riconoscere il risultato come propria soluzione.

## Adattamento alla visuale dall'alto

Problemi specifici da risolvere:

- distinguere altezza, profondita e pendenza senza camera ravvicinata;
- mirare dietro ostacoli e sui bordi verticali;
- evitare che il personaggio o i nemici scompaiano in scavi profondi;
- mostrare con precisione volume rimosso o aggiunto;
- mantenere leggibili proiettili, telegraph e collisioni;
- impedire modifiche accidentali durante combattimenti intensi;
- offrire precisione equivalente con stick e mouse.

Soluzioni candidate da prototipare:

- cursore proiettato sul terreno con volume del pennello visibile;
- anteprima colorata di rimozione, aggiunta e livellamento;
- aggancio opzionale a pendenze, altezze o direzioni utili;
- velocita del pennello dipendente dall'inclinazione dello stick o dalla pressione del comando;
- modalita costruzione con rallentamento o pausa controllata in single-player;
- trasparenza, dissolvenza o taglio visivo per pareti che coprono il giocatore;
- limiti di profondita e pendenza comunicati prima dell'azione;
- undo locale limitato o funzione di ripristino costosa per correggere errori;
- vibrazione e audio distinti per materiale, resistenza e risultato.

Nel primo test dall'alto privilegiare superficie, rampe, trincee e terrapieni. Tunnel profondi, caverne sovrapposte e grandi sporgenze entrano solo dopo aver risolto occlusione e leggibilita.

## Due scale di intervento

### Tool personali

Funzione: interventi precisi, rapidi e limitati mentre il giocatore e a piedi.

Caratteristiche candidate:

- rimuovere un piccolo ostacolo o aprire un varco;
- piazzare un ancoraggio, ponte breve o supporto;
- consolidare terreno fragile;
- deviare una piccola quantita d'acqua o energia;
- tagliare vegetazione e recuperare materiale senza distruggere indiscriminatamente;
- marcare un punto per una macchina;
- creare temporaneamente luce, ombra o un segnale.

Costi possibili: tempo di utilizzo, esposizione, carica, calore, durabilita o consumo di materiale.

### Macchine

Funzione: trasformazioni ampie, persistenti e capaci di cambiare la strategia dell'intera arena.

Caratteristiche candidate:

- scavare trincee o corridoi;
- sollevare terrapieni e piattaforme;
- comprimere, frantumare o stabilizzare superfici;
- spostare grandi rovine o radici;
- pompare, trattenere o liberare acqua;
- creare ponti, rampe o linee di trasporto;
- schermare, riflettere o concentrare luce;
- accelerare o ripristinare localmente uno stato del terreno.

Costi possibili: energia, rumore, tempo di preparazione, spazio, nuovi ingressi nemici, blocco delle vie di fuga, instabilita o perdita del modulo.

## Regola di complementarita

Tool e macchine non devono duplicarsi:

- il tool prepara, corregge o rifinisce;
- la macchina trasforma, mantiene o automatizza;
- il mezzo pilotabile trasporta e applica la trasformazione mentre si muove;
- la carovana collegata combina piu effetti ma aumenta ingombro e costo;
- la forma colossale puo produrre una trasformazione eccezionale, mai disponibile senza la build che l'ha generata.

Esempio: il giocatore usa un tool per segnare una linea e rimuovere piccoli detriti; l'escavatore apre il corridoio completo; un modulo di consolidamento impedisce il crollo; la scelta crea pero un nuovo percorso per le orde.

## Famiglie di terreno candidate

Il primo prototipo usa soltanto due o tre famiglie. Il set esteso puo includere:

- **suolo morbido:** facile da scavare, instabile e adatto a trincee;
- **roccia o rovina:** resistente, utile come barriera e ricca di componenti;
- **vegetazione:** puo bloccare, sostenere, ricrescere o reagire a luce e acqua;
- **acqua:** cambia accesso, flusso e comportamento delle macchine;
- **terreno temporale:** conserva stati, accelera crescita/crollo o ripete una trasformazione;
- **superficie luminosa/ombrosa:** influenza sensori, energia e minacce.

## Conseguenze sistemiche richieste

Una trasformazione significativa deve influenzare almeno due aree:

- percorso e densita dei nemici;
- movimento e vie di fuga del giocatore;
- posizione o efficienza delle macchine;
- accesso a risorse, segreti o obiettivi;
- distribuzione di luce e ombra;
- flusso dell'acqua o di altra materia;
- linee di tiro, traiettorie e visibilita;
- stabilita, crollo o ricrescita;
- percorso della carovana e possibilita di aggancio/separazione.

Modifiche puramente cosmetiche non contano come profondita del sistema.

## Principi di leggibilita

- Il giocatore deve capire prima dell'azione che cosa puo essere modificato.
- Anteprima, area d'effetto e possibile conseguenza primaria devono essere mostrate.
- Collisione visiva e collisione reale devono coincidere.
- I bordi fra stati del terreno devono restare leggibili con molti nemici e VFX.
- Un errore non deve intrappolare definitivamente il giocatore senza via di recupero comprensibile.
- Controller e tastiera/mouse devono permettere selezione e orientamento equivalenti.
- Le trasformazioni devono restare riconoscibili a 1280x800 su Steam Deck.

## Persistenza candidata

- Le modifiche persistono per la durata della situazione o della run, salvo azioni di ripristino esplicite.
- Il mondo fra le run non memorizza inizialmente ogni deformazione geometrica.
- Eventuali cambiamenti permanenti usano stati narrativi o macro-varianti controllate, non salvataggio completo di tutta la geometria.
- Riavvolgimento temporale e rigenerazione della natura devono essere regole visibili, non reset arbitrari.

Questa impostazione protegge salvataggi, dimensione dei dati e riproducibilita dei test.

## Inondazioni dinamiche

I super-temporali causati dall'instabilita planetaria possono cambiare lo stato di bacini e canali durante una situazione.

Prima implementazione candidata:

- pochi livelli d'acqua predefiniti o interpolati;
- segnali di tempesta e tempo di preparazione leggibile;
- argini, canali e pompe come punti di controllo;
- percorsi terrestri che diventano acquatici o impraticabili;
- risorse e pericoli che emergono con la piena;
- aggiornamento limitato e misurabile della navigazione;
- nessuna simulazione fluidodinamica generale.

La macchina acquatica diventa necessaria soltanto nelle situazioni in cui offre decisioni oltre il semplice attraversamento: deviazione, pompaggio, trasporto, recupero o controllo di pericoli conduttivi.

## Strategie tecniche da confrontare

### A. Celle e stati discreti - prova delle regole

Il campo e composto da celle o regioni con pochi stati: integro, scavato, rialzato, allagato, consolidato.

Vantaggi:

- collisioni e navigazione prevedibili;
- facile anteprima con controller;
- salvataggio e replica dello stato semplici;
- costo misurabile su Steam Deck;
- rapido da prototipare con mesh provvisorie.

Limiti:

- bordi piu artificiali;
- minore liberta geometrica;
- necessita di buona presentazione per non sembrare una griglia rigida.

Questa strategia serve a verificare conseguenze, input e AI. Non rappresenta necessariamente la fedelta finale desiderata dopo aver assunto *Astroneer* come riferimento di profondita.

### B. Zone deformabili controllate - ponte produttivo

Solo alcune superfici consentono deformazioni piu continue o combinano stati discreti con mesh e materiali dinamici.

Vantaggi:

- resa piu organica;
- permette rovine e natura visivamente convincenti;
- conserva controllo su collisioni e performance.

Limiti:

- transizioni, navmesh e sincronizzazione visiva piu complesse;
- authoring specifico per area.

### C. Terreno voxel completamente dinamico - ricerca successiva

Offre grande liberta, ma introduce rischi rilevanti per performance, salvataggi, pathfinding, collisioni, arte, packaging e dipendenze esterne.

La profondita ispirata ad *Astroneer* rende una rappresentazione volumetrica o equivalente una candidata seria, soprattutto per aggiunta/rimozione libera, rampe, cavita e sporgenze. Non adottarla pero solo perche promette liberta. Valutarla dopo il prototipo discreto con un esperimento isolato e una matrice build-vs-buy. Qualsiasi plugin deve superare verifica di costo, licenza, manutenzione, accesso al sorgente, Godot 4.x (GDScript o GDExtension), Windows, Linux/Proton e Steam Deck.

### D. Approccio ibrido - candidato principale da ricercare

Usare deformazione continua soltanto in volumi o superfici predisposte, mantenendo rovine, strutture principali e limiti del livello come geometria controllata.

Possibili vantaggi:

- sensazione di scavo e modellazione profonda nelle aree importanti;
- protezione di landmark, obiettivi e struttura del livello;
- costi e salvataggi piu prevedibili;
- migliore convivenza con vegetazione, acqua, rovine e navigazione;
- possibilita di mantenere leggibili bordi e limiti dall'alto.

Rischio: se i confini delle zone deformabili risultano arbitrari, il sistema perde credibilita. Materiali, lore e feedback devono spiegare perche alcune strutture resistono.

## Primo micro-prototipo

Arena piccola con griglia o regioni nascoste alla presentazione finale.

Contenuto minimo:

- suolo normale;
- ostacolo resistente;
- area scavabile;
- tool personale per modificare una singola cella o piccola regione;
- macchina che modifica una linea o area piu ampia;
- due tipi di nemico con reazioni diverse al nuovo percorso;
- anteprima di modifica;
- annullamento o recupero controllato;
- misurazione di frame time e aggiornamento della navigazione.

Test A:

- aprire un corridoio accorcia il percorso e offre risorse;
- lo stesso corridoio consente alle orde un ingresso aggiuntivo.

Test B:

- sollevare una barriera devia i nemici e protegge una macchina;
- la barriera riduce lo spazio di schivata e puo bloccare la carovana.

## Spike tecnico di deformazione continua

Dopo che i test A/B hanno dimostrato valore sistemico, costruire una scena isolata senza gameplay completo per confrontare rappresentazione volumetrica e ibrida.

Azioni minime:

- scavare una trincea curva;
- creare un terrapieno;
- livellare una piattaforma per una macchina;
- formare una rampa percorribile;
- modificare ripetutamente la stessa zona;
- salvare e ricaricare lo stato;
- aggiornare collisione e un percorso nemico;
- usare le stesse azioni con controller e mouse;
- eseguire la scena su Steam Deck LCD.

Misure:

- frame time durante e dopo la modifica;
- picchi e stutter di collisione/navigazione;
- memoria e dimensione del salvataggio;
- precisione e tempo necessario per ottenere la forma desiderata;
- errori di occlusione e comprensione dalla camera di gioco;
- comportamento ai bordi fra terreno modificabile e strutture protette.

Lo spike non entra nel progetto principale finche non supera i gate e una revisione della dipendenza scelta.

## Rilievo continuo (tappa A: quartiere, 12 ottobre 2026)

Cosa c'e: `TerrainField` (quote, pennello a campana, livella, pendenza, aree protette, base e delta, salvataggio), `TerrainCollision` (chunk `HeightMapShape3D` rigenerati sotto il pennello nello stesso passo), `SoilPack` (zainetto da 60 m3, 20 all'avvio: scavare riempie, alzare svuota), tool del giocatore in quattro modi (Scava, Alza, Livella, Lampione) con anello a decal e portata di 3,6 m, campo di percorso sulla pendenza (0,8 m/m; saltatori 1,2), orda che rallenta in salita e rosicchia gli argini quando resta bloccata, quartiere a pennellate (argini dei cortili, cumuli con vene di rottami, solchi) su una base mossa, rottami solo dalle vene (uno ogni 0,8 m3 sotto la base del cumulo), Demolitore che spiana le cime conservando la terra e alza barricate a cumulo, lampioni su suolo piano che cadono se il suolo si muove di 40 cm, terremoto a cresta e solco, piazzola di estrazione a disco piano di 3 m, mappa di fine livello sui delta di quota, upgrade `pack_size`, `brush_size`, Prolunga in metri, resa a cinque strati con tinte di alzato, scavato e fango, prato e prop sulle quote, zainetto sul modello.

Misure (PC, headless, 12 ottobre 2026): pennellata del giocatore 1,1 ms in media e 4 ms al massimo con i chunk aggiornati (0,6 ms a chunk), base ricalcolata 0,58 s, pennellate del quartiere e assestamento di prato e prop 1,0 s, passo del direttore con 70 nemici 3,0 ms. Steam Deck non misurato.

Gate tecnici: navigazione e collisioni senza blocchi (i nemici bloccati rosicchiano, le pendenze oltre 0,8 sono muri), controller e tastiera equivalenti (il tool e lo stesso), budget su PC rispettato; **gate di gioco (i tester usano il terreno per risolvere problemi, due soluzioni valide, vantaggio e conseguenza prevedibili) aperti fino al playtest del proprietario**.

## Gate per proseguire

- I tester usano il terreno per risolvere problemi, non soltanto per raccogliere risorse.
- Almeno due soluzioni sono valide nella stessa situazione.
- Vantaggio e conseguenza sono prevedibili prima dell'attivazione.
- Tool e macchina hanno ruoli complementari.
- Nemici e proiettili restano leggibili durante e dopo la trasformazione.
- Navigazione e collisioni non producono blocchi frequenti.
- Controller e tastiera/mouse risultano entrambi naturali.
- La scena di stress rispetta il budget provvisorio su PC e Steam Deck LCD.

Se questi gate falliscono, modificare la grammatica del terreno prima di aumentare liberta, risoluzione o numero di materiali.

## Decisioni aperte

- ~~griglia visibile, nascosta o regioni irregolari~~ (rilievo continuo senza griglia, D-082/D-085);
- visuale e strumenti di anteprima durante la costruzione;
- quantita di terreno modificabile per situazione;
- velocita e rischio degli interventi personali;
- pathfinding continuo, a regioni o comportamento ibrido dei nemici;
- ruolo di acqua, vegetazione e ricrescita;
- velocita, preavviso e reversibilita delle inondazioni;
- persistenza fra tappe della stessa run;
- possibilita e costo di riparare una trasformazione sbagliata;
- ~~necessita reale di deformazione continua~~ (scelta: continua, D-085) o voxel (no);
- livello massimo di profondita, cavita e sporgenze leggibile dalla camera isometrica;
- confini e giustificazione delle eventuali zone non deformabili.
