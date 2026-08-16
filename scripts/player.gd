# TODO: these should all be interfacable/reflectable for lua support in the future.

extends CharacterBody3D

@export var move_speed := 3.0
@export var jump_velocity := 7.0
@export var gravity := 18.0
@export var turn_speed := 6.0

const DeathUIScript := preload("res://scripts/death_ui.gd")

@onready var pivot: Node3D = $Pivot
@onready var camera_pivot: Node3D = $"../CameraYaw"
@onready var skeleton: Skeleton3D = $Pivot/Character/Armature/Skeleton3D
@onready var character: Node3D = $Pivot/Character
@onready var walk_audio: AudioStreamPlayer = $WalkAudio
@onready var jump_audio: AudioStreamPlayer = $JumpAudio
@onready var die_audio: AudioStreamPlayer = $DieAudio
@onready var spawn_audio: AudioStreamPlayer = $SpawnAudio
@onready var death_ui: DeathUIScript = get_node("../DeathUI/Root")

@onready var camera_rig = get_node("..")

var r_leg: int
var l_leg: int
var r_arm: int
var l_arm: int

var base_pose := {}
var walk_time := 0.0
var walk_blend := 0.0
var jump_blend := 0.0
var climb_blend := 0.0

var r_arm_angle := 0.0
var l_arm_angle := 0.0

const MAX_HP := 20
const HP_PER_HEART := 2
const POISON_HALF_LIFE := 30.0
const POISON_TICK_INTERVAL := 15.0

var hp := MAX_HP
var poison := 0.0
var poison_tick_timer := 0.0

const WALK_FREQ := 8.5
const WALK_AMPLITUDE := 0.7
const IDLE_FREQ := 0.8
const IDLE_AMPLITUDE := 0.1
const WALK_BLEND_SPEED := 5.0
const JUMP_BLEND_SPEED := 6.0
const LAND_BLEND_SPEED := 1.8
const JUMP_ARM_RAISE := PI

# WIP for ramp handling.
# this will also be used for trusses, etc.
const CLIMB_SLOPE_MIN_DEG := 12.0
const CLIMB_ARM_LIFT := 0.9
const CLIMB_WOBBLE_FREQ := 9.0
const CLIMB_WOBBLE_AMPLITUDE := 0.25
const CLIMB_BLEND_SPEED := 6.0

# manually coded offsets for normalizing the rotations due to rig being slightly quirky
const RLEG_SWING_AXIS := Vector3(-0.0498, 0.3779, 0.9245)
const LLEG_SWING_AXIS := Vector3(-0.0498, -0.3779, -0.9245)
const RARM_SWING_AXIS := Vector3(-0.7399, 0.6727, 0.0)
const LARM_SWING_AXIS := Vector3(-0.7399, -0.6727, 0.0)

# temporary until real physics aand building are implemented. 
const RAGDOLL_PARTS := [
	"RLeg_BONE/RLeg",
	"LLeg_BONE/LLeg",
	"RArm_BONE/RArm",
	"LArm_BONE/LArm",
	"Head_BONE/Head",
	"Spine/Torso",
]
const RAGDOLL_IMPULSE := 0.5
const RAGDOLL_TORQUE := 0.3
const FORCEFIELD_DURATION := 8.0

const SMOKE_TEXTURE := preload("res://art/smoke.png")
const STAR_TEXTURE := preload("res://art/star.png")
const POOF_SMOKE_COUNT := 5
const POOF_STAR_COUNT := 10
const POOF_DURATION := 1.0

var is_dead := false
var spawn_transform := Transform3D.IDENTITY
var ragdoll_bodies: Array[RigidBody3D] = []

func _ready():
	r_leg = skeleton.find_bone("RLeg_BONE")
	l_leg = skeleton.find_bone("LLeg_BONE")
	r_arm = skeleton.find_bone("RArm_BONE")
	l_arm = skeleton.find_bone("LArm_BONE")

	for bone in [r_leg, l_leg, r_arm, l_arm]:
		base_pose[bone] = skeleton.get_bone_pose_rotation(bone)

	spawn_transform = global_transform
	death_ui.respawn_requested.connect(respawn)
	spawn_forcefield()
	spawn_poof()


func _physics_process(delta):
	if is_dead:
		return

	handle_movement(delta)

	if is_on_floor():
		walk_time += delta

	update_animation(delta)
	update_health(delta)

