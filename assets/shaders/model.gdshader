shader_type spatial;
// Shared material for the code-built models (weapons, players): the colour
// comes from the vertices (sRGB), metalness from the vertex alpha, so a whole
// model is one surface = one draw call. `tint` recolours team armour.

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * tint.rgb;
	METALLIC = COLOR.a;
	ROUGHNESS = mix(0.8, 0.32, COLOR.a);
}
