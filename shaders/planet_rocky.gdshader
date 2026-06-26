shader_type canvas_item;

uniform float rotation_offset    : hint_range(0.0, 6.2832) = 0.0;
uniform float cloud_speed        : hint_range(0.0, 2.0)    = 0.12;
uniform float cloud_coverage     : hint_range(0.0, 1.0)    = 0.5;
uniform float has_clouds         : hint_range(0.0, 1.0)    = 1.0;
uniform float atmosphere_density : hint_range(0.0, 3.0)    = 1.0;
uniform float terrain_roughness  : hint_range(0.2, 2.0)    = 1.0;
uniform float continent_scale    : hint_range(0.2, 3.0)    = 1.0;  // low=big continents, high=islands
uniform float sea_level          : hint_range(-0.5, 0.5)   = 0.0;
uniform float specular_strength  : hint_range(0.0, 1.0)    = 1.0;
uniform float city_lights        : hint_range(0.0, 1.0)    = 0.6;  // night city glow intensity
uniform float planet_radius      : hint_range(0.1, 0.5)    = 0.42;
uniform float pixel_count        : hint_range(32.0, 512.0) = 140.0;
uniform float aspect_ratio       : hint_range(0.1, 4.0)    = 1.0;
uniform int   seed               : hint_range(0, 99999)    = 12345;

// POI city light hotspots (world-space sphere normals + intensity)
uniform vec4 poi_lights_0 = vec4(0.0);
uniform vec4 poi_lights_1 = vec4(0.0);
uniform vec4 poi_lights_2 = vec4(0.0);
uniform vec4 poi_lights_3 = vec4(0.0);
uniform vec4 poi_lights_4 = vec4(0.0);
uniform int  poi_count    = 0;

uniform vec3 light_direction = vec3(0.6, -0.55, 0.65);

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
	float dist = length(c);
	float atmo = planet_radius + 0.028;

	if (dist > atmo) {
		COLOR = vec4(0.0);
	} else if (dist > planet_radius) {
		// atmosphere ring — always visible regardless of clouds
		float t = 1.0 - (dist - planet_radius) / 0.028;
		float g = pow(t, 2.0) * atmosphere_density;
		COLOR = vec4(color_atmosphere * g * 0.65, clamp(g * 0.55, 0.0, 1.0));
	} else {
		float nx = c.x / planet_radius;
		float ny = c.y / planet_radius;
		float nz = sqrt(max(0.0, 1.0 - nx*nx - ny*ny));
		vec3  n  = normalize(vec3(nx, ny, nz));
		float lat = asin(clamp(ny, -1.0, 1.0));

		vec3 rn = rot_y(n, rotation_offset);

		// continent_scale: low = big features (fewer, larger continents)
		float h = fbm3(rn * 3.2 * continent_scale * terrain_roughness, 7) - sea_level;

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
		surf += vec3(fbm3(rn * 14.0, 2) * 0.04 - 0.02);

		// clouds — auto-rotate with TIME (always animating)
		vec3 crn = rot_y(n, rotation_offset + TIME * cloud_speed);
		float cv  = fbm3(crn * 3.5 + vec3(73.1, float(seed)*0.007, 0.0), 6);
		float ct  = mix(0.30, 0.08, cloud_coverage);
		float cm  = smoothstep(ct, ct + 0.14, cv)
		            * (1.0 - smoothstep(0.80, 0.96, polar))
		            * has_clouds;
		surf = mix(surf, color_cloud, cm * 0.90);

		// lighting
		vec3  ld   = normalize(light_direction);
		float diff = max(dot(n, ld), 0.0);
		float lit  = smoothstep(0.0, 0.45, diff);
		surf *= 0.07 + 0.93 * lit;

		// ocean specular (controlled by specular_strength)
		if (h < 0.07) {
			vec3  hv   = normalize(ld + vec3(0,0,1));
			float spec = pow(max(dot(n, hv), 0.0), 28.0) * (1.0 - cm);
			surf += vec3(spec * 0.30 * lit * specular_strength);
		}

		// city lights: POI-based, world-space cells (rotate with terrain)
		float night = smoothstep(0.15, 0.0, diff);
		if (night > 0.0 && city_lights > 0.0 && poi_count > 0) {
			// gaussian density from each POI
			float poi_density = 0.0;
			float spread = 28.0;
			if (poi_count > 0) poi_density += exp(-dot(rn-poi_lights_0.xyz, rn-poi_lights_0.xyz) * spread) * poi_lights_0.w;
			if (poi_count > 1) poi_density += exp(-dot(rn-poi_lights_1.xyz, rn-poi_lights_1.xyz) * spread) * poi_lights_1.w;
			if (poi_count > 2) poi_density += exp(-dot(rn-poi_lights_2.xyz, rn-poi_lights_2.xyz) * spread) * poi_lights_2.w;
			if (poi_count > 3) poi_density += exp(-dot(rn-poi_lights_3.xyz, rn-poi_lights_3.xyz) * spread) * poi_lights_3.w;
			if (poi_count > 4) poi_density += exp(-dot(rn-poi_lights_4.xyz, rn-poi_lights_4.xyz) * spread) * poi_lights_4.w;
			poi_density = clamp(poi_density, 0.0, 1.0);

			if (poi_density > 0.003) {
				float land = smoothstep(0.04, 0.12, h);
				float pop  = poi_density * land * (1.0 - cm * 0.65);

				// world-space cell — K=30 → ~3-4 screen pixels per dot → stable during rotation
				float K   = 30.0;
				vec3  wc  = floor(rn * K + float(seed) * 0.01);
				float cr  = fract(sin(dot(wc.xy, vec2(127.1, 311.7)) + wc.z * 74.7) * 43758.5453);
				float cr2 = fract(cr * 7.3517 + 0.5);

				float is_bright = step(1.0 - clamp(pop * 0.22, 0.0, 0.55), cr);
				float is_dim    = step(1.0 - clamp(pop * 0.42, 0.0, 0.70), cr2) * (1.0 - is_bright);
				float dots      = is_bright + is_dim * 0.40;

				// soft haze underneath the dots
				float haze = clamp(pop * 0.55, 0.0, 0.25);
				vec3  lc   = vec3(0.72, 0.48, 0.14);

				surf = mix(surf, surf + lc * dots * 1.0 + lc * 0.28 * haze, night * city_lights * 0.80);
			}
		}

		COLOR = vec4(clamp(surf, vec3(0.0), vec3(1.0)), 1.0);
	}
}
