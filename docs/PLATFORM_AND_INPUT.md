# Piattaforme e input

## Stato e obiettivi

- Piattaforma di sviluppo e prima release: **Windows PC**.
- Distribuzione prevista: **Steam**.
- Input primario: **controller/gamepad**.
- Input pienamente supportato: **tastiera e mouse**.
- Obiettivo secondario: buona esperienza su **Steam Deck**, con aspirazione alla classificazione Verified se sostenibile.
- Build Linux nativa: non prevista inizialmente; la prima strategia e testare la build Windows attraverso Proton.
- Hardware di test: Steam Deck LCD gia posseduto dal proprietario; capacita e configurazione da registrare al primo test.

La classificazione Steam Deck non puo essere promessa prima dei test e della revisione Valve. Il progetto deve tuttavia evitare fin dall'inizio scelte che la rendano inutilmente difficile.

## Principio controller-first, input-parity

Controller-first significa che movimento, combattimento, costruzione, guida, inventario, menu e impostazioni vengono progettati prima per un gamepad standard. Non significa offrire a tastiera e mouse un'esperienza inferiore.

Requisiti:

- ogni funzione necessaria deve essere raggiungibile con entrambi gli schemi;
- nessun menu deve richiedere il mouse;
- nessuna azione obbligatoria deve richiedere precisione da cursore non riproducibile con stick;
- cambiare dispositivo deve aggiornare rapidamente i glifi mostrati;
- controller collegato o scollegato durante il gioco non deve bloccare la sessione;
- rimappatura, sensibilita, inversione assi e dead zone devono essere previste nell'architettura;
- la mira deve offrire inversione indipendente degli assi orizzontale e verticale, almeno per lo stick destro e senza imporre la stessa scelta al mouse;
- le impostazioni devono distinguere chiaramente controller, tastiera e mouse;
- il gameplay non deve dipendere da combinazioni scomode o dal clic degli stick per azioni frequenti;
- vibrazione e aim assist, se presenti, devono essere configurabili.

## Impostazioni grafiche (requisito della versione definitiva)

Il gioco avra un menu Impostazioni con le opzioni grafiche (D-031): limite di fps (default 120), VSync (Mailbox, classico, off), antialiasing, risoluzione e modalita finestra, eventuale scala di rendering, con preset adatti a Steam Deck. Oggi questi valori sono fissi in `godot/project.godot`; F2 alterna la VSync solo come strumento di playtest.

## Implementazione Godot

Implementata dal 3 ottobre 2026 con la **mappa input di progetto** di Godot (`godot/project.godot`, sezione `[input]`), dead zone per azione. Al 17 ottobre 2026 le azioni del progetto sono 21: 19 di gioco, ognuna con un evento controller e uno tastiera/mouse tranne `aim_up`/`aim_down`/`aim_left`/`aim_right` (solo stick destro: col mouse si punta) e `camera_zoom_in`/`camera_zoom_out` (solo rotellina; col controller la distanza cambia con `camera_zoom_cycle`); 2 di debug solo da tastiera, `debug_next_tuning` (Tab) e `debug_cycle_vsync` (F2). In piu `ui_accept` e `ui_cancel`, ridefinite con A e B. L'ultima arrivata e `interact` (Interagisci, X / R: tenuto ripara una macchina della carovana; premuto sulla pedana di fusione apre il banco, a gioco fermo, D-093). Il gameplay legge solo azioni (`Input.get_vector`, `is_action_pressed`), mai tasti fisici. Rimappatura e inversione assi si appoggeranno a `InputMap` a runtime. L'implementazione Unreal precedente usava Enhanced Input con mapping costruiti in C++.

Contesti previsti, da realizzare quando servono come gruppi di azioni attivati dal gioco:

- gameplay a piedi;
- modalita costruzione;
- guida delle macchine;
- menu e UI;
- eventuale modalità foto o debug, non inclusa nel prototipo.

Le azioni devono descrivere intenzioni (`Move`, `Aim`, `Dash`, `Build`, `RotateMachine`, `Interact`, `EnterVehicle`) e non tasti fisici. Il codice deve ascoltare le azioni, non controllare direttamente pulsanti specifici.

## Schema iniziale candidato

Non e ancora approvato e verra verificato nel prototipo.

| Intenzione | Controller | Tastiera/mouse |
|---|---|---|
| Movimento | stick sinistro | WASD |
| Mira o orientamento costruzione | stick destro | mouse |
| Dash/evasione | pulsante frontale | Spazio |
| Distanza camera, tre preset: 11, 15, 20 m (D-078) | Y cicla | C cicla; rotellina avvicina/allontana |
| Interagisci (interact) | X | R |
| Modalita costruzione | dorsale o grilletto | tasto dedicato |
| Posizionamento/conferma | grilletto o pulsante frontale | clic sinistro |
| Rotazione/modulo | dorsali o croce direzionale | rotella/tasti |
| Abilita mirata | grilletto | clic destro o tasto dedicato |
| Pausa/menu | Menu | Esc |

