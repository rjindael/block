extends WorldEnvironment

const SKY_DIR := "res://art/sky/"
const DEFAULT_SKY := "default.png"

const SKIES := 20

@onready var sun: DirectionalLight3D = get_node("../DirectionalLight3D")

var sky_files: Array[String] = []
var sky_index := 0

func _ready() -> void:
	sky_files = [DEFAULT_SKY]
	for i in range(1, SKIES + 1):
		var filename := "%02d.png" % i
		if ResourceLoader.exists(SKY_DIR + filename):
			sky_files.append(filename)

	set_sky(sky_index)


# Called from debug
func cycle_sky() -> void:
	sky_index = (sky_index + 1) % sky_files.size()
	set_sky(sky_index)


func set_sky(index: int) -> void:
	var texture: Texture2D = load(SKY_DIR + sky_files[index])
	var sky_material := environment.sky.sky_material as PanoramaSkyMaterial
	sky_material.panorama = texture
	apply_ambience(texture)

func apply_ambience(texture: Texture2D) -> void:
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_BG

	var image := texture.get_image()
	image.decompress()
	image.resize(16, 8, Image.INTERPOLATE_LANCZOS)

	var sky_color := Color(0, 0, 0)
	var horizon_color := Color(0, 0, 0)
	var sky_n := 0
	var horizon_n := 0
	var h := image.get_height()
	var w := image.get_width()

	# get average colors
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			if y < h * 0.35:
				sky_color += c
				sky_n += 1
			elif y < h * 0.6:
				horizon_color += c
				horizon_n += 1

	# normalize
	sky_color /= max(sky_n, 1)
	horizon_color /= max(horizon_n, 1)
	var brightness := (sky_color.r + sky_color.g + sky_color.b) / 3.0

	# and apply
	sun.light_color = horizon_color.lightened(0.3)
	sun.light_energy = clampf(brightness * 1.8, 0.5, 2.5)
