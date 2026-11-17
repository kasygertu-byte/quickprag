extends CanvasLayer
## On-screen HUD: crosshair, integrity, bandwidth, ammo, quickhack list,
## scan overlay, breach grid and game-over screen.

const HackGridScript := preload("res://scripts/hack_grid.gd")

var player: Node   # player.gd instance, set by main.gd

var root: Control
var crosshair: Control
var bw_bar: Control
var hp_bar: ProgressBar
var ammo_label: Label
var wave_label: Label
var message_label: Label
var target_label: Label
var hack_labels: Array[Label] = []
var scan_tint: ColorRect
var scan_label: Label
var damage_tint: ColorRect
var help_label: Label
var game_over_panel: Control
var game_over_label: Label
var grid: Control

var hit_timer := 0.0
var hit_armored := false
var message_timer := 0.0
var game_over := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	scan_tint = _rect(Color(0.1, 0.5, 1.0, 0.13))
	scan_tint.visible = false
	damage_tint = _rect(Color(1.0, 0.0, 0.0, 0.0))

	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	root.add_child(crosshair)

	# Bottom-left: integrity + bandwidth
	var hp_title := _label("INTEGRITY", 14, Color(0.7, 0.85, 1.0))
	_place(hp_title, Control.PRESET_BOTTOM_LEFT, Vector2(30, -110))
	hp_bar = ProgressBar.new()
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(320, 14)
	hp_bar.size = Vector2(320, 14)
	hp_bar.add_theme_stylebox_override("background", _style(Color(0.1, 0.1, 0.15, 0.8)))
	hp_bar.add_theme_stylebox_override("fill", _style(Color(0.3, 0.9, 1.0)))
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(hp_bar, Control.PRESET_BOTTOM_LEFT, Vector2(30, -88))

	var bw_title := _label("BANDWIDTH", 14, Color(1.0, 0.6, 0.95))
	_place(bw_title, Control.PRESET_BOTTOM_LEFT, Vector2(30, -66))
	bw_bar = Control.new()
	bw_bar.size = Vector2(320, 14)
	bw_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bw_bar.draw.connect(_draw_bandwidth)
	_place(bw_bar, Control.PRESET_BOTTOM_LEFT, Vector2(30, -44))

	ammo_label = _label("", 30, Color(0.9, 0.95, 1.0))
	_place(ammo_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-200, -70))

	wave_label = _label("", 20, Color(0.8, 0.9, 1.0))
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.size = Vector2(400, 30)
	_place(wave_label, Control.PRESET_CENTER_TOP, Vector2(-200, 18))

	message_label = _label("", 26, Color(1.0, 0.9, 0.5))
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.size = Vector2(900, 40)
	_place(message_label, Control.PRESET_CENTER, Vector2(-450, -190))

	# Right side: target info + quickhack list
	target_label = _label("", 16, Color(1, 1, 1))
	_place(target_label, Control.PRESET_CENTER_RIGHT, Vector2(-540, -150))
	for i in 4:
		var l := _label("", 16, Color(1, 1, 1))
		_place(l, Control.PRESET_CENTER_RIGHT, Vector2(-540, -80 + i * 26))
		hack_labels.append(l)

	scan_label = _label("SCAN MODE  -  time slowed  -  [1-4] upload quickhack  -  [Tab] exit", 16, Color(0.5, 0.85, 1.0))
	scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scan_label.size = Vector2(800, 24)
	_place(scan_label, Control.PRESET_CENTER_BOTTOM, Vector2(-400, -140))
	scan_label.visible = false

	help_label = _label(
		"WASD move  Shift sprint  Space jump  LMB fire  RMB aim  R reload\n" +
		"Q / MMB breach target (grid hack: strips armor)\n" +
		"Tab scan mode  1-4 quickhacks  Esc free mouse", 13, Color(0.75, 0.8, 0.9, 0.8))
	_place(help_label, Control.PRESET_TOP_LEFT, Vector2(20, 16))

	grid = HackGridScript.new()
	root.add_child(grid)
	grid.finished.connect(_on_grid_finished)

	game_over_panel = _rect(Color(0, 0, 0, 0.7))
	game_over_panel.visible = false
	game_over_label = _label("", 30, Color(1.0, 0.4, 0.4))
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_panel.add_child(game_over_label)


# ---------------------------------------------------------------- helpers

