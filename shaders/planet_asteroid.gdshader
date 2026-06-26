shader_type canvas_item;

uniform float rotation_offset   : hint_range(0.0, 6.2832) = 0.0;
uniform float planet_radius     : hint_range(0.05, 0.4)   = 0.20;
uniform float pixel_count       : hint_range(32.0, 512.0) = 140.0;
uniform float aspect_ratio      : hint_range(0.1, 4.0)    = 1.0;
uniform float elongation        : hint_range(0.5, 2.5)    = 1.35;
uniform float irregularity      : hint_range(0.0, 1.0)    = 0.3;   // 0=round, 1=chaotic
uniform int   seed              : hint_range(0, 99999)    = 12345;

uniform vec3 color_rock_a   = vec3(0.32, 0.28, 0.24);
uniform vec3 color_rock_b   = vec3(0.22, 0.20, 0.17);
uniform vec3 color_highlight = vec3(0.48, 0.44, 0.38);

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

void fragment() {
	vec2 uv = floor(UV * pixel_count) / pixel_count;
	vec2 c  = uv - vec2(0.5);
	c.x    *= aspect_ratio;

	// irregular SDF: ellipse + noise bump on boundary
	vec2 ell = vec2(c.x / (planet_radius * elongation), c.y / planet_radius);
	float base_dist = length(ell);

	// bump the silhouette — more irregularity = bigger bumps
	float angle = atan(c.y, c.x);
	float bump_seed = float(seed) * 0.0001;
	float bump_amp = 0.10 + irregularity * 0.35;
	float bump_lo = noise3(vec3(cos(angle)*1.4, sin(angle)*1.4, bump_seed)) * bump_amp;
	float bump_hi = noise3(vec3(cos(angle)*4.0, sin(angle)*4.0, bump_seed+0.5)) * bump_amp * 0.4 * irregularity;
	float bump = 1.0 + bump_lo + bump_hi;
	float dist = base_dist / bump;

	if (dist > 1.0) {
		COLOR = vec4(0.0);
	} else {
		// fake normal from ellipse gradient + noise
		vec2 grad = ell / max(base_dist, 0.001);
		float nz  = sqrt(max(0.0, 1.0 - dot(grad, grad)));
		vec3  n   = normalize(vec3(grad, nz));

		vec3 rn = rot_y(n, rotation_offset);
		float h = fbm3(rn * 4.0, 6);
		vec3 surf = mix(color_rock_b, color_rock_a, h * 0.5 + 0.5);

		// craters
		float cr = fbm3(rn * 8.0, 4);
		float crater_mask = smoothstep(0.30, 0.36, abs(cr)) * smoothstep(0.42, 0.36, abs(cr));
		surf = mix(surf, color_rock_b * 0.7, crater_mask * 0.8);
		surf = mix(surf, color_highlight, crater_mask * 0.3);

		// detail
		surf += vec3(fbm3(rn*16.0, 3) * 0.05 - 0.025);

		// lighting
		vec3  ld   = normalize(vec3(0.6, -0.55, 0.65));
		float diff = max(dot(n, ld), 0.0);
		float lit  = smoothstep(0.0, 0.5, diff);
		surf *= 0.06 + 0.94 * lit;

		// soft edge
		float edge = smoothstep(0.95, 1.0, dist);
		float alpha = 1.0 - edge;

		COLOR = vec4(clamp(surf, vec3(0.0), vec3(1.0)), alpha);
	}
}
