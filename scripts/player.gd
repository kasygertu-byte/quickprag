extends CharacterBody3D
## Third-person player: movement, rifle, breach (grid hack) and quickhacks.

signal died

const WALK_SPEED := 6.0
const SPRINT_SPEED := 9.5
const AIM_SPEED := 3.5
const GROUND_ACCEL := 45.0
const AIR_ACCEL := 8.0
const GRAVITY := 7.5            # low lunar gravity
const JUMP_VELOCITY := 5.0
const MOUSE_SENS := 0.0025

const FIRE_INTERVAL := 0.11
const MAG_SIZE := 30
const RELOAD_TIME := 1.4
const BULLET_DAMAGE := 10.0
const WEAPON_RANGE := 120.0

const MAX_BANDWIDTH := 12.0
const BANDWIDTH_REGEN := 0.6    # per second
const BREACH_RANGE := 35.0
const SCAN_TIME_SCALE := 0.25

## Cyberpunk-style quickhacks. Cost is halved on a breached target.
const QUICKHACKS := [
	{"id": "arc", "name": "ARC SURGE", "cost": 3, "upload": 0.6, "desc": "45 damage, ignores armor"},
	{"id": "thermal", "name": "THERMAL SPIKE", "cost": 4, "upload": 1.0, "desc": "Burns 12/s for 5s"},
	{"id": "blind", "name": "BLINDSIGHT", "cost": 2, "upload": 0.5, "desc": "Loses track of you for 6s"},
	{"id": "turncoat", "name": "TURNCOAT", "cost": 6, "upload": 1.5, "desc": "Attacks its allies for 8s"},
]

var hud: CanvasLayer

var max_health := 100.0
var health := 100.0
var bandwidth := MAX_BANDWIDTH
var ammo := MAG_SIZE
var reloading := false
var reload_timer := 0.0
var fire_timer := 0.0
var breach_cooldown := 0.0
var aiming := false
var scanning := false
var breaching := false
var breach_target: Enemy = null
var current_target: Enemy = null
var dead := false

var yaw := 0.0
var pitch := -0.15

var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var model: Node3D
var muzzle: Node3D
var companion: MeshInstance3D
var companion_mat: StandardMaterial3D
var tracer_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	_build_model()

	cam_yaw = Node3D.new()
	cam_yaw.position.y = 1.55
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.position = Vector3(0.65, 0, 0)
	spring.spring_length = 3.4
	spring.collision_mask = 1
	var ss := SphereShape3D.new()
	ss.radius = 0.2
	spring.shape = ss
	spring.add_excluded_object(get_rid())
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 72.0
	spring.add_child(camera)
	camera.make_current()

	tracer_mat = StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.albedo_color = Color(0.6, 0.95, 1.0)
	tracer_mat.emission_enabled = true
	tracer_mat.emission = Color(0.6, 0.95, 1.0)
	tracer_mat.emission_energy_multiplier = 4.0

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_model() -> void:
	model = Node3D.new()
	add_child(model)

	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.85, 0.87, 0.9)
	suit.metallic = 0.3
	suit.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.16, 0.18)
	var visor := StandardMaterial3D.new()
	visor.albedo_color = Color(0.2, 0.9, 1.0)
	visor.emission_enabled = true
	visor.emission = Color(0.2, 0.9, 1.0)
	visor.emission_energy_multiplier = 3.0

	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.36
	cm.height = 1.7
	body.mesh = cm
	body.material_override = suit
	body.position.y = 0.88
	model.add_child(body)

	_part(model, Vector3(0.36, 0.1, 0.06), Vector3(0, 1.52, -0.32), visor)
	_part(model, Vector3(0.5, 0.6, 0.25), Vector3(0, 1.15, 0.38), dark)       # backpack
	_part(model, Vector3(0.08, 0.08, 0.5), Vector3(-0.15, 1.3, 0.52), visor)  # pack light
	_part(model, Vector3(0.12, 0.16, 0.8), Vector3(0.32, 1.2, -0.45), dark)   # rifle
	_part(model, Vector3(0.13, 0.04, 0.5), Vector3(0.32, 1.3, -0.45), visor)  # rifle strip

	muzzle = Node3D.new()
	muzzle.position = Vector3(0.32, 1.22, -0.9)
	model.add_child(muzzle)

	# Hacking companion drone that floats at the player's shoulder.
	companion = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	companion.mesh = sm
	companion_mat = StandardMaterial3D.new()
	companion_mat.albedo_color = Color(0.6, 1.0, 0.95)
	companion_mat.emission_enabled = true
	companion_mat.emission = Color(0.4, 1.0, 0.9)
	companion_mat.emission_energy_multiplier = 3.0
	companion.material_override = companion_mat
	companion.top_level = true
	add_child(companion)
	var cl := OmniLight3D.new()
	cl.light_color = Color(0.4, 1.0, 0.9)
	cl.light_energy = 0.6
	cl.omni_range = 3.0
	companion.add_child(cl)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not breaching:
		var motion := event as InputEventMouseMotion
		var s := MOUSE_SENS * (0.55 if aiming else 1.0)
		yaw -= motion.relative.x * s
		pitch = clampf(pitch - motion.relative.y * s, -1.2, 0.85)
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("scan"):
		set_scanning(not scanning)
	elif event.is_action_pressed("breach"):
		_try_breach()
	elif event.is_action_pressed("reload"):
		_start_reload()
	else:
		for i in QUICKHACKS.size():
			if event.is_action_pressed("hack_%d" % (i + 1)):
				_try_quickhack(i)
				break


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if dead:
		return
	breach_cooldown = maxf(breach_cooldown - delta, 0.0)
	bandwidth = minf(bandwidth + BANDWIDTH_REGEN * delta, MAX_BANDWIDTH)
	aiming = Input.is_action_pressed("aim") and not breaching

	_handle_movement(delta)
	_handle_weapon(delta)
	_update_camera(delta)
	_update_model(delta)
	current_target = get_aim_target(60.0)


