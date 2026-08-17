extends Node3D

const MOUSELOCK_ON := preload("res://art/ui/mouselock/on.png")
const MOUSELOCK_OFF := preload("res://art/ui/mouselock/off.png")
const PlayerScene := preload("res://scenes/player.tscn")

# tab-out zoom distance
const TAB_ZOOM_DISTANCE := 4.0

# sprint FOV
const SPRINT_FOV_BOOST := 6.0
const FOV_LERP_SPEED := 10.0

# global time scale that should be state dependent but its here for now
@export var time_scale := 0.9

@onready var player: CharacterBody3D = $Player
@onready var camera_target: Marker3D = $Player/Pivot/CameraTarget
@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var camera: Camera3D = $CameraYaw/CameraPitch/Camera3D
@onready var head_camera: Marker3D = $Player/Pivot/HeadCamera
@onready var player_pivot: Node3D = $Player/Pivot
@onready var mouselock_icon: TextureRect = $HUD/MouseLockIcon

@export var mouse_sensitivity := 0.004
@export var controller_sensitivity := 3.0

@export var min_pitch := deg_to_rad(-75)
@export var max_pitch := deg_to_rad(80)
@export var fp_min_pitch := deg_to_rad(-89)
@export var fp_max_pitch := deg_to_rad(89)

@export var min_zoom := 0.0
@export var max_zoom := 36.0
@export var zoom_speed := 16.0
@export var zoom_smooth := 8.0
@export var scroll_step := 1.2

@export var fp_lock_threshold := 1.5
@export var fp_full_threshold := 0.0

@export var look_offset := Vector3(0, 0, 0)
@export var head_bias_start := 3.0
@export var head_bias_end := 0.0

var yaw := 0.0
var pitch := deg_to_rad(-10)
var zoom := 4.0
var zoom_target := 4.0
var first_person := false
var rotating := false

# Mouse lock/shift lock
var mouse_locked := false
var _was_in_fp_zone := false

var _body_meshes: Array[MeshInstance3D] = []
var _body_mats: Array[StandardMaterial3D] = []

var base_fov := 60.0

func _enter_tree() -> void:
	add_child(PlayerScene.instantiate())

func _ready() -> void:
	Engine.time_scale = time_scale
	camera.position = Vector3(0.0, 0.0, zoom)
	base_fov = camera.fov
	_cache_body_meshes()
	_update_mouselock_icon()

#TODO: not necessary if the character becomes joined again so it'll have one mat.
func _cache_body_meshes() -> void:
	for node in player_pivot.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var mat := mesh.get_active_material(0)
		if mat:
			var dup := mat.duplicate() as StandardMaterial3D
			dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.set_surface_override_material(0, dup)
			_body_meshes.append(mesh)
			_body_mats.append(dup)

func _set_body_alpha(alpha: float) -> void:
	for mat in _body_mats:
		mat.albedo_color.a = alpha

func register_fade_material(mat: StandardMaterial3D) -> void:
	_body_mats.append(mat)

func unregister_fade_material(mat: StandardMaterial3D) -> void:
	_body_mats.erase(mat)

func _clamp_pitch() -> void:
	if first_person:
		pitch = clamp(pitch, fp_min_pitch, fp_max_pitch)
	else:
		pitch = clamp(pitch, min_pitch, max_pitch)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M:
			if not player.get("is_dead"):
				mouse_locked = not mouse_locked
				_update_mouselock_icon()
		elif event.physical_keycode == KEY_TAB:
			zoom_target = TAB_ZOOM_DISTANCE if first_person else min_zoom
			mouse_locked = true
			_update_mouselock_icon()
		elif event.physical_keycode == KEY_ESCAPE:
			mouse_locked = false
			rotating = false
			if not player.get("is_dead"):
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_update_mouselock_icon()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if not first_person and not mouse_locked:
			rotating = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if rotating else Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion:
		if rotating or mouse_locked or player.get("is_dead"):
			yaw   -= event.relative.x * mouse_sensitivity
			pitch -= event.relative.y * mouse_sensitivity
			_clamp_pitch()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_target -= scroll_step
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target += scroll_step
			# Scrolling out is the manual "let me out" gesture - unlike Tab
			# (which explicitly wants lock engaged), zooming out by hand should
			# hand control back rather than staying shift-locked.
			if mouse_locked:
				mouse_locked = false
				_update_mouselock_icon()
		zoom_target = clamp(zoom_target, min_zoom, max_zoom)


func _update_mouselock_icon() -> void:
	var active : bool = mouse_locked or player.get("is_dead")
	mouselock_icon.texture = MOUSELOCK_ON if active else MOUSELOCK_OFF


func _process(delta: float) -> void:
	var yaw_input   := Input.get_action_strength("camera_left")  - Input.get_action_strength("camera_right")
	var pitch_input := Input.get_action_strength("camera_up") - Input.get_action_strength("camera_down")

	if abs(yaw_input)   < 0.1:
		yaw_input   = 0.0
	if abs(pitch_input) < 0.1:
		pitch_input = 0.0
	
	#TODO: THIS WHOLE BUNCH OF BULLSHIT IS HORRIBLE
	# 1: need to remove the fp transition
	# 2: should respect the original yaw/pitch when entering fp mode

	yaw += yaw_input   * controller_sensitivity * delta
	pitch += pitch_input * controller_sensitivity * delta
	_clamp_pitch()

	var zoom_input := Input.get_action_strength("camera_zoom_in") - Input.get_action_strength("camera_zoom_out")
	if zoom_input != 0.0:
		zoom_target -= zoom_input * zoom_speed * delta
		zoom_target  = clamp(zoom_target, min_zoom, max_zoom)

	zoom = lerp(zoom, zoom_target, zoom_smooth * delta)
	first_person = zoom <= fp_full_threshold + 0.5

	var in_fp_zone := zoom_target <= fp_lock_threshold
	if in_fp_zone and not _was_in_fp_zone:
		mouse_locked = true
	_was_in_fp_zone = in_fp_zone
	_update_mouselock_icon()

	# While dead, mouse lock preference is disregarded entirely - always
	# captured, no matter what state it was in when you died.
	if player.get("is_dead"):
		rotating = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif mouse_locked:
		rotating = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not rotating:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var fade : Variant = clamp(inverse_lerp(fp_lock_threshold, fp_full_threshold + 0.5, zoom), 0.0, 1.0)
	_set_body_alpha(1.0 - fade)

	var sprint_blend : float = player.get("sprint_blend")
	var target_fov := base_fov + SPRINT_FOV_BOOST * sprint_blend
	camera.fov = lerp(camera.fov, target_fov, FOV_LERP_SPEED * delta)

	camera_yaw.global_position = camera_target.global_position
	camera_yaw.rotation.y = yaw
	camera_pitch.rotation.x = pitch
	camera.global_transform.basis = camera_pitch.global_transform.basis
	if mouse_locked:
		player_pivot.rotation.y = yaw
	if first_person:
		camera.global_position = head_camera.global_position
		camera.global_transform.basis = camera_pitch.global_transform.basis
	else:
		var bias : Variant = 0
		var focus := (camera_target.global_position + look_offset).lerp(head_camera.global_position, bias)
		var fp_blend : Variant = clamp(inverse_lerp(fp_lock_threshold, fp_full_threshold, zoom), 0.0, 1.0)
		var arm_tip := camera_pitch.global_position + camera_pitch.global_transform.basis.z * zoom

		camera.global_position = arm_tip.lerp(head_camera.global_position, fp_blend)

		var look_dir := focus - camera.global_position
