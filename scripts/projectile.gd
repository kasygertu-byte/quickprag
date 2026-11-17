extends Node3D
## Enemy energy bolt. Raycasts along its path each physics frame.

var velocity := Vector3.ZERO
var damage := 9.0
var shooter_rid: RID
var life := 4.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.3, 0.2)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.3, 0.2)
	m.emission_energy_multiplier = 5.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.2)
	l.light_energy = 0.8
	l.omni_range = 2.5
	add_child(l)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	var exclude: Array[RID] = []
	if shooter_rid.is_valid():
		exclude.append(shooter_rid)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		return
	var col: Object = hit.collider
	if col is Enemy:
		(col as Enemy).take_damage(damage, true)
	elif col != null and col.has_method("take_damage"):
		col.call("take_damage", damage)
	queue_free()