func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Anchor a control to a screen corner/edge, then offset it in pixels.
func _place(c: Control, preset: Control.LayoutPreset, offset: Vector2) -> void:
	root.add_child(c)
	var sz := c.size
	c.set_anchors_preset(preset)
	c.position = Vector2.ZERO
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + sz.x
	c.offset_bottom = offset.y + sz.y


func _style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	return s


# ---------------------------------------------------------------- API used by player / main

func show_hitmarker(armored: bool) -> void:
	hit_timer = 0.12
	hit_armored = armored


func flash_damage() -> void:
	damage_tint.color.a = 0.35


func show_message(text: String, duration: float) -> void:
	message_label.text = text
	message_timer = duration


func set_wave(wave: int, alive: int) -> void:
	wave_label.text = "WAVE %d   -   HOSTILES %d" % [wave, alive]


func set_scan(on: bool) -> void:
	scan_tint.visible = on
	scan_label.visible = on


func start_breach(target: Enemy) -> void:
	grid.begin(target)


func cancel_breach() -> void:
	grid.cancel()


func _on_grid_finished(success: bool, amp: int, leech: int) -> void:
	player.on_breach_finished(success, amp, leech)


func show_game_over(wave: int, kills: int) -> void:
	game_over = true
	game_over_panel.visible = true
	game_over_label.text = "SIGNAL LOST\n\nReached wave %d   -   %d machines destroyed\n\nPress Enter to redeploy" % [wave, kills]
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
		return

	hit_timer = maxf(hit_timer - real_dt, 0.0)
	damage_tint.color.a = maxf(damage_tint.color.a - real_dt * 1.2, 0.0)
	message_timer -= real_dt
	message_label.modulate.a = clampf(message_timer * 2.0, 0.0, 1.0)

	var vs := root.get_viewport_rect().size
	grid.position = vs * 0.5 + Vector2(90, -grid.size.y * 0.5)

	hp_bar.max_value = player.max_health
	hp_bar.value = player.health
	if player.reloading:
		ammo_label.text = "RELOADING"
	else:
		ammo_label.text = "%d / %d" % [player.ammo, player.MAG_SIZE]

	_update_hack_panel()
	crosshair.queue_redraw()
	bw_bar.queue_redraw()


func _update_hack_panel() -> void:
	var t: Enemy = player.current_target
	if t == null:
		target_label.text = "NO TARGET"
		target_label.modulate = Color(0.6, 0.6, 0.7)
	else:
		var armor := "ARMOR OFFLINE" if t.breached else "ARMORED"
		target_label.text = "%s   %d HP   %s" % [t.display_name, int(ceil(t.health)), armor]
		target_label.modulate = Color(1.0, 0.8, 0.3) if t.breached else Color(1.0, 0.5, 0.5)
	var hacks: Array = player.QUICKHACKS
	for i in hacks.size():
		var h: Dictionary = hacks[i]
		var cost: int = player.hack_cost(i, t)
		var line := "[%d] %-14s %2d BW" % [i + 1, h["name"], cost]
		if player.scanning:
			line += "   " + str(h["desc"])
		hack_labels[i].text = line
		var usable: bool = t != null and player.bandwidth >= cost
		hack_labels[i].modulate = Color(0.75, 1.0, 0.95) if usable else Color(0.45, 0.45, 0.5)


func _draw_crosshair() -> void:
	var c := crosshair.size * 0.5
	var col := Color(1, 1, 1, 0.85)
	if player.current_target != null:
		col = Color(1.0, 0.4, 0.3)
	var gap := 4.0 if player.aiming else 8.0
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		crosshair.draw_line(c + d * gap, c + d * (gap + 8.0), col, 2.0)
	crosshair.draw_circle(c, 1.5, col)
	if hit_timer > 0.0:
		var hc := Color(0.6, 0.8, 1.0) if hit_armored else Color(1.0, 0.85, 0.2)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			crosshair.draw_line(c + d * 6.0, c + d * 13.0, hc, 2.5)


func _draw_bandwidth() -> void:
	var segs := int(player.MAX_BANDWIDTH)
	var w := bw_bar.size.x / segs
	for i in segs:
		var r := Rect2(i * w + 1.0, 0, w - 2.0, bw_bar.size.y)
		bw_bar.draw_rect(r, Color(0.15, 0.08, 0.15, 0.8))
		var fill := clampf(player.bandwidth - i, 0.0, 1.0)
		if fill > 0.0:
			var fr := Rect2(r.position, Vector2(r.size.x * fill, r.size.y))
			bw_bar.draw_rect(fr, Color(1.0, 0.4, 0.9) if fill >= 1.0 else Color(0.6, 0.25, 0.55))