func update_health(delta: float):
	poison *= pow(0.5, delta / POISON_HALF_LIFE)
	if poison < 0.01:
		poison = 0.0

	if poison > 0.0:
		poison_tick_timer += delta
		if poison_tick_timer >= POISON_TICK_INTERVAL:
			poison_tick_timer -= POISON_TICK_INTERVAL
			var poison_hearts := roundi(poison / float(HP_PER_HEART))
			hp = max(hp - poison_hearts, 0)
			if hp <= 0:
				die()
	else:
		poison_tick_timer = 0.0


func add_poison(hearts: float):
	poison += hearts * HP_PER_HEART

func take_damage(amount: int):
	hp = clamp(hp - amount, 0, MAX_HP)
	if hp <= 0:
		die()

func heal(amount: int):
	hp = clamp(hp + amount, 0, MAX_HP)

func handle_movement(delta):
	var input_vec := Vector2.ZERO
	if Input.is_action_pressed("move_right"):  input_vec.x += 1
	if Input.is_action_pressed("move_left"):   input_vec.x -= 1
	if Input.is_action_pressed("move_back"):   input_vec.y += 1
	if Input.is_action_pressed("move_forward"): input_vec.y -= 1
	if input_vec.length() > 1.0:
		input_vec = input_vec.normalized()

	var cam_forward := camera_pivot.global_transform.basis.z
	var cam_right := camera_pivot.global_transform.basis.x
	cam_forward.y = 0.0
	cam_right.y = 0.0
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()

	var move_dir := cam_right * input_vec.x + cam_forward * input_vec.y
	velocity.x = move_dir.x * move_speed
	velocity.z = move_dir.z * move_speed

	if move_dir.length() > 0.001:
		var target_basis := Basis.looking_at(move_dir, Vector3.UP)
		pivot.basis = pivot.basis.slerp(target_basis, turn_speed * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_pressed("jump"):
		velocity.y = jump_velocity
		if Input.is_action_just_pressed("jump"):
			jump_audio.play()

	move_and_slide()

func update_walk_audio(walking: bool) -> void:
	if walking:
		if not walk_audio.playing:
			walk_audio.play()
	elif walk_audio.playing:
		walk_audio.stop()


func update_animation(delta: float):
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	walk_blend = move_toward(walk_blend, 1.0 if moving else 0.0, delta * WALK_BLEND_SPEED)

	update_walk_audio(moving and is_on_floor())

	var jump_blend_speed := LAND_BLEND_SPEED if is_on_floor() else JUMP_BLEND_SPEED
	jump_blend = move_toward(jump_blend, 0.0 if is_on_floor() else 1.0, delta * jump_blend_speed)

	var slope_deg := 0.0

	# RAMP correction
	if is_on_floor():
		slope_deg = rad_to_deg(get_floor_normal().angle_to(Vector3.UP))
	# TRUSS/RAMP detection
	var climbing := is_on_floor() and moving and slope_deg > CLIMB_SLOPE_MIN_DEG
	climb_blend = move_toward(climb_blend, 1.0 if climbing else 0.0, delta * CLIMB_BLEND_SPEED)

	apply_locomotion(walk_time)

	if jump_blend > 0.0:
		apply_jump_overlay()

func apply_locomotion(time: float):
	var idle_angle := IDLE_AMPLITUDE * sin(time * IDLE_FREQ)
	var walk_angle := WALK_AMPLITUDE * sin(time * WALK_FREQ)
	var locomotion_angle: float = lerp(idle_angle, walk_angle, walk_blend)

	# Climbing a ramp: lift both arms partway up, with a bit of alternating
	# wobble layered on top, like classic Roblox's scrambling-up-a-slope look.
	var climb_lift := CLIMB_ARM_LIFT * climb_blend
	var climb_wobble := CLIMB_WOBBLE_AMPLITUDE * sin(time * CLIMB_WOBBLE_FREQ) * climb_blend

	r_arm_angle = -locomotion_angle + climb_lift - climb_wobble
	l_arm_angle = locomotion_angle + climb_lift + climb_wobble

	skeleton.set_bone_pose_rotation(r_arm, base_pose[r_arm] * Quaternion(RARM_SWING_AXIS, r_arm_angle))
	skeleton.set_bone_pose_rotation(l_arm, base_pose[l_arm] * Quaternion(LARM_SWING_AXIS, l_arm_angle))

	var idle_r_leg: Quaternion = base_pose[r_leg] * Quaternion(Vector3.FORWARD, -idle_angle)
	var idle_l_leg: Quaternion = base_pose[l_leg] * Quaternion(Vector3.FORWARD, -idle_angle)
	var walk_r_leg: Quaternion = base_pose[r_leg] * Quaternion(RLEG_SWING_AXIS, -walk_angle)
	var walk_l_leg: Quaternion = base_pose[l_leg] * Quaternion(LLEG_SWING_AXIS, walk_angle)

	skeleton.set_bone_pose_rotation(r_leg, idle_r_leg.slerp(walk_r_leg, walk_blend))
	skeleton.set_bone_pose_rotation(l_leg, idle_l_leg.slerp(walk_l_leg, walk_blend))


func apply_jump_overlay():
	var blend := smoothstep(0.0, 1.0, jump_blend)

	var final_r_angle: float = lerp(r_arm_angle, JUMP_ARM_RAISE, blend)
	var final_l_angle: float = lerp(l_arm_angle, JUMP_ARM_RAISE, blend)

	skeleton.set_bone_pose_rotation(r_arm, base_pose[r_arm] * Quaternion(RARM_SWING_AXIS, final_r_angle))
	skeleton.set_bone_pose_rotation(l_arm, base_pose[l_arm] * Quaternion(LARM_SWING_AXIS, final_l_angle))

	skeleton.set_bone_pose_rotation(r_leg, skeleton.get_bone_pose_rotation(r_leg).slerp(base_pose[r_leg], blend))
	skeleton.set_bone_pose_rotation(l_leg, skeleton.get_bone_pose_rotation(l_leg).slerp(base_pose[l_leg], blend))


func die() -> void:
	if is_dead:
		return

	is_dead = true
	hp = 0
	velocity = Vector3.ZERO
	walk_audio.stop()
	die_audio.play()

	# Mouse capture while dead is handled by camera.gd (always captured,
	# regardless of mouse_locked, the instant is_dead is true) - clicking to
	# respawn doesn't need a visible cursor since it's just "any left click."

	spawn_ragdoll()
	death_ui.start_countdown()


func respawn() -> void:
	is_dead = false
	hp = MAX_HP
	poison = 0.0
	poison_tick_timer = 0.0
	global_transform = spawn_transform
	velocity = Vector3.ZERO

	clear_ragdoll()
	character.visible = true
	spawn_forcefield()
	spawn_poof()

func spawn_poof() -> void:
	var origin := global_transform.origin
	var world : Node3D = camera_rig

	spawn_audio.play()

	for i in POOF_SMOKE_COUNT:
		var puff := Sprite3D.new()
		puff.texture = SMOKE_TEXTURE
		puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		puff.pixel_size = 0.008
		puff.modulate = Color(1.0, 1.0, 1.0, randf_range(0.6, 0.85))
		world.add_child.call_deferred(puff)

		puff.global_position = origin + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 1.3), randf_range(-0.3, 0.3))
		puff.rotation.z = randf_range(0.0, TAU)
		var start_scale := randf_range(0.7, 1.3)
		puff.scale = Vector3.ONE * start_scale

		var tw := puff.create_tween()
		tw.set_parallel(true)
		tw.tween_property(puff, "position:y", puff.position.y + randf_range(0.4, 0.9), POOF_DURATION)
		tw.tween_property(puff, "scale", Vector3.ONE * start_scale * 1.6, POOF_DURATION)
		tw.tween_property(puff, "modulate:a", 0.0, POOF_DURATION)
		tw.chain().tween_callback(puff.queue_free)

	for i in POOF_STAR_COUNT:
		var star := Sprite3D.new()
		star.texture = STAR_TEXTURE
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		star.pixel_size = 0.025
		star.modulate = Color.from_hsv(randf(), 0.85, 1.0)
		world.add_child.call_deferred(star)

		star.global_position = origin + Vector3(0.0, 0.7, 0.0)

		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.0), randf_range(-1.0, 1.0)).normalized()
		var dist := randf_range(0.4, 1.0)

		var tw := star.create_tween()
		tw.set_parallel(true)
		tw.tween_property(star, "position", star.position + dir * dist, POOF_DURATION * 0.8) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(star, "rotation:z", randf_range(-TAU, TAU), POOF_DURATION)
		tw.tween_property(star, "modulate:a", 0.0, POOF_DURATION * 0.7).set_delay(POOF_DURATION * 0.3)
		tw.chain().tween_callback(star.queue_free)


