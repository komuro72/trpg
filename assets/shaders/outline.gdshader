shader_type canvas_item;

uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 16.0) = 2.0;

void fragment() {
	vec4 modulate_color = COLOR; // modulate（HP色変化等）を保持
	vec4 col = texture(TEXTURE, UV) * modulate_color;

	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	vec2 px = outline_width / tex_size;

	float neighbor_alpha = 0.0;
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( px.x,      0.0)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-px.x,      0.0)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(     0.0,  px.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(     0.0, -px.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( px.x,  px.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-px.x,  px.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( px.x, -px.y)).a);
	neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);

	bool show_outline = outline_enabled && col.a < 0.5 && neighbor_alpha > 0.5;
	COLOR = show_outline ? outline_color : col;
}
