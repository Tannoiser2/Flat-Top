# Flat Top

Versione digitale di **Flat Top** (Avalon Hill, 1977): battaglie di portaerei nelle isole Salomone, 1942.
Godot 4.7 (gl_compatibility), esportazione web, tutto in italiano.

## Cosa c'è
- Mappa originale (modulo VASSAL di Scott Giese e Wim Oudshoorn), pedine, tabelle e regolamento con le errata 1984.
- Undici scenari: Anelli attorno a Rabaul; Mar dei Coralli (battaglia, giorni cruciali, campagna di 109 turni); Salomone orientali (battaglia, campagna); Santa Cruz (battaglia, campagna); Guadalcanal; Midway e Wake, ognuno con la sua mappa.
- Schieramento segreto nelle zone degli scenari, guardacoste, scogliere e crinali, basi fuori mappa con i turni di transito.
- Ogni decisione è del giocatore (intercettazioni, bersagli e metodi d'attacco, contraerea, aerei distrutti a bordo, ingaggio, posizioni, dado e fuoco nel combattimento di superficie), con i tasti Suggerisci e Auto.
- Movimento nascosto con avvistamenti a tre condizioni, meteo (vento, nubi, tempeste), notte.
- Operazioni aeree complete: preparazione, armamento, fattori di lancio, autonomia, CAP, missioni con pilota automatico.
- Combattimento aria-aria, contraerea, attacco aereo, superficie con siluri, bombardamento costiero, sbarchi, punti vittoria.
- IA che usa solo i propri avvistamenti (ricognizione a ventaglio, attacchi coordinati, gestione delle portaerei).
- Partita in solitario, in due sullo stesso dispositivo, online in due (Firebase, radice `flattop/rooms`), salvataggi (`flattop/partite`).

## Strumenti
- `tools/costruisci_dati.py`: ricava i dati (esagoni, aerei, navi, basi, scenari) dal materiale originale.
- `tools/costruisci_lati.py`: scogliere, terra piena, crinali, isole e guardacoste dalla mappa.
- `tools/costruisci_mappe_isole.py`: mappe di Midway e Wake.
- `tools/controlla_glifi.py`: controlla che ogni carattere esista nei font.
- `tests/sim.gd`: partita IA contro IA (`godot --headless --path . -s tests/sim.gd -- coral_battaglia 1`).
- `tests/shot.gd`: fotografie dell'interfaccia (con xvfb-run).
- `tests/shot_dec.gd`: fotografie delle finestre di decisione (schieramento e combattimenti).

## Pubblicazione
Solo a richiesta: Actions → Pubblica → Run workflow, oppure un commit con `[pubblica]` nel messaggio.
