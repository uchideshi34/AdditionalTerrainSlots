shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D terrain_atlas0;
uniform sampler2D terrain_atlas1;
uniform sampler2D terrain_atlas2;
uniform sampler2D terrain_atlas3;

uniform sampler2D tile_scale_tex;
uniform float tile_scale_count;

uniform sampler2D splat0;
uniform sampler2D splat1;
uniform sampler2D splat2;
uniform sampler2D splat3;

uniform vec2 map_size;
uniform float blend_step = 0.04;
uniform int active_blocks = 1; // 1..4

uniform bool smoothblending = false;

varying vec2 world_uv;

/* -------------------- HELPERS -------------------- */

vec2 get_tile_scale(float tile_index)
{
	float u = (tile_index + 0.5) / tile_scale_count;
	return texture(tile_scale_tex, vec2(u, 0.5)).rg;
}

vec2 tile_uv(vec2 uv, float index)
{
	vec2 scale = get_tile_scale(index);
	return fract(uv / scale);  // Returns 0..1 range, tiled
}

vec2 atlas_uv(vec2 uv, float index)
{
	// 2x2 grid within each atlas
	vec2 tile_size = vec2(0.5, 0.5);
	float local_idx = mod(index, 4.0);
	float x = mod(local_idx, 2.0);
	float y = floor(local_idx / 2.0);
	
	return uv * tile_size + vec2(x, y) * tile_size;
}

vec4 sample_atlas(vec2 uv, float index)
{
	vec2 final_uv = atlas_uv(uv, index);
	float splat_idx = floor(index / 4.0);
	
	if (splat_idx < 0.5) return texture(terrain_atlas0, final_uv);
	if (splat_idx < 1.5) return texture(terrain_atlas1, final_uv);
	if (splat_idx < 2.5) return texture(terrain_atlas2, final_uv);
	return texture(terrain_atlas3, final_uv);
}

vec4 accum_texture(vec2 uv, float index, float splat_val, float hmax)
{
	float w = 0.0;
	vec4 t = sample_atlas(tile_uv(uv, index), index);
	if (smoothblending) {
		w = max(splat_val, 0.0);
	}
	else {
		w = max(t.a * splat_val - hmax, 0.0);
	}
	return vec4(t.rgb * w, w);
}

/* -------------------- MAIN -------------------- */

void vertex()
{
	world_uv = VERTEX;
}

void fragment()
{
	vec2 splat_uv = world_uv / map_size;
	float hmax = 0.0;
	
	if (!smoothblending) {

		/* ========= PASS 1: GLOBAL HMAX ========= */

		if (active_blocks > 0) {
			vec4 s = texture(splat0, splat_uv);
			hmax = max(hmax, texture(terrain_atlas0, atlas_uv(tile_uv(world_uv, 0.0), 0.0)).a * s.r);
			hmax = max(hmax, texture(terrain_atlas0, atlas_uv(tile_uv(world_uv, 1.0), 1.0)).a * s.g);
			hmax = max(hmax, texture(terrain_atlas0, atlas_uv(tile_uv(world_uv, 2.0), 2.0)).a * s.b);
			hmax = max(hmax, texture(terrain_atlas0, atlas_uv(tile_uv(world_uv, 3.0), 3.0)).a * s.a);
		}

		if (active_blocks > 1) {
			vec4 s = texture(splat1, splat_uv);
			hmax = max(hmax, texture(terrain_atlas1, atlas_uv(tile_uv(world_uv, 4.0), 4.0)).a * s.r);
			hmax = max(hmax, texture(terrain_atlas1, atlas_uv(tile_uv(world_uv, 5.0), 5.0)).a * s.g);
			hmax = max(hmax, texture(terrain_atlas1, atlas_uv(tile_uv(world_uv, 6.0), 6.0)).a * s.b);
			hmax = max(hmax, texture(terrain_atlas1, atlas_uv(tile_uv(world_uv, 7.0), 7.0)).a * s.a);
		}

		if (active_blocks > 2) {
			vec4 s = texture(splat2, splat_uv);
			hmax = max(hmax, texture(terrain_atlas2, atlas_uv(tile_uv(world_uv, 8.0), 8.0)).a * s.r);
			hmax = max(hmax, texture(terrain_atlas2, atlas_uv(tile_uv(world_uv, 9.0), 9.0)).a * s.g);
			hmax = max(hmax, texture(terrain_atlas2, atlas_uv(tile_uv(world_uv,10.0),10.0)).a * s.b);
			hmax = max(hmax, texture(terrain_atlas2, atlas_uv(tile_uv(world_uv,11.0),11.0)).a * s.a);
		}

		if (active_blocks > 3) {
			vec4 s = texture(splat3, splat_uv);
			hmax = max(hmax, texture(terrain_atlas3, atlas_uv(tile_uv(world_uv,12.0),12.0)).a * s.r);
			hmax = max(hmax, texture(terrain_atlas3, atlas_uv(tile_uv(world_uv,13.0),13.0)).a * s.g);
			hmax = max(hmax, texture(terrain_atlas3, atlas_uv(tile_uv(world_uv,14.0),14.0)).a * s.b);
			hmax = max(hmax, texture(terrain_atlas3, atlas_uv(tile_uv(world_uv,15.0),15.0)).a * s.a);
		}

		hmax -= blend_step;
	}

	/* ========= PASS 2: ACCUMULATE ========= */

	vec3 color = vec3(0.0);
	float total = 0.0;

	if (active_blocks > 0) {
		vec4 s = texture(splat0, splat_uv);

		vec4 r;
		r = accum_texture(world_uv, 0.0, s.r, hmax); color += r.rgb; total += r.a;
		r = accum_texture(world_uv, 1.0, s.g, hmax); color += r.rgb; total += r.a;
		r = accum_texture(world_uv, 2.0, s.b, hmax); color += r.rgb; total += r.a;
		r = accum_texture(world_uv, 3.0, s.a, hmax); color += r.rgb; total += r.a;
	}

	if (active_blocks > 1) {
		vec4 s = texture(splat1, splat_uv);

		vec4 r;
		r = accum_texture(world_uv, 4.0, s.r, hmax); color += r.rgb; total += r.a;
		r = accum_texture(world_uv, 5.0, s.g, hmax); color += r.rgb; total += r.a;
		r = accum_texture(world_uv, 6.0, s.b, hmax); color += r.rgb; total += r.a;
		r = accum_texture(world_uv, 7.0, s.a, hmax); color += r.rgb; total += r.a;
	}

	if (active_blocks > 2) {
		vec4 s = texture(splat2, splat_uv);

		vec4 r;
		r = accum_texture(world_uv, 8.0, s.r, hmax);  color += r.rgb; total += r.a;
		r = accum_texture(world_uv, 9.0, s.g, hmax);  color += r.rgb; total += r.a;
		r = accum_texture(world_uv,10.0, s.b, hmax);  color += r.rgb; total += r.a;
		r = accum_texture(world_uv,11.0, s.a, hmax);  color += r.rgb; total += r.a;
	}

	if (active_blocks > 3) {
		vec4 s = texture(splat3, splat_uv);

		vec4 r;
		r = accum_texture(world_uv,12.0, s.r, hmax);  color += r.rgb; total += r.a;
		r = accum_texture(world_uv,13.0, s.g, hmax);  color += r.rgb; total += r.a;
		r = accum_texture(world_uv,14.0, s.b, hmax);  color += r.rgb; total += r.a;
		r = accum_texture(world_uv,15.0, s.a, hmax);  color += r.rgb; total += r.a;
	}

	COLOR.rgb = color / (total + 0.0001);

}
