extends RefCounted

const Icon = preload("res://icon.gd")
const FACE = preload("res://InterVariable.ttf")
const INK := Color("#f0f6f6")
const MUTED := Color("#a3b6ba")
const DIM := Color("#91a5aa")
const ACCENT := Color("#91e5d3")
const GREEN := Color("#a4e5a7")
const SURFACE := Color("#18252b")
const LINE := Color("#344248")
const BG := Color("#0b1317")

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
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	return box

static func row(parent: Control, gap := 10) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	return box

static func inset(parent: Control, x: int, y: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left","right"]: m.add_theme_constant_override("margin_"+side, x)
	for side in ["top","bottom"]: m.add_theme_constant_override("margin_"+side, y)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(m)
	return m

static func glass_panel(parent: Control, fill: Color, radius := 20) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(panel)
	var surface := ColorRect.new()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://glass.gdshader")
	glass.set_shader_parameter("tint", Color(fill,0.72))
	glass.set_shader_parameter("radius", float(radius))
	surface.material = glass
	panel.add_child(surface)
	return panel

static func card(parent: Control, fill := SURFACE, x := 14, y := 10) -> VBoxContainer:
	var panel := glass_panel(parent, fill)
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

static func button(parent: Control, title: String, action: Callable, variant := "normal", symbol := "", icon_only := false) -> Button:
	var b := Button.new()
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	var primary := variant == "primary"
	var quiet := variant == "quiet"
	var fill := ACCENT if primary else (Color.TRANSPARENT if quiet else SURFACE)
	var ink := Color("#102b29") if primary else (ACCENT if quiet else INK)
	b.custom_minimum_size.y = 48
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
	if not symbol.is_empty(): icon(h, symbol, ink, 23 if icon_only else 17)
	if icon_only: b.tooltip_text = title
	else: label(h, title, 14, ink, 630)
	b.custom_minimum_size.x = maxf(48, h.get_combined_minimum_size().x + 12)
	b.pressed.connect(action)
	return b

static func field(parent: Control, hint: String, secret := false) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = hint
	f.secret = secret
	f.custom_minimum_size.y = 48
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

static func divider(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 1
	rule.color = Color(LINE, .65)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)

# The whole row is one button. Let layout containers calculate its minimum height.
static func list_row(parent: Control, title: String, action: Callable) -> HBoxContainer:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(holder)
	if action.is_valid():
		var target := button(holder, title, action, "quiet", "", true)
		target.tooltip_text = ""
	var contents := row(inset(holder, 4, 5), 10)
	contents.custom_minimum_size.y = 38
	contents.get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return contents