func spawn_ragdoll() -> void:
	var world : Node3D = camera_rig

	for rel_path in RAGDOLL_PARTS:
		var part := skeleton.get_node(rel_path) as MeshInstance3D
		if part == null or part.mesh == null:
			continue

		var body := RigidBody3D.new()
		body.global_transform = part.global_transform
		world.add_child(body)

		var mesh_copy := MeshInstance3D.new()
		mesh_copy.mesh = part.mesh
		var mat := part.get_surface_override_material(0)
		if mat:
			mesh_copy.set_surface_override_material(0, mat)
		body.add_child(mesh_copy)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var aabb := part.mesh.get_aabb()
		box.size = aabb.size
		shape.shape = box
		shape.position = aabb.get_center()
		body.add_child(shape)

		body.apply_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * RAGDOLL_IMPULSE)
		body.apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * RAGDOLL_TORQUE)

		ragdoll_bodies.append(body)

	character.visible = false


func clear_ragdoll() -> void:
	for body in ragdoll_bodies:
		if is_instance_valid(body):
			body.queue_free()
	ragdoll_bodies.clear()

# this should be its own script soon
const FORCEFIELD_CAGE_MARGIN := 1
const FORCEFIELD_BAR_THICKNESS := 0.25
const FORCEFIELD_CYCLE_SPEED := 0.5
const FORCEFIELD_COLORS := [
	Color(1.0, 0.2, 0.2),
	Color(1.0, 0.6, 0.1),
	Color(1.0, 1.0, 0.2),
	Color(0.2, 1.0, 0.3),
	Color(0.2, 0.6, 1.0),
	Color(0.8, 0.2, 1.0),
]
const BOX_EDGES := [
	[0, 1], [1, 2], [2, 3], [3, 0],
	[4, 5], [5, 6], [6, 7], [7, 4],
	[0, 4], [1, 5], [2, 6], [3, 7],
]

