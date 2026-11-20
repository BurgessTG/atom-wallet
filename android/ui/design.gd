extends RefCounted

const Icon = preload("res://icon.gd")
const FACE = preload("res://InterVariable.ttf")
const INK := Color("#f2effc")
const MUTED := Color("#afaec3")
const DIM := Color("#8e8ca4")
const ACCENT := Color("#beb1ff")
const GREEN := Color("#8cdebb")
const SURFACE := Color("#181923")
const LINE := Color("#30303e")
const BG := Color("#0e0f16")

static func style(fill: Color, radius := 16, border := Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.set_border_width_all(width)
	box.border_color = border
	box.corner_detail = 8
	return box

static func font(weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = FACE
	f.variation_opentype = { TextServerManager.get_primary_interface().name_to_tag("wght"): weight }
	return f

static func label(parent: Control, value: String, px := 15, ink := INK, weight := 450, wrap := false) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_override("font", font(weight))
	item.add_theme_font_size_override("font_size", px)
	item.add_theme_color_override("font_color", ink)
	item.add_theme_constant_override("line_spacing", 2)
	if wrap: item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

static func vbox(parent: Control, gap := 12) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

static func row(parent: Control, gap := 10) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

static func inset(parent: Control, x: int, y: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left","right"]: m.add_theme_constant_override("margin_"+side, x)
	for side in ["top","bottom"]: m.add_theme_constant_override("margin_"+side, y)
	parent.add_child(m)
	return m

static func card(parent: Control, fill := SURFACE, x := 16, y := 14) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(fill, 18, LINE))
	parent.add_child(panel)
	return vbox(inset(panel, x, y), 6)

static func space(parent: Control, height := 0, expand := false) -> Control:
	var pad := Control.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.custom_minimum_size.y = height
	if expand:
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(pad)
	return pad

static func icon(parent: Control, symbol: String, ink := INK, px := 21) -> Control:
	var glyph = Icon.new()
	glyph.symbol = symbol
	glyph.ink = ink
	glyph.custom_minimum_size = Vector2(px, px)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(glyph)
	return glyph

static func button(parent: Control, title: String, action: Callable, variant := "normal", symbol := "") -> Button:
	var b := Button.new()
	var primary := variant == "primary"
	var quiet := variant == "quiet"
	var fill := ACCENT if primary else (Color.TRANSPARENT if quiet else SURFACE)
	var ink := Color("#171326") if primary else (ACCENT if quiet else INK)
	b.custom_minimum_size.y = 49
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.accessibility_name = title
	b.add_theme_stylebox_override("normal", style(fill, 14, LINE if variant == "normal" else Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover", style(fill.lightened(.06), 14))
	b.add_theme_stylebox_override("pressed", style(fill.lightened(.12), 14))
	b.add_theme_stylebox_override("disabled", style(fill.darkened(.28), 14))
	var focus := style(Color.TRANSPARENT, 14, ACCENT, 2)
	b.add_theme_stylebox_override("focus", focus)
	parent.add_child(b)
	var h := row(b, 7)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not symbol.is_empty(): icon(h, symbol, ink, 17)
	label(h, title, 14, ink, 630)
	b.pressed.connect(action)
	return b

static func field(parent: Control, hint: String, secret := false) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = hint
	f.secret = secret
	f.custom_minimum_size.y = 52
	f.add_theme_font_override("font", FACE)
	f.add_theme_font_size_override("font_size",16)
	f.add_theme_color_override("font_color", INK)
	f.add_theme_color_override("font_placeholder_color", DIM)
	for state in ["normal", "focus"]:
		var box := style(SURFACE, 12, ACCENT if state == "focus" else LINE)
		box.content_margin_left = 14; box.content_margin_right = 14
		f.add_theme_stylebox_override(state, box)
	if secret:
		f.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
		f.context_menu_enabled = false
	parent.add_child(f)
	return f
