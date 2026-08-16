extends Control

signal respawn_requested

const PALATINO_FONT := preload("res://fonts/PalatinoLinotype.ttf")

const COUNTDOWN_SECONDS := 3
const FONT_COLOR := Color(0.1, 0.35, 1.0)
const FONT_OUTLINE_COLOR := Color(0.02, 0.07, 0.2)
const FONT_OUTLINE_SIZE := 6
const FONT_SIZE := 24

@onready var label: Label = $Label

var seconds_left := 0
var ready_to_respawn := false


func _ready() -> void:
	visible = false

	label.add_theme_font_override("font", PALATINO_FONT)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", FONT_COLOR)
	label.add_theme_color_override("font_outline_color", FONT_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", FONT_OUTLINE_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func start_countdown() -> void:
	visible = true
	ready_to_respawn = false
	seconds_left = COUNTDOWN_SECONDS
	_update_text()
	_run_countdown()

func _run_countdown() -> void:
	while seconds_left > 1:
		await get_tree().create_timer(1.0).timeout
		seconds_left -= 1
		_update_text()

	await get_tree().create_timer(1.0).timeout
	ready_to_respawn = true
	_update_text()


func _update_text() -> void:
	if ready_to_respawn:
		label.text = "Click to respawn"
	else:
		label.text = "Click to respawn in %d seconds..." % seconds_left


func _unhandled_input(event: InputEvent) -> void:
	if not (visible and ready_to_respawn):
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		visible = false
		ready_to_respawn = false
		respawn_requested.emit()
