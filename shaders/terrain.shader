shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D terrain_atlas0;
uniform sampler2D terrain_atlas1;
uniform sampler2D terrain_atlas2;
uniform sampler2D terrain_atlas3;

uniform sampler2D tile_scale_tex;
uniform float tile_scale_count;

/* ---- 6 RGB splat textures ---- */
uniform sampler2D splat0;
uniform sampler2D splat1;
uniform sampler2D splat2;
uniform sampler2D splat3;
uniform sampler2D splat4;
uniform sampler2D splat5;

uniform vec2 map_size;
uniform float blend_step = 0.04;
uniform int active_blocks = 1;
uniform bool smoothblending = false;

varying vec2 world_uv;

/* ---------------- HELPERS ---------------- */

vec2 get_tile_scale(float tile_index)
{
	float u = (tile_index + 0.5) / tile_scale_count;
	return texture(tile_scale_tex, vec2(u, 0.5)).rg;
}

vec2 tile_uv(vec2 uv, float index)
{
	vec2 scale = get_tile_scale(index);
	return fract(uv / scale);
}

vec2 atlas_uv(vec2 uv, float index)
{
	vec2 tile_size = vec2(0.5, 0.5);

	float local_idx = mod(index, 4.0);
	float x = mod(local_idx, 2.0);
	float y = floor(local_idx / 2.0);

	return uv * tile_size + vec2(x, y) * tile_size;
}

vec4 sample_atlas(vec2 uv, float index)
{
	vec2 final_uv = atlas_uv(uv, index);
	float atlas_index = floor(index / 4.0);

	if (atlas_index < 0.5) return texture(terrain_atlas0, final_uv);
	if (atlas_index < 1.5) return texture(terrain_atlas1, final_uv);
	if (atlas_index < 2.5) return texture(terrain_atlas2, final_uv);
	return texture(terrain_atlas3, final_uv);
}

/* ---- Fetch layer weight from packed RGB splats ---- */

float get_layer_weight(int layer, vec2 uv)
{
	int tex_index = layer / 3;
	int comp = layer % 3;

	vec3 data;

	if (tex_index == 0) data = texture(splat0, uv).rgb;
	else if (tex_index == 1) data = texture(splat1, uv).rgb;
	else if (tex_index == 2) data = texture(splat2, uv).rgb;
	else if (tex_index == 3) data = texture(splat3, uv).rgb;
	else if (tex_index == 4) data = texture(splat4, uv).rgb;
	else data = texture(splat5, uv).rgb;

	if (comp == 0) return data.r;
	if (comp == 1) return data.g;
	return data.b;
}

vec4 accum_texture(vec2 uv, float index, float splat_val, float hmax)
{
	vec4 t = sample_atlas(tile_uv(uv, index), index);

	float w;
	if (smoothblending)
		w = max(splat_val, 0.0);
	else
		w = max(t.a * splat_val - hmax, 0.0);

	return vec4(t.rgb * w, w);
}

/* ---------------- MAIN ---------------- */

void vertex()
{
	world_uv = VERTEX;
}

void fragment()
{
	vec2 splat_uv = world_uv / map_size;

	float hmax = 0.0;

	/* ========= PASS 1: GLOBAL HMAX ========= */

	if (!smoothblending)
	{
		for (int i = 0; i < 16; i++)
		{
			if (i >= active_blocks * 4) break;

			float weight = get_layer_weight(i, splat_uv);
			vec4 tex = sample_atlas(tile_uv(world_uv, float(i)), float(i));
			hmax = max(hmax, tex.a * weight);
		}

		hmax -= blend_step;
	}

	/* ========= PASS 2: ACCUMULATE ========= */

	vec3 color = vec3(0.0);
	float total = 0.0;

	for (int i = 0; i < 16; i++)
	{
		if (i >= active_blocks * 4) break;

		float weight = get_layer_weight(i, splat_uv);
		vec4 r = accum_texture(world_uv, float(i), weight, hmax);

		color += r.rgb;
		total += r.a;
	}

	if (total < 0.001)
	{
		COLOR = vec4(0.0,0.0,1.0,1.0);
	}
	else
	{
		COLOR = vec4(color / (total + 0.0001), 1.0);
	}

	
}
