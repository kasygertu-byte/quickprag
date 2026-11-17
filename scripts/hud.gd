extends CanvasLayer
## On-screen HUD, drawn with vector shapes on one full-screen canvas:
## vitals, weapon, wave, target + quickhack deck, scan overlay, toasts,
## controls overlay, breach grid and game-over screen.

const HackGridScript := preload("res://scripts/hack_grid.gd")

# Palette
const C_PANEL := Color(0.03, 0.05, 0.09, 0.78)
const C_EDGE := Color(0.4, 0.75, 1.0, 0.35)
const C_TEXT := Color(0.9, 0.94, 1.0)
const C_DIM := Color(0.55, 0.62, 0.75)
const C_CYAN := Color(0.25, 0.88, 1.0)
const C_MAGENTA := Color(1.0, 0.31, 0.85)
const C_AMBER := Color(1.0, 0.72, 0.28)
const C_RED := Color(1.0, 0.3, 0.3)
const C_GREEN := Color(0.35, 1.0, 0.55)
const MARGIN := 24.0

var player: Node   # player.gd instance, set by main.gd

var canvas: Control
var grid: Control
var font: Font

var wave := 0
var hostiles := 0
var hit_timer := 0.0
var hit_armored := false
var damage_flash := 0.0
var message := ""
var message_timer := 0.0
var message_duration := 1.0
var scanning := false
var help_timer := 10.0      # controls overlay shows for the first seconds
var help_pinned := false
var game_over := false
var final_wave := 0
var final_kills := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_hud)
	add_child(canvas)

	grid = HackGridScript.new()
	add_child(grid)
	grid.finished.connect(_on_grid_finished)


# ---------------------------------------------------------------- API used by player / main

func show_hitmarker(armored: bool) -> void:
	hit_timer = 0.12
	hit_armored = armored


func flash_damage() -> void:
	damage_flash = 1.0


func show_message(text: String, duration: float) -> void:
	message = text
	message_timer = duration
	message_duration = duration


func set_wave(w: int, alive: int) -> void:
	wave = w
	hostiles = alive


func set_scan(on: bool) -> void:
	scanning = on


func start_breach(target: Enemy) -> void:
	grid.begin(target)


func cancel_breach() -> void:
	grid.cancel()


func _on_grid_finished(success: bool, amp: int, leech: int) -> void:
	player.on_breach_finished(success, amp, leech)


func show_game_over(w: int, kills: int) -> void:
	game_over = true
	final_wave = w
	final_kills = kills
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	if game_over:
		if Input.is_action_just_pressed("restart"):
			get_tree().paused = false
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		canvas.queue_redraw()
		return
	if Input.is_action_just_pressed("help"):
		help_pinned = not help_pinned
		help_timer = 0.0
	hit_timer = maxf(hit_timer - real_dt, 0.0)
	damage_flash = maxf(damage_flash - real_dt * 2.5, 0.0)
	message_timer -= real_dt
	help_timer = maxf(help_timer - real_dt, 0.0)

	var vs := canvas.size
	grid.position = Vector2(vs.x * 0.5 + 70.0, vs.y * 0.5 - grid.size.y * 0.5)
	canvas.queue_redraw()


# ---------------------------------------------------------------- drawing helpers

func _text(pos: Vector2, t: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	canvas.draw_string_outline(font, pos, t, align, width, sz, 4, Color(0, 0, 0, 0.75 * col.a))
	canvas.draw_string(font, pos, t, align, width, sz, col)


func _text_w(t: String, sz: int) -> float:
	return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x


## Panel with a cut corner and a coloured accent strip on the left.
func _panel(r: Rect2, accent: Color, alpha := 1.0) -> void:
	var cut := 10.0
	var pts := PackedVector2Array([
		r.position + Vector2(cut, 0), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y - cut), Vector2(r.end.x - cut, r.end.y),
		Vector2(r.position.x, r.end.y), r.position + Vector2(0, cut)])
	canvas.draw_colored_polygon(pts, Color(C_PANEL, C_PANEL.a * alpha))
	var outline := pts.duplicate()
	outline.append(pts[0])
	canvas.draw_polyline(outline, Color(C_EDGE, C_EDGE.a * alpha), 1.0, true)
	canvas.draw_rect(Rect2(r.position + Vector2(0, cut), Vector2(3, r.size.y - cut)), Color(accent, alpha))


