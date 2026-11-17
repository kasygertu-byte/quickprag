extends Control
## Breach minigame: trace a path from START to the CORE node through the
## grid before time runs out. Optional AMP / LEECH nodes on the path add
## bonuses. Combat keeps running while you hack.

signal finished(success: bool, amp: int, leech: int)

const COLS := 6
const ROWS := 6
const CELL := 46.0
const PAD := 18.0
const HEADER := 52.0
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
	size = Vector2(COLS * CELL + PAD * 2.0, ROWS * CELL + PAD * 2.0 + HEADER + 24.0)
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
	var off := Vector2(PAD, PAD + HEADER)
	if shake > 0.0:
		off.x += sin(shake * 120.0) * 4.0
	return Rect2(off + Vector2(c.x, c.y) * CELL, Vector2(CELL, CELL)).grow(-3.0)


func _draw() -> void:
	if not active:
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.3, 0.9, 0.9), false, 2.0)
	var tname := target.display_name if is_instance_valid(target) else ""
	draw_string(font, Vector2(PAD, 26), "BREACH :: " + tname, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.5, 0.95))
	# Timer bar
	var frac := clampf(time_left / TIME_LIMIT, 0.0, 1.0)
	var bar_w := size.x - PAD * 2.0
	draw_rect(Rect2(PAD, 36, bar_w, 6), Color(0.2, 0.2, 0.25))
	draw_rect(Rect2(PAD, 36, bar_w * frac, 6), Color(1.0, 0.3, 0.3) if frac < 0.3 else Color(1.0, 0.4, 0.9))

	for x in COLS:
		for y in ROWS:
			var c := Vector2i(x, y)
			var r := _cell_rect(c)
			if blocked.has(c):
				draw_rect(r, Color(0.12, 0.05, 0.08))
				draw_line(r.position, r.end, Color(0.5, 0.1, 0.15), 2.0)
				draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(0.5, 0.1, 0.15), 2.0)
				continue
			var col := Color(0.1, 0.14, 0.2)
			if path.has(c):
				col = Color(0.15, 0.4, 0.5)
			draw_rect(r, col)
			draw_rect(r, Color(0.3, 0.5, 0.7, 0.5), false, 1.0)
			var tag := ""
			var tcol := Color.WHITE
			if c == start:
				tag = "IN"
				tcol = Color(0.5, 0.9, 1.0)
			elif c == goal:
				tag = "CORE"
				tcol = Color(0.4, 1.0, 0.5)
			elif bonus.has(c):
				tag = bonus[c]
				tcol = Color(1.0, 0.85, 0.2) if tag == "AMP" else Color(0.9, 0.4, 1.0)
			if tag != "":
				draw_rect(r, tcol, false, 2.0)
				draw_string(font, r.position + Vector2(0, r.size.y * 0.5 + 5), tag, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, tcol)

	# Path trace
	for i in range(1, path.size()):
		draw_line(_cell_rect(path[i - 1]).get_center(), _cell_rect(path[i]).get_center(), Color(0.4, 1.0, 1.0), 4.0)
	var head := _cell_rect(path[-1])
	draw_rect(head.grow(2.0), Color(1, 1, 1), false, 3.0)

	var foot := PAD + HEADER + ROWS * CELL + 18
	draw_string(font, Vector2(PAD, foot), "WASD/Arrows: trace   Back-step: undo   Q: abort", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.75, 0.85))
