shader_type spatial;
render_mode diffuse_burley;

uniform vec4 wood_color : source_color = vec4(0.36, 0.235, 0.125, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * vec2(20.0, 12.0);
	float warp = noise(p * vec2(0.45, 3.0)) * 3.0;
	float grain = sin(p.y * 42.0 + warp * 2.0 + sin(p.x * 2.0) * 0.5);
	float fibers = noise(p * vec2(4.0, 110.0));
	float board_id = floor(p.y * 1.6);
	float plank = 0.93 + hash(vec2(board_id, 4.0)) * 0.11;
	float edge = min(fract(p.y * 1.6), 1.0 - fract(p.y * 1.6));
	float seam = mix(0.9, 1.0, smoothstep(0.0, 0.007, edge));
	ALBEDO = wood_color.rgb * (0.95 + grain * 0.012 + fibers * 0.04) * plank * seam;
	ROUGHNESS = 0.8;
}
