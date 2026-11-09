shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray tex_array : source_color, filter_nearest_mipmap, repeat_enable;
uniform float wind_strength = 1.0;

varying flat int v_layer;
varying float v_emissive;
varying vec3 v_color;

void vertex() {
	v_layer = int(round(UV2.x));
	v_emissive = UV2.y;
	v_color = COLOR.rgb;
	// COLOR.a encodes sway mode: 0.0 = static, 0.5 = leaves, 1.0 = top of cross-plants
	if (COLOR.a > 0.2) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float amp = (COLOR.a > 0.7 ? 0.07 : 0.025) * wind_strength;
		VERTEX.x += sin(TIME * 2.2 + wp.x * 0.9 + wp.z * 0.7) * amp;
		VERTEX.z += cos(TIME * 1.9 + wp.z * 0.9 + wp.x * 0.6) * amp;
	}
}

void fragment() {
	vec4 tex = texture(tex_array, vec3(UV, float(v_layer)));
	if (tex.a < 0.5) {
		discard;
	}
	ALBEDO = tex.rgb * v_color;
	ROUGHNESS = 0.92;
	SPECULAR = 0.08;
	if (v_emissive > 0.05) {
		EMISSION = tex.rgb * v_emissive * 1.6;
	}
}
