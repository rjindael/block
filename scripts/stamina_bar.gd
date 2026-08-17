extends ProgressBar

const PlayerScript := preload("res://scripts/player.gd")

@onready var player: PlayerScript = get_node("../../Player")

func _ready() -> void:
	min_value = 0.0
	max_value = player.MAX_STAMINA
	show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.91, 0.91, 0.85)
	bg.border_color = Color(0.32, 0.42, 0.66)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(2)
	add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.30, 0.72, 0.24)
	fill.border_color = Color(0.62, 0.95, 0.48)
	fill.border_width_top = 2
	fill.set_corner_radius_all(2)
	add_theme_stylebox_override("fill", fill)

func _process(_delta: float) -> void:
	value = player.stamina
