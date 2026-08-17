# TODO: these should all be interfacable/reflectable for lua support in the future.

extends CharacterBody3D

@export var move_speed := 3.0
@export var jump_velocity := 7.0
@export var gravity := 18.0
@export var turn_speed := 6.0
@export var sprint_multiplier := 1.7

const DeathUIScript := preload("res://scripts/death_ui.gd")

@onready var pivot: Node3D = $Pivot
@onready var camera_pivot: Node3D = $"../CameraYaw"
@onready var skeleton: Skeleton3D = $Pivot/Character/Armature/Skeleton3D
@onready var character: Node3D = $Pivot/Character
@onready var walk_audio: AudioStreamPlayer = $WalkAudio
@onready var jump_audio: AudioStreamPlayer = $JumpAudio
@onready var die_audio: AudioStreamPlayer3D = $DieAudio
@onready var spawn_audio: AudioStreamPlayer3D = $SpawnAudio
@onready var death_ui: DeathUIScript = get_node("../DeathUI/Root")

@onready var camera_rig = get_node("..")

var r_leg: int
var l_leg: int
var r_arm: int
var l_arm: int

var base_pose := {}
var walk_time := 0.0
var walk_phase := 0.0
var walk_blend := 0.0
var jump_blend := 0.0
var climb_blend := 0.0
var sprinting := false
var sprint_blend := 0.0

var r_arm_angle := 0.0
var l_arm_angle := 0.0

const MAX_STAMINA := 130.0
const STAMINA_SPRINT_DRAIN := 18.0
const STAMINA_JUMP_COST := 6.0
const STAMINA_REGEN := 16.0
const STAMINA_EXHAUST_PAUSE := 1.5

var stamina := MAX_STAMINA
var stamina_regen_delay := 0.0

const JUMP_COMBO_VELOCITIES := [8.0, 9.6, 11.5]
const JUMP_COMBO_WINDOW := 0.35
const POSE_ARM_ANGLE := -1.3
const BACKFLIP_ARM_TUCK := 0.9
const BACKFLIP_LEG_TUCK := 1.3
const BACKFLIP_SPIN_DURATION := 0.9

var jump_combo := 0
var grounded_time := 0.0
var air_combo := 0
var backflip_spin_time := 0.0

const TORSO_HEIGHT := 0.9

const CROUCH_BLEND_SPEED := 6.0
const CRAWL_BLEND_SPEED := 3.0
const CROUCH_LEG_SCALE := 0.65
const CRAWL_LEG_SCALE := 0.45
const CROUCH_ARM_ANGLE := 0.4
const CRAWL_ARM_ANGLE := 0.9
const CRAWL_LEAN_ANGLE := 1.3
const CRAWL_SPEED := 0.8

var crouching := false
var crouch_blend := 0.0
var crawl_blend := 0.0
var leg_height := 0.0

const SLIDE_FRICTION := 6.0
const SLIDE_SMOKE_INTERVAL := 0.07

var sliding := false
var slide_speed := 0.0
var slide_smoke_timer := 0.0

const CROUCH_BACKFLIP_VELOCITY := 12.0
const CROUCH_BACKFLIP_BACK_SPEED := 3.0

const LONG_JUMP_VELOCITY := 6.0
const LONG_JUMP_SPEED := 9.0
const LONG_JUMP_ARM_ANGLE := -1.6
const LONG_JUMP_LEAN := 0.9

# broken
const WALL_JUMP_PUSH := 5.0
const WALL_JUMP_VELOCITY := 8.5
const WALL_JUMP_COOLDOWN := 0.4

var wall_jump_cooldown_timer := 0.0

const LEDGE_CHECK_DISTANCE := 0.6
const LEDGE_CHECK_HEIGHT_WALL := 1.3
const LEDGE_CHECK_HEIGHT_TOP := 1.85
const LEDGE_GRAB_DROP := 1.5
const LEDGE_HANG_ARM_ANGLE := 2.4
const HANG_CLIMB_HOLD_TIME := 0.4

