extends Node

# A finger stays a possible tap until it crosses the system's scroll threshold.
# Waiting to dispatch the tap lets a drag begin on a field or a button.
var area: ScrollContainer
var finger := -1
var origin := Vector2.ZERO
var start_offset := 0
var dragging := false
var scrollable := false
var velocity := 0.0
var last_y := 0.0
var last_time := 0
var gesture_area: ScrollContainer

func _ready() -> void:
	Input.emulate_mouse_from_touch = false
	set_process(false)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if finger != -1: return
			finger = event.index
			origin = event.position
			gesture_area = area
			dragging = false
			scrollable = is_instance_valid(area) and area.get_global_rect().has_point(origin)
			start_offset = area.scroll_vertical if scrollable else 0
			last_y = origin.y
			last_time = Time.get_ticks_msec()
			velocity = 0.0
			set_process(false)
		elif event.index == finger:
			finger = -1
			var moved := origin.distance_to(event.position) > 8.0
			if not event.canceled and not dragging and not moved and gesture_area == area:
				_tap(event.position)
			elif dragging and scrollable and gesture_area == area and Time.get_ticks_msec()-last_time < 110:
				set_process(absf(velocity) > 40)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == finger:
		if absf(event.position.y - origin.y) > 8: dragging = true
		if dragging and scrollable and is_instance_valid(gesture_area) and area == gesture_area:
			area.scroll_vertical = roundi(start_offset + origin.y - event.position.y)
			var now := Time.get_ticks_msec()
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