## Bar split into segments; `frac` 0..1.
func _bar(r: Rect2, frac: float, col: Color, segments: int, alpha := 1.0) -> void:
	var gap := 2.0
	var w := (r.size.x - gap * (segments - 1)) / segments
	for i in segments:
		var sr := Rect2(r.position.x + i * (w + gap), r.position.y, w, r.size.y)
		canvas.draw_rect(sr, Color(1, 1, 1, 0.07 * alpha))
		var fill := clampf(frac * segments - i, 0.0, 1.0)
		if fill > 0.0:
			var c := col if fill >= 1.0 else col.darkened(0.45)
			canvas.draw_rect(Rect2(sr.position, Vector2(sr.size.x * fill, sr.size.y)), Color(c, alpha))


# ---------------------------------------------------------------- main draw

func _draw_hud() -> void:
	var vs := canvas.size
	if scanning:
		_draw_scan_overlay(vs)
	if damage_flash > 0.0:
		_draw_damage(vs)
	if game_over:
		_draw_game_over(vs)
		return
	_draw_crosshair(vs)
	_draw_wave(vs)
	_draw_vitals(vs)
	_draw_weapon(vs)
	if not player.breaching:
		_draw_hack_deck(vs)
	_draw_message(vs)
	_draw_help(vs)


func _draw_scan_overlay(vs: Vector2) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.45, 1.0, 0.1))
	# Corner brackets framing the screen.
	var m := 40.0
	var l := 70.0
	var c := Color(C_CYAN, 0.7)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := Vector2(lerpf(m, vs.x - m, corner.x), lerpf(m, vs.y - m, corner.y))
		var dx := l if corner.x == 0 else -l
		var dy := l if corner.y == 0 else -l
		canvas.draw_line(p, p + Vector2(dx, 0), c, 2.0)
		canvas.draw_line(p, p + Vector2(0, dy), c, 2.0)
	var t := "SCAN  //  TIME x0.25  //  1-4 UPLOAD  //  TAB EXIT"
	var w := _text_w(t, 13) + 28.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, 74, w, 26)
	_panel(r, C_CYAN)
	_text(r.position + Vector2(14, 18), t, 13, C_CYAN)


func _draw_damage(vs: Vector2) -> void:
	for i in 8:
		var a := damage_flash * 0.09 * (1.0 - i / 8.0)
		canvas.draw_rect(Rect2(Vector2(i, i) * 10.0, vs - Vector2(i, i) * 20.0), Color(1, 0.1, 0.1, a), false, 10.0)


func _draw_crosshair(vs: Vector2) -> void:
	var c := vs * 0.5
	var target: Enemy = player.current_target
	var col := Color(1, 1, 1, 0.9)
	if target != null:
		col = C_AMBER if target.breached else C_RED
	var gap := 5.0 if player.aiming else 9.0
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		canvas.draw_line(c + d * gap, c + d * (gap + 7.0), Color(0, 0, 0, 0.5), 4.0)
		canvas.draw_line(c + d * gap, c + d * (gap + 7.0), col, 2.0)
	canvas.draw_circle(c, 1.6, col)

	if target != null:
		# Lock-on brackets + breach prompt.
		var b := 22.0
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var p: Vector2 = c + corner * b
			canvas.draw_line(p, p - Vector2(corner.x * 7.0, 0), col, 2.0)
			canvas.draw_line(p, p - Vector2(0, corner.y * 7.0), col, 2.0)
		var in_range: bool = player.global_position.distance_to(target.global_position) <= player.BREACH_RANGE
		if not target.breached and in_range:
			_key_hint(c + Vector2(0, 46), "Q", "BREACH", C_MAGENTA)
		elif target.breached:
			_key_hint(c + Vector2(0, 46), "", "ARMOR OFFLINE %.0fs" % target.breach_timer, C_AMBER)

	if hit_timer > 0.0:
		var hc := Color(0.6, 0.8, 1.0) if hit_armored else C_AMBER
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			canvas.draw_line(c + d * 7.0, c + d * 14.0, hc, 2.5)


