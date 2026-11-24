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

Le basi fuori mappa (Truk, Kavieng, Australia, Nuova Caledonia) sono collegate al tavolo dalla pista rossa: gli aerei la percorrono come il resto della mappa."""],
	["Missioni aeree", """In questa versione ogni formazione ha una missione e vola da sola:
- Attacco: punta sulle navi avvistate (seguendone gli spostamenti), su una base o su un esagono; cerca a ogni turno, attacca nel combattimento e poi rientra. Se il carburante non basta per tornare, rinuncia per tempo.
- Ricognizione: un aereo vola verso il punto indicato cercando a ogni turno e poi torna indietro.
- Pattuglia (CAP): i caccia restano sopra la portaerei o la base, si muovono con la TF e si danno il cambio da soli. Basta indicare quanti caccia tenere in aria.
- Trasferimento: gli aerei vanno su un'altra portaerei o base e atterrano.
Nella fase del movimento aereo puoi cambiare missione a ogni formazione, darle una rotta esagono per esagono, cambiare quota o farla atterrare."""],
	["Combattimento aereo", """Il combattimento aria-aria avviene negli esagoni con navi o basi, oppure fino a due esagoni da una portaerei o una base con un tiro sulla tabella d'intercettazione. Solo gli intercettori possono attaccare: i caccia che volano con i propri bombardieri fanno da scorta.

Prima gli intercettori affrontano le scorte; se alla fine sono almeno il doppio delle scorte sopravvissute passano tutti sui bombardieri, se le scorte sono il doppio degli intercettori i bombardieri sono salvi. Il tiro è simultaneo e ogni tipo d'aereo usa il suo valore aria-aria. Modificatori: -1 nelle nubi, -2 di notte, -6 per i caccia armati di bombe.

Contraerea: ogni nave della TF attaccata spara contro ogni formazione che la attacca, con valore 4 sul totale della sua contraerea (-2 contro gli aerei in alta quota, -1 nelle nubi, -2 di notte).

Attacco aereo: picchiata (gli aerei scendono dall'alta quota), siluri (a bassa quota) o bombardamento orizzontale. Il valore viene dalle tabelle d'impatto aereo: +2 contro navi immobilizzate o all'ancora, -2 nelle nubi, -4 di notte. I colpi raddoppiano se la portaerei o la base ha aerei sul ponte (pronti o appena atterrati) o, contro i siluri, aerei in preparazione."""],
	["La tabella dei risultati", """Ogni tiro usa la tabella dei risultati: si incrocia il valore (BHT, da 1 a 15) con il numero di fattori che attaccano e si ottiene il numero risultato. Poi un dado: con 1 si sottrae 2, con 2 si sottrae 1, con 3-4 vale il numero, con 5 si aggiunge 1, con 6 si aggiunge 2. Con l'asterisco solo un 6 fa un colpo.

Ogni colpo su una nave toglie un fattore d'artiglieria e uno di contraerea e, sulle portaerei, riduce il fattore di lancio e distrugge un aereo a bordo. Con metà dei punti di danno la nave dimezza la velocità, con il danno meno uno resta immobilizzata, con tutti affonda (e porta con sé gli aerei a bordo).

Ogni colpo su una base riduce il fattore di lancio di 2/1, la contraerea e il fattore di superficie di 1 e distrugge un aereo (due colpi per un aereo disperso). Le basi riparano un colpo per turno se non vengono attaccate."""],
	["Combattimento di superficie", """Quando TF nemiche si trovano nello stesso esagono e si vedono, si combatte se almeno una delle due ha il contegno «Attacca». Ogni nave sta in linea d'artiglieria, in attacco con siluri oppure nello schermo (portaerei, trasporti, navi immobilizzate o all'ancora). Ognuno sceglie in segreto un dado: la somma è il valore per tutti i tiri del turno.

Prima spara l'artiglieria (solo corazzate e incrociatori pesanti possono colpire le corazzate), poi i siluri se il valore è almeno 10 di giorno o 7 di notte: quelli giapponesi valgono 15, quelli alleati 10. Chi resta con il triplo dell'artiglieria nemica sfonda e colpisce le navi dello schermo. Le munizioni si consumano a ogni tiro.

Con il contegno «Bombarda» le navi nell'esagono di una base nemica la cannoneggiano con valore 8; la base risponde con il suo fattore di superficie."""],
	["Sbarchi e vittoria", """I trasporti (AP e APD) devono gettare l'ancora negli esagoni indicati dallo scenario; dal turno dopo scaricano un turno alla volta, fino a otto turni, e ogni turno di scarico vale 3 punti (1 per gli APD). Un trasporto scarico vale meno se affondato.

Punti vittoria: 2 per ogni fattore aereo abbattuto (10 se perso senza combattere), 1 per ogni colpo su una base, 10 o 5 per ogni turno in cui Henderson, Rabaul o un'altra base hanno il fattore di lancio a zero, i punti di danno e d'affondamento delle navi secondo la tabella.

Alle 2400 di ogni giorno, se lo scarto supera il livello di vittoria automatica dello scenario, la partita finisce. Altrimenti vince chi ha più punti alla fine, purché ne abbia almeno quanti chiede lo scenario."""],
	["Questa versione", """- Le missioni e il pilota automatico sostituiscono la scheda di registrazione aerea: l'autonomia e i turni d'atterraggio sono calcolati dal gioco.
- Il condizione 2 dell'avvistamento (il nemico può mentire del 50%) è resa da numeri approssimati in modo casuale.
- Le formazioni hanno una sola quota per volta: gli attacchi misti si dividono in due formazioni (picchiatori in alto, aerosiluranti in basso), come fa la finestra di lancio.
- La pattuglia (CAP) è automatica sul numero di caccia scelto per ogni portaerei e base.
- Nel combattimento aereo gli intercettori si dividono a metà fra scorte e bombardieri; i bersagli degli attacchi sono scelti dalla priorità della missione (portaerei o trasporti).
- Le basi fuori mappa si raggiungono volando lungo la pista rossa.
- Non sono usate le regole opzionali (sottomarini, colpi critici, rifornimento), né i guardacoste e i lati d'esagono di scogliera.
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
