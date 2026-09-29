shader_type spatial;
// Teammate outline (PlayerModel.set_outline): the back faces of the model,
// pushed out along the normals and drawn flat in the team colour, show as
// a glowing edge round the soldier.
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.55, 1.0, 1.0);
uniform float width = 0.022;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = color.rgb;
	EMISSION = color.rgb * 0.6;
}
