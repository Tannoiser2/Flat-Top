extends Control
## Regolamento in italiano, riassunto dalle regole di Flat Top (con le errata ufficiali del 1984)
## e dalle scelte di questa versione digitale.

var main
var incorporato := false
var chiudi: Callable

const CAPITOLI := [
	["Il gioco", """Flat Top ricostruisce le battaglie di portaerei del 1942 attorno alle isole Salomone e alla Nuova Guinea. Ogni esagono della mappa misura circa 20 miglia, ogni turno è un'ora, ogni pedina navale è una nave e ogni fattore aereo vale circa tre aerei.

Il cuore del gioco è il movimento nascosto: le Task Force (TF) e le formazioni aeree (AF) che il nemico non ha avvistato non sono sul tavolo. Ognuno vede solo quello che le sue unità riescono a scoprire. Le basi aeree sono sempre visibili.

Si vince con i punti vittoria: navi affondate o danneggiate, aerei abbattuti, basi colpite, truppe sbarcate. Ogni scenario ha le sue condizioni speciali."""],
	["Sequenza del turno", """1. Meteo: ogni sei ore il vento può girare in ogni settore; ogni due turni le nubi si spostano di un esagono con il vento.
2. Ordini (simultanei): preparazione degli aerei, nuove formazioni aeree, rotte delle Task Force, ancore, contegno in battaglia.
3. Movimento delle Task Force, un esagono alla volta per tutti; prima si muovono le TF pedinate e chi le pedina.
4. Iniziativa: un dado a testa, il più alto muove per primo gli aerei (in parità la prende chi non l'aveva).
5. Movimento aereo: prima tutte le AF di chi ha l'iniziativa, poi quelle dell'altro. Si atterra a fine movimento.
6. Combattimento in ogni esagono: aria-aria, contraerea, attacco aereo, combattimento di superficie, bombardamento costiero.
7. Fine turno: riparazione delle basi, sbarchi, punti vittoria, avanzamento dell'orologio.

I turni dalle 1900 alle 0500 sono notturni: si vede poco, gli attacchi aerei sono molto meno precisi e ogni atterraggio è rischioso."""],
	["Avvistamento", """Osservano le basi (sempre), le TF messe sul tavolo e le AF che cercano. Una AF che vuole cercare tira un dado prima di muovere: riesce con 1-4 (di notte serve 1, con un +1 se vola alta in mezzo alle nubi). Le AF appena decollate non cercano nel primo turno.

Il numero di condizione dice quanto si vede:
- condizione 1: c'è qualcosa (navi o aerei), niente di più;
- condizione 2: il numero di TF e di navi, a meno del 50%, e se ci sono portaerei, navi maggiori o minori;
- condizione 3: la composizione esatta per classe e la quota degli aerei.
La condizione dipende dalla distanza (0-3 esagoni), dal tipo di osservatore, dalle nubi e dalla notte, come nella tabella di osservazione. Il radar vede gli aerei ad alta quota fino a 3 esagoni, anche di notte.

Chi viene avvistato finisce sul tavolo e da lì può osservare anche lui. Una TF nascosta non osserva: puoi metterla sul tavolo apposta, ma il nemico vedrà il segnalino. Nessuno vede né combatte dentro una tempesta (due nubi sovrapposte)."""],
	["Operazioni aeree", """Su ogni portaerei e base gli aerei passano da una casella all'altra: appena atterrati, in preparazione, pronti. Ogni turno il fattore di prontezza dice quanti fattori si possono spostare. Gli aerei si armano quando passano in «pronti»: siluri (T), bombe perforanti (AP, contro le navi) o bombe dirompenti (GP, contro le basi). Con la preparazione automatica i bombardieri si armano da soli e i caccia restano scarichi per la scorta e la pattuglia.

Il fattore di lancio limita gli aerei che decollano e atterrano in un turno: fino al valore minimo volano a pieno movimento, fino al normale a metà, fino al doppio del normale restano fermi sopra il ponte. Gli aerei armati non salgono in quota nel turno del decollo.

L'autonomia è in turni: ogni AF deve atterrare entro il turno segnato. Chi resta senza carburante si perde e vale 10 punti al nemico invece di 2. Ogni combattimento aereo e ogni attacco in picchiata, con siluri o a bassa quota costa un turno di autonomia.

Ogni lancio ha una categoria: la migliore possibile, oppure minima, normale o massima a scelta. Scegliere una categoria peggiore lascia libero il fattore minimo per far atterrare altre formazioni nello stesso turno. Per cambiare armamento gli aerei pronti tornano in preparazione e poi di nuovo in pronti: ogni passaggio consuma fattore di prontezza.

Le basi fuori mappa (Truk, Kavieng, Australia, Nuova Caledonia; Hawaii, Johnston, Marshall, Kwajalein e Midway sulle mappe degli scenari 6 e 7) non si raggiungono in volo: le formazioni decollate restano alcuni turni in transito e compaiono sull'esagono d'ingresso, dove nel primo turno non muovono. Per tornare raggiungono l'esagono d'ingresso, escono di mappa e atterrano dopo lo stesso numero di turni. Il transito dipende dalla distanza lungo la pista e dal movimento dell'aereo; sulle mappe di Midway e Wake è il numero stampato sul bordo."""],
	["Schieramento", """Prima del primo turno ognuno schiera in segreto le sue Task Force nelle zone indicate dallo scenario (settori, distanza da un'isola o dal bordo della mappa). Le zone si vedono evidenziate sulla mappa quando tocchi una TF. Le TF che arrivano più tardi scelgono l'esagono d'ingresso e, dove lo scenario lo permette, anche il turno in cui entrano.

Alcune navi partono all'ancora: nel Mar dei Coralli quelle schierate a Rabaul fino alle 1800 del 5 maggio, il convoglio di Tulagi finché non avvista una nave alleata o viene attaccato."""],
	["Guardacoste, scogliere e montagne", """Le stelle sulle isole sono i guardacoste: rossi giapponesi, blu alleati. Vedono gli aerei sopra la loro isola (condizione 3 col sereno sopra la terra, 2 sopra gli esagoni costieri, 1 nelle nubi), quelli negli esagoni di mare accanto alla costa (condizione 1, solo col sereno) e le navi lungo la costa (condizione 2) o appena al largo (condizione 1). Non vedono gli aerei sopra una base nemica. I guardacoste giapponesi della Nuova Guinea vedono solo nel loro perimetro; alcuni scenari ne ignorano altri.

Le Task Force non attraversano i lati d'esagono di scogliera (le linee blu tratteggiate) né quelli di terra piena fra due esagoni costieri. Gli aerei a bassa quota non scavalcano le montagne né i crinali neri delle isole: il pilota automatico sale in quota quando serve."""],
	["Missioni aeree", """In questa versione ogni formazione ha una missione e vola da sola:
- Attacco: punta sulle navi avvistate (seguendone gli spostamenti), su una base o su un esagono; cerca a ogni turno, attacca nel combattimento e poi rientra. Se il carburante non basta per tornare, rinuncia per tempo.
- Ricognizione: un aereo vola verso il punto indicato cercando a ogni turno e poi torna indietro.
- Pattuglia (CAP): i caccia restano sopra la portaerei o la base, si muovono con la TF e si danno il cambio da soli. Basta indicare quanti caccia tenere in aria.
- Trasferimento: gli aerei vanno su un'altra portaerei o base e atterrano.
Nella fase del movimento aereo puoi cambiare missione a ogni formazione, darle una rotta esagono per esagono, cambiare quota o farla atterrare, staccarne un gruppo in una nuova formazione alla quota opposta o unire due formazioni nello stesso esagono."""],
	["Combattimento aereo", """Il combattimento aria-aria avviene negli esagoni con navi o basi, oppure fino a due esagoni da una portaerei o una base con un tiro sulla tabella d'intercettazione, e anche durante il movimento quando una formazione entra dove ci sono caccia nemici sul tavolo alla stessa quota. Per ogni gruppo di caccia decidi tu: attacca le scorte, attacca i bombardieri o resta dov'è (di scorta ai tuoi bombardieri). Un caccia che intercetta non fa da scorta nello stesso turno.

Prima gli intercettori affrontano le scorte; se alla fine sono almeno il doppio delle scorte sopravvissute passano tutti sui bombardieri, se le scorte sono il doppio degli intercettori i bombardieri sono salvi. Il tiro è simultaneo e ogni tipo d'aereo usa il suo valore aria-aria. Modificatori: -1 nelle nubi, -2 di notte, -6 per i caccia armati di bombe.

Contraerea: chi difende divide la contraerea delle TF attaccate (e della base, se c'entra) fra i gruppi attaccanti; il tiro vale 4 (-2 contro chi bombarda d'alta quota, -1 nelle nubi, -2 di notte).

Attacco aereo: chi attacca sceglie per ogni gruppo armato la nave o la base bersaglio e il metodo: picchiata o bombardamento d'alta quota (solo se la formazione vola alta), bassa quota o siluri (solo contro le navi). Un gruppo può anche non attaccare e tenere le bombe. Il valore viene dalle tabelle d'impatto aereo: +2 contro navi immobilizzate o all'ancora, -2 nelle nubi, -4 di notte. I colpi raddoppiano se la portaerei o la base ha aerei sul ponte (pronti o appena atterrati) o, contro i siluri, aerei in preparazione."""],
	["La tabella dei risultati", """Ogni tiro usa la tabella dei risultati: si incrocia il valore (BHT, da 1 a 15) con il numero di fattori che attaccano e si ottiene il numero risultato. Poi un dado: con 1 si sottrae 2, con 2 si sottrae 1, con 3-4 vale il numero, con 5 si aggiunge 1, con 6 si aggiunge 2. Con l'asterisco solo un 6 fa un colpo.

Ogni colpo su una nave toglie un fattore d'artiglieria e uno di contraerea e, sulle portaerei, riduce il fattore di lancio e distrugge un aereo a bordo: lo sceglie chi attacca dopo una picchiata o un attacco a bassa quota di giorno, altrimenti chi difende. Con metà dei punti di danno la nave dimezza la velocità, con il danno meno uno resta immobilizzata, con tutti affonda (e porta con sé gli aerei a bordo).

Ogni colpo su una base riduce il fattore di lancio di 2/1, la contraerea e il fattore di superficie di 1 e distrugge un aereo (due colpi per un aereo disperso). Le basi riparano un colpo per turno se non vengono attaccate."""],
	["Combattimento di superficie", """Quando TF nemiche si trovano nello stesso esagono e si vedono, ognuno decide in segreto se ingaggiare: basta che uno lo voglia e l'altro non può evitarlo. Poi ognuno assegna in segreto ogni nave alla linea d'artiglieria, all'attacco con siluri o allo schermo (le navi all'ancora o immobilizzate stanno nello schermo) e sceglie un dado: la somma dei due dadi è il valore per tutti i tiri.

Prima spara l'artiglieria: ognuno divide i suoi fattori fra le navi nemiche (contro le corazzate valgono solo quelli di corazzate e incrociatori pesanti). Poi i siluri, divisi allo stesso modo, se il valore è almeno 10 di giorno o 7 di notte: quelli giapponesi valgono 15, quelli alleati 10. Chi resta con il triplo dell'artiglieria nemica può sfondare e colpire le navi dello schermo, che rispondono al fuoco. Le munizioni si consumano a ogni tiro.

Con il contegno «Bombarda» le navi nell'esagono di una base nemica la cannoneggiano con valore 8; la base risponde con il suo fattore di superficie."""],
	["Sbarchi e vittoria", """I trasporti (AP e APD) devono gettare l'ancora negli esagoni indicati dallo scenario; dal turno dopo scaricano un turno alla volta, fino a otto turni, e ogni turno di scarico vale 3 punti (1 per gli APD). Un trasporto scarico vale meno se affondato.

Punti vittoria: 2 per ogni fattore aereo abbattuto (10 se perso senza combattere), 1 per ogni colpo su una base, 10 o 5 per ogni turno in cui Henderson, Rabaul o un'altra base hanno il fattore di lancio a zero, i punti di danno e d'affondamento delle navi secondo la tabella.

Alle 2400 di ogni giorno, se lo scarto supera il livello di vittoria automatica dello scenario, la partita finisce. Altrimenti vince chi ha più punti alla fine, purché ne abbia almeno quanti chiede lo scenario."""],
	["Decisioni: Suggerisci e Auto", """Ogni decisione è tua: schieramento, intercettazioni, bersagli e metodo d'attacco, contraerea, aerei distrutti a bordo, ingaggio, posizioni, dado e fuoco nel combattimento di superficie. In ogni finestra:
- Suggerisci compila la scelta come la farebbe l'IA: puoi cambiarla prima di confermare;
- Auto accetta subito la scelta dell'IA;
- «Sempre automatico» fa decidere all'IA quel tipo di decisione per il resto della partita (si riattiva dal pannello degli ordini).

Quando il nemico ti avvista con la condizione 2 puoi dichiarare il numero di navi e aerei vero, gonfiato del 50%, ridotto del 50% o a caso: si sceglie nel pannello degli ordini e vale finché non lo cambi. Dal pannello di un avvistamento puoi ordinare a una tua TF o AF nello stesso esagono di pedinare la TF nemica."""],
	["Scenari 6 e 7: Midway e Wake", """Hanno mappe proprie, quasi tutte di mare, con gli atolli e i numeri sul bordo che indicano i turni di volo dalle basi fuori mappa (H Hawaii, J Johnston, M Marshall o Midway, K Kwajalein).
Midway: il Giappone vince se sbarca almeno 200 punti sull'atollo; con 250 Midway diventa una base giapponese e gli aerei alleati rimasti a terra sono perduti. Sull'Hosho atterrano solo i Kate.
Wake: vince il Giappone se sbarca a Wake almeno 50 punti più degli Alleati. I Buffalo partono dal Saratoga ma possono atterrare solo a terra. Alla fine ogni portaerei giapponese lontana più di 10 colonne dal bordo ovest dà 50 punti agli Alleati.
I valori di Buffalo, Vindicator e B-24 vengono dalla tabella d'impatto aereo del modulo; movimento e autonomia sono stimati dai tipi simili, e così le capacità delle basi di Midway e Wake."""],
	["Questa versione", """- Le missioni e il pilota automatico sostituiscono la scheda di registrazione aerea: l'autonomia e i turni d'atterraggio sono calcolati dal gioco, ma rotta, quota, atterraggio, divisione e unione delle formazioni si possono comandare a mano.
- La pattuglia (CAP) è automatica sul numero di caccia scelto per ogni portaerei e base.
- Le zone di schieramento «A» e «B» di Midway non sono stampate sulla mappa: qui sono il nord-ovest e il sud-ovest.
- Non sono usate le regole opzionali (sottomarini, sommergibili tascabili, colpi critici, rifornimento in mare).
- Le partite salvate con le versioni precedenti, che avevano meno decisioni, non si possono più riprendere.
- Partite salvate sul server con un codice di sei lettere; partita online in due con ognuno che vede solo il suo lato."""],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc.offset_left = 60
	pc.offset_right = -60
	pc.offset_top = 40
	pc.offset_bottom = -40
	add_child(pc)
	var v := UI.vbox(10)
	pc.add_child(v)
	var h := UI.hbox(12)
	v.add_child(h)
	h.add_child(UI.title("Regolamento", 44))
	h.add_child(UI.spacer())
	h.add_child(UI.button("Chiudi", _chiudi, 22, 160))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var body := UI.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	for cap in CAPITOLI:
		body.add_child(UI.label(cap[0], 30, UI.BRASS_L, UI.font_title))
		var p := UI.dispatch(cap[1].strip_edges(), 1100)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(p)


func _chiudi() -> void:
	if incorporato:
		if chiudi.is_valid():
			chiudi.call()
		queue_free()
	elif main != null:
		main.show_menu()
