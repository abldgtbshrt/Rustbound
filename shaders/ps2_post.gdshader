shader_type canvas_item;

// Applied to the SubViewportContainer that shows the low-res 3D view:
// 4x4 ordered dither + per-channel color quantization (PS2-era 15/16-bit look).

uniform bool enabled = true;
// Levels per channel. 32 = 5-bit (15-bit color).
uniform float color_levels : hint_range(4.0, 256.0) = 32.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled) {
		// Dither in source (low-res) pixels, not screen pixels.
		ivec2 p = ivec2(floor(UV / TEXTURE_PIXEL_SIZE)) % 4;
		float t = BAYER[p.y * 4 + p.x] / 16.0 - 0.5;
		float steps = color_levels - 1.0;
		c.rgb += t * dither_strength / steps;
		c.rgb = floor(c.rgb * steps + 0.5) / steps;
	}
	COLOR = c;
}
