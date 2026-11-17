class_name Enemy
extends CharacterBody3D
## Hostile machine. Armored until breached; can receive quickhack uploads.

signal died(enemy: Node)

enum Type { WALKER, DRONE }

const ProjectileScript := preload("res://scripts/projectile.gd")

const ARMOR_MULT := 0.25          # damage taken while armor is up
const GRAVITY := 7.5
const WALKER_ATTACK_RANGE := 2.0
const WALKER_WINDUP := 0.35
const DRONE_HOVER := 3.2
const DRONE_FIRE_INTERVAL := 1.8

var type: Type = Type.WALKER
var display_name := ""
var max_health := 120.0
var health := 120.0
var speed := 4.5
var dead := false

# Status
var breached := false
var breach_timer := 0.0
var stagger_timer := 0.0
var blind_timer := 0.0
var burn_timer := 0.0
var burn_dps := 0.0
var turncoat_timer := 0.0
var scanned := false

# Quickhack upload in progress
var upload_hack: Dictionary = {}
var upload_timer := 0.0

var player: Node3D
var attack_timer := 1.0
var windup_timer := -1.0
var repath_timer := 0.0
var wander_target := Vector3.ZERO
var hit_flash := 0.0
var strafe_dir := 1.0

var nav_agent: NavigationAgent3D
var visual: Node3D
var eye_mat: StandardMaterial3D
var shell_mat: StandardMaterial3D
var shield: MeshInstance3D
var label: Label3D


func setup(t: Type, p: Node3D, health_scale: float) -> void:
	type = t
	player = p
	if type == Type.WALKER:
		max_health = 120.0 * health_scale
		speed = 4.5
		display_name = "HOUND-%03d" % (randi() % 1000)
	else:
		max_health = 70.0 * health_scale
		speed = 5.5
		display_name = "WARDEN-%03d" % (randi() % 1000)
	health = max_health


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	strafe_dir = 1.0 if randf() < 0.5 else -1.0
	attack_timer = randf_range(0.8, 1.8)

	shell_mat = StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.22, 0.22, 0.25)
	shell_mat.metallic = 0.6
	shell_mat.roughness = 0.35
	eye_mat = StandardMaterial3D.new()
	eye_mat.emission_enabled = true
	eye_mat.emission_energy_multiplier = 4.0

	visual = Node3D.new()
	add_child(visual)
	var cs := CollisionShape3D.new()
	if type == Type.WALKER:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.5
		cap.height = 1.9
		cs.shape = cap
		cs.position.y = 0.95
		_part(Vector3(0.9, 1.0, 0.6), Vector3(0, 1.2, 0), shell_mat)
		_part(Vector3(0.22, 0.75, 0.22), Vector3(-0.25, 0.38, 0), shell_mat)
		_part(Vector3(0.22, 0.75, 0.22), Vector3(0.25, 0.38, 0), shell_mat)
		_part(Vector3(0.18, 0.8, 0.18), Vector3(-0.58, 1.1, -0.15), shell_mat)
		_part(Vector3(0.18, 0.8, 0.18), Vector3(0.58, 1.1, -0.15), shell_mat)
		_part(Vector3(0.5, 0.35, 0.45), Vector3(0, 1.85, -0.05), shell_mat)
		_part(Vector3(0.4, 0.08, 0.05), Vector3(0, 1.88, -0.29), eye_mat)
		nav_agent = NavigationAgent3D.new()
		nav_agent.path_desired_distance = 0.8
		nav_agent.target_desired_distance = 1.2
		nav_agent.radius = 0.6
		nav_agent.height = 1.8
		add_child(nav_agent)
	else:
		motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		var sph := SphereShape3D.new()
		sph.radius = 0.55
		cs.shape = sph
		var body := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		body.mesh = sm
		body.material_override = shell_mat
		visual.add_child(body)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.6
		tm.outer_radius = 0.72
		ring.mesh = tm
		ring.material_override = eye_mat
		visual.add_child(ring)
		_part(Vector3(0.25, 0.12, 0.1), Vector3(0, 0, -0.45), eye_mat)
		position.y = DRONE_HOVER
	add_child(cs)

	# Armor shield bubble, hidden while breached.
	shield = MeshInstance3D.new()
	var shm := SphereMesh.new()
	shm.radius = 1.15 if type == Type.WALKER else 0.85
	shm.height = shm.radius * 2.0
	shield.mesh = shm
	var shmat := StandardMaterial3D.new()
	shmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shmat.albedo_color = Color(0.3, 0.7, 1.0, 0.12)
	shield.material_override = shmat
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield.position = _aim_offset()
	add_child(shield)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 26
	label.outline_size = 8
	label.position = _aim_offset() + Vector3(0, 1.3 if type == Type.WALKER else 1.0, 0)
	label.visible = false
	add_child(label)

	set_scanned(player != null and player.scanning)