## Small centred chip: [KEY] LABEL
func _key_hint(center: Vector2, key: String, label: String, col: Color) -> void:
	var kw := 0.0 if key == "" else 22.0
	var w := kw + _text_w(label, 12) + 16.0
	var r := Rect2(center.x - w * 0.5, center.y - 10, w, 20)
	canvas.draw_rect(r, Color(0, 0, 0, 0.55))
	var x := r.position.x + 6.0
	if key != "":
		canvas.draw_rect(Rect2(x, r.position.y + 3, 16, 14), col)
		_text(Vector2(x, r.position.y + 15), key, 11, Color(0, 0, 0), HORIZONTAL_ALIGNMENT_CENTER, 16)
		x += kw
	_text(Vector2(x, r.position.y + 15), label, 12, col)


func _draw_wave(vs: Vector2) -> void:
	if wave == 0:
		return
	var r := Rect2(vs.x * 0.5 - 130, 18, 260, 42)
	_panel(r, C_CYAN)
	_text(r.position + Vector2(16, 28), "WAVE", 12, C_DIM)
	_text(r.position + Vector2(56, 29), str(wave), 22, C_TEXT)
	var ht := "%d HOSTILES" % hostiles
	canvas.draw_circle(Vector2(r.end.x - 24 - _text_w(ht, 13), r.position.y + 23), 4.0, C_RED)
	_text(Vector2(r.end.x - 14 - _text_w(ht, 13), r.position.y + 28), ht, 13, C_TEXT)


func _draw_vitals(vs: Vector2) -> void:
	var r := Rect2(MARGIN, vs.y - MARGIN - 96, 360, 96)
	_panel(r, C_CYAN)
	var x := r.position.x + 18
	var y := r.position.y + 26
	# Integrity
	var hp_frac: float = player.health / player.max_health
	var hp_col := C_CYAN if hp_frac > 0.3 else C_RED
	Icons.draw(canvas, "health", Vector2(x + 6, y - 5), 6.0, hp_col)
	_text(Vector2(x + 20, y), "INTEGRITY", 12, C_DIM)
	_text(Vector2(r.end.x - 18 - 80, y), str(int(ceil(player.health))), 16, hp_col, HORIZONTAL_ALIGNMENT_RIGHT, 80)
	_bar(Rect2(x, y + 8, r.size.x - 36, 9), hp_frac, hp_col, 20)
	# Bandwidth
	y += 42
	var bw: float = player.bandwidth
	var bw_max: float = player.MAX_BANDWIDTH
	Icons.draw(canvas, "bandwidth", Vector2(x + 6, y - 5), 6.0, C_MAGENTA)
	_text(Vector2(x + 20, y), "BANDWIDTH", 12, C_DIM)
	_text(Vector2(r.end.x - 18 - 80, y), "%d / %d" % [int(bw), int(bw_max)], 16, C_MAGENTA, HORIZONTAL_ALIGNMENT_RIGHT, 80)
	_bar(Rect2(x, y + 8, r.size.x - 36, 9), bw / bw_max, C_MAGENTA, int(bw_max))


