shader_type canvas_item;

uniform float rotation_offset : hint_range(0.0, 6.2832) = 0.0;
uniform float planet_radius   : hint_range(0.05, 0.45)  = 0.18;
uniform float pixel_count     : hint_range(32.0, 512.0) = 140.0;
uniform float aspect_ratio    : hint_range(0.1, 4.0)    = 1.0;
uniform float elongation      : hint_range(0.6, 2.2)    = 1.4;
uniform float irregularity    : hint_range(0.0, 1.0)    = 0.4;
uniform float terrain_roughness : hint_range(0.5, 2.0)  = 1.3;
uniform int   seed             : hint_range(0, 99999)   = 12345;

uniform vec3 color_rock_dark  = vec3(0.18, 0.16, 0.14);
uniform vec3 color_rock_mid   = vec3(0.32, 0.28, 0.24);
uniform vec3 color_rock_light = vec3(0.50, 0.45, 0.38);

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

// Irregular silhouette: bumps along the edge circle
float silhouette_bump(float angle) {
	float b  = sin(angle * 2.0 + float(seed) * 0.3) * 0.18 * irregularity;
	b += sin(angle * 3.7 + float(seed) * 1.1) * 0.12 * irregularity;
	b += sin(angle * 6.3 + float(seed) * 2.3) * 0.07 * irregularity;
	b += sin(angle * 11.0 + float(seed) * 0.7) * 0.04 * irregularity;
	return 1.0 + b;
}

void fragment() {
	vec2 uv = floor(UV * pixel_count) / pixel_count;
	vec2 c  = uv - vec2(0.5);
	c.x    *= aspect_ratio;

	float angle   = atan(c.y, c.x / elongation);
	float bump    = silhouette_bump(angle);
	float ell_d   = length(vec2(c.x / elongation, c.y));
	float shape_d = ell_d / (planet_radius * bump);

	if (shape_d > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// Use corrected sphere-like normal for lighting stability
		vec2 sn2  = vec2(c.x / (planet_radius * elongation), c.y / planet_radius);
		float snd = length(sn2);
		float snz = sqrt(max(0.0, 1.0 - snd * snd));
		vec3  n   = normalize(vec3(sn2, snz));

		vec3 rn = rot_y(n, rotation_offset);
		vec3 rp = rn * terrain_roughness;

		// single-toned rocky surface with subtle variation
		float h1 = fbm3(rp * 3.5, 5) * 0.5 + 0.5;
		vec3 surf = mix(color_rock_dark, color_rock_mid, smoothstep(0.35, 0.65, h1));
		// very subtle highlight from a second layer
		float h2 = fbm3(rp * 9.0, 3) * 0.5 + 0.5;
		surf = mix(surf, color_rock_light, smoothstep(0.72, 0.90, h2) * 0.30);

		// craters — dark floor, bright rim ring
		float cr_a = abs(fbm3(rp * 2.0, 4));
		float cr_b = abs(fbm3(rp * 5.0, 4));
		float crater_floor = smoothstep(0.16, 0.06, cr_a) + smoothstep(0.11, 0.04, cr_b) * 0.45;
		float crater_rim   = smoothstep(0.14, 0.18, cr_a) * smoothstep(0.22, 0.18, cr_a)
		                   + smoothstep(0.09, 0.12, cr_b) * smoothstep(0.15, 0.12, cr_b) * 0.5;
		surf = mix(surf, color_rock_dark * 0.4, clamp(crater_floor, 0.0, 1.0));
		surf = mix(surf, color_rock_light * 0.85, clamp(crater_rim, 0.0, 1.0));

		// lighting — strong directional
		vec3  ld   = normalize(vec3(0.6, -0.55, 0.65));
		float diff = max(dot(n, ld), 0.0);
		float lit  = smoothstep(0.0, 0.35, diff);
		surf *= 0.04 + 0.96 * lit;

		// soft edge fade
		float edge  = smoothstep(0.85, 1.0, shape_d);
		float alpha = 1.0 - edge;

		COLOR = vec4(clamp(surf, vec3(0.0), vec3(1.0)), alpha);
	}
}
