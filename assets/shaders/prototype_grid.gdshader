shader_type spatial;
// Procedural surfaces for the greybox levels — no textures, so no download
// size and no VRAM. World-space (triplanar-style) so boxes of any size tile
// correctly. `kind` picks the look:
//   0 panels (neutral grid)   1 concrete    2 metal (brushed)   3 wood (planks)
//   4 painted plaster         5 stone paving 6 foliage
//   7 sandstone blocks        8 weathered plaster (bricks show through)
//   9 flagstones (irregular)  10 cloth (awnings)
// The global `surface_detail` (0 on the Low preset) turns the noise off:
// flat colour + seams, as cheap as the old grid shader.

uniform vec4 base_color : source_color = vec4(0.45, 0.47, 0.5, 1.0);
uniform vec4 line_color : source_color = vec4(0.25, 0.26, 0.28, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 0.03;
uniform float roughness_value = 0.85;
uniform int kind = 0;
uniform float metallic_value = 0.0;
// Darkening at the bottom of walls (dirt / ambient occlusion look).
uniform float grime = 0.3;
global uniform float surface_detail;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.03 + 7.1) * 0.3 + noise(p * 4.07 + 3.3) * 0.2;
}

// Running-bond masonry: x = mortar (1 on a joint), y = per-block random.
vec2 masonry(vec2 uv, float cell, float width) {
	vec2 b = vec2(cell * 0.9, cell * 0.36);
	float row = floor(uv.y / b.y);
	vec2 p = vec2(uv.x / b.x + row * 0.5, uv.y / b.y);
	vec2 g = abs(fract(p) - 0.5) * b; // distance to the block centre (m)
	vec2 edge = b * 0.5 - g;
	float joint = 1.0 - smoothstep(width * 0.5, width, min(edge.x, edge.y));
	return vec2(joint, hash(floor(p) + 11.0));
}

// Irregular flagstones (cellular): x = grout, y = per-stone random.
vec2 flagstones(vec2 uv, float cell) {
	vec2 p = uv / cell;
	vec2 i = floor(p);
	float d1 = 8.0, d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = i + vec2(float(x), float(y));
			vec2 o = c + 0.15 + 0.7 * vec2(hash(c), hash(c + 17.0));
			float d = length(p - o);
			if (d < d1) { d2 = d1; d1 = d; id = hash(c + 5.0); }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec2(1.0 - smoothstep(0.03, 0.07, d2 - d1), id);
}

// 1 on a seam line of a grid with the given cell size, else 0.
float seam(vec2 uv, float cell, float width) {
	vec2 g = abs(fract(uv / cell - 0.5) - 0.5) * cell;
	return 1.0 - smoothstep(width * 0.5, width, min(g.x, g.y));
}

