shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray tex_array : source_color, filter_nearest_mipmap, repeat_enable;

varying flat int v_layer;
varying float v_emissive;
varying vec3 v_color;

void vertex() {
	v_layer = int(round(UV2.x));
	v_emissive = UV2.y;
	v_color = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(TIME * 2.4 + wp.x * 1.1 + wp.z * 0.9) * 0.035 - 0.06;
}

void fragment() {
	vec2 uv = UV + vec2(TIME * 0.06, TIME * 0.04);
	vec4 tex = texture(tex_array, vec3(uv, float(v_layer)));
	ALBEDO = tex.rgb * v_color;
	if (v_emissive > 0.05) {
		ALPHA = 0.96;
		ROUGHNESS = 0.4;
		EMISSION = tex.rgb * 1.8;
	} else {
		ALPHA = 0.72;
		ROUGHNESS = 0.12;
		SPECULAR = 0.75;
	}
}
