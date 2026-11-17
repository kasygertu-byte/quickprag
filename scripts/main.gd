extends Node3D
## Builds the lunar arena, spawns the player and HUD, and runs enemy waves.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const HudScript := preload("res://scripts/hud.gd")

const ARENA_HALF := 35.0
const WALL_HEIGHT := 8.0

var nav_region: NavigationRegion3D
var player: CharacterBody3D
var hud: CanvasLayer
var spawn_points: Array[Vector3] = []

var wave := 0
var kills := 0
var enemies_alive := 0
var spawning := false

var mat_floor: StandardMaterial3D
var mat_wall: StandardMaterial3D
var mat_cover: StandardMaterial3D
var mat_glow_cyan: StandardMaterial3D
var mat_glow_amber: StandardMaterial3D


func _ready() -> void:
	Engine.time_scale = 1.0
	randomize()
	_setup_input()
	_make_materials()
	_build_environment()
	_build_level()
	_spawn_player()
	_build_hud()
	# Colliders must be in the physics world before the navmesh is parsed.
	await get_tree().physics_frame
	nav_region.bake_navigation_mesh(false)
	await get_tree().create_timer(1.5).timeout
	_start_next_wave()


# ---------------------------------------------------------------- input map

func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W])
	_add_keys("move_back", [KEY_S])
	_add_keys("move_left", [KEY_A])
	_add_keys("move_right", [KEY_D])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("reload", [KEY_R])
	_add_keys("breach", [KEY_Q])
	_add_mouse("breach", MOUSE_BUTTON_MIDDLE)
	_add_keys("scan", [KEY_TAB])
	_add_keys("hack_1", [KEY_1])
	_add_keys("hack_2", [KEY_2])
	_add_keys("hack_3", [KEY_3])
	_add_keys("hack_4", [KEY_4])
	_add_keys("restart", [KEY_ENTER, KEY_KP_ENTER])
	_add_keys("pause", [KEY_ESCAPE])
	_add_keys("help", [KEY_F1])
	_add_keys("grid_up", [KEY_W, KEY_UP])
	_add_keys("grid_down", [KEY_S, KEY_DOWN])
	_add_keys("grid_left", [KEY_A, KEY_LEFT])
	_add_keys("grid_right", [KEY_D, KEY_RIGHT])
	_add_mouse("fire", MOUSE_BUTTON_LEFT)
	_add_mouse("aim", MOUSE_BUTTON_RIGHT)


func _add_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _add_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- visuals

func _make_materials() -> void:
	mat_floor = StandardMaterial3D.new()
	mat_floor.albedo_color = Color(0.32, 0.32, 0.34)
	mat_floor.roughness = 0.95

	mat_wall = StandardMaterial3D.new()
	mat_wall.albedo_color = Color(0.55, 0.57, 0.62)
	mat_wall.metallic = 0.4
	mat_wall.roughness = 0.5

	mat_cover = StandardMaterial3D.new()
	mat_cover.albedo_color = Color(0.78, 0.78, 0.8)
	mat_cover.metallic = 0.2
	mat_cover.roughness = 0.6

	mat_glow_cyan = _glow(Color(0.2, 0.9, 1.0), 3.0)
	mat_glow_amber = _glow(Color(1.0, 0.6, 0.15), 2.5)


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.0, 0.0, 0.02)
	sky_mat.sky_horizon_color = Color(0.04, 0.05, 0.09)
	sky_mat.ground_horizon_color = Color(0.04, 0.05, 0.09)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.01)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(0.9, 0.93, 1.0)
	sun.shadow_enabled = true
	add_child(sun)

	# Distant planet hanging over the moon base.
	var planet := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 45.0
	sm.height = 90.0
	planet.mesh = sm
	planet.material_override = _glow(Color(0.25, 0.5, 1.0), 1.2)
	planet.position = Vector3(-160, 140, -320)
	add_child(planet)

	# Star field.
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.6
	star_mesh.height = 1.2
	star_mesh.radial_segments = 6
	star_mesh.rings = 3
	star_mesh.material = _glow(Color(1, 1, 1), 4.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = star_mesh
	mm.instance_count = 400
	for i in mm.instance_count:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.08, 1), randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * randf_range(0.4, 1.3)), dir * 420.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


# ---------------------------------------------------------------- level

