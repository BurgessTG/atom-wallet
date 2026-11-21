extends Control

# One 24-unit stroke set. Every glyph draws with the same 1.8-unit line.
var symbol := ""
var ink := Color.WHITE
var weight := 1.8

func _draw() -> void:
	var s := minf(size.x, size.y) / 24.0
	draw_set_transform((size - Vector2(24, 24) * s) * 0.5, 0, Vector2.ONE * s)
	match symbol:
		"atom", "mark":
			for tilt in [0.35, 1.4, 2.45]: ellipse(Vector2(12,12), 10.5, 3.6, tilt)
			draw_circle(Vector2(12,12), 2.4, ink)
		"plane": line([2,10,22,3,16,21,11,15,18,7,9,13,2,10])
		"qr":
			for pos in [Vector2(3,3),Vector2(14,3),Vector2(3,14)]:
				draw_rect(Rect2(pos,Vector2(7,7)),ink,false,weight,true)
				draw_rect(Rect2(pos+Vector2(2.5,2.5),Vector2(2,2)),ink)
			line([14,14,17,14,17,18,21,18,21,21]); line([14,18,14,21,17,21]); line([20,14,21,14])
		"scan":
			line([4,8,4,4,8,4]); line([16,4,20,4,20,8]); line([20,16,20,20,16,20]); line([8,20,4,20,4,16]); line([7,12,17,12])
		"explore":
			draw_circle(Vector2(12,12),9,ink,false,weight,true)
			line([16.5,7.5,13.5,13.5,7.5,16.5,10.5,10.5,16.5,7.5])
		"globe":
			draw_circle(Vector2(12,12),9,ink,false,weight,true)
			line([3,12,21,12]); ellipse(Vector2(12,12), 9, 4, PI/2)
		"close": line([6,6,18,18]); line([18,6,6,18])
		"refresh": draw_arc(Vector2(12,12),8,-.6,4.5,32,ink,weight,true); line([13,3,19,4,18,10])
		"send": line([5,19,19,5]); line([8,5,19,5,19,16])
		"receive": line([19,5,5,19]); line([5,8,5,19,16,19])
		"wallet":
			line([3,7,3,19,21,19,21,7,3,7,15,3,17,7]); line([21,11,16,11,16,15,21,15])
		"activity":
			draw_arc(Vector2(12,12), 8.7, -2.7, 2.9, 40, ink, weight, true)
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
			line([5,11,19,11,19,21,5,21,5,11]); draw_arc(Vector2(12,10),4.5,PI,TAU,24,ink,weight,true)
		"back": line([15,5,8,12,15,19])
		"next": line([9,6,15,12,9,18])
		"down": line([6,9,12,15,18,9])
		"copy":
			line([8,8,20,8,20,21,8,21,8,8]); line([5,16,3,16,3,3,15,3,15,5])
		"contracts":
			line([5,3,15,3,19,7,19,21,5,21,5,3]); line([14,3,14,8,19,8]); line([10,11,8,14,10,17]); line([14,11,16,14,14,17])
		"code": line([8,7,3,12,8,17]); line([16,7,21,12,16,17]); line([14,4,10,20])
		"shield": line([12,2,20,5,20,12,17,17,12,21,7,17,4,12,4,5,12,2])
		"check": line([4,12,9,17,20,6])
		"eye", "eyeoff":
			ellipse(Vector2(12,12), 10, 6, 0)
			draw_circle(Vector2(12,12), 3, ink, false, weight, true)
			if symbol == "eyeoff": line([4,3,20,21])
		"gear":
			draw_circle(Vector2(12,12), 3.2, ink, false, weight, true)
			var teeth := PackedVector2Array()
			for i in 17:
				var a := TAU * i / 16.0
				var rr := 9.2 if i % 2 == 0 else 7.2
				teeth.append(Vector2(12,12) + Vector2.from_angle(a) * rr)
			draw_polyline(teeth, ink, weight, true)
		"key":
			draw_circle(Vector2(8,15), 4, ink, false, weight, true); line([11,12,20,3]); line([17,6,20,9]); line([15,8,17,10])
		"finger":
			draw_arc(Vector2(12,13), 8, PI*1.1, PI*1.9, 20, ink, weight, true)
			draw_arc(Vector2(12,13), 5, PI*1.05, TAU+.4, 24, ink, weight, true)
			draw_arc(Vector2(12,13), 2, PI, TAU+.9, 16, ink, weight, true)
			line([12,13,12,20])
		"cpu":
			line([6,6,18,6,18,18,6,18,6,6]); line([10,10,14,10,14,14,10,14,10,10])
			for v in [9,15]:
				line([v,2,v,6]); line([v,18,v,22]); line([2,v,6,v]); line([18,v,22,v])
		"share":
			draw_circle(Vector2(18,5), 2.6, ink, false, weight, true)
			draw_circle(Vector2(6,12), 2.6, ink, false, weight, true)
			draw_circle(Vector2(18,19), 2.6, ink, false, weight, true)
			line([8.3,10.7,15.7,6.3]); line([8.3,13.3,15.7,17.7])
		"trash": line([4,6,20,6]); line([9,6,9,3,15,3,15,6]); line([6,6,7,21,17,21,18,6])
		"info": draw_circle(Vector2(12,12),9,ink,false,weight,true); line([12,11,12,17]); draw_circle(Vector2(12,7.5),1.1,ink)
		"faucet": line([4,8,14,8,14,12]); line([4,5,4,11]); line([14,10,18,10,18,13]); line([18,16,17,18,18,20,19,18,18,16])
		"link": line([10,14,14,10]); draw_arc(Vector2(7.5,16.5),4,PI*.25,PI*1.25,16,ink,weight,true); draw_arc(Vector2(16.5,7.5),4,PI*1.25,PI*2.25,16,ink,weight,true)
		"plus": line([12,5,12,19]); line([5,12,19,12])
		"chain": line([7,12,17,12]); draw_circle(Vector2(5,12),2.5,ink,false,weight,true); draw_circle(Vector2(19,12),2.5,ink,false,weight,true); draw_circle(Vector2(12,5),2.5,ink,false,weight,true); line([12,7.5,12,12])
		"bolt": line([13,2,5,14,12,14,11,22,19,10,12,10,13,2])

func line(coords: Array) -> void:
	var pts := PackedVector2Array()
	for i in range(0, coords.size(), 2): pts.append(Vector2(coords[i], coords[i+1]))
	draw_polyline(pts, ink, weight, true)

func ellipse(center: Vector2, rx: float, ry: float, tilt: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry).rotated(tilt))
	draw_polyline(pts, ink, weight, true)
