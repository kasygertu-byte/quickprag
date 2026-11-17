extends Control
## Breach minigame: trace a path from START to the CORE node through the
## grid before time runs out. Optional AMP / LEECH nodes on the path add
## bonuses. Combat keeps running while you hack.

signal finished(success: bool, amp: int, leech: int)

const COLS := 6
const ROWS := 6
const CELL := 52.0
const PAD := 18.0
const HEADER := 64.0
const FOOTER := 64.0

const C_BG := Color(0.03, 0.05, 0.09, 0.92)
const C_EDGE := Color(1.0, 0.31, 0.85)
const C_CELL := Color(0.09, 0.13, 0.2)
const C_PATH := Color(0.25, 0.88, 1.0)
const C_TEXT := Color(0.85, 0.9, 1.0)
const C_DIM := Color(0.55, 0.62, 0.75)
const NODE_COLORS := {
	"in": Color(0.25, 0.88, 1.0),
	"core": Color(0.35, 1.0, 0.55),
	"AMP": Color(1.0, 0.72, 0.28),
	"LEECH": Color(1.0, 0.31, 0.85),
}
const TIME_LIMIT := 7.0

var active := false
var target: Enemy = null
var blocked := {}        # Vector2i -> true
var bonus := {}          # Vector2i -> "AMP" / "LEECH"
var path: Array[Vector2i] = []
var start := Vector2i.ZERO
var goal := Vector2i.ZERO
var time_left := 0.0
var shake := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(COLS * CELL + PAD * 2.0, ROWS * CELL + PAD + HEADER + FOOTER)
	visible = false


func begin(t: Enemy) -> void:
	target = t
	_generate()
	time_left = TIME_LIMIT
	active = true
	visible = true
	queue_redraw()


func cancel() -> void:
	if active:
		_finish(false)


func _generate() -> void:
	for attempt in 100:
		blocked.clear()
		bonus.clear()
		start = Vector2i(0, randi() % ROWS)
		goal = Vector2i(COLS - 1, randi() % ROWS)
		var n_block := 8 + randi() % 4
		while blocked.size() < n_block:
			var c := Vector2i(randi() % COLS, randi() % ROWS)
			if c != start and c != goal:
				blocked[c] = true
		if not _reachable(start, goal):
			continue
		var free: Array[Vector2i] = []
		for x in COLS:
			for y in ROWS:
				var c := Vector2i(x, y)
				if not blocked.has(c) and c != start and c != goal and _reachable(start, c):
					free.append(c)
		if free.size() < 2:
			continue
		free.shuffle()
		bonus[free[0]] = "AMP"
		bonus[free[1]] = "LEECH"
		break
	path = [start]


func _reachable(a: Vector2i, b: Vector2i) -> bool:
	var seen := {a: true}
	var frontier: Array[Vector2i] = [a]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		if c == b:
			return true
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if _in_bounds(n) and not blocked.has(n) and not seen.has(n):
				seen[n] = true
				frontier.append(n)
	return false


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func _process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(target) or target.dead:
		_finish(false, true)
		return
	time_left -= delta
	shake = maxf(shake - delta, 0.0)
	if time_left <= 0.0:
		_finish(false)
		return
	if Input.is_action_just_pressed("grid_up"):
		_try_move(Vector2i.UP)
	elif Input.is_action_just_pressed("grid_down"):
		_try_move(Vector2i.DOWN)
	elif Input.is_action_just_pressed("grid_left"):
		_try_move(Vector2i.LEFT)
	elif Input.is_action_just_pressed("grid_right"):
		_try_move(Vector2i.RIGHT)
	queue_redraw()


func _try_move(d: Vector2i) -> void:
	var cur: Vector2i = path[-1]
	var nxt := cur + d
	if path.size() >= 2 and nxt == path[-2]:
		path.pop_back()            # step back = undo
		return
	if not _in_bounds(nxt) or blocked.has(nxt) or path.has(nxt):
		shake = 0.15
		return
	path.append(nxt)
	if nxt == goal:
		_finish(true)


func _finish(success: bool, silent := false) -> void:
	active = false
	visible = false
	var amp := 0
	var leech := 0
	if success:
		for c in path:
			if bonus.get(c, "") == "AMP":
				amp += 1
			elif bonus.get(c, "") == "LEECH":
				leech += 1
	target = null
	if silent:
		finished.emit(false, -1, -1)
	else:
		finished.emit(success, amp, leech)