L'arma personale automatica resta la prima ipotesi, per lasciare gli stick a movimento e orientamento/ingegneria. Un attacco manuale o semi-automatico verra aggiunto soltanto se non sovraccarica il controllo durante costruzione e trasformazione del campo.

## UI e accessibilita di input

- navigazione direzionale esplicita e prevedibile;
- focus sempre visibile;
- nessun hover indispensabile;
- conferma e annullamento coerenti in tutti i menu;
- slider regolabili con controller senza salti eccessivi;
- prompt con glifi corretti per il dispositivo attivo;
- opzione per aumentare dimensione testo e UI;
- contrasto sufficiente in luce e buio;
- pausa disponibile durante le schermate di scelta in single-player, salvo test contrario;
- evitare input a pressione prolungata senza indicatore di avanzamento;
- valutare alternative a ripetute pressioni rapide.

## Obiettivo Steam Deck

La build Windows puo essere eseguita su Steam Deck tramite Proton. La build Linux nativa verra valutata soltanto se Proton presenta problemi non risolvibili o se esiste un vantaggio misurabile.

Obiettivi di progettazione:

- funzionamento completo con i controlli fisici del Deck e configurazione predefinita;
- nessuna configurazione manuale richiesta prima di giocare;
- supporto a 1280x800, aspect ratio 16:10, e 1280x720;
- UI sicura ai bordi e scalabile;
- testo mai sotto il minimo richiesto da Valve; target interno almeno 12 pixel a 1280x800, salvo elementi non testuali;
- glifi coerenti con l'input effettivamente usato;
- nessun launcher esterno necessario;
- tastiera virtuale richiamata automaticamente se viene richiesto testo;
- preset grafico adatto al Deck selezionato automaticamente o come default appropriato;
- frame pacing stabile e gameplay leggibile nelle scene di stress;
- salvataggi e Steam Cloud, se adottato, coerenti fra PC e Deck;
- niente middleware, codec o anti-cheat non verificati con Proton.

Target prestazionale iniziale: progettare per 60 fps, misurare appena esiste una scena di stress e definire solo allora preset e fallback realistici. Non dichiarare compatibilita sulla base dell'Editor o di un PC desktop.

## Strategia di test

### Dal primo prototipo

- testare ogni incremento sia con controller sia con tastiera/mouse;
- iniziare ogni nuova schermata verificando la navigazione senza mouse;
- simulare 1280x800 e 16:10 nell'Editor;
- controllare glifi, focus e cambio dispositivo;
- registrare separatamente bug specifici dei due schemi.
- non appena esiste la prima build Windows pacchettizzata, eseguire uno smoke test sullo Steam Deck disponibile tramite Proton.

### Dalla prima build pacchettizzata alla vertical slice

- provare la build Windows reale tramite Proton;
- testare sullo Steam Deck fisico gia disponibile;
- configurare SteamOS Devkit Client quando la distribuzione frequente sul dispositivo diventa utile;
- misurare frame time, memoria, temperature percepite, consumo e leggibilita;
- testare sospensione/ripresa, dock/undock e cambio fra controlli integrati ed esterni;
- verificare testo e UI alla distanza d'uso reale.

### Prima della release

- eseguire la checklist Valve aggiornata;
- richiedere la Compatibility Review quando disponibile nel partner site;
- correggere i risultati e richiedere una nuova revisione se necessario;
- non usare badge o dichiarazioni di compatibilita non ancora assegnati da Valve.

## Hardware e acquisti

Il proprietario possiede gia uno Steam Deck, quindi non e previsto alcun acquisto hardware per questa verifica. Il dispositivo entra nella matrice di test dalla prima build Windows pacchettizzata. Emulatori e test desktop restano utili, ma non sostituiscono display, controlli, sospensione e prestazioni reali.

Dispositivo di riferimento attuale: **Steam Deck LCD**. Al primo utilizzo registrare:

- capacita e spazio disponibile;
- versione SteamOS e canale aggiornamenti;
- eventuale microSD o dock usato nei test;
- refresh rate e limite frame selezionati;
- versione Proton e preset grafico della build.

## Gate di input del prototipo

Il prototipo del core loop non supera il gate se:

- una funzione necessaria e disponibile soltanto su uno schema;
- costruzione o orientamento risultano significativamente frustranti con il controller;
- il focus UI puo andare perduto;
- i prompt mostrano input errati dopo il cambio dispositivo;
- dead zone o sensibilita non permettono movimento e orientamento precisi;
- il gioco richiede il mouse per riprendere una sessione avviata col controller.

## Fonti ufficiali

- [Valve - Steam Deck e Steam Machine Compatibility Review](https://partner.steamgames.com/doc/steamhardware/compat?l=english)
- [Valve - Caricare ed eseguire build su Steam Deck](https://partner.steamgames.com/doc/steamhardware/loadgames?language=english)
- [Epic Games - Steam Deck Quick Start per Unreal Engine](https://dev.epicgames.com/documentation/unreal-engine/steam-deck-quick-start-in-unreal-engine)

I criteri Valve, Proton e Unreal possono cambiare e devono essere ricontrollati prima della vertical slice e della release.