func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	visual.add_child(mi)


func _aim_offset() -> Vector3:
	return Vector3(0, 1.1, 0) if type == Type.WALKER else Vector3.ZERO


func get_aim_point() -> Vector3:
	return global_position + _aim_offset()


func is_armored() -> bool:
	return not breached


func is_uploading() -> bool:
	return not upload_hack.is_empty()


func set_scanned(on: bool) -> void:
	scanned = on


# ---------------------------------------------------------------- damage / status

func take_damage(amount: float, ignore_armor := false) -> void:
	if dead:
		return
	var mult := 1.0 if (breached or ignore_armor) else ARMOR_MULT
	health -= amount * mult
	hit_flash = 0.08
	if health <= 0.0:
		_die()


func apply_breach(duration: float) -> void:
	breached = true
	breach_timer = duration
	stagger_timer = 1.0
	windup_timer = -1.0


func start_upload(hack: Dictionary) -> void:
	upload_hack = hack
	upload_timer = 0.0


func _apply_hack(hack: Dictionary) -> void:
	match hack["id"]:
		"arc":
			take_damage(45.0, true)
			stagger_timer = maxf(stagger_timer, 0.5)
		"thermal":
			burn_timer = 5.0
			burn_dps = 12.0
		"blind":
			blind_timer = 6.0
			windup_timer = -1.0
			_pick_wander_target()
		"turncoat":
			turncoat_timer = 8.0
			windup_timer = -1.0


func _tick_status(delta: float) -> void:
	if breached:
		breach_timer -= delta
		if breach_timer <= 0.0:
			breached = false
	stagger_timer = maxf(stagger_timer - delta, 0.0)
	blind_timer = maxf(blind_timer - delta, 0.0)
	turncoat_timer = maxf(turncoat_timer - delta, 0.0)
	hit_flash = maxf(hit_flash - delta, 0.0)
	attack_timer -= delta
	repath_timer -= delta
	if burn_timer > 0.0:
		burn_timer -= delta
		take_damage(burn_dps * delta, true)
	if not upload_hack.is_empty() and not dead:
		upload_timer += delta
		if upload_timer >= float(upload_hack["upload"]):
			var h := upload_hack
			upload_hack = {}
			_apply_hack(h)


func _die() -> void:
	dead = true
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	label.visible = false
	shield.visible = false
	died.emit(self)
	# Simple burst effect, then remove.
	var burst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	burst.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.6, 0.2, 0.9)
	burst.material_override = m
	burst.position = _aim_offset()
	add_child(burst)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(burst, "scale", Vector3.ONE * 4.0, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.3)
	tw.chain().tween_callback(queue_free)


# ---------------------------------------------------------------- AI

func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick_status(delta)
	if dead:
		return
	var target := _pick_target()
	if type == Type.WALKER:
		_walker_ai(delta, target)
	else:
		_drone_ai(delta, target)
	_update_visuals()


## Turncoat: nearest other enemy. Blinded: nothing. Otherwise the player.
func _pick_target() -> Node3D:
	if turncoat_timer > 0.0:
		var best: Node3D = null
		var best_d := INF
		for n in get_tree().get_nodes_in_group("enemies"):
			if n == self:
				continue
			var d := global_position.distance_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n
		return best
	if blind_timer > 0.0:
		return null
	if player != null and not player.dead:
		return player
	return null


func _target_point(target: Node3D) -> Vector3:
	if target is Enemy:
		return (target as Enemy).get_aim_point()
	return target.global_position + Vector3(0, 1.2, 0)


func _deal_damage(target: Node3D, amount: float) -> void:
	if target is Enemy:
		(target as Enemy).take_damage(amount, true)   # turncoat hits bypass ally armor
	elif target.has_method("take_damage"):
		target.call("take_damage", amount)


