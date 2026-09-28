shader_type spatial;
// Shared material for the code-built models (weapons, players): the colour
// comes from the vertices (sRGB), metalness from the vertex alpha, so a whole
// model is one surface = one draw call. `tint` recolours team armour.
// UV.x > 0 paints a camouflage over the part (character outfits):
// 1 woodland, 2 desert, 3 urban, 4 winter, 5 multicam — blotches from 3D
// value noise in model space, so they wrap round limbs and stay put.

uniform vec4 tint : source_color = vec4(1.0);

varying vec3 model_pos;
varying float pattern;

void vertex() {
	model_pos = VERTEX;
	pattern = UV.x;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 camo(vec3 base, int kind, vec3 p) {
	vec3 c1; vec3 c2; vec3 c3; float scale = 9.0;
	if (kind == 1) { c1 = vec3(0.30, 0.22, 0.13); c2 = vec3(0.07, 0.08, 0.06); c3 = vec3(0.17, 0.25, 0.12); }
	else if (kind == 2) { c1 = vec3(0.50, 0.40, 0.26); c2 = vec3(0.34, 0.25, 0.15); c3 = vec3(0.70, 0.62, 0.46); }
	else if (kind == 3) { c1 = vec3(0.22, 0.23, 0.24); c2 = vec3(0.09, 0.09, 0.10); c3 = vec3(0.50, 0.51, 0.52); scale = 12.0; }
	else if (kind == 4) { c1 = vec3(0.70, 0.72, 0.74); c2 = vec3(0.42, 0.44, 0.47); c3 = vec3(0.93, 0.94, 0.95); scale = 11.0; }
	else { c1 = vec3(0.40, 0.36, 0.24); c2 = vec3(0.24, 0.20, 0.13); c3 = vec3(0.30, 0.33, 0.20); scale = 13.0; }
	c1 = pow(c1, vec3(2.2)); c2 = pow(c2, vec3(2.2)); c3 = pow(c3, vec3(2.2));
	float a = noise3(p * scale);
	float b = noise3(p * scale * 1.7 + vec3(7.3, 1.1, 3.9));
	vec3 col = base;
	col = mix(col, c1, step(0.55, a));
	col = mix(col, c3, step(0.62, b) * (1.0 - step(0.55, a)));
	col = mix(col, c2, step(0.72, a * 0.6 + b * 0.5));
	return col;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	if (pattern > 0.5) {
		base = camo(base, int(pattern + 0.5), model_pos);
	}
	ALBEDO = base * tint.rgb;
	METALLIC = COLOR.a;
	ROUGHNESS = mix(0.8, 0.32, COLOR.a);
}
