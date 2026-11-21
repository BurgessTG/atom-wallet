extends Control

var symbol := ""
var ink := Color.WHITE

func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	draw_set_transform((size - Vector2(24, 24) * s) * 0.5, 0, Vector2.ONE * s)
	match symbol:
		"mark":
			for v in [[2,16,9,4,13,4,6,16], [8,20,17,4,21,4,12,20], [15,20,21,10,24,10,18,20]]:
				var poly := PackedVector2Array()
				for i in range(0, v.size(), 2): poly.append(Vector2(v[i], v[i+1]))
				draw_colored_polygon(poly, ink)
		"plane": line([2,10,22,3,16,21,11,15,18,7,9,13,2,10])
		"qr":
			for pos in [Vector2(3,3),Vector2(14,3),Vector2(3,14)]:
				draw_rect(Rect2(pos,Vector2(7,7)),ink,false,1.8,true)
				draw_rect(Rect2(pos+Vector2(2.5,2.5),Vector2(2,2)),ink)
			line([14,14,17,14,17,18,21,18,21,21]); line([14,18,14,21,17,21]); line([20,14,21,14])
		"explore":
			draw_circle(Vector2(12,12),9,ink,false,1.7,true)
			line([16.5,7.5,13.5,13.5,7.5,16.5,10.5,10.5,16.5,7.5])
		"close": line([6,6,18,18]); line([18,6,6,18])
		"refresh": draw_arc(Vector2(12,12),8,-.6,4.5,32,ink,1.8,true); line([13,3,19,4,18,10])
		"send", "receive":
			if symbol == "send":
				line([5,19,19,5]); line([8,5,19,5,19,16])
			else:
				line([19,5,5,19]); line([5,8,5,19,16,19])
		"wallet":
			line([3,7,3,19,21,19,21,7,3,7,15,3,17,7]); line([21,11,16,11,16,15,21,15])
		"activity":
			draw_arc(Vector2(12,12), 8.7, -2.7, 2.9, 40, ink, 1.7, true)
			line([12,6,12,12,16,14]); line([2,8,5,8,5,4])
		"dust":
			line([12,2,18,11,19,14,18,18,15,21,10,21,6,19,5,15,6,11,12,2])
		"night":
			var pts := PackedVector2Array()
			for i in range(31):
				var angle := deg_to_rad(40.0 + (235.0 * i / 30))
				pts.append(Vector2(12,12) + Vector2.from_angle(angle)*9)
			pts.append_array(PackedVector2Array([Vector2(10,6),Vector2(9,10),Vector2(10,14),Vector2(13,17),Vector2(17,18)]))
			draw_colored_polygon(pts, ink)
		"lock":
			line([5,11,19,11,19,21,5,21,5,11]); draw_arc(Vector2(12,10),4.5,PI,TAU,24,ink,1.7,true)
		"back": line([15,5,8,12,15,19])
		"next": line([9,6,15,12,9,18])
		"copy":
			line([8,8,20,8,20,21,8,21,8,8]); line([5,16,3,16,3,3,15,3,15,5])
		"contracts":
			line([5,3,15,3,19,7,19,21,5,21,5,3]); line([14,3,14,8,19,8]); line([10,11,8,14,10,17]); line([14,11,16,14,14,17])
		"shield": line([12,2,20,5,20,12,17,17,12,21,7,17,4,12,4,5,12,2])
		"check": line([4,12,9,17,20,6])

func line(coords: Array) -> void:
	var pts := PackedVector2Array()
	for i in range(0, coords.size(), 2): pts.append(Vector2(coords[i], coords[i+1]))
	draw_polyline(pts, ink, 1.8, true)