void fragment() {
	vec3 n = abs(world_normal);
	bool floor_like = n.y > 0.5;
	vec2 uv = floor_like ? world_pos.xz : (n.x > 0.5 ? world_pos.zy : world_pos.xy);
	vec3 col = base_color.rgb;
	float rough = roughness_value;
	float metal = metallic_value;

	// Seams / planks / grout: always (cheap).
	if (kind == 7 || kind == 8) {
		// Cheap everywhere: mortar joints only (on 8 they are hidden under
		// the plaster unless the detail pass exposes them).
		if (kind == 7) {
			col = mix(col, line_color.rgb, masonry(uv, cell_size, line_width).x * 0.45);
		}
	} else if (kind == 9) {
		if (surface_detail < 0.5) {
			float s1 = seam(uv + vec2(floor(uv.y / cell_size) * cell_size * 0.5, 0.0), cell_size, line_width);
			col = mix(col, line_color.rgb, s1 * 0.6);
		}
	} else if (kind == 10) {
		// cloth: broad stripes
		float stripe = step(0.5, fract(uv.x / (cell_size * 2.0)));
		col = mix(col, line_color.rgb, stripe);
	} else if (kind == 3) {
		float gap = 1.0 - smoothstep(line_width * 0.5, line_width, abs(fract(uv.y / cell_size - 0.5) - 0.5) * cell_size);
		col = mix(col, line_color.rgb, gap * 0.7);
	} else if (kind == 6) {
		// foliage: no seams
	} else {
		float s1 = kind == 0 ? max(seam(uv, cell_size, line_width) * 0.45, seam(uv, cell_size * 4.0, line_width * 2.0) * 0.8)
			: seam(uv, kind == 4 ? cell_size * 4.0 : cell_size, line_width) * (kind == 5 ? 0.8 : (kind == 4 ? 0.3 : 0.5));
		col = mix(col, line_color.rgb, s1);
	}

	// Procedural detail: only when enabled (off on the Low preset) — a real
	// branch, so Low doesn't pay for the noise at all.
	if (surface_detail > 0.5) {
		if (kind == 1) { // concrete: soft mottling + speckles
			col *= (0.82 + 0.3 * fbm(uv * 0.9)) * (0.95 + 0.1 * noise(uv * 23.0));
		} else if (kind == 2) { // brushed metal: streaks along one axis
			col *= 0.88 + 0.2 * noise(vec2(uv.x * 45.0, uv.y * 1.2));
			rough *= 0.8 + 0.4 * noise(uv * 3.0);
		} else if (kind == 3) { // wood: grain + per-plank shade
			float grain = sin((uv.y * 9.0 + fbm(uv * vec2(0.6, 4.0)) * 3.0) * 6.2831) * 0.5 + 0.5;
			float plank = hash(vec2(floor(uv.y / cell_size), 3.0));
			col *= (0.78 + 0.22 * grain) * (0.88 + 0.24 * plank);
		} else if (kind == 4) { // painted plaster
			col *= 0.93 + 0.12 * fbm(uv * 0.6);
		} else if (kind == 5) { // stone paving: per-tile tint
			col *= (0.88 + 0.2 * hash(floor(uv / cell_size))) * (0.9 + 0.18 * fbm(uv * 1.7));
		} else if (kind == 6) { // foliage: clumpy greens
			col *= 0.6 + 0.7 * fbm(uv * 3.0 + world_pos.y * 2.0);
		} else if (kind == 7) { // sandstone: per-block tint, eroded faces
			vec2 m = masonry(uv, cell_size, line_width);
			col *= (0.86 + 0.24 * m.y) * (0.88 + 0.22 * fbm(uv * 2.3));
			col = mix(col, line_color.rgb * 0.9, m.x * 0.2);
		} else if (kind == 8) { // plaster with bald patches + water stains
			float patches = smoothstep(0.66, 0.7, fbm(uv * 0.45 + 4.0));
			vec2 m = masonry(uv, cell_size, line_width);
			vec3 brick = line_color.rgb * (0.85 + 0.3 * m.y);
			brick = mix(brick, brick * 0.6, m.x);
			col *= 0.9 + 0.14 * fbm(uv * 0.9);
			// A soft shadowed rim where the plaster broke off.
			float rim = smoothstep(0.62, 0.66, fbm(uv * 0.45 + 4.0)) - patches;
			col = mix(col * (1.0 - rim * 0.25), brick, patches);
			float streak = noise(vec2(uv.x * 3.0, 0.5)) * smoothstep(0.6, 1.0, noise(vec2(uv.x * 1.3, uv.y * 0.35)));
			col *= 1.0 - streak * 0.25;
		} else if (kind == 9) { // flagstones
			vec2 f = flagstones(uv, cell_size);
			col *= (0.84 + 0.28 * f.y) * (0.9 + 0.16 * noise(uv * 6.0));
			col = mix(col, line_color.rgb, f.x * 0.75);
			rough = mix(rough, 1.0, f.x);
		} else if (kind == 10) { // cloth weave
			col *= 0.92 + 0.1 * noise(uv * 40.0) + 0.06 * fbm(uv * 1.5);
		} else {
			col *= 0.95 + 0.08 * noise(uv * 0.8);
		}
	} else if (kind == 6) {
		col *= 0.9;
	}

	// Grime: walls get darker towards the ground.
	if (!floor_like) {
		col *= mix(1.0 - grime, 1.0, smoothstep(0.0, 0.9, world_pos.y));
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
