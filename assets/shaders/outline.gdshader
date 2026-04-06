shader_type canvas_item;

uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 16.0) = 2.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	if (outline_enabled && col.a < 0.5) {
		// TEXTURE_PIXEL_SIZE はテクスチャ1ピクセル分のUV幅（canvas_item シェーダーの組み込み変数）
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;

		float neighbor_alpha = 0.0;
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( px.x,      0.0)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-px.x,      0.0)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(     0.0,  px.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(     0.0, -px.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( px.x,  px.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-px.x,  px.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2( px.x, -px.y)).a);
		neighbor_alpha = max(neighbor_alpha, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);

		if (neighbor_alpha > 0.5) {
			COLOR = outline_color;
			return;
		}
	}

	COLOR = col;
}
