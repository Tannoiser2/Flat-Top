class_name UI
extends RefCounted
## Grafica condivisa. Tema «sala operativa della flotta, 1942»: pannelli d'acciaio blu marina con
## bordi ottone, moduli di messaggio color carta per i rapporti, giallo cachi per gli Alleati e
## rosso per il Giappone come le pedine del gioco originale.
## Caratteri liberi: Stardos Stencil (titoli a stampino), Barlow Condensed (interfaccia),
## Special Elite (dispacci battuti a macchina), Courier Prime (tabelle).

const BG := Color("#0b1118")
const PANEL := Color("#16212c")
const PANEL_L := Color("#223242")
const STEEL := Color("#3a4f63")
const BRASS := Color("#c8a352")
const BRASS_L := Color("#ecd28e")
const PAPER := Color("#e9e0c6")
const PAPER_D := Color("#cfc29b")
const INK := Color("#1f1a12")
const TEXT := Color("#e8eef2")
const MUTED := Color("#9fb0bf")
const ALLIED := Color("#e3c54a")
const ALLIED_D := Color("#8a7420")
const JAPAN := Color("#d23a2c")
const JAPAN_D := Color("#7c1d15")
const SEA := Color("#2a6f99")
const GOOD := Color("#8fd27a")
const BAD := Color("#ff6b5a")
const NIGHT := Color("#0e1b3a")

static var font_title: Font
static var font_ui: Font
static var font_ui_b: Font
static var font_type: Font
static var font_mono: Font
static var _tex := {}


static func init_fonts() -> void:
	if font_ui != null:
		return
	font_title = load("res://assets/fonts/StardosStencil-Bold.ttf")
	font_ui = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	font_ui_b = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	font_type = load("res://assets/fonts/SpecialElite-Regular.ttf")
	font_mono = load("res://assets/fonts/CourierPrime-Regular.ttf")


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


static func lato_col(s: String) -> Color:
	return ALLIED if s == "A" else JAPAN


static func lato_dark(s: String) -> Color:
	return ALLIED_D if s == "A" else JAPAN_D


static func panel_style(bg: Color, border: Color = BRASS, bw := 2, radius := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb


static func dark_style(alpha := 0.95) -> StyleBoxFlat:
	var sb := panel_style(Color(PANEL, alpha), Color(BRASS, 0.55), 2, 4)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	return sb


static func paper_style() -> StyleBoxFlat:
	var sb := panel_style(PAPER, Color("#8c7a4e"), 1, 2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	sb.set_content_margin_all(14)
	return sb


static func make_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font_ui
	t.default_font_size = 22
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", BRASS_L)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.6))
	t.set_font("font", "Button", font_ui_b)
	t.set_font_size("font_size", "Button", 22)
	var bn := panel_style(PANEL_L, Color(BRASS, 0.7), 2, 4)
	bn.set_content_margin_all(8)
	bn.content_margin_left = 14
	bn.content_margin_right = 14
	var bh := bn.duplicate()
	bh.bg_color = STEEL
	bh.border_color = BRASS_L
	var bp := bn.duplicate()
	bp.bg_color = BRASS
	bp.border_color = BRASS_L
	var bd := bn.duplicate()
	bd.bg_color = Color(PANEL, 0.7)
	bd.border_color = Color(STEEL, 0.6)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", dark_style())
	t.set_stylebox("panel", "Panel", dark_style())
	t.set_color("font_color", "LineEdit", INK)
	var le := panel_style(PAPER, BRASS, 2, 3)
	le.set_content_margin_all(8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_font("font", "LineEdit", font_type)
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_font_size("font_size", "CheckButton", 20)
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color(BRASS, 0.5)
	sc.set_corner_radius_all(4)
	t.set_stylebox("grabber", "VScrollBar", sc)
	t.set_stylebox("grabber_highlight", "VScrollBar", sc)
	t.set_stylebox("grabber_pressed", "VScrollBar", sc)
	var sct := StyleBoxFlat.new()
	sct.bg_color = Color(0, 0, 0, 0.25)
	sct.set_content_margin_all(4)
	t.set_stylebox("scroll", "VScrollBar", sct)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font_ui)
	t.set_font("bold_font", "RichTextLabel", font_ui_b)
	t.set_font_size("normal_font_size", "RichTextLabel", 21)
	t.set_font_size("bold_font_size", "RichTextLabel", 21)
	var tip := panel_style(PAPER, BRASS, 1, 3)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font("font", "TooltipLabel", font_type)
	return t


static func label(text: String, size := 22, col: Color = TEXT, font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


## Testo che va a capo: ha sempre una larghezza minima, così non si schiaccia in colonna.
static func wrap(text: String, size := 20, col: Color = TEXT, min_w := 260.0, font: Font = null) -> Label:
	var l := label(text, size, col, font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(min_w, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func title(text: String, size := 44, col: Color = BRASS_L) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, cb: Callable, size := 22, min_w := 120.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(min_w, 44)
	b.pressed.connect(cb)
	return b


static func big_button(text: String, cb: Callable, w := 420.0) -> Button:
	var b := button(text, cb, 28, w)
	b.custom_minimum_size = Vector2(w, 64)
	return b


static func hsep(col: Color = Color(BRASS, 0.4)) -> Control:
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(0, 2)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func margin(child: Control, m := 12) -> MarginContainer:
	var mc := MarginContainer.new()
	for k in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + k, m)
	mc.add_child(child)
	return mc


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Pannello carta con testo battuto a macchina (rapporti, dispacci).
static func dispatch(text: String, w := 520.0) -> PanelContainer:
	init_fonts()
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", paper_style())
	var l: Label = UI.wrap(text, 20, INK, w, font_type)
	p.add_child(l)
	return p


static func aereo_tex(tipo: String) -> Texture2D:
	return tex("res://assets/pedine/aereo_%s.png" % tipo)


static func tf_tex(lato: String, num: int) -> Texture2D:
	var t := tex("res://assets/pedine/tf_%s_%d.png" % [lato, num])
	return t if t != null else tex("res://assets/pedine/tf_%s.png" % lato)


static func af_tex(lato: String, num: int) -> Texture2D:
	var t := tex("res://assets/pedine/af_%s_%d.png" % [lato, num])
	return t if t != null else tex("res://assets/pedine/af_%s.png" % lato)


## Sfondo della sala operativa: la mappa sfumata e una griglia leggera.
class Backdrop extends Control:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UI.BG)
		var t := UI.tex("res://assets/map/mappa.webp")
		if t != null:
			var sc := maxf(size.x / t.get_width(), size.y / t.get_height())
			var ts := Vector2(t.get_width(), t.get_height()) * sc
			draw_texture_rect(t, Rect2((size - ts) / 2.0, ts), false, Color(0.35, 0.42, 0.5, 0.55))
		var step := 64.0
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.035), 1.0)
			x += step
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.035), 1.0)
			y += step

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