func _walker_ai(delta: float, target: Node3D) -> void:
	var desired := Vector3.ZERO
	if stagger_timer > 0.0:
		windup_timer = -1.0
	elif target != null:
		var to_t := target.global_position - global_position
		to_t.y = 0
		var dist := to_t.length()
		if dist > WALKER_ATTACK_RANGE * 0.8 and windup_timer < 0.0:
			if repath_timer <= 0.0:
				nav_agent.target_position = target.global_position
				repath_timer = 0.25
			var next := nav_agent.get_next_path_position()
			var d := next - global_position
			d.y = 0
			if d.length() < 0.05:
				d = to_t
			desired = d.normalized() * speed * (1.3 if turncoat_timer > 0.0 else 1.0)
		# Melee with a short telegraphed wind-up.
		if windup_timer < 0.0 and dist < WALKER_ATTACK_RANGE and attack_timer <= 0.0:
			windup_timer = WALKER_WINDUP
		if windup_timer >= 0.0:
			windup_timer -= delta
			if windup_timer < 0.0:
				attack_timer = 1.2
				if dist < WALKER_ATTACK_RANGE + 0.4:
					_deal_damage(target, 14.0)
		_face(to_t, delta)
	else:
		# Blinded: wander aimlessly.
		var to_w := wander_target - global_position
		to_w.y = 0
		if to_w.length() < 1.0:
			_pick_wander_target()
		desired = to_w.normalized() * speed * 0.4
		_face(to_w, delta)

	velocity.x = move_toward(velocity.x, desired.x, 25.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, 25.0 * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


func _drone_ai(delta: float, target: Node3D) -> void:
	var desired := Vector3.ZERO
	var t := Time.get_ticks_msec() * 0.001
	var hover := DRONE_HOVER + sin(t * 2.0 + float(get_instance_id() % 100)) * 0.3
	if stagger_timer > 0.0:
		desired.y = -1.0
	elif target != null:
		var to_t := target.global_position - global_position
		to_t.y = 0
		var dist := to_t.length()
		var dir := to_t.normalized()
		var side := Vector3(-dir.z, 0, dir.x) * strafe_dir
		if dist > 11.0:
			desired = dir * speed
		elif dist < 7.0:
			desired = -dir * speed
		desired += side * speed * 0.5
		desired.y = (hover - global_position.y) * 2.0
		_face(to_t, delta)
		if attack_timer <= 0.0 and dist < 25.0 and _has_line_of_sight(target):
			attack_timer = DRONE_FIRE_INTERVAL * randf_range(0.85, 1.2)
			_shoot(target)
	else:
		var to_w := wander_target - global_position
		to_w.y = 0
		if to_w.length() < 1.0:
			_pick_wander_target()
		desired = to_w.normalized() * speed * 0.4
		desired.y = (hover - global_position.y) * 2.0
		_face(to_w, delta)
	velocity = velocity.move_toward(desired, 12.0 * delta)
	if move_and_slide() and randf() < 0.02:
		strafe_dir = -strafe_dir


func _has_line_of_sight(target: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(get_aim_point(), _target_point(target), 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot(target: Node3D) -> void:
	var from := get_aim_point() + (-visual.global_basis.z) * 0.6
	var aim := _target_point(target)
	var p := ProjectileScript.new()
	p.shooter_rid = get_rid()
	p.velocity = (aim - from).normalized() * 22.0
	p.damage = 9.0
	get_parent().add_child(p)
	p.global_position = from


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, yaw, 1.0 - exp(-10.0 * delta))


func _pick_wander_target() -> void:
	wander_target = global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	wander_target.x = clampf(wander_target.x, -32, 32)
	wander_target.z = clampf(wander_target.z, -32, 32)


# ---------------------------------------------------------------- visuals

func _update_visuals() -> void:
	var c := Color(1.0, 0.15, 0.1)                 # hostile
	if turncoat_timer > 0.0:
		c = Color(0.3, 1.0, 0.3)
	elif blind_timer > 0.0:
		c = Color(0.5, 0.5, 0.6)
	elif breached:
		c = Color(1.0, 0.75, 0.1)
	if burn_timer > 0.0 and int(Time.get_ticks_msec() / 80) % 2 == 0:
		c = Color(1.0, 0.45, 0.0)
	if windup_timer >= 0.0:
		c = Color(1, 1, 1)
	eye_mat.albedo_color = c
	eye_mat.emission = c
	shell_mat.emission_enabled = hit_flash > 0.0
	shell_mat.emission = Color(1, 1, 1)
	shield.visible = not breached

	var show := scanned or is_uploading() or breached or blind_timer > 0.0 or turncoat_timer > 0.0 or burn_timer > 0.0
	label.visible = show
	if not show:
		return
	var lines: Array[String] = []
	if scanned:
		lines.append("%s  %d/%d" % [display_name, int(ceil(health)), int(max_health)])
		lines.append("ARMOR: " + ("OFFLINE %.0fs" % breach_timer if breached else "ACTIVE (Q to breach)"))
	elif breached:
		lines.append("ARMOR OFFLINE %.0fs" % breach_timer)
	var st: Array[String] = []
	if burn_timer > 0.0:
		st.append("BURNING")
	if blind_timer > 0.0:
		st.append("BLIND")
	if turncoat_timer > 0.0:
		st.append("TURNCOAT")
	if not st.is_empty():
		lines.append(" | ".join(st))
	if is_uploading():
		var frac := clampf(upload_timer / float(upload_hack["upload"]), 0.0, 1.0)
		var n := int(frac * 10.0)
		lines.append("UPLOADING %s [%s%s]" % [upload_hack["name"], "#".repeat(n), "-".repeat(10 - n)])
	label.text = "\n".join(lines)
	label.modulate = c.lightened(0.3)
