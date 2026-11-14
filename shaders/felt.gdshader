shader_type spatial;
render_mode diffuse_burley;

uniform vec4 felt_color : source_color = vec4(0.27, 0.025, 0.045, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float grain = hash(floor(UV * 1800.0));
	float weave = sin(UV.x * 4200.0) * sin(UV.y * 3100.0);
	float vignette = 1.0 - 0.26 * length((UV - 0.5) * 1.4);
	ALBEDO = felt_color.rgb * (0.97 + grain * 0.04 + weave * 0.015) * vignette;
	ROUGHNESS = 0.96;
}