func _draw_weapon(vs: Vector2) -> void:
	var r := Rect2(vs.x - MARGIN - 220, vs.y - MARGIN - 96, 220, 96)
	_panel(r, C_CYAN)
	_text(r.position + Vector2(18, 24), "PULSE RIFLE", 12, C_DIM)
	if player.reloading:
		_text(r.position + Vector2(18, 60), "RELOADING", 22, C_AMBER)
		var f: float = 1.0 - player.reload_timer / player.RELOAD_TIME
		_bar(Rect2(r.position.x + 18, r.position.y + 72, r.size.x - 36, 6), f, C_AMBER, 1)
	else:
		var ammo: int = player.ammo
		var low := ammo <= int(player.MAG_SIZE * 0.25)
		var at := str(ammo)
		_text(r.position + Vector2(18, 68), at, 42, C_RED if low else C_TEXT)
		_text(r.position + Vector2(26 + _text_w(at, 42), 68), "/ %d" % player.MAG_SIZE, 16, C_DIM)
		_text(Vector2(r.end.x - 18 - 60, r.position.y + 68), "R", 12, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 60)


func _draw_hack_deck(vs: Vector2) -> void:
	var w := 300.0
	var x := vs.x - MARGIN - w
	var y := vs.y * 0.5 - 170.0
	var target: Enemy = player.current_target

	# Target card
	var tr := Rect2(x, y, w, 70)
	if target == null:
		_panel(tr, C_DIM, 0.8)
		Icons.draw(canvas, "target", tr.position + Vector2(24, 35), 9.0, C_DIM)
		_text(tr.position + Vector2(44, 31), "NO TARGET", 14, C_DIM)
		_text(tr.position + Vector2(44, 50), "Aim at a machine to hack it", 12, Color(C_DIM, 0.7))
	else:
		var acc := C_AMBER if target.breached else C_RED
		_panel(tr, acc)
		_text(tr.position + Vector2(18, 24), target.display_name, 15, C_TEXT)
		var chip := "ARMOR OFFLINE" if target.breached else "ARMORED"
		var cw := _text_w(chip, 11) + 26
		var cr := Rect2(tr.end.x - 14 - cw, tr.position.y + 10, cw, 18)
		canvas.draw_rect(cr, Color(acc, 0.18))
		canvas.draw_rect(cr, acc, false, 1.0)
		Icons.draw(canvas, "shield", cr.position + Vector2(10, 9), 5.0, acc)
		_text(cr.position + Vector2(19, 13), chip, 11, acc)
		_bar(Rect2(tr.position.x + 18, tr.position.y + 34, w - 36, 7), target.health / target.max_health, acc, 1)
		if target.is_uploading():
			var h: Dictionary = target.upload_hack
			var f: float = target.upload_timer / float(h["upload"])
			Icons.draw(canvas, h["id"], tr.position + Vector2(25, 56), 6.0, C_MAGENTA)
			_text(tr.position + Vector2(38, 61), "UPLOADING " + String(h["name"]), 11, C_MAGENTA)
			_bar(Rect2(tr.position.x + 170, tr.position.y + 53, w - 188, 6), f, C_MAGENTA, 1)
		else:
			_text(tr.position + Vector2(18, 61), "%d / %d HP" % [int(ceil(target.health)), int(target.max_health)], 11, C_DIM)

	# Quickhack cards
	y += 82
	var hacks: Array = player.QUICKHACKS
	for i in hacks.size():
		var h: Dictionary = hacks[i]
		var cost: int = player.hack_cost(i, target)
		var affordable: bool = player.bandwidth >= cost
		var usable := target != null and affordable and not target.is_uploading()
		var a := 1.0 if usable else 0.45
		var r := Rect2(x, y + i * 60.0, w, 52)
		_panel(r, C_MAGENTA, a)
		# Key badge
		var kb := Rect2(r.position.x + 12, r.position.y + 14, 24, 24)
		canvas.draw_rect(kb, Color(C_MAGENTA, 0.9 * a))
		_text(Vector2(kb.position.x, kb.position.y + 18), str(i + 1), 15, Color(0, 0, 0, a), HORIZONTAL_ALIGNMENT_CENTER, 24)
		# Icon
		Icons.draw(canvas, h["id"], r.position + Vector2(60, 26), 11.0, Color(C_TEXT, a))
		# Name + description
		_text(r.position + Vector2(82, 22), h["name"], 14, Color(C_TEXT, a))
		_text(r.position + Vector2(82, 40), h["desc"], 11, Color(C_DIM, a))
		# Cost
		var cost_col := C_MAGENTA if affordable else C_RED
		var discounted := target != null and target.breached
		var cs := str(cost)
		_text(Vector2(r.end.x - 34 - 40, r.position.y + 31), cs, 18, Color(cost_col, maxf(a, 0.7)), HORIZONTAL_ALIGNMENT_RIGHT, 40)
		Icons.draw(canvas, "bandwidth", Vector2(r.end.x - 22, r.position.y + 25), 6.0, Color(cost_col, maxf(a, 0.7)))
		if discounted:
			_text(Vector2(r.end.x - 14 - 60, r.position.y + 46), "-50%", 10, Color(C_AMBER, a), HORIZONTAL_ALIGNMENT_RIGHT, 60)