func spawn_forcefield() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = FORCEFIELD_COLORS[0]
	mat.emission_enabled = true
	mat.emission = FORCEFIELD_COLORS[0]
	mat.emission_energy_multiplier = 1.5

	var tween := create_tween().set_loops()
	var colors := FORCEFIELD_COLORS + [FORCEFIELD_COLORS[0]]
	for i in range(1, colors.size()):
		tween.tween_method(_set_forcefield_hue.bind(mat), colors[i - 1], colors[i], FORCEFIELD_CYCLE_SPEED)

	camera_rig.register_fade_material(mat)

	var is_tween_bound := false

	for i in RAGDOLL_PARTS.size():
		var part := skeleton.get_node(RAGDOLL_PARTS[i]) as MeshInstance3D
		if part == null or part.mesh == null:
			continue

		var aabb := part.mesh.get_aabb()
		var cage := make_wireframe_cage(aabb.size * FORCEFIELD_CAGE_MARGIN, mat)
		cage.position = aabb.get_center()

		part.add_child(cage)

		if not is_tween_bound:
			tween.bind_node(cage)
			is_tween_bound = true

		get_tree().create_timer(FORCEFIELD_DURATION).timeout.connect(cage.queue_free)

	var cleanup_timer := get_tree().create_timer(FORCEFIELD_DURATION)
	cleanup_timer.timeout.connect(tween.kill)
	cleanup_timer.timeout.connect(camera_rig.unregister_fade_material.bind(mat))


func _set_forcefield_hue(color: Color, mat: StandardMaterial3D) -> void:
	mat.albedo_color = Color(color.r, color.g, color.b, mat.albedo_color.a)
	mat.emission = color


func make_wireframe_cage(size: Vector3, mat: Material) -> Node3D:
	var root := Node3D.new()
	var h := size * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]

	for edge in BOX_EDGES:
		root.add_child(make_cage_bar(corners[edge[0]], corners[edge[1]], mat))

	return root


func make_cage_bar(a: Vector3, b: Vector3, mat: Material) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()

	box.size = Vector3(FORCEFIELD_BAR_THICKNESS, FORCEFIELD_BAR_THICKNESS, a.distance_to(b) + FORCEFIELD_BAR_THICKNESS)
	
	bar.mesh = box
	bar.material_override = mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var dir := (b - a).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	bar.transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)

	return bar
