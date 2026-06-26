shader_type canvas_item;

uniform float star_radius    : hint_range(0.04, 0.46) = 0.13;
uniform float pixel_count    : hint_range(32.0, 256.0) = 96.0;
uniform float aspect_ratio   : hint_range(0.1, 4.0)   = 1.0;
uniform float corona_size    : hint_range(0.02, 0.40)  = 0.18;
uniform float flicker_speed  : hint_range(0.0, 2.0)   = 0.35;
uniform int   seed            : hint_range(0, 99999)   = 42;

uniform vec3 color_core    = vec3(1.0, 0.98, 0.90);
uniform vec3 color_surface = vec3(1.0, 0.78, 0.30);
uniform vec3 color_corona  = vec3(1.0, 0.45, 0.08);

vec3 hash3s(vec3 p, int s) {
	float fs = float(s) * 0.001;
	p = vec3(dot(p, vec3(127.1+fs,311.7,74.7)),
	         dot(p, vec3(269.5+fs,183.3,246.1)),
	         dot(p, vec3(113.5,271.9,124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}
float noise3s(vec3 p, int s) {
	vec3 i=floor(p); vec3 f=fract(p); vec3 u=f*f*(3.0-2.0*f);
	return mix(mix(mix(dot(hash3s(i,s),f),
	                   dot(hash3s(i+vec3(1,0,0),s),f-vec3(1,0,0)),u.x),
	               mix(dot(hash3s(i+vec3(0,1,0),s),f-vec3(0,1,0)),
	                   dot(hash3s(i+vec3(1,1,0),s),f-vec3(1,1,0)),u.x),u.y),
	           mix(mix(dot(hash3s(i+vec3(0,0,1),s),f-vec3(0,0,1)),
	                   dot(hash3s(i+vec3(1,0,1),s),f-vec3(1,0,1)),u.x),
	               mix(dot(hash3s(i+vec3(0,1,1),s),f-vec3(0,1,1)),
	                   dot(hash3s(i+vec3(1,1,1),s),f-vec3(1,1,1)),u.x),u.y),u.z);
}
float fbm3s(vec3 p, int oct, int s) {
	float v=0.0,a=0.5,f=1.0;
	for(int i=0;i<oct;i++){v+=a*noise3s(p*f,s);f*=2.0;a*=0.5;}
	return v;
}

void fragment() {
	vec2 uv  = floor(UV * pixel_count) / pixel_count;
	vec2 c   = uv - vec2(0.5);
	c.x     *= aspect_ratio;
	float d  = length(c);
	float maxr = star_radius + corona_size;

	if (d > maxr) {
		COLOR = vec4(0.0);
	} else if (d > star_radius) {
		// corona — soft glow with angular flicker
		float t     = 1.0 - (d - star_radius) / corona_size;
		float angle = atan(c.y, c.x);
		float flk   = fbm3s(vec3(cos(angle)*3.0, sin(angle)*3.0, TIME * flicker_speed), 3, seed);
		float bright = t * t * (0.85 + flk * 0.22);
		COLOR = vec4(color_corona * bright, bright * t * 0.92);
	} else {
		// star sphere
		float nx = c.x / star_radius;
		float ny = c.y / star_radius;
		float nz = sqrt(max(0.0, 1.0 - nx*nx - ny*ny));
		vec3  n  = vec3(nx, ny, nz);

		// solar granulation (slow drift)
		vec3 sn    = n + vec3(TIME * flicker_speed * 0.05, 0.0, 0.0);
		float gran  = fbm3s(sn * 5.0, 5, seed);
		float gran2 = fbm3s(sn * 14.0 + vec3(47.0, 0, 0), 3, seed);

		// limb darkening
		float limb = sqrt(max(nz, 0.0));

		// sunspots
		float spot = smoothstep(0.18, 0.10, abs(gran)) * (1.0 - smoothstep(0.65, 0.88, limb));

		vec3 surf = mix(color_surface, color_core, limb * 0.75 + gran2 * 0.12);
		surf = mix(surf * 0.45, surf, 1.0 - spot * 0.65);
		// edge corona bleed
		surf += color_corona * smoothstep(0.5, 0.0, nz) * 0.35;

		COLOR = vec4(clamp(surf, vec3(0.0), vec3(1.5)), 1.0);
	}
}
