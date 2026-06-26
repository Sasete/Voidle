shader_type canvas_item;

uniform float rotation_offset : hint_range(0.0, 6.2832) = 0.0;
uniform float planet_radius   : hint_range(0.1, 0.5)    = 0.32;
uniform float pixel_count     : hint_range(32.0, 512.0) = 140.0;
uniform float aspect_ratio    : hint_range(0.1, 4.0)    = 1.0;
uniform float terrain_roughness : hint_range(0.2, 2.0)  = 1.2;
uniform int   seed             : hint_range(0, 99999)   = 12345;

uniform vec3 color_highland = vec3(0.62, 0.60, 0.56);
uniform vec3 color_mare     = vec3(0.22, 0.21, 0.20);
uniform vec3 color_rim      = vec3(0.78, 0.76, 0.72);
uniform vec3 color_floor    = vec3(0.16, 0.15, 0.14);

vec3 hash3(vec3 p) {
	float s = float(seed) * 0.001;
	p = vec3(dot(p, vec3(127.1+s,311.7,74.7)),
	         dot(p, vec3(269.5+s,183.3,246.1)),
	         dot(p, vec3(113.5,271.9,124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}
float noise3(vec3 p) {
	vec3 i=floor(p); vec3 f=fract(p); vec3 u=f*f*(3.0-2.0*f);
	return mix(mix(mix(dot(hash3(i),             f),
	                   dot(hash3(i+vec3(1,0,0)), f-vec3(1,0,0)),u.x),
	               mix(dot(hash3(i+vec3(0,1,0)), f-vec3(0,1,0)),
	                   dot(hash3(i+vec3(1,1,0)), f-vec3(1,1,0)),u.x),u.y),
	           mix(mix(dot(hash3(i+vec3(0,0,1)), f-vec3(0,0,1)),
	                   dot(hash3(i+vec3(1,0,1)), f-vec3(1,0,1)),u.x),
	               mix(dot(hash3(i+vec3(0,1,1)), f-vec3(0,1,1)),
	                   dot(hash3(i+vec3(1,1,1)), f-vec3(1,1,1)),u.x),u.y),u.z);
}
float fbm3(vec3 p, int oct) {
	float v=0.0,a=0.5,f=1.0;
	for(int i=0;i<oct;i++){v+=a*noise3(p*f);f*=2.0;a*=0.5;}
	return v;
}
vec3 rot_y(vec3 p, float a) { float c=cos(a),s=sin(a); return vec3(p.x*c+p.z*s,p.y,-p.x*s+p.z*c); }

// crater SDF: returns (depth, rim_brightness)
vec2 crater(vec3 p, float scale, float seed_off) {
	vec3 sp = p * scale + vec3(seed_off, 0.0, 0.0);
	float n = noise3(sp);
	float d = abs(n);            // 0 = crater center/rim
	float depth  = -smoothstep(0.0, 0.18, d) + smoothstep(0.18, 0.05, d) * 0.6;
	float rim    = smoothstep(0.14, 0.18, d) * smoothstep(0.22, 0.18, d);
	return vec2(depth, rim);
}

void fragment() {
	vec2 uv = floor(UV * pixel_count) / pixel_count;
	vec2 c  = uv - vec2(0.5);
	c.x    *= aspect_ratio;
	float dist = length(c);

	if (dist > planet_radius) {
		COLOR = vec4(0.0);
	} else {
		float nx = c.x / planet_radius;
		float ny = c.y / planet_radius;
		float nz = sqrt(max(0.0, 1.0 - nx*nx - ny*ny));
		vec3  n  = normalize(vec3(nx, ny, nz));
		vec3  rn = rot_y(n, rotation_offset);
		vec3  rp = rn * terrain_roughness;

		// mare regions (dark basalt plains)
		float mare_n = fbm3(rp * 1.8, 4);
		float mare_mask = smoothstep(0.05, -0.08, mare_n);

		// craters at 3 scales
		vec2 c_large  = crater(rp, 2.5,  0.0);
		vec2 c_medium = crater(rp, 5.5,  13.7);
		vec2 c_small  = crater(rp, 12.0, 33.1);
		vec2 c_tiny   = crater(rp, 24.0, 71.4);

		float total_depth = c_large.x * 0.5
		                  + c_medium.x * 0.3
		                  + c_small.x  * 0.15
		                  + c_tiny.x   * 0.05;
		float total_rim   = c_large.y * 0.7
		                  + c_medium.y * 0.5
		                  + c_small.y  * 0.3
		                  + c_tiny.y   * 0.2;

		// highland base with fine regolith
		float regolith = fbm3(rp * 8.0, 4);
		vec3 surf = mix(color_highland, color_mare, mare_mask);
		surf = mix(surf, surf * 0.85, regolith * 0.3);

		// apply craters: dark floor, bright rim
		surf = mix(surf, color_floor, clamp(-total_depth, 0.0, 1.0));
		surf = mix(surf, color_rim,   clamp(total_rim, 0.0, 1.0) * (1.0 - mare_mask * 0.8));

		// lighting — no atmosphere, sharp terminator
		vec3  ld   = normalize(vec3(0.6, -0.55, 0.65));
		float diff = max(dot(n, ld), 0.0);
		float lit  = smoothstep(0.0, 0.25, diff);
		surf *= 0.04 + 0.96 * lit;

		COLOR = vec4(clamp(surf, vec3(0.0), vec3(1.0)), 1.0);
	}
}
