class_name Icons
extends RefCounted
## Vector icons drawn with CanvasItem draw calls (no image assets).
## Coordinates are in a -1..1 box, scaled by `s` (half-size) around `c`.


static func draw(ci: CanvasItem, id: String, c: Vector2, s: float, col: Color, w := 2.0) -> void:
	match id:
		"arc":       # lightning bolt
			_poly(ci, c, s, col, [Vector2(0.15, -1), Vector2(-0.55, 0.1), Vector2(-0.05, 0.1),
				Vector2(-0.2, 1), Vector2(0.55, -0.15), Vector2(0.05, -0.15)])
		"thermal":   # flame with side tongues
			_poly(ci, c, s, col, [Vector2(0, -1), Vector2(0.22, -0.42), Vector2(0.5, -0.78),
				Vector2(0.66, -0.1), Vector2(0.62, 0.5), Vector2(0.32, 0.92), Vector2(-0.32, 0.92),
				Vector2(-0.62, 0.5), Vector2(-0.64, -0.02), Vector2(-0.4, -0.5), Vector2(-0.24, -0.12),
				Vector2(-0.12, -0.6)])
			_poly(ci, c, s, Color(0, 0, 0, 0.55), [Vector2(0, 0.0), Vector2(0.3, 0.48),
				Vector2(0.18, 0.8), Vector2(-0.18, 0.8), Vector2(-0.3, 0.48)])
		"blind":     # eye with a slash
			var pts := PackedVector2Array()
			for i in 25:
				var a := TAU * i / 24.0
				pts.append(c + Vector2(cos(a) * 0.95, sin(a) * 0.5) * s)
			ci.draw_polyline(pts, col, w, true)
			ci.draw_circle(c, 0.24 * s, col)
			ci.draw_line(c + Vector2(-0.85, -0.85) * s, c + Vector2(0.85, 0.85) * s, col, w * 1.4, true)
		"turncoat":  # two opposing arrows (switch sides)
			ci.draw_line(c + Vector2(-0.85, -0.38) * s, c + Vector2(0.5, -0.38) * s, col, w * 1.3, true)
			_poly(ci, c, s, col, [Vector2(0.95, -0.38), Vector2(0.45, -0.75), Vector2(0.45, -0.01)])
			ci.draw_line(c + Vector2(0.85, 0.38) * s, c + Vector2(-0.5, 0.38) * s, col, w * 1.3, true)
			_poly(ci, c, s, col, [Vector2(-0.95, 0.38), Vector2(-0.45, 0.01), Vector2(-0.45, 0.75)])
		"amp":       # double chevron up
			_line(ci, c, s, col, w * 1.6, [Vector2(-0.7, 0.05), Vector2(0, -0.65), Vector2(0.7, 0.05)])
			_line(ci, c, s, col, w * 1.6, [Vector2(-0.7, 0.7), Vector2(0, 0), Vector2(0.7, 0.7)])
		"leech":     # droplet
			var d := PackedVector2Array([c + Vector2(0, -1) * s])
			for i in 13:
				var a := deg_to_rad(-25.0 + 230.0 * i / 12.0)
				d.append(c + (Vector2(0, 0.3) + Vector2(cos(a), sin(a)) * 0.62) * s)
			ci.draw_colored_polygon(d, col)
		"in":        # arrow entering a bracket
			ci.draw_line(c + Vector2(-0.95, 0) * s, c + Vector2(0.15, 0) * s, col, w * 1.3, true)
			_poly(ci, c, s, col, [Vector2(0.45, 0), Vector2(0.05, -0.38), Vector2(0.05, 0.38)])
			_line(ci, c, s, col, w * 1.3, [Vector2(0.35, -0.85), Vector2(0.9, -0.85), Vector2(0.9, 0.85), Vector2(0.35, 0.85)])
		"core":      # diamond with filled centre
			_line(ci, c, s, col, w * 1.3, [Vector2(0, -0.95), Vector2(0.95, 0), Vector2(0, 0.95), Vector2(-0.95, 0), Vector2(0, -0.95)])
			_poly(ci, c, s, col, [Vector2(0, -0.4), Vector2(0.4, 0), Vector2(0, 0.4), Vector2(-0.4, 0)])
		"lock":      # firewall / blocked
			ci.draw_arc(c + Vector2(0, -0.1) * s, 0.38 * s, PI, TAU, 12, col, w * 1.4, true)
			ci.draw_line(c + Vector2(-0.38, -0.1) * s, c + Vector2(-0.38, 0.05) * s, col, w * 1.4)
			ci.draw_line(c + Vector2(0.38, -0.1) * s, c + Vector2(0.38, 0.05) * s, col, w * 1.4)
			ci.draw_rect(Rect2(c + Vector2(-0.62, 0.05) * s, Vector2(1.24, 0.85) * s), col)
		"health":    # plus
			ci.draw_rect(Rect2(c + Vector2(-0.25, -0.85) * s, Vector2(0.5, 1.7) * s), col)
			ci.draw_rect(Rect2(c + Vector2(-0.85, -0.25) * s, Vector2(1.7, 0.5) * s), col)
		"bandwidth": # hexagon chip
			var h := PackedVector2Array()
			for i in 7:
				var a := TAU * i / 6.0 + PI / 6.0
				h.append(c + Vector2(cos(a), sin(a)) * 0.9 * s)
			ci.draw_polyline(h, col, w * 1.2, true)
			ci.draw_circle(c, 0.32 * s, col)
		"shield":
			_poly(ci, c, s, col, [Vector2(0, -0.95), Vector2(0.8, -0.6), Vector2(0.7, 0.2),
				Vector2(0, 0.95), Vector2(-0.7, 0.2), Vector2(-0.8, -0.6)])
		"target":    # crosshair
			ci.draw_arc(c, 0.65 * s, 0, TAU, 20, col, w, true)
			for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + v * 0.35 * s, c + v * 1.0 * s, col, w)


static func _poly(ci: CanvasItem, c: Vector2, s: float, col: Color, pts: Array) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(c + v * s)
	ci.draw_colored_polygon(p, col)


static func _line(ci: CanvasItem, c: Vector2, s: float, col: Color, w: float, pts: Array) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(c + v * s)
	ci.draw_polyline(p, col, w, true)
