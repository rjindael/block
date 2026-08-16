# TODO: these should all be interfacable/reflectable for lua support in the future.

extends CharacterBody3D

@export var move_speed := 2.5
@export var jump_velocity := 7.0
@export var gravity := 24.0
@export var turn_speed := 6.0

@onready var pivot: Node3D = $Pivot
@onready var camera_pivot: Node3D = $"../CameraYaw"
@onready var skeleton: Skeleton3D = $Pivot/Character/Armature/Skeleton3D

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

const WALK_FREQ := 7.5
const WALK_AMPLITUDE := 0.7
const IDLE_FREQ := 0.8
const IDLE_AMPLITUDE := 0.1
const WALK_BLEND_SPEED := 5.0
const JUMP_BLEND_SPEED := 6.0
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

func _ready():
	r_leg = skeleton.find_bone("RLeg_BONE")
	l_leg = skeleton.find_bone("LLeg_BONE")
	r_arm = skeleton.find_bone("RArm_BONE")
	l_arm = skeleton.find_bone("LArm_BONE")

	for bone in [r_leg, l_leg, r_arm, l_arm]:
		base_pose[bone] = skeleton.get_bone_pose_rotation(bone)


func _physics_process(delta):
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
			var poison_hearts := int(poison / float(HP_PER_HEART))
			hp = max(hp - poison_hearts, 0)
	else:
		poison_tick_timer = 0.0


func add_poison(hearts: float):
	poison += hearts * HP_PER_HEART

func take_damage(amount: int):
	hp = clamp(hp - amount, 0, MAX_HP)

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

	move_and_slide()


func update_animation(delta: float):
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	walk_blend = move_toward(walk_blend, 1.0 if moving else 0.0, delta * WALK_BLEND_SPEED)

	jump_blend = move_toward(jump_blend, 0.0 if is_on_floor() else 1.0, delta * JUMP_BLEND_SPEED)

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
	var final_r_angle: float = lerp(r_arm_angle, JUMP_ARM_RAISE, jump_blend)
	var final_l_angle: float = lerp(l_arm_angle, JUMP_ARM_RAISE, jump_blend)

	skeleton.set_bone_pose_rotation(r_arm, base_pose[r_arm] * Quaternion(RARM_SWING_AXIS, final_r_angle))
	skeleton.set_bone_pose_rotation(l_arm, base_pose[l_arm] * Quaternion(LARM_SWING_AXIS, final_l_angle))

	skeleton.set_bone_pose_rotation(r_leg, skeleton.get_bone_pose_rotation(r_leg).slerp(base_pose[r_leg], jump_blend))
	skeleton.set_bone_pose_rotation(l_leg, skeleton.get_bone_pose_rotation(l_leg).slerp(base_pose[l_leg], jump_blend))
