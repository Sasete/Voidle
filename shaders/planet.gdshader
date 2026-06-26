shader_type canvas_item;

uniform float rotation_offset    : hint_range(0.0, 6.2832) = 0.0;
uniform float cloud_speed        : hint_range(0.0, 2.0)    = 0.05;
uniform float cloud_coverage     : hint_range(0.0, 1.0)    = 0.5;
uniform float has_clouds         : hint_range(0.0, 1.0)    = 1.0;
uniform float atmosphere_density : hint_range(0.0, 3.0)    = 1.0;
uniform float terrain_roughness  : hint_range(0.2, 2.0)    = 1.0;
uniform float sea_level          : hint_range(-0.5, 0.5)   = 0.0;
uniform float planet_radius      : hint_range(0.1, 0.5)    = 0.42;
uniform float pixel_count        : hint_range(32.0, 512.0) = 140.0;
uniform float aspect_ratio       : hint_range(0.1, 4.0)    = 1.0;
uniform int   seed               : hint_range(0, 99999)    = 12345;

uniform vec3 color_deep_ocean = vec3(0.05, 0.13, 0.30);
uniform vec3 color_ocean      = vec3(0.08, 0.20, 0.46);
uniform vec3 color_shallow    = vec3(0.12, 0.33, 0.50);
uniform vec3 color_sand       = vec3(0.52, 0.46, 0.26);
uniform vec3 color_grass      = vec3(0.18, 0.40, 0.15);
uniform vec3 color_forest     = vec3(0.09, 0.26, 0.11);
uniform vec3 color_mountain   = vec3(0.36, 0.32, 0.26);
uniform vec3 color_snow       = vec3(0.86, 0.89, 0.93);
uniform vec3 color_cloud      = vec3(0.86, 0.89, 0.94);
uniform vec3 color_atmosphere = vec3(0.26, 0.50, 0.90);

vec2 hash2(vec2 p) {
	float s = float(seed) * 0.001;
	p = vec2(dot(p, vec2(127.1 + s, 311.7)), dot(p, vec2(269.5 + s, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dot(hash2(i),           f),
	               dot(hash2(i+vec2(1,0)), f-vec2(1,0)), u.x),
	           mix(dot(hash2(i+vec2(0,1)), f-vec2(0,1)),
	               dot(hash2(i+vec2(1,1)), f-vec2(1,1)), u.x), u.y);
}
float fbm(vec2 p, int oct) {
	float v=0.0, a=0.5, f=1.0;
	for (int i=0;i<oct;i++){v+=a*noise(p*f);f*=2.0;a*=0.5;}
	return v;
}

void fragment() {
	vec2 uv = floor(UV * pixel_count) / pixel_count;
	vec2 c  = uv - vec2(0.5);
	c.x    *= aspect_ratio;
	float dist = length(c);
	float atmo = planet_radius + 0.020;

	if (dist > atmo) {
		COLOR = vec4(0.0);
	} else if (dist > planet_radius) {
		float t = 1.0 - (dist - planet_radius) / 0.020;
		float g = pow(t, 2.5) * atmosphere_density;
		COLOR = vec4(color_atmosphere * g * 0.5, clamp(g * 0.42, 0.0, 1.0));
	} else {
		float nx = c.x / planet_radius;
		float ny = c.y / planet_radius;
		float nz = sqrt(max(0.0, 1.0 - nx*nx - ny*ny));
		vec3  n  = normalize(vec3(nx, ny, nz));

		float lon = atan(nx, nz) + rotation_offset;
		float lat = asin(clamp(ny, -1.0, 1.0));

		// fract → always [0,1), eliminates the ±π seam
		vec2 suv = vec2(fract(lon / 6.2832), lat / 3.1416 + 0.5);

		// sea_level shifts the h boundary: positive = more land, negative = more ocean
		float h = fbm(suv * 3.2 * terrain_roughness + vec2(float(seed) * 0.013), 7) - sea_level;

		vec3 surf;
		if      (h < -0.12) { surf = color_deep_ocean; }
		else if (h <  0.00) { surf = mix(color_deep_ocean, color_ocean,   (h+0.12)/0.12); }
		else if (h <  0.07) { surf = mix(color_ocean,      color_shallow,  h/0.07); }
		else if (h <  0.12) { surf = mix(color_shallow,    color_sand,    (h-0.07)/0.05); }
		else if (h <  0.26) { surf = mix(color_grass,      color_forest,  (h-0.12)/0.14); }
		else if (h <  0.38) { surf = mix(color_forest,     color_mountain,(h-0.26)/0.12); }
		else                 { surf = mix(color_mountain,   color_snow,    clamp((h-0.38)/0.10,0.,1.)); }

		float polar = abs(lat) / (PI * 0.5);
		float ice   = smoothstep(0.78, 0.94, polar);
		surf = mix(surf, color_snow * 0.95, ice);

		surf += vec3(fbm(suv*14.0+vec2(5.1),2)*0.04 - 0.02);

		// clouds with same seam fix
		float clon = atan(nx, nz) + rotation_offset + TIME * cloud_speed;
		vec2  cuv  = vec2(fract(clon / 6.2832), lat / 3.1416 + 0.5);
		float cv   = fbm(cuv * 4.0 + vec2(float(seed)*0.007+33.0), 6);
		float cloud_thresh = mix(0.46, 0.20, cloud_coverage);
		float cm   = smoothstep(cloud_thresh, cloud_thresh + 0.18, cv)
		             * (1.0 - smoothstep(0.80, 0.95, polar))
		             * has_clouds;
		surf = mix(surf, color_cloud, cm * 0.85);

		vec3  ld   = normalize(vec3(0.6, -0.55, 0.65));
		float diff = max(dot(n, ld), 0.0);
		float lit  = smoothstep(0.0, 0.45, diff);
		surf *= 0.07 + 0.93 * lit;

		if (h < 0.07) {
			vec3  hv   = normalize(ld + vec3(0,0,1));
			float spec = pow(max(dot(n, hv), 0.0), 28.0) * (1.0 - cm);
			surf += vec3(spec * 0.30 * lit);
		}

		COLOR = vec4(clamp(surf, vec3(0.0), vec3(1.0)), 1.0);
	}
}