func _draw_message(vs: Vector2) -> void:
	if message_timer <= 0.0 or message == "":
		return
	var a := clampf(message_timer * 3.0, 0.0, 1.0) * clampf((message_duration - message_timer) * 8.0 + 0.2, 0.0, 1.0)
	var w := _text_w(message, 20) + 48.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y * 0.27, w, 40)
	_panel(r, C_AMBER, a)
	_text(r.position + Vector2(24, 27), message, 20, Color(C_AMBER, a))


func _draw_help(vs: Vector2) -> void:
	var show := help_pinned or help_timer > 0.0
	if not show:
		_text(Vector2(MARGIN, 32), "F1  CONTROLS", 11, Color(C_DIM, 0.7))
		return
	var a := 1.0 if help_pinned else clampf(help_timer, 0.0, 1.0)
	var rows := [
		["WASD", "Move"], ["SHIFT", "Sprint"], ["SPACE", "Jump"],
		["LMB / RMB", "Fire / Aim"], ["R", "Reload"],
		["Q / MMB", "Breach target (strip armor)"],
		["TAB", "Scan mode (slow time)"], ["1 - 4", "Quickhacks"],
		["ESC", "Free mouse"], ["F1", "Toggle this panel"],
	]
	var r := Rect2(MARGIN, 18, 300, 40 + rows.size() * 20)
	_panel(r, C_CYAN, a)
	_text(r.position + Vector2(18, 24), "CONTROLS", 12, Color(C_CYAN, a))
	for i in rows.size():
		var y := r.position.y + 48 + i * 20
		_text(Vector2(r.position.x + 18, y), rows[i][0], 12, Color(C_TEXT, a))
		_text(Vector2(r.position.x + 112, y), rows[i][1], 12, Color(C_DIM, a))


func _draw_game_over(vs: Vector2) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.7))
	var r := Rect2(vs.x * 0.5 - 260, vs.y * 0.5 - 120, 520, 240)
	_panel(r, C_RED)
	_text(Vector2(r.position.x, r.position.y + 64), "SIGNAL LOST", 40, C_RED, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var half := r.size.x * 0.5
	_text(Vector2(r.position.x, r.position.y + 110), "WAVE REACHED", 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, half)
	_text(Vector2(r.position.x, r.position.y + 146), str(final_wave), 32, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, half)
	_text(Vector2(r.position.x + half, r.position.y + 110), "MACHINES DESTROYED", 12, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, half)
	_text(Vector2(r.position.x + half, r.position.y + 146), str(final_kills), 32, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, half)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.005)
	_text(Vector2(r.position.x, r.position.y + 206), "PRESS ENTER TO REDEPLOY", 14, Color(C_CYAN, pulse), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
