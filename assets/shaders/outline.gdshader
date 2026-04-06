shader_type canvas_item;

uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 16.0) = 2.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	if (outline_enabled && col.a < 0.5) {
		vec2 tex_size = vec2(textureSize(TEXTURE, 0));
		vec2 step = outline_width / tex_size;

		float neighbor_alpha = 0.0;
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( step.x,       0.0)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-step.x,       0.0)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(      0.0,  step.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(      0.0, -step.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( step.x,  step.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-step.x,  step.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( step.x, -step.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-step.x, -step.y)).a);

		if (neighbor_alpha > 0.5) {
			COLOR = outline_color;
			return;
		}
	}

	COLOR = col;
}
