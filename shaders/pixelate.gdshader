shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;

uniform float pixel_size : hint_range(1.0, 8.0) = 1.5;

void fragment() {
    vec2 uv = SCREEN_UV;
    if (pixel_size > 1.0) {
        vec2 screen_size = vec2(textureSize(screen_texture, 0));
        vec2 pixel_uv = floor(uv * screen_size / pixel_size) * pixel_size / screen_size;
        uv = pixel_uv;
    }

    vec4 original = texture(screen_texture, uv);
    COLOR = original;
}