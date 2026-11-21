extends RefCounted

# Atom Wallet's Moonlight design system. One accent carries brand, action and
# privacy; mint marks DUST and incoming value; everything else is ink and grays.
const Icon = preload("res://icon.gd")
const FACE = preload("res://InterVariable.ttf")
const BG := Color("#0b0b14")
const INK := Color("#f2f0fa")
const MUTED := Color("#a39fbd")
const DIM := Color("#77738f")
const ACCENT := Color("#c7bfff")
const ON_ACCENT := Color("#17132e")
const ACCENT_SOFT := Color(0.78, 0.75, 1.0, 0.13)
const MINT := Color("#9fe3c0")
const MINT_SOFT := Color(0.62, 0.89, 0.75, 0.12)
const AMBER := Color("#f2cf8f")
const DANGER := Color("#ff9e8f")
const DANGER_SOFT := Color(1.0, 0.62, 0.56, 0.12)
const SURFACE := Color("#14131f")
const RAISED := Color("#1b1a29")
const SHEET := Color("#15131f")
const LINE := Color("#272536")
# Kept for callers that still name the previous tokens.
const GREEN := MINT

static var haptic := Callable()
static var motion := 1.0
static var _fonts := {}

static func buzz(kind := "tap") -> void:
	if haptic.is_valid(): haptic.call(kind)