var hanging := false
var ledge_point := Vector3.ZERO
var ledge_normal := Vector3.ZERO
var hang_climb_timer := 0.0

const MAX_HP := 20
const HP_PER_HEART := 2
const POISON_HALF_LIFE := 30.0
const POISON_TICK_INTERVAL := 15.0

var hp := MAX_HP
var poison := 0.0
var poison_tick_timer := 0.0

const WALK_FREQ := 8.5
const WALK_AMPLITUDE := 0.7
const RUN_FREQ := 13.0
const RUN_AMPLITUDE := 1.05
const RUN_ARM_SWING_MULT := 1.3
const RUN_ARM_LIFT := 0.5
const SPRINT_LEAN_ANGLE := 0.24
const SPRINT_BLEND_SPEED := 6.0
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

	var rleg_part := skeleton.get_node("RLeg_BONE/RLeg") as MeshInstance3D
	if rleg_part and rleg_part.mesh:
		leg_height = rleg_part.mesh.get_aabb().size.y

	spawn_transform = global_transform
	death_ui.respawn_requested.connect(respawn)
	spawn_forcefield()
	spawn_poof()


func _physics_process(delta):
	if is_dead:
		return

	if hanging:
		update_hang(delta)
		update_health(delta)
		return

	handle_movement(delta)
	update_stamina(delta)

	if is_on_floor():
		walk_time += delta

	update_animation(delta)
	update_health(delta)