func _build_level() -> void:
	nav_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nav_region.navigation_mesh = nm
	add_child(nav_region)

	var size := ARENA_HALF * 2.0
	_box(nav_region, Vector3(size, 1, size), Vector3(0, -0.5, 0), mat_floor)

	# Perimeter walls with glowing base strips.
	for s in [-1.0, 1.0]:
		_box(nav_region, Vector3(size, WALL_HEIGHT, 1), Vector3(0, WALL_HEIGHT * 0.5, s * (ARENA_HALF + 0.5)), mat_wall)
		_box(nav_region, Vector3(1, WALL_HEIGHT, size), Vector3(s * (ARENA_HALF + 0.5), WALL_HEIGHT * 0.5, 0), mat_wall)
		_box(nav_region, Vector3(size, 0.15, 0.1), Vector3(0, 0.6, s * (ARENA_HALF - 0.02)), mat_glow_cyan, false)
		_box(nav_region, Vector3(0.1, 0.15, size), Vector3(s * (ARENA_HALF - 0.02), 0.6, 0), mat_glow_cyan, false)

	# Central relay core (landmark).
	_cylinder(nav_region, 2.2, 10.0, Vector3(0, 5, 0), mat_wall)
	for h in [2.0, 5.0, 8.0]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.25
		tm.outer_radius = 2.5
		ring.mesh = tm
		ring.material_override = mat_glow_cyan
		ring.position = Vector3(0, h, 0)
		nav_region.add_child(ring)
	var core_light := OmniLight3D.new()
	core_light.light_color = Color(0.3, 0.85, 1.0)
	core_light.light_energy = 2.5
	core_light.omni_range = 18.0
	core_light.position = Vector3(0, 4, 0)
	nav_region.add_child(core_light)

	# Pillars.
	for p in [Vector3(-14, 0, -14), Vector3(14, 0, -14), Vector3(-14, 0, 14), Vector3(14, 0, 14)]:
		_box(nav_region, Vector3(2.5, WALL_HEIGHT, 2.5), p + Vector3(0, WALL_HEIGHT * 0.5, 0), mat_wall)
		_box(nav_region, Vector3(2.6, 0.2, 2.6), p + Vector3(0, 3.0, 0), mat_glow_amber, false)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.3)
		l.light_energy = 1.4
		l.omni_range = 10.0
		l.position = p + Vector3(0, 3.5, 0)
		nav_region.add_child(l)

	# Cover blocks (size, position on floor).
	var cover := [
		[Vector3(4, 1.3, 1), Vector3(-7, 0, -4)],
		[Vector3(4, 1.3, 1), Vector3(7, 0, 4)],
		[Vector3(1, 1.3, 4), Vector3(-6, 0, 8)],
		[Vector3(1, 1.3, 4), Vector3(6, 0, -8)],
		[Vector3(3, 2.2, 3), Vector3(-22, 0, 0)],
		[Vector3(3, 2.2, 3), Vector3(22, 0, 0)],
		[Vector3(3, 2.2, 3), Vector3(0, 0, -22)],
		[Vector3(3, 2.2, 3), Vector3(0, 0, 22)],
		[Vector3(6, 1.3, 1), Vector3(-24, 0, -24)],
		[Vector3(6, 1.3, 1), Vector3(24, 0, 24)],
		[Vector3(1, 1.3, 6), Vector3(24, 0, -24)],
		[Vector3(1, 1.3, 6), Vector3(-24, 0, 24)],
		[Vector3(2, 1.0, 2), Vector3(-12, 0, 2)],
		[Vector3(2, 1.0, 2), Vector3(12, 0, -2)],
		[Vector3(2, 1.0, 2), Vector3(-2, 0, 13)],
		[Vector3(2, 1.0, 2), Vector3(2, 0, -13)],
	]
	for c in cover:
		var sz: Vector3 = c[0]
		var pos: Vector3 = c[1]
		_box(nav_region, sz, pos + Vector3(0, sz.y * 0.5, 0), mat_cover)
		_box(nav_region, Vector3(sz.x + 0.02, 0.08, sz.z + 0.02), pos + Vector3(0, sz.y - 0.15, 0), mat_glow_cyan, false)

	# Enemy spawn points around the edge.
	for x in [-30.0, 0.0, 30.0]:
		for z in [-30.0, 0.0, 30.0]:
			if x == 0.0 and z == 0.0:
				continue
			spawn_points.append(Vector3(x, 0.2, z))


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, collide := true) -> Node3D:
	var root: Node3D
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		root = sb
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	root.add_child(mi)
	root.position = pos
	parent.add_child(root)
	return root


func _cylinder(parent: Node, radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	sb.add_child(mi)
	sb.position = pos
	parent.add_child(sb)


# ---------------------------------------------------------------- actors

func _spawn_player() -> void:
	player = PlayerScript.new()
	player.position = Vector3(0, 0.2, 10)
	add_child(player)
	player.died.connect(_on_player_died)


func _build_hud() -> void:
	hud = HudScript.new()
	hud.player = player
	add_child(hud)
	player.hud = hud


func _start_next_wave() -> void:
	if player.dead:
		return
	wave += 1
	spawning = true
	hud.set_wave(wave, enemies_alive)
	hud.show_message("WAVE %d" % wave, 2.5)
	var walkers := 2 + wave
	var drones := 1 + wave / 2
	var queue: Array[int] = []
	for i in walkers:
		queue.append(EnemyScript.Type.WALKER)
	for i in drones:
		queue.append(EnemyScript.Type.DRONE)
	queue.shuffle()
	for t in queue:
		if player.dead:
			return
		_spawn_enemy(t)
		await get_tree().create_timer(0.6).timeout
	spawning = false
	_check_wave_clear()


func _spawn_enemy(type: int) -> void:
	var candidates: Array[Vector3] = []
	for p in spawn_points:
		if p.distance_to(player.global_position) > 18.0:
			candidates.append(p)
	if candidates.is_empty():
		candidates = spawn_points.duplicate()
	var pos: Vector3 = candidates.pick_random() + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	var e: CharacterBody3D = EnemyScript.new()
	e.setup(type, player, 1.0 + 0.12 * (wave - 1))
	e.position = pos
	add_child(e)
	e.died.connect(_on_enemy_died)
	enemies_alive += 1
	hud.set_wave(wave, enemies_alive)


func _on_enemy_died(_e: Node) -> void:
	enemies_alive -= 1
	kills += 1
	hud.set_wave(wave, enemies_alive)
	_check_wave_clear()


func _check_wave_clear() -> void:
	if spawning or enemies_alive > 0 or player.dead:
		return
	player.heal(35.0)
	hud.show_message("WAVE %d CLEARED  -  INTEGRITY RESTORED" % wave, 3.0)
	await get_tree().create_timer(4.0).timeout
	_start_next_wave()


func _on_player_died() -> void:
	hud.show_game_over(wave, kills)
