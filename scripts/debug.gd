extends Node

const PlayerScript := preload("res://scripts/player.gd")
const SkyScript := preload("res://scripts/sky.gd")

const SKY_CYCLE_KEY := KEY_N
const POISON_KEY := KEY_P

const POISON_DOSE := 1.0 # .. for now.... (in # of hearts to make ill)

@onready var player: PlayerScript = get_node("../Player")
@onready var sky: SkyScript = get_node("../WorldEnvironment")

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.physical_keycode == POISON_KEY:
		print("hi")
		player.add_poison(POISON_DOSE)
	elif event.physical_keycode == SKY_CYCLE_KEY:
		sky.cycle_sky()