static func style(fill: Color, radius := 16, border := Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.set_border_width_all(width if border.a > 0 else 0)
	box.border_color = border
	box.corner_detail = 10
	box.anti_aliasing = true
	return box

static func font(weight: int) -> FontVariation:
	if _fonts.has(weight): return _fonts[weight]
	var f := FontVariation.new()
	f.base_font = FACE
	f.variation_opentype = { TextServerManager.get_primary_interface().name_to_tag("wght"): weight }
	f.opentype_features = { TextServerManager.get_primary_interface().name_to_tag("tnum"): 1 }
	_fonts[weight] = f
	return f

static func label(parent: Control, value: String, px := 14, ink := INK, weight := 500, wrap := false) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_override("font", font(weight))
	item.add_theme_font_size_override("font_size", px)
	item.add_theme_color_override("font_color", ink)
	item.add_theme_constant_override("line_spacing", 1)
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

static func inset(parent: Control, x: int, y: int, bottom := -1) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left","right"]: m.add_theme_constant_override("margin_"+side, x)
	m.add_theme_constant_override("margin_top", y)
	m.add_theme_constant_override("margin_bottom", y if bottom < 0 else bottom)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(m)
	return m

static func panel(parent: Control, fill := SURFACE, radius := 20, border := LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(fill, radius, border))
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(p)
	return p

static func card(parent: Control, fill := SURFACE, x := 16, y := 14, gap := 6) -> VBoxContainer:
	return vbox(inset(panel(parent, fill), x, y), gap)

# A grouped list. Rows added with list_row get hairlines between them.
static func list(parent: Control) -> VBoxContainer:
	var box := vbox(panel(parent, SURFACE, 20), 0)
	return box

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

static func badge(parent: Control, symbol: String, tint := ACCENT, px := 38) -> PanelContainer:
	var b := PanelContainer.new()
	b.add_theme_stylebox_override("panel", style(Color(tint, 0.13), int(px * 0.34)))
	b.custom_minimum_size = Vector2(px, px)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(c)
	icon(c, symbol, tint, int(px * 0.5))
	return b

static func pill(parent: Control, text: String, tint := ACCENT) -> PanelContainer:
	var p := PanelContainer.new()
	var box := style(Color(tint, 0.14), 99)
	box.content_margin_left = 7; box.content_margin_right = 7; box.content_margin_top = 1; box.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(p)
	label(p, text, 11, tint, 620)
	return p

static func section(parent: Control, text: String, right := "") -> HBoxContainer:
	var h := row(parent, 6)
	var title := label(h, text, 15, INK, 650)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if right: label(h, right, 12, MUTED, 520)
	return h

static func caption(parent: Control, text: String) -> Label:
	var l := label(parent, text, 12, MUTED, 560)
	return l

static func _press_feedback(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if b is BaseButton:
		b.button_down.connect(func():
			if motion > 0: b.create_tween().tween_property(b, "scale", Vector2.ONE * 0.965, 0.08 * motion)
		)
		b.button_up.connect(func():
			if motion > 0: b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.14 * motion).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			else: b.scale = Vector2.ONE
		)

# Variants: primary (accent fill), secondary (raised), soft (accent tint),
# ghost (accent text only), quiet (alias of ghost), danger (red tint).
static func button(parent: Control, title: String, action: Callable, variant := "secondary", symbol := "", icon_only := false) -> Button:
	var b := Button.new()
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	if variant == "normal": variant = "secondary"
	if variant == "quiet": variant = "ghost"
	var fill: Color = {"primary":ACCENT,"secondary":RAISED,"soft":ACCENT_SOFT,"ghost":Color.TRANSPARENT,"danger":DANGER_SOFT}.get(variant, RAISED)
	var ink: Color = {"primary":ON_ACCENT,"secondary":INK,"soft":ACCENT,"ghost":ACCENT,"danger":DANGER}.get(variant, INK)
	if icon_only and variant == "ghost": ink = MUTED
	var radius := 16
	b.custom_minimum_size.y = 50
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.accessibility_name = title
	b.focus_mode = Control.FOCUS_NONE
	var border := LINE if variant == "secondary" else Color.TRANSPARENT
	b.add_theme_stylebox_override("normal", style(fill, radius, border))
	b.add_theme_stylebox_override("hover", style(fill if variant != "ghost" else Color(1,1,1,0.04), radius, border))
	b.add_theme_stylebox_override("pressed", style(fill.lightened(0.08) if variant != "ghost" else Color(1,1,1,0.07), radius, border))
	b.add_theme_stylebox_override("disabled", style(Color(fill, fill.a * 0.45), radius, Color(border, border.a * 0.5)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(b)
	var h := row(b, 8)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not symbol.is_empty(): icon(h, symbol, ink, 22 if icon_only else 18)
	if icon_only: b.tooltip_text = title
	else: label(h, title, 15, ink, 650)
	b.custom_minimum_size.x = maxf(48, h.get_combined_minimum_size().x + 20)
	b.draw.connect(func(): h.modulate.a = 0.45 if b.disabled else 1.0)
	b.pressed.connect(func(): buzz("tap"); action.call())
	_press_feedback(b)
	return b

static func chip(parent: Control, title: String, action: Callable, selected := false, symbol := "") -> Button:
	var b := Button.new()
	b.accessibility_name = title
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fill := ACCENT_SOFT if selected else Color(1,1,1,0.05)
	var ink := ACCENT if selected else MUTED
	for s in ["normal","hover","pressed","disabled"]:
		var box := style(fill.lightened(0.05) if s == "pressed" else fill, 99, Color.TRANSPARENT if selected else LINE)
		box.content_margin_left = 14; box.content_margin_right = 14
		box.expand_margin_top = -8; box.expand_margin_bottom = -8
		b.add_theme_stylebox_override(s, box)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(b)
	var h := row(b, 6)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if symbol: icon(h, symbol, ink, 15)
	label(h, title, 13, ink, 620)
	b.custom_minimum_size.x = maxf(48, h.get_combined_minimum_size().x + 28)
	b.pressed.connect(func(): buzz("tick"); action.call())
	_press_feedback(b)
	return b

static func field(parent: Control, hint: String, secret := false) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = hint
	f.secret = secret
	f.custom_minimum_size.y = 52
	f.add_theme_font_override("font", font(500))
	f.add_theme_font_size_override("font_size", 16)
	f.add_theme_color_override("font_color", INK)
	f.add_theme_color_override("font_placeholder_color", DIM)
	f.add_theme_color_override("caret_color", ACCENT)
	f.add_theme_color_override("selection_color", Color(ACCENT, 0.3))
	for state in ["normal", "focus", "read_only"]:
		var box := style(SURFACE, 16, ACCENT if state == "focus" else LINE, 2 if state == "focus" else 1)
		box.content_margin_left = 16; box.content_margin_right = 16
		f.add_theme_stylebox_override(state, box)
	if secret:
		f.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
		f.context_menu_enabled = false
	parent.add_child(f)
	return f

static func divider(parent: Control, indent := 0) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", indent)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(m)
	var rule := ColorRect.new()
	rule.custom_minimum_size.y = 1
	rule.color = LINE
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(rule)

# The whole row is one button. Its contents sit above it and ignore input.
static func list_row(parent: Control, title: String, action: Callable, divided := true) -> HBoxContainer:
	if divided and parent.get_child_count() > 0: divider(parent, 64)
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(holder)
	if action.is_valid():
		var target := Button.new()
		target.accessibility_name = title
		target.focus_mode = Control.FOCUS_NONE
		target.mouse_filter = Control.MOUSE_FILTER_PASS
		target.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		target.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		target.add_theme_stylebox_override("pressed", style(Color(1,1,1,0.045), 14))
		target.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		target.custom_minimum_size = Vector2(48, 48)
		target.pressed.connect(func(): buzz("tap"); action.call())
		holder.add_child(target)
	var contents := row(inset(holder, 12, 11), 12)
	contents.custom_minimum_size.y = 40
	contents.get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return contents

static func text_column(parent: Control, title: String, subtitle := "", title_px := 15) -> VBoxContainer:
	var names := vbox(parent, 1)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := label(names, title, title_px, INK, 600)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	if subtitle:
		var s := label(names, subtitle, 12, MUTED, 500)
		s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		s.clip_text = true
	return names

# A two- or three-way choice with a thumb that slides to the selection before
# the change is applied.
static func segmented(parent: Control, options: Array, selected: Variant, on_change: Callable) -> PanelContainer:
	var holder := panel(parent, Color(1,1,1,0.045), 18, Color.TRANSPARENT)
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(stage)
	var thumb := Panel.new()
	thumb.add_theme_stylebox_override("panel", style(ACCENT_SOFT, 14, Color(ACCENT, 0.55)))
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(thumb)
	var h := row(stage, 0)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var buttons := []
	var has_sub := options.any(func(o): return o.size() > 2 and o[2])
	for option in options:
		var b := Button.new()
		b.accessibility_name = option[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 58 if has_sub else 48
		for s in ["normal","hover","pressed","focus"]: b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
		h.add_child(b)
		var v := vbox(b, 0)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var on: bool = option[0] == selected
		label(v, option[1], 14, INK if on else MUTED, 640).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if option.size() > 2 and option[2]:
			label(v, option[2], 11, MUTED, 500).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buttons.append(b)
		var value = option[0]
		b.pressed.connect(func():
			if value == selected: return
			buzz("tick")
			var target: Rect2 = b.get_rect().grow(-4)
			if motion > 0:
				var tw := thumb.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				tw.tween_property(thumb, "position", target.position, 0.18 * motion)
				tw.tween_property(thumb, "size", target.size, 0.18 * motion)
				tw.chain().tween_callback(on_change.bind(value))
			else: on_change.call(value)
		)
	stage.custom_minimum_size.y = 58 if has_sub else 48
	var place := func():
		var index := options.find_custom(func(o): return o[0] == selected)
		if index >= 0 and index < buttons.size():
			var r: Rect2 = buttons[index].get_rect().grow(-4)
			thumb.position = r.position; thumb.size = r.size
		thumb.visible = index >= 0
	h.sort_children.connect(place.call_deferred)
	place.call_deferred()
	return holder

class Toggle extends Control:
	var on := false
	var knob := 0.0
	func _init(value := false) -> void:
		on = value; knob = 1.0 if value else 0.0
		custom_minimum_size = Vector2(46, 28)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func set_on(value: bool) -> void:
		on = value
		create_tween().tween_property(self, "knob", 1.0 if on else 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	func _process(_d: float) -> void: queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2(0, (size.y - 28) * 0.5), Vector2(46, 28))
		var track := Color(1,1,1,0.14).lerp(Color("#c7bfff"), clampf(knob, 0, 1))
		draw_style_box(_box(track, 14), r)
		var x := lerpf(r.position.x + 14, r.end.x - 14, knob)
		draw_circle(Vector2(x, r.get_center().y), 10, Color.WHITE.lerp(Color("#17132e"), clampf(knob, 0, 1)))
	func _box(fill: Color, radius: int) -> StyleBoxFlat:
		var b := StyleBoxFlat.new(); b.bg_color = fill; b.set_corner_radius_all(radius); b.anti_aliasing = true; return b

# A progress ring. With spinning set it turns as an indeterminate spinner.
class Ring extends Control:
	var value := 0.0
	var tint := Color("#c7bfff")
	var track := Color(1,1,1,0.08)
	var width := 5.0
	var spinning := false
	var turn := 0.0
	func _init(px := 52.0) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _process(delta: float) -> void:
		if spinning:
			turn = fmod(turn + delta * 4.2, TAU)
			queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - width
		draw_arc(c, r, 0, TAU, 64, track, width, true)
		if spinning: draw_arc(c, r, turn, turn + 1.7, 32, tint, width, true)
		elif value > 0.001: draw_arc(c, r, -PI / 2, -PI / 2 + TAU * clampf(value, 0, 1), 64, tint, width, true)

# Press and hold to confirm. The fill grows under the finger with haptic ticks;
# letting go early drains it. Touch input reaches it through touch_scroll's
# "hold" group, mouse input through the button's own down and up signals.
class HoldButton extends Button:
	signal completed
	signal ticked
	var progress := 0.0
	var holding := false
	var done := false
	var duration := 0.8
	var last_tick := 0
	func _init() -> void:
		add_to_group("hold")
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size.y = 56
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for s in ["normal","hover","pressed","disabled","focus"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
		button_down.connect(begin)
		button_up.connect(release)
	func begin() -> void:
		if disabled or done: return
		holding = true
		last_tick = 0
	func release() -> void:
		holding = false
	func _process(delta: float) -> void:
		if done: return
		var before := progress
		progress = clampf(progress + (delta / duration if holding else -delta * 3.0), 0.0, 1.0)
		var step := int(progress * 4)
		if holding and step > last_tick:
			last_tick = step
			ticked.emit()
		if progress >= 1.0:
			done = true
			holding = false
			completed.emit()
		if before != progress: queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(_box(Color(0.78, 0.75, 1.0, 0.16), 18), r)
		if progress > 0.0:
			var w := maxf(36.0, size.x * progress)
			draw_style_box(_box(Color("#c7bfff"), 18), Rect2(Vector2.ZERO, Vector2(w, size.y)))
	func _box(fill: Color, radius: int) -> StyleBoxFlat:
		var b := StyleBoxFlat.new(); b.bg_color = fill; b.set_corner_radius_all(radius); b.anti_aliasing = true; b.corner_detail = 10; return b

static func hold_button(parent: Control, title: String, action: Callable, symbol := "send") -> HoldButton:
	var b := HoldButton.new()
	b.accessibility_name = title
	parent.add_child(b)
	var h := row(b, 8)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph = icon(h, symbol, ACCENT, 18)
	var text := label(h, title, 15, ACCENT, 680)
	b.ticked.connect(func(): buzz("tick"))
	b.completed.connect(func():
		text.add_theme_color_override("font_color", ON_ACCENT); glyph.ink = ON_ACCENT; glyph.queue_redraw()
		buzz("confirm"); action.call()
	)
	b.draw.connect(func():
		var over := b.progress > 0.5
		text.add_theme_color_override("font_color", ON_ACCENT if over else ACCENT)
		if glyph.ink != (ON_ACCENT if over else ACCENT): glyph.ink = ON_ACCENT if over else ACCENT; glyph.queue_redraw()
	)
	return b

# A placeholder row that pulses while data loads.
static func skeleton(parent: Control, rows := 3) -> void:
	var box := list(parent)
	for i in rows:
		if i > 0: divider(box, 64)
		var h := row(inset(box, 14, 14), 12)
		var a := Panel.new(); a.add_theme_stylebox_override("panel", style(Color(1,1,1,0.06), 12)); a.custom_minimum_size = Vector2(38, 38); h.add_child(a)
		var v := vbox(h, 7); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for w in [0.55, 0.32]:
			var bar := Panel.new(); bar.add_theme_stylebox_override("panel", style(Color(1,1,1,0.06), 6))
			bar.custom_minimum_size = Vector2(0, 10); bar.size_flags_horizontal = Control.SIZE_FILL
			var holder := HBoxContainer.new(); v.add_child(holder); holder.add_child(bar)
			bar.size_flags_stretch_ratio = w; bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var rest := Control.new(); rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rest.size_flags_stretch_ratio = 1.0 - w; holder.add_child(rest)
	if motion > 0:
		var tw := box.get_parent().create_tween().set_loops()
		tw.tween_property(box.get_parent(), "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(box.get_parent(), "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
