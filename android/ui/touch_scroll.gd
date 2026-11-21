extends Node

# A finger stays a possible tap until it crosses the system's scroll threshold.
# Waiting to dispatch the tap lets a drag begin on a field or a button.
# Controls in the "hold" group get begin/release calls instead of a tap, and a
# downward drag on a sheet's handle, or from the top of its scroll, moves the sheet.
var area: ScrollContainer
var sheet_area: ScrollContainer
var sheet_handle: Control
var sheet_drag := Callable()
var finger := -1
var origin := Vector2.ZERO
var start_offset := 0
var dragging := false
var scrollable := false
var velocity := 0.0
var last_y := 0.0
var last_time := 0
var gesture_area: ScrollContainer
var mode := ""
var hold_target: Control
var sheet_velocity := 0.0

func _ready() -> void:
	Input.emulate_mouse_from_touch = false
	set_process(false)

func _hold_at(point: Vector2) -> Control:
	for node in get_tree().get_nodes_in_group("hold"):
		if node is Control and node.is_visible_in_tree() and not node.get("disabled") and node.get_global_rect().has_point(point):
			return node
	return null

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger != -1: return
			finger = event.index
			origin = event.position
			gesture_area = area
			dragging = false
			mode = ""
			scrollable = is_instance_valid(area) and area.get_global_rect().has_point(origin)
			start_offset = area.scroll_vertical if scrollable else 0
			last_y = origin.y
			last_time = Time.get_ticks_msec()
			velocity = 0.0
			sheet_velocity = 0.0
			set_process(false)
			hold_target = _hold_at(origin)
			if hold_target: hold_target.begin()
		elif event.index == finger:
			finger = -1
			var moved := origin.distance_to(event.position) > 8.0
			if is_instance_valid(hold_target):
				hold_target.release()
				hold_target = null
			elif mode == "sheet":
				sheet_drag.call(event.position.y - origin.y, "end", sheet_velocity)
			elif not event.canceled and not dragging and not moved and gesture_area == area:
				_tap(event.position)
			elif dragging and scrollable and gesture_area == area and Time.get_ticks_msec()-last_time < 110:
				set_process(absf(velocity) > 40)
			mode = ""
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == finger:
		var dy: float = event.position.y - origin.y
		if not dragging and absf(dy) > 8:
			dragging = true
			if is_instance_valid(hold_target):
				hold_target.release()
				hold_target = null
			var on_handle := is_instance_valid(sheet_handle) and sheet_handle.get_global_rect().has_point(origin)
			var at_top := is_instance_valid(sheet_area) and area == sheet_area and area.scroll_vertical <= 0 and dy > 0
			if sheet_drag.is_valid() and (on_handle or at_top): mode = "sheet"
			else: mode = "scroll"
		var now := Time.get_ticks_msec()
		if mode == "sheet":
			sheet_velocity = lerpf(sheet_velocity, (event.position.y - last_y) * 1000.0 / maxi(1, now - last_time), .5)
			sheet_drag.call(dy, "move", sheet_velocity)
		elif dragging and scrollable and is_instance_valid(gesture_area) and area == gesture_area:
			area.scroll_vertical = roundi(start_offset - dy)
			velocity = lerpf(velocity, clampf((last_y-event.position.y)*1000/maxi(1,now-last_time),-2300,2300),.55)
		last_y = event.position.y
		last_time = now
		get_viewport().set_input_as_handled()

func _tap(at: Vector2) -> void:
	for pressed in [true,false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = at
		mouse.global_position = at
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		get_viewport().push_input(mouse, true)

func _process(delta: float) -> void:
	if not is_instance_valid(gesture_area) or gesture_area != area:
		set_process(false)
		return
	var previous := area.scroll_vertical
	area.scroll_vertical += roundi(velocity * delta)
	velocity *= exp(-6.5 * delta)
	if absf(velocity) < 40 or area.scroll_vertical == previous: set_process(false)
