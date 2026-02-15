shader_type canvas_item;
render_mode unshaded, blend_disabled;

/* ----------- SPLATS (RGB only) ----------- */
uniform sampler2D splat0 : hint_albedo;
uniform sampler2D splat1 : hint_albedo;
uniform sampler2D splat2 : hint_albedo;
uniform sampler2D splat3 : hint_albedo;
uniform sampler2D splat4 : hint_albedo;
uniform sampler2D splat5 : hint_albedo;

uniform int num_active_terrain_slots;

/* ----------- BRUSH ----------- */
uniform sampler2D brush_texture;

uniform vec2 brush_position;  // In pixel coordinates
uniform vec2 brush_size;      // In pixels
uniform float paint_rate;     // 0.0 to 1.0
uniform int target_channel;   // 0–15
uniform int output_splat;     // 0–5
uniform vec2 splat_map_size;  // Width, height in pixels

/* ----------- MAIN ----------- */
void fragment() {
	vec2 pixel_pos = UV * splat_map_size;
	vec2 brush_uv = (pixel_pos - brush_position) / brush_size + 0.5;

	float weight = 0.0;
	if (brush_uv.x >= 0.0 && brush_uv.x <= 1.0 && brush_uv.y >= 0.0 && brush_uv.y <= 1.0) {
		weight = texture(brush_texture, brush_uv).a;
	}

	/* ----------- Read current splats ----------- */
	vec3 s0 = texture(splat0, UV).rgb;
	vec3 s1 = texture(splat1, UV).rgb;
	vec3 s2 = texture(splat2, UV).rgb;
	vec3 s3 = texture(splat3, UV).rgb;
	vec3 s4 = texture(splat4, UV).rgb;
	vec3 s5 = texture(splat5, UV).rgb;

	vec4 output_color;

	if (weight < 0.001) {
		// No brush influence, just show the splat
		if (output_splat == 0) output_color = vec4(s0, 1.0);
		else if (output_splat == 1) output_color = vec4(s1, 1.0);
		else if (output_splat == 2) output_color = vec4(s2, 1.0);
		else if (output_splat == 3) output_color = vec4(s3, 1.0);
		else if (output_splat == 4) output_color = vec4(s4, 1.0);
		else output_color = vec4(s5.r, 0.0, 0.0, 1.0);
	} else {
		// Brush influence
		float change = paint_rate * weight;

		// Pack 16 channels manually
		float c0  = s0.r; float c1  = s0.g; float c2  = s0.b;
		float c3  = s1.r; float c4  = s1.g; float c5  = s1.b;
		float c6  = s2.r; float c7  = s2.g; float c8  = s2.b;
		float c9  = s3.r; float c10 = s3.g; float c11 = s3.b;
		float c12 = s4.r; float c13 = s4.g; float c14 = s4.b;
		float c15 = s5.r; // last slot only uses R


		// Always include channels up to and including the target channel
		float total = c0+c1+c2+c3+c4+c5+c6+c7+c8+c9+c10+c11;

		if (num_active_terrain_slots > 12) {
			total += c12+c13+c14+c15;
		}

		float old_value;
		float new_value;

		// Update target channel
		if (target_channel == 0) old_value = c0;
		else if (target_channel == 1) old_value = c1;
		else if (target_channel == 2) old_value = c2;
		else if (target_channel == 3) old_value = c3;
		else if (target_channel == 4) old_value = c4;
		else if (target_channel == 5) old_value = c5;
		else if (target_channel == 6) old_value = c6;
		else if (target_channel == 7) old_value = c7;
		else if (target_channel == 8) old_value = c8;
		else if (target_channel == 9) old_value = c9;
		else if (target_channel == 10) old_value = c10;
		else if (target_channel == 11) old_value = c11;
		else if (target_channel == 12) old_value = c12;
		else if (target_channel == 13) old_value = c13;
		else if (target_channel == 14) old_value = c14;
		else old_value = c15;

		new_value = clamp(old_value + change, 0.0, 1.0);
		if (total < 1.0) {
			float deficit = 1.0 - total;
			new_value = clamp(old_value + max(change, deficit), 0.0, 1.0);
		}

		float actual_change = new_value - old_value;

		// Apply new value to the target channel
		if (target_channel == 0) c0 = new_value;
		else if (target_channel == 1) c1 = new_value;
		else if (target_channel == 2) c2 = new_value;
		else if (target_channel == 3) c3 = new_value;
		else if (target_channel == 4) c4 = new_value;
		else if (target_channel == 5) c5 = new_value;
		else if (target_channel == 6) c6 = new_value;
		else if (target_channel == 7) c7 = new_value;
		else if (target_channel == 8) c8 = new_value;
		else if (target_channel == 9) c9 = new_value;
		else if (target_channel == 10) c10 = new_value;
		else if (target_channel == 11) c11 = new_value;
		else if (target_channel == 12) c12 = new_value;
		else if (target_channel == 13) c13 = new_value;
		else if (target_channel == 14) c14 = new_value;
		else c15 = new_value;

		// Scale other channels proportionally
		float reduction_ratio = (1.0 - new_value)/(total - old_value);
		if (target_channel != 0) c0 *= reduction_ratio;
		if (target_channel != 1) c1 *= reduction_ratio;
		if (target_channel != 2) c2 *= reduction_ratio;
		if (target_channel != 3) c3 *= reduction_ratio;
		if (target_channel != 4) c4 *= reduction_ratio;
		if (target_channel != 5) c5 *= reduction_ratio;
		if (target_channel != 6) c6 *= reduction_ratio;
		if (target_channel != 7) c7 *= reduction_ratio;
		if (target_channel != 8) c8 *= reduction_ratio;
		if (target_channel != 9) c9 *= reduction_ratio;
		if (target_channel != 10) c10 *= reduction_ratio;
		if (target_channel != 11) c11 *= reduction_ratio;
		if (target_channel != 12) c12 *= reduction_ratio;
		if (target_channel != 13) c13 *= reduction_ratio;
		if (target_channel != 14) c14 *= reduction_ratio;
		if (target_channel != 15) c15 *= reduction_ratio;

		// Output the requested splat
		if (output_splat == 0) output_color = vec4(c0, c1, c2, 1.0);
		else if (output_splat == 1) output_color = vec4(c3, c4, c5, 1.0);
		else if (output_splat == 2) output_color = vec4(c6, c7, c8, 1.0);
		else if (output_splat == 3) output_color = vec4(c9, c10, c11, 1.0);
		else if (output_splat == 4) output_color = vec4(c12, c13, c14, 1.0);
		else output_color = vec4(c15, 0.0, 0.0, 1.0);
	}

	COLOR = output_color;
}