func _cell_rect(c: Vector2i) -> Rect2:
	var off := Vector2(PAD, HEADER)
	if shake > 0.0:
		off.x += sin(shake * 120.0) * 4.0
	return Rect2(off + Vector2(c.x, c.y) * CELL, Vector2(CELL, CELL)).grow(-3.0)


func _text(pos: Vector2, t: String, sz: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.8))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw() -> void:
	if not active:
		return
	var t := Time.get_ticks_msec() * 0.001
	# Panel with a cut top-left corner.
	var cut := 14.0
	var panel := PackedVector2Array([Vector2(cut, 0), Vector2(size.x, 0), size, Vector2(0, size.y), Vector2(0, cut)])
	draw_colored_polygon(panel, C_BG)
	var outline := panel.duplicate()
	outline.append(panel[0])
	draw_polyline(outline, Color(C_EDGE, 0.85), 2.0, true)

	# Header
	Icons.draw(self, "lock", Vector2(PAD + 9, 24), 9.0, C_EDGE)
	_text(Vector2(PAD + 26, 30), "BREACH", 18, C_EDGE)
	var tname := target.display_name if is_instance_valid(target) else ""
	_text(Vector2(PAD + 108, 30), tname, 14, C_DIM)
	var secs := "%.1fs" % maxf(time_left, 0.0)
	var font := ThemeDB.fallback_font
	var sw := font.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var low := time_left < TIME_LIMIT * 0.3
	_text(Vector2(size.x - PAD - sw, 30), secs, 16, Color(1, 0.35, 0.35) if low else C_TEXT)
	var frac := clampf(time_left / TIME_LIMIT, 0.0, 1.0)
	var bar := Rect2(PAD, 42, size.x - PAD * 2.0, 5)
	draw_rect(bar, Color(1, 1, 1, 0.08))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(1, 0.35, 0.35) if low else C_EDGE)

	# Cells
	for x in COLS:
		for y in ROWS:
			var c := Vector2i(x, y)
			var r := _cell_rect(c)
			if blocked.has(c):
				draw_rect(r, Color(0.16, 0.04, 0.07))
				draw_rect(r, Color(0.55, 0.12, 0.2, 0.6), false, 1.0)
				Icons.draw(self, "lock", r.get_center(), r.size.x * 0.22, Color(0.75, 0.2, 0.28))
				continue
			var on_path := path.has(c)
			draw_rect(r, Color(0.1, 0.3, 0.4) if on_path else C_CELL)
			draw_rect(r, Color(0.35, 0.55, 0.8, 0.35), false, 1.0)
			var id := ""
			if c == start:
				id = "in"
			elif c == goal:
				id = "core"
			elif bonus.has(c):
				id = bonus[c]
			if id == "":
				continue
			var col: Color = NODE_COLORS[id]
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			if id == "core":
				draw_rect(r.grow(-2.0), Color(col, 0.12 + 0.12 * pulse))
			draw_rect(r, col, false, 2.0)
			Icons.draw(self, id.to_lower(), r.get_center(), r.size.x * 0.28, col)

	# Path trace: soft glow + bright core line.
	if path.size() > 1:
		var pts := PackedVector2Array()
		for c in path:
			pts.append(_cell_rect(c).get_center())
		draw_polyline(pts, Color(C_PATH, 0.25), 10.0, true)
		draw_polyline(pts, C_PATH, 3.0, true)
	var head := _cell_rect(path[-1])
	draw_rect(head.grow(3.0), Color(1, 1, 1, 0.9), false, 2.5)
	draw_circle(head.get_center(), 4.0, Color.WHITE)

	# Legend
	var ly := HEADER + ROWS * CELL + 22.0
	var legend := [["in", "START"], ["core", "TARGET (finish)"], ["AMP", "+4s ARMOR OFF"], ["LEECH", "+3 BANDWIDTH"]]
	for i in legend.size():
		var e: Array = legend[i]
		var p := Vector2(PAD + (i % 2) * 160.0, ly + (i / 2) * 20.0)
		var col: Color = NODE_COLORS[e[0]]
		Icons.draw(self, String(e[0]).to_lower(), p + Vector2(7, -4), 7.0, col)
		_text(p + Vector2(20, 0), e[1], 12, C_DIM)
	_text(Vector2(PAD, ly + 46), "WASD / ARROWS trace   STEP BACK undo   Q abort", 11, Color(C_DIM, 0.8))
