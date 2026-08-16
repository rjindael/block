extends HBoxContainer

# i dont know if this is best practice tho
const PlayerScript := preload("res://scripts/player.gd")

const HP_FULL := preload("res://art/ui/hp/full.png")
const HP_HALF := preload("res://art/ui/hp/half.png")
const HP_NONE := preload("res://art/ui/hp/none.png")
const HP_ILL := preload("res://art/ui/hp/ill.png")

const HEART_SIZE := Vector2(16, 16)

@onready var player: PlayerScript = get_node("../../Player")

var hearts: Array[TextureRect] = []

func _ready():
	for i in player.MAX_HP / player.HP_PER_HEART:
		var heart := make_heart()
		add_child(heart)
		hearts.append(heart)

func _process(_delta):
	update_hearts()

func make_heart() -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = HEART_SIZE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect

func update_hearts():
	var total := hearts.size()
	var poison_hearts := roundi(player.poison / float(player.HP_PER_HEART))
	poison_hearts = min(poison_hearts, total)
	var poison_start := total - poison_hearts

	for i in total:
		if i >= poison_start:
			hearts[i].texture = HP_ILL
		else:
			var heart_hp := player.hp - i * player.HP_PER_HEART
			if heart_hp >= player.HP_PER_HEART:
				hearts[i].texture = HP_FULL
			elif heart_hp > 0:
				hearts[i].texture = HP_HALF
			else:
				hearts[i].texture = HP_NONE