func _handle_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if breaching:
		input = Vector2.ZERO   # WASD drives the hack grid while breaching
	var dir := cam_yaw.global_basis * Vector3(input.x, 0, input.y)
	dir.y = 0
	dir = dir.normalized() * input.length()

	var speed := WALK_SPEED
	if aiming:
		speed = AIM_SPEED
	elif Input.is_action_pressed("sprint") and input.y < 0:
		speed = SPRINT_SPEED

	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not breaching:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


func _handle_weapon(delta: float) -> void:
	fire_timer -= delta
	if reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			reloading = false
			ammo = MAG_SIZE
	var can_fire := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not breaching and not scanning and not reloading
	if can_fire and Input.is_action_pressed("fire") and fire_timer <= 0.0:
		if ammo <= 0:
			_start_reload()
		else:
			_fire()


func _fire() -> void:
	fire_timer = FIRE_INTERVAL
	ammo -= 1
	var spread := 0.0 if aiming else 0.015
	var b := camera.global_basis
	var fwd := (-b.z + b.x * randf_range(-spread, spread) + b.y * randf_range(-spread, spread)).normalized()
	var from := camera.global_position
	var to := from + fwd * WEAPON_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to
	if not hit.is_empty():
		end = hit.position
		var col := hit.collider as Enemy
		if col != null:
			var armored := col.is_armored()
			col.take_damage(BULLET_DAMAGE)
			if hud:
				hud.show_hitmarker(armored)
	_spawn_tracer(muzzle.global_position, end)
	pitch = clampf(pitch + 0.004, -1.2, 0.85)   # recoil
	yaw += randf_range(-0.002, 0.002)
	if ammo <= 0:
		_start_reload()


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, length)
	t.mesh = bm
	t.material_override = tracer_mat
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(t)
	var mid := (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	t.look_at_from_position(mid, to, up)
	get_tree().create_timer(0.04).timeout.connect(t.queue_free)


func _start_reload() -> void:
	if reloading or ammo == MAG_SIZE or breaching:
		return
	reloading = true
	reload_timer = RELOAD_TIME


func _update_camera(delta: float) -> void:
	cam_yaw.rotation.y = yaw
	cam_pitch.rotation.x = pitch
	var k := 1.0 - exp(-12.0 * delta / maxf(Engine.time_scale, 0.01))
	spring.spring_length = lerpf(spring.spring_length, 1.7 if aiming else 3.4, k)
	camera.fov = lerpf(camera.fov, 55.0 if aiming else 72.0, k)


func _update_model(delta: float) -> void:
	var face := model.rotation.y
	var flat := Vector2(velocity.x, velocity.z)
	if aiming or breaching or Input.is_action_pressed("fire"):
		face = yaw
	elif flat.length() > 0.5:
		face = atan2(-velocity.x, -velocity.z)
	model.rotation.y = lerp_angle(model.rotation.y, face, 1.0 - exp(-14.0 * delta))

	var t := Time.get_ticks_msec() * 0.001
	var shoulder := global_position + cam_yaw.global_basis * Vector3(-0.75, 2.0, 0.3)
	shoulder.y += sin(t * 2.5) * 0.08
	if breaching and is_instance_valid(breach_target):
		shoulder = shoulder.lerp(breach_target.get_aim_point(), 0.15)
	companion.global_position = companion.global_position.lerp(shoulder, 1.0 - exp(-8.0 * delta))
	var c := Color(1.0, 0.3, 0.9) if breaching else Color(0.4, 1.0, 0.9)
	companion_mat.emission = c
	companion_mat.emission_energy_multiplier = 3.0 + (sin(t * 20.0) * 2.0 if breaching else 0.0)


# ---------------------------------------------------------------- targeting

## Enemy under the crosshair, with a small soft-lock cone as fallback.
func get_aim_target(max_range: float) -> Enemy:
	var from := camera.global_position
	var fwd := -camera.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * max_range, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider is Enemy and not hit.collider.dead:
		return hit.collider
	var best: Enemy = null
	var best_angle := deg_to_rad(5.0)
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		var p := e.get_aim_point()
		var to_e := p - from
		if to_e.length() > max_range:
			continue
		var ang := fwd.angle_to(to_e)
		if ang < best_angle:
			var los := PhysicsRayQueryParameters3D.create(from, p, 1, [get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(los).is_empty():
				best = e
				best_angle = ang
	return best


# ---------------------------------------------------------------- scan / hacks

func set_scanning(on: bool) -> void:
	if dead or (on and breaching):
		return
	scanning = on
	Engine.time_scale = SCAN_TIME_SCALE if on else 1.0
	get_tree().call_group("enemies", "set_scanned", on)
	if hud:
		hud.set_scan(on)


func hack_cost(index: int, target: Enemy) -> int:
	var cost: int = QUICKHACKS[index]["cost"]
	if target != null and target.breached:
		cost = int(ceil(cost / 2.0))
	return cost


func _try_quickhack(index: int) -> void:
	if breaching:
		return
	var target := current_target
	if target == null:
		hud.show_message("NO TARGET", 1.0)
		return
	if target.is_uploading():
		hud.show_message("UPLOAD ALREADY IN PROGRESS", 1.0)
		return
	var cost := hack_cost(index, target)
	if bandwidth < cost:
		hud.show_message("INSUFFICIENT BANDWIDTH", 1.0)
		return
	bandwidth -= cost
	target.start_upload(QUICKHACKS[index])


func _try_breach() -> void:
	if breaching:
		hud.cancel_breach()
		return
	if breach_cooldown > 0.0:
		return
	var target := get_aim_target(BREACH_RANGE)
	if target == null:
		hud.show_message("NO BREACH TARGET IN RANGE", 1.0)
		return
	if target.breached:
		hud.show_message("TARGET ALREADY BREACHED", 1.0)
		return
	set_scanning(false)
	breaching = true
	breach_target = target
	hud.start_breach(target)


## Called by the HUD hack grid when the breach ends.
func on_breach_finished(success: bool, amp: int, leech: int) -> void:
	breaching = false
	if amp < 0:   # target was destroyed mid-breach; nothing to report
		breach_target = null
		return
	if success and is_instance_valid(breach_target) and not breach_target.dead:
		breach_target.apply_breach(8.0 + 4.0 * amp)
		bandwidth = minf(bandwidth + 3.0 * leech, MAX_BANDWIDTH)
		var extra := ""
		if amp > 0:
			extra += "  +AMP"
		if leech > 0:
			extra += "  +LEECH"
		hud.show_message("BREACH SUCCESS - ARMOR OFFLINE" + extra, 1.6)
	elif not success:
		breach_cooldown = 2.0
		hud.show_message("BREACH FAILED", 1.2)
	breach_target = null


# ---------------------------------------------------------------- health

func take_damage(amount: float) -> void:
	if dead:
		return
	health -= amount
	if hud:
		hud.flash_damage()
	if health <= 0.0:
		health = 0.0
		_die()


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)


func _die() -> void:
	if breaching:
		hud.cancel_breach()
	set_scanning(false)
	dead = true
	Engine.time_scale = 1.0
	model.rotation.x = deg_to_rad(80)
	died.emit()