func update_stamina(delta: float) -> void:
	if sprinting:
		stamina = max(stamina - STAMINA_SPRINT_DRAIN * delta, 0.0)
		if stamina <= 0.0:
			stamina_regen_delay = STAMINA_EXHAUST_PAUSE
	elif stamina_regen_delay > 0.0:
		stamina_regen_delay = max(stamina_regen_delay - delta, 0.0)
	else:
		stamina = min(stamina + STAMINA_REGEN * delta, MAX_STAMINA)

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

	var crouch_pressed := Input.is_action_pressed("crouch") and is_on_floor()
	if crouch_pressed and not crouching and sprinting:
		sliding = true
		slide_speed = Vector2(velocity.x, velocity.z).length()
		slide_smoke_timer = 0.0
	crouching = crouch_pressed
	if not crouching:
		sliding = false

	sprinting = Input.is_action_pressed("sprint") and input_vec.length() > 0.1 and stamina > 0.0 and not crouching
	sprint_blend = move_toward(sprint_blend, 1.0 if sprinting else 0.0, delta * SPRINT_BLEND_SPEED)

	var wants_crawl := crouching and not sliding and input_vec.length() > 0.15
	crouch_blend = move_toward(crouch_blend, 1.0 if crouching else 0.0, delta * CROUCH_BLEND_SPEED)
	crawl_blend = move_toward(crawl_blend, 1.0 if wants_crawl else 0.0, delta * CRAWL_BLEND_SPEED)

	var cam_forward := camera_pivot.global_transform.basis.z
	var cam_right := camera_pivot.global_transform.basis.x
	cam_forward.y = 0.0
	cam_right.y = 0.0
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()

	if sliding:
		slide_speed = max(slide_speed - SLIDE_FRICTION * delta, 0.0)
		var slide_dir := Vector3(velocity.x, 0.0, velocity.z)
		slide_dir = slide_dir.normalized() if slide_dir.length() > 0.01 else -pivot.basis.z
		velocity.x = slide_dir.x * slide_speed
		velocity.z = slide_dir.z * slide_speed

		slide_smoke_timer -= delta
		if slide_smoke_timer <= 0.0:
			slide_smoke_timer = SLIDE_SMOKE_INTERVAL
			spawn_slide_smoke()

		if slide_speed <= 0.15:
			sliding = false
	else:
		var move_dir := cam_right * input_vec.x + cam_forward * input_vec.y
		var speed: float
		if crouching:
			speed = lerp(0.0, CRAWL_SPEED, crawl_blend)
		else:
			speed = move_speed * lerp(1.0, sprint_multiplier, sprint_blend)
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed

		if move_dir.length() > 0.001:
			var target_basis := Basis.looking_at(move_dir, Vector3.UP)
			pivot.basis = pivot.basis.slerp(target_basis, turn_speed * delta)

	if wall_jump_cooldown_timer > 0.0:
		wall_jump_cooldown_timer = max(wall_jump_cooldown_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

		check_ledge_grab()

		#if is_on_wall() and wall_jump_cooldown_timer <= 0.0 and velocity.y < 0.0 and Input.is_action_pressed("jump"):
		#	perform_wall_jump()
	else:
		grounded_time += delta
		if jump_combo > 0 and grounded_time > JUMP_COMBO_WINDOW:
			jump_combo = 0
		if Input.is_action_pressed("jump"):
			if sliding:
				perform_long_jump()
			elif crouching and input_vec.length() < 0.15:
				perform_backflip_jump()
			else:
				perform_jump()

	move_and_slide()

func perform_jump() -> void:
	if sprinting and jump_combo > 0 and grounded_time <= JUMP_COMBO_WINDOW:
		jump_combo = jump_combo % 3 + 1
	elif sprinting:
		jump_combo = 1
	else:
		jump_combo = 0

	velocity.y = JUMP_COMBO_VELOCITIES[jump_combo - 1] if jump_combo > 0 else jump_velocity
	grounded_time = 0.0
	air_combo = jump_combo
	backflip_spin_time = 0.0

	stamina = max(stamina - STAMINA_JUMP_COST, 0.0)

	jump_audio.play()


func perform_backflip_jump() -> void:
	var back_dir := pivot.basis.z
	velocity.x = back_dir.x * CROUCH_BACKFLIP_BACK_SPEED
	velocity.z = back_dir.z * CROUCH_BACKFLIP_BACK_SPEED
	velocity.y = CROUCH_BACKFLIP_VELOCITY

	grounded_time = 0.0
	jump_combo = 0
	air_combo = 4
	backflip_spin_time = 0.0

	stamina = max(stamina - STAMINA_JUMP_COST, 0.0)
	jump_audio.play()


func perform_wall_jump() -> void:
	var wall_normal := get_wall_normal()

	velocity = wall_normal * WALL_JUMP_PUSH
	velocity.y = WALL_JUMP_VELOCITY

	if wall_normal.length() > 0.01:
		pivot.basis = Basis.looking_at(wall_normal, Vector3.UP)

	wall_jump_cooldown_timer = WALL_JUMP_COOLDOWN
	grounded_time = 0.0
	jump_combo = 0
	air_combo = 0
	backflip_spin_time = 0.0

	stamina = max(stamina - STAMINA_JUMP_COST, 0.0)
	jump_audio.play()


func check_ledge_grab() -> void:
	if hanging or velocity.y > 0.5:
		return

	var space_state := get_world_3d().direct_space_state
	var forward := -pivot.basis.z
	var origin := global_transform.origin

	var wall_from := origin + Vector3(0.0, LEDGE_CHECK_HEIGHT_WALL, 0.0)
	var wall_query := PhysicsRayQueryParameters3D.create(wall_from, wall_from + forward * LEDGE_CHECK_DISTANCE)
	wall_query.exclude = [get_rid()]
	var wall_hit := space_state.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return

	var top_from := origin + Vector3(0.0, LEDGE_CHECK_HEIGHT_TOP, 0.0)
	var top_query := PhysicsRayQueryParameters3D.create(top_from, top_from + forward * LEDGE_CHECK_DISTANCE)
	top_query.exclude = [get_rid()]
	var top_hit := space_state.intersect_ray(top_query)
	if not top_hit.is_empty():
		return  # blocked above - a tall wall, not a ledge to grab

	start_hang(wall_hit.position, wall_hit.normal)


func start_hang(point: Vector3, normal: Vector3) -> void:
	hanging = true
	ledge_point = point
	ledge_normal = normal
	hang_climb_timer = 0.0
	velocity = Vector3.ZERO

	global_transform.origin = point + normal * 0.3 - Vector3(0.0, LEDGE_GRAB_DROP, 0.0)
	if normal.length() > 0.01:
		pivot.basis = Basis.looking_at(-normal, Vector3.UP)

	jump_combo = 0
	air_combo = 0
	sliding = false


func update_hang(delta: float) -> void:
	skeleton.set_bone_pose_rotation(r_arm, base_pose[r_arm] * Quaternion(RARM_SWING_AXIS, LEDGE_HANG_ARM_ANGLE))
	skeleton.set_bone_pose_rotation(l_arm, base_pose[l_arm] * Quaternion(LARM_SWING_AXIS, LEDGE_HANG_ARM_ANGLE))

	if Input.is_action_just_pressed("jump"):
		drop_hang()
		return

	if Input.is_action_pressed("move_forward"):
		hang_climb_timer += delta
		if hang_climb_timer >= HANG_CLIMB_HOLD_TIME:
			hanging = false
			global_transform.origin = ledge_point + ledge_normal * 0.5 + Vector3(0.0, 0.15, 0.0)
			velocity = Vector3.ZERO
	else:
		hang_climb_timer = 0.0


func drop_hang() -> void:
	hanging = false
	velocity = Vector3.ZERO


func perform_long_jump() -> void:
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	dir = dir.normalized() if dir.length() > 0.1 else -pivot.basis.z

	velocity.x = dir.x * LONG_JUMP_SPEED
	velocity.z = dir.z * LONG_JUMP_SPEED
	velocity.y = LONG_JUMP_VELOCITY

	sliding = false
	grounded_time = 0.0
	jump_combo = 0
	air_combo = 5

	stamina = max(stamina - STAMINA_JUMP_COST, 0.0)
	jump_audio.play()


func spawn_slide_smoke() -> void:
	var puff := Sprite3D.new()
	puff.texture = SMOKE_TEXTURE
	puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	puff.pixel_size = 0.005
	puff.modulate = Color(1.0, 1.0, 1.0, 0.5)
	camera_rig.add_child.call_deferred(puff)

	puff.global_position = global_transform.origin + Vector3(randf_range(-0.15, 0.15), 0.05, randf_range(-0.15, 0.15))
	var start_scale := randf_range(0.4, 0.7)
	puff.scale = Vector3.ONE * start_scale

	var tw := puff.create_tween()
	tw.set_parallel(true)
	tw.tween_property(puff, "position:y", puff.position.y + 0.25, 0.35)
	tw.tween_property(puff, "scale", Vector3.ONE * start_scale * 1.4, 0.35)
	tw.tween_property(puff, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(puff.queue_free)

func update_walk_audio(walking: bool) -> void:
	walk_audio.pitch_scale = lerp(1.0, RUN_FREQ / WALK_FREQ, sprint_blend)

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

	var stride_freq: float = lerp(WALK_FREQ, RUN_FREQ, sprint_blend)
	if is_on_floor():
		walk_phase += stride_freq * delta

	if (air_combo == 3 or air_combo == 4) and not is_on_floor():
		backflip_spin_time += delta

	apply_locomotion()

	if jump_blend > 0.0:
		apply_jump_overlay()

	if crouch_blend > 0.0 or crawl_blend > 0.0:
		apply_crouch_overlay()

func apply_locomotion() -> void:
	var idle_angle := IDLE_AMPLITUDE * sin(walk_time * IDLE_FREQ)

	var amplitude: float = lerp(WALK_AMPLITUDE, RUN_AMPLITUDE, sprint_blend)
	var walk_angle := amplitude * sin(walk_phase)

	var locomotion_angle: float = lerp(idle_angle, walk_angle, walk_blend)

	# Climbing a ramp: lift both arms partway up, with a bit of alternating
	# wobble layered on top, like classic Roblox's scrambling-up-a-slope look.
	var climb_lift := CLIMB_ARM_LIFT * climb_blend
	var climb_wobble := CLIMB_WOBBLE_AMPLITUDE * sin(walk_time * CLIMB_WOBBLE_FREQ) * climb_blend

	var arm_swing: float = locomotion_angle * lerp(1.0, RUN_ARM_SWING_MULT, sprint_blend)
	var arm_lift := RUN_ARM_LIFT * sprint_blend

	r_arm_angle = -arm_swing + climb_lift - climb_wobble + arm_lift
	l_arm_angle = arm_swing + climb_lift + climb_wobble + arm_lift

	skeleton.set_bone_pose_rotation(r_arm, base_pose[r_arm] * Quaternion(RARM_SWING_AXIS, r_arm_angle))
	skeleton.set_bone_pose_rotation(l_arm, base_pose[l_arm] * Quaternion(LARM_SWING_AXIS, l_arm_angle))

	var idle_r_leg: Quaternion = base_pose[r_leg] * Quaternion(Vector3.FORWARD, -idle_angle)
	var idle_l_leg: Quaternion = base_pose[l_leg] * Quaternion(Vector3.FORWARD, -idle_angle)
	var walk_r_leg: Quaternion = base_pose[r_leg] * Quaternion(RLEG_SWING_AXIS, -walk_angle)
	var walk_l_leg: Quaternion = base_pose[l_leg] * Quaternion(LLEG_SWING_AXIS, walk_angle)

	skeleton.set_bone_pose_rotation(r_leg, idle_r_leg.slerp(walk_r_leg, walk_blend))
	skeleton.set_bone_pose_rotation(l_leg, idle_l_leg.slerp(walk_l_leg, walk_blend))

	# Baseline every frame - apply_jump_overlay/apply_crouch_overlay override
	# this afterward when a special pose is active.
	_set_character_pose(-SPRINT_LEAN_ANGLE * sprint_blend, 0.0)


func _set_character_pose(lean_angle: float, height_drop: float) -> void:
	# Leans/spins pivot around the torso instead of the character node's
	# own origin (which sits at the feet), otherwise the body swings from
	# the ground like a metronome instead of rotating in place.
	var rot := Basis(Vector3.RIGHT, lean_angle)
	var pivot_point := Vector3(0.0, TORSO_HEIGHT, 0.0)
	character.transform.basis = rot
	character.transform.origin = pivot_point - rot * pivot_point + Vector3(0.0, -height_drop, 0.0)


func apply_jump_overlay():
	var blend := smoothstep(0.0, 1.0, jump_blend)

	var raise_r := JUMP_ARM_RAISE
	var raise_l := JUMP_ARM_RAISE
	var leg_target_r: Quaternion = base_pose[r_leg]
	var leg_target_l: Quaternion = base_pose[l_leg]

	if air_combo == 2:
		raise_r = POSE_ARM_ANGLE
		raise_l = POSE_ARM_ANGLE
	elif air_combo == 3 or air_combo == 4:
		raise_r = BACKFLIP_ARM_TUCK
		raise_l = BACKFLIP_ARM_TUCK
		leg_target_r = base_pose[r_leg] * Quaternion(RLEG_SWING_AXIS, -BACKFLIP_LEG_TUCK)
		leg_target_l = base_pose[l_leg] * Quaternion(LLEG_SWING_AXIS, BACKFLIP_LEG_TUCK)
	elif air_combo == 5:
		# Long jump: arms swept back, diving forward.
		raise_r = LONG_JUMP_ARM_ANGLE
		raise_l = LONG_JUMP_ARM_ANGLE

	var final_r_angle: float = lerp(r_arm_angle, raise_r, blend)
	var final_l_angle: float = lerp(l_arm_angle, raise_l, blend)

	skeleton.set_bone_pose_rotation(r_arm, base_pose[r_arm] * Quaternion(RARM_SWING_AXIS, final_r_angle))
	skeleton.set_bone_pose_rotation(l_arm, base_pose[l_arm] * Quaternion(LARM_SWING_AXIS, final_l_angle))

	skeleton.set_bone_pose_rotation(r_leg, skeleton.get_bone_pose_rotation(r_leg).slerp(leg_target_r, blend))
	skeleton.set_bone_pose_rotation(l_leg, skeleton.get_bone_pose_rotation(l_leg).slerp(leg_target_l, blend))

	if air_combo == 3 or air_combo == 4:
		var spin_progress: float = clamp(backflip_spin_time / BACKFLIP_SPIN_DURATION, 0.0, 1.0)
		var spin_dir := -1.0 if air_combo == 3 else 1.0
		_set_character_pose(spin_dir * TAU * spin_progress, 0.0)
	elif air_combo == 5:
		_set_character_pose(-LONG_JUMP_LEAN * blend, 0.0)


func apply_crouch_overlay() -> void:
	var leg_scale_target: float = lerp(CROUCH_LEG_SCALE, CRAWL_LEG_SCALE, crawl_blend)
	var leg_scale: float = lerp(1.0, leg_scale_target, crouch_blend)
	skeleton.set_bone_pose_scale(r_leg, Vector3.ONE * leg_scale)
	skeleton.set_bone_pose_scale(l_leg, Vector3.ONE * leg_scale)

	var arm_target: float = lerp(CROUCH_ARM_ANGLE, CRAWL_ARM_ANGLE, crawl_blend)
	var arm_angle: float = lerp(0.0, arm_target, crouch_blend)
	skeleton.set_bone_pose_rotation(r_arm, base_pose[r_arm] * Quaternion(RARM_SWING_AXIS, -arm_angle))
	skeleton.set_bone_pose_rotation(l_arm, base_pose[l_arm] * Quaternion(LARM_SWING_AXIS, -arm_angle))

	var drop: float = leg_height * (1.0 - leg_scale)
	var lean: float = lerp(0.0, -CRAWL_LEAN_ANGLE * crawl_blend, crouch_blend)
	_set_character_pose(lean, drop)


func die() -> void:
	if is_dead:
		return

	is_dead = true
	hp = 0
	velocity = Vector3.ZERO
	walk_audio.stop()
	die_audio.play()

	clear_forcefield()

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

	jump_combo = 0
	grounded_time = 0.0
	air_combo = 0
	backflip_spin_time = 0.0
	crouching = false
	crouch_blend = 0.0
	crawl_blend = 0.0
	sliding = false
	slide_speed = 0.0
	character.transform = Transform3D.IDENTITY
	skeleton.set_bone_pose_scale(r_leg, Vector3.ONE)
	skeleton.set_bone_pose_scale(l_leg, Vector3.ONE)

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

var forcefield_cages: Array[Node3D] = []
var forcefield_tween: Tween
var forcefield_mat: StandardMaterial3D
var forcefield_generation := 0

func spawn_forcefield() -> void:
	clear_forcefield()

	forcefield_generation += 1
	var generation := forcefield_generation

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = FORCEFIELD_COLORS[0]
	mat.emission_enabled = true
	mat.emission = FORCEFIELD_COLORS[0]
	mat.emission_energy_multiplier = 1.5
	forcefield_mat = mat

	var tween := create_tween().set_loops()
	var colors := FORCEFIELD_COLORS + [FORCEFIELD_COLORS[0]]
	for i in range(1, colors.size()):
		tween.tween_method(_set_forcefield_hue.bind(mat), colors[i - 1], colors[i], FORCEFIELD_CYCLE_SPEED)
	forcefield_tween = tween

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
		forcefield_cages.append(cage)

		if not is_tween_bound:
			tween.bind_node(cage)
			is_tween_bound = true

	get_tree().create_timer(FORCEFIELD_DURATION).timeout.connect(_on_forcefield_timeout.bind(generation))


func _on_forcefield_timeout(generation: int) -> void:
	if generation == forcefield_generation:
		clear_forcefield()


func clear_forcefield() -> void:
	for cage in forcefield_cages:
		if is_instance_valid(cage):
			cage.queue_free()
	forcefield_cages.clear()

	if forcefield_tween and forcefield_tween.is_valid():
		forcefield_tween.kill()
	forcefield_tween = null

	if forcefield_mat:
		camera_rig.unregister_fade_material(forcefield_mat)
	forcefield_mat = null


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
