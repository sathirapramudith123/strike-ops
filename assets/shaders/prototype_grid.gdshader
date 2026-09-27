shader_type spatial;
// World-space grid for greybox levels. Cheap enough for the Compatibility renderer.

uniform vec4 base_color : source_color = vec4(0.45, 0.47, 0.5, 1.0);
uniform vec4 line_color : source_color = vec4(0.25, 0.26, 0.28, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 0.03;
uniform float roughness_value = 0.85;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Pick the two axes that lie on the surface (triplanar-style).
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.5 ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	vec2 g = abs(fract(uv / cell_size - 0.5) - 0.5) * cell_size;
	float line = 1.0 - step(line_width, min(g.x, g.y));
	vec2 big = abs(fract(uv / (cell_size * 4.0) - 0.5) - 0.5) * cell_size * 4.0;
	float big_line = 1.0 - step(line_width * 2.0, min(big.x, big.y));
	ALBEDO = mix(base_color.rgb, line_color.rgb, max(line * 0.6, big_line));
	ROUGHNESS = roughness_value;
}
