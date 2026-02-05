extends MeshInstance2D

var level = null
var splatImages = []
var splatTextures = []
var splat_is_modified = []
var store_splat_hashes = []

var textures = []
var width = 0
var height = 0

var brush_image = null
var brush_data: PoolByteArray = []
var brush_width = 0
var brush_height = 0

var first = true

var normalshader = null
var smoothshader = null


var terrain_atlases = []  # Array of 4 atlases (one per splat)
var terrain_atlas_tile_sizes = [] # tile size for the atlas allowing it to vary by atlas

var terrain_atlas_grid = Vector2.ZERO
var terrain_scales = []

var smoothblending = false
var num_splats = 0
var global = null


const BLOB_SIZE = 64.0
const BLOB_OFFSET = 32.0
const MAX_TEXTURE_PIXEL_SIZE = 2048 * 1.5 # Strictly speaking this isn't a hard max but 4096 is for 4 columns
const ALTAS_COLUMNS_NUMBER = 4
const NODE_NAME = "ExtraTerrain987234"

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 2

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <ExtraTerrain>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Loads an image texture from ResourceLoader if that is possible or direct from a file if not
func safe_load_texture(path: String) -> Texture:

	outputlog("safe_load_texture: " + str(path),2)

	var texture = null
	if ResourceLoader.exists(path):
		texture = ResourceLoader.load(path)
	else:
		var file = File.new()
		if file.file_exists(path):
			texture = load_runtime_image(path)
			if texture != null:
				texture.resource_path = path

	return texture

# Load an image from a file
func load_runtime_image(path: String) -> Texture:
	var img := Image.new()
	if img.load(path) != OK:
		return null

	var tex := ImageTexture.new()
	tex.create_from_image(img)
	return tex

# Forces the texture image to rgba8 as observed that some textures are not in this format and we need them all consistent for the terrain atlas
func ensure_rgba8(img: Image) -> Image:
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	return img

# Makes a dummy texture for the splatTextures so they are never not populated
func make_dummy_texture() -> ImageTexture:
	var img = Image.new()
	img.create(1, 1, false, Image.FORMAT_RGBA8)
	img.lock()
	img.set_pixel(0, 0, Color(1,0,0,1))
	img.unlock()

	var tex = ImageTexture.new()
	tex.create_from_image(img, ImageTexture.FLAG_MIPMAPS)
	return tex

# Debugging print statement
func print_pixel(img: Image, x, y):

	outputlog("print_pixel")

	img.lock()
	outputlog("pixel: " + str(x) + "," + str(y) + " value: " + str(img.get_pixel(x, y)))
	img.unlock()

func time_function_start(function_name: String) -> Dictionary:
	return {
		"name": function_name,
		"start": OS.get_ticks_msec()
	}

func time_function_end(data: Dictionary, log_level: int = 2):
	var print_this ="%s took: %.1f ms" % [data["name"], OS.get_ticks_msec() - data["start"]]
	outputlog(print_this,log_level)


func poolbytearray_to_string(arr: PoolByteArray) -> String:
	if arr.size() == 0:
		return "PoolByteArray(  )"
	
	var result = "PoolByteArray( "
	for i in range(arr.size()):
		if i > 0:
			result += ", "
		result += str(arr[i])
	result += " )"
	
	return result

func string_to_poolbytearray(s: String) -> PoolByteArray:
	var result = PoolByteArray()
	
	# Strip "PoolByteArray( " and " )"
	s = s.strip_edges()
	if s.begins_with("PoolByteArray("):
		s = s.substr(14)  # len("PoolByteArray(")
	if s.ends_with(")"):
		s = s.substr(0, s.length() - 1)
	
	s = s.strip_edges()
	if s == "":
		return result
	
	var parts = s.split(", ")
	for part in parts:
		result.append(int(part.strip_edges()))
	
	return result

#########################################################################################################
##
## _INIT FUNCTIONS
##
#########################################################################################################

# Init function
func _init(parent_level, woxelDimensions: Vector2):

	outputlog("_init: level: " + str(parent_level) + " size: " + str(woxelDimensions),0)

	width = int(woxelDimensions.x / BLOB_SIZE)
	height = int(woxelDimensions.y / BLOB_SIZE)
	update_mesh(woxelDimensions)
	level = parent_level
	level.add_child(self)
	self.name = NODE_NAME
	self.z_index = -498

	# Initialise splatimage
	textures = []
	add_splat()
	splatImages[0].fill(Color(1.0, 0.0, 0.0, 0.0))
	update_splats()
	var new_material = ShaderMaterial.new()
	self.material = new_material
	self.material.set_shader_param("map_size",woxelDimensions)

# Function to update the mesh to the World size
func update_mesh(woxelDimensions: Vector2):

	var width = woxelDimensions.x
	var height = woxelDimensions.y

	var new_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	# Vertices (top-left origin)
	arrays[Mesh.ARRAY_VERTEX] = PoolVector2Array([
		Vector2(0, 0),           # Top-left
		Vector2(width, 0),       # Top-right
		Vector2(width, height),  # Bottom-right
		Vector2(0, height)       # Bottom-left
	])

	# UVs
	arrays[Mesh.ARRAY_TEX_UV] = PoolVector2Array([
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(1, 1),
		Vector2(0, 1)
	])

	# Indices (two triangles)
	arrays[Mesh.ARRAY_INDEX] = PoolIntArray([
		0, 1, 2,
		0, 2, 3
	])

	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	self.mesh = new_mesh


#########################################################################################################
##
## SPLAT FUNCTIONS
##
#########################################################################################################

func add_splat():

	outputlog("add_splat",2)

	splatImages.append(SplatImage.new(num_splats))
	splatImages[num_splats].create(width, height, false, Image.FORMAT_RGBA8)
	splatImages[num_splats].fill(Color(0.0, 0.0, 0.0, 0.0))
	splatTextures.append(ImageTexture.new())
	splatTextures[num_splats].create_from_image(splatImages[num_splats], 4)
	textures.append_array([null,null,null,null])
	num_splats += 1
	splat_is_modified.append(true)
	update_splats()
	
func remove_splat():

	outputlog("remove_splat",2)

	splatImages.remove(splatImages.size()-1)
	splatTextures.remove(splatTextures.size()-1)
	splat_is_modified.append(splat_is_modified.size()-1)

	for _i in 4:
		textures.remove(textures.size()-1)
	
	num_splats -= 1
	update_splats()

func set_splat_number(target_number: int):

	outputlog("set_splat_number: " + str(target_number),2)

	if num_splats < target_number:
		for _i in target_number-num_splats:
			add_splat()
	if num_splats > target_number:
		for _i in num_splats-target_number:
			remove_splat()

# Updates the splat texture from the spla
func update_splats():

	outputlog("update_splats",3)

	for _i in num_splats:
		update_splat(_i)
	for _i in range(num_splats,4,1):
		material.set_shader_param("splat"+ str(_i), make_dummy_texture())

	material.set_shader_param("active_blocks", num_splats)

# Function to update only a single splat
func update_splat(index: int):

	outputlog("update_splat: " + str(index),3)
	var time_record = time_function_start("update_splat")

	if index < num_splats:
		splatTextures[index].create_from_image(splatImages[index], 4)
		material.set_shader_param("splat"+ str(index),splatTextures[index])
	
	time_function_end(time_record, 3)

func mark_splat_modified(splat_idx: int, modified: bool = true):

	if splat_idx < num_splats:
		splat_is_modified[splat_idx] = modified

func mark_all_splats_modified(modified: bool = true):

	for _i in splat_is_modified.size():
		mark_splat_modified(_i, modified)

func are_splats_modified() -> bool:

	for splat_idx in splat_is_modified.size():
		if splat_is_modified[splat_idx]:
			return true

	return false

#########################################################################################################
##
## CHANGE TERRAIN FUNCTIONS
##
#########################################################################################################

# Set texture at terrain slot
func set_terrain_texture(texture_path: String, index: int, update_atlas: bool = true):

	outputlog("set_terrain_texture: " + str(index),2)
	var time_record = time_function_start("set_terrain_texture")

	var texture = safe_load_texture(texture_path)

	if texture.get_width() > MAX_TEXTURE_PIXEL_SIZE || texture.get_width() > MAX_TEXTURE_PIXEL_SIZE:
		return

	if texture == null: return

	if index < textures.size():
		textures[index] = texture
		outputlog("setting: " + str(index) + " terrain: " + str(texture.resource_path),2)
	
	update_splat(int(index/4.0))
	if update_atlas:
		update_terrain_atlas()
	
	time_function_end(time_record)

# Fills in the splat maps with a single channel
func fill_channel(channel: int):

	outputlog("fill_channel: " + str(channel),2)

	for splatimg in splatImages:
		splatimg.fill_channel(channel)
	mark_all_splats_modified()
	update_splats()

# Function to paint terrain
func paint_terrain(mouse_position: Vector2, terrain_index: int, rate: float, brush_size: float):

	outputlog("paint_terrain: index " + str(terrain_index) + "target_splat: " + str(int(terrain_index/4.0)) + " rate: " + str(rate),3)
	if not is_equal_approx(brush_size, brush_width * 2.0):
		update_brush_data(brush_size)

	# Core paint function call noting this only calls the splatImage that controls the positive channel
	blend_towards_channel(mouse_position, terrain_index, rate)
	mark_all_splats_modified()
	update_splats()

func set_smoothblending(button_pressed: bool):

	outputlog("set_smoothblending: " + str(button_pressed),2)

	smoothblending = button_pressed
	material.set_shader_param("smoothblending", smoothblending)

#########################################################################################################
##
## BRUSH FUNCTIONS
##
#########################################################################################################

# Function to update the brush data to reflect the brush and its size
func update_brush_data(scale: float):

	var base_size = brush_image.get_size()
	var scaled_brush = Image.new()

	scaled_brush.copy_from(brush_image)
	scaled_brush.resize(base_size.x * scale * 2.0, base_size.y * scale * 2.0, Image.INTERPOLATE_LANCZOS)
	brush_data = scaled_brush.get_data()
	brush_width = scaled_brush.get_width()
	brush_height = scaled_brush.get_height()

#########################################################################################################
##
## FLAT IMAGE FUNCTIONS
##
#########################################################################################################

var terrain_viewport: Viewport
var terrain_sprite: Sprite
var is_terrain_baked: bool = false

func bake_terrain_to_texture():
	if is_terrain_baked:
		return
	
	outputlog("Baking terrain to static texture", 2)
	var time_record = time_function_start("bake_terrain_to_texture")
	
	# Create a viewport the size of your terrain
	terrain_viewport = Viewport.new()
	terrain_viewport.size = Vector2(width * BLOB_SIZE, height * BLOB_SIZE)
	terrain_viewport.render_target_update_mode = Viewport.UPDATE_ONCE
	terrain_viewport.render_target_v_flip = true
	
	# Add viewport to scene tree (required for rendering)
	self.add_child(terrain_viewport)
	
	# Clone this mesh into the viewport
	var mesh_copy = MeshInstance2D.new()
	mesh_copy.mesh = self.mesh
	mesh_copy.material = self.material
	mesh_copy.position = Vector2.ZERO  # Position at origin in viewport
	terrain_viewport.add_child(mesh_copy)
	
	# Force render (wait 2 frames)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	
	# Get the rendered texture
	var texture = terrain_viewport.get_texture()
	
	# Create a simple sprite to display it
	terrain_sprite = Sprite.new()
	terrain_sprite.texture = texture
	terrain_sprite.centered = false
	terrain_sprite.position = self.position
	terrain_sprite.z_index = self.z_index
	terrain_sprite.name = "BakedTerrain"
	
	# Add sprite to parent
	self.get_parent().add_child(terrain_sprite)
	
	# Hide the original mesh (keep it around in case you need to update)
	self.visible = false
	
	is_terrain_baked = true
	time_function_end(time_record)
	outputlog("Terrain baked successfully", 2)

# Call this when you want to update the terrain
func unbake_terrain():
	if not is_terrain_baked:
		return
	
	if terrain_sprite:
		terrain_sprite.queue_free()
		terrain_sprite = null
	
	if terrain_viewport:
		terrain_viewport.queue_free()
		terrain_viewport = null
	
	self.visible = true
	is_terrain_baked = false

#########################################################################################################
##
## TERRAIN ATLAS FUNCTIONS
##
#########################################################################################################

# Modified update function
func update_terrain_atlas(index: int = -1):
	outputlog("update_terrain_atlas", 2)
	var time_record = time_function_start("update_terrain_atlas")
	
	if index > -1 && index < textures.size():
		# Update only the affected atlas
		update_single_atlas(index)
	else:
		# Rebuild all atlases
		build_all_atlases()
	
	time_function_end(time_record)

# Build all atlases
func build_all_atlases():

	outputlog("build_all_atlases", 2)

	terrain_atlases.resize(4)
	
	for splat_idx in range(num_splats):
		build_single_atlas(splat_idx)
	
	# Set dummy textures for unused splats
	for splat_idx in range(num_splats, 4):
		terrain_atlases[splat_idx] = make_dummy_texture()
		material.set_shader_param("terrain_atlas" + str(splat_idx), terrain_atlases[splat_idx])
	
	# Update the terrain scales
	update_terrain_scales()

# Find the tile_size of an atlas
func get_atlas_tile_size(splat_idx: int) -> Vector2:

	outputlog("get_atlas_tile_size: " + str(splat_idx), 2)

	var max_size = Vector2.ZERO
	for local_idx in range(4):
		var tex_idx = splat_idx * 4 + local_idx
		if tex_idx >= textures.size() or textures[tex_idx] == null:
			continue
		var tex = textures[tex_idx]
		if tex.get_size().x > max_size.x:
			max_size.x = tex.get_size().x
		if tex.get_size().y > max_size.y:
			max_size.y = tex.get_size().y
	
	return max_size

# Build a single atlas
func build_single_atlas(splat_idx: int):

	outputlog("build_single_atlas: " + str(splat_idx), 2)

	var tile_size = get_atlas_tile_size(splat_idx)
	terrain_atlas_tile_sizes[splat_idx] = tile_size

	var atlas_image = Image.new()
	atlas_image.create(int(tile_size.x) * 2, int(tile_size.y) * 2, false, Image.FORMAT_RGBA8)
	atlas_image.lock()
	
	# 2x2 grid for 4 textures
	for local_idx in range(4):
		var tex_idx = splat_idx * 4 + local_idx
		if tex_idx >= textures.size() or textures[tex_idx] == null:
			continue
		
		var tex = textures[tex_idx]
		var img = tex.get_data()
		img = ensure_rgba8(img)
		img.resize(int(tile_size.x), int(tile_size.y), Image.INTERPOLATE_LANCZOS)
		img.lock()
		
		var x = (local_idx % 2) * int(tile_size.x)
		var y = int(local_idx / 2) * int(tile_size.y)
		atlas_image.blit_rect(img, Rect2(Vector2.ZERO, tile_size), Vector2(x, y))
		img.unlock()
	
	atlas_image.unlock()
	
	var atlas_texture = ImageTexture.new()
	atlas_texture.create_from_image(atlas_image, Texture.FLAG_FILTER | Texture.FLAG_REPEAT)
	terrain_atlases[splat_idx] = atlas_texture
	material.set_shader_param("terrain_atlas" + str(splat_idx), atlas_texture)

# Update a single atlas - use when only a single terrain changes
func update_single_atlas(tex_idx: int):

	var splat_idx = int(tex_idx / 4)

	if tex_idx >= textures.size() or textures[tex_idx] == null:
		return
	
	# Get the altas tile size
	var tile_size = get_atlas_tile_size(splat_idx)
	# If it is bigger than the current version then we need to do a rebuild instead
	if terrain_atlas_tile_sizes[splat_idx].x < tile_size.x || terrain_atlas_tile_sizes[splat_idx].y < tile_size.y:
		build_single_atlas(splat_idx)
		update_terrain_scale(tex_idx)
		# We are done here 
		return

	var atlas_image = terrain_atlases[splat_idx].get_data()
	atlas_image.lock()
	
	var tex = textures[tex_idx]
	var img = tex.get_data()
	img = ensure_rgba8(img)
	img.resize(int(tile_size.x), int(tile_size.y), Image.INTERPOLATE_LANCZOS)
	img.lock()
	
	var x = (tex_idx % 2) * int(tile_size.x)
	var y = int(tex_idx / 2) * int(tile_size.y)
	atlas_image.blit_rect(img, Rect2(Vector2.ZERO, tile_size), Vector2(x, y))
	
	img.unlock()
	atlas_image.unlock()
	
	#terrain_atlases[splat_idx].create_from_image(atlas_image, Texture.FLAG_FILTER | Texture.FLAG_REPEAT)
	terrain_atlases[splat_idx].set_data(atlas_image)
	material.set_shader_param("terrain_atlas" + str(splat_idx), terrain_atlases[splat_idx])
	update_terrain_scale(tex_idx)

func update_terrain_scales():

	outputlog("update_terrain_scales",2)
	var time_record = time_function_start("update_terrain_scales")

	# Build scales array
	var max_size = Vector2.ZERO
	terrain_scales = []
	for _i in 4:
		if _i < num_splats:
			for _j in 4:
				if (_i * 4 + _j) < textures.size():
					var tex = textures[_i * 4 + _j]
					terrain_scales.append(get_texture_scale(tex))
				else:
					terrain_scales.append(Vector2.ONE)
		else:
			terrain_scales.append_array([Vector2.ONE,Vector2.ONE,Vector2.ONE,Vector2.ONE])
	
	# Encode it into a texture
	var scale_texture = build_tile_scale_texture(terrain_scales)
	material.set_shader_param("tile_scale_tex", scale_texture)
	material.set_shader_param("tile_scale_count", terrain_scales.size())
	time_function_end(time_record)

func update_terrain_scale(index: int):

	if index < textures.size():
		terrain_scales[index] = get_texture_scale(textures[index])
		var scale_texture = build_tile_scale_texture(terrain_scales)
		material.set_shader_param("tile_scale_tex", scale_texture)

# Build an image texture to hold the terrain scales
func build_tile_scale_texture(scales: Array) -> ImageTexture:
	var img = Image.new()
	img.create(scales.size(), 1, false, Image.FORMAT_RGBAF)
	img.lock()

	for i in range(scales.size()):
		var s = scales[i] # Vector2(width, height)
		img.set_pixel(i, 0, Color(s.x, s.y, 0, 0))

	img.unlock()

	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	tex.flags = 0
	return tex

# Get the terrain scale from a texture
func get_texture_scale(texture: Texture):

	var pixels_per_unit = 1.0
	if texture == null: return Vector2.ONE
	return Vector2(texture.get_width(), texture.get_height())

#########################################################################################################
##
## BLEND TOWARDS CHANNEL FUNCTIONS
##
#########################################################################################################


# Main blend towards channel algorithm
func blend_towards_channel(mouse_position: Vector2, channel: int, rate: float):

	outputlog("blend_towards_channel",3)
	var target_splat = splatImages[int(channel / 4.0)]

	# Load the byte data for all splats into a byte array
	refresh_all_splats_byte_data()

	# Mark splats as dirty 
	mark_splat_modified(target_splat)

	# Get the bounds of the brush
	first = true
	var min_position = (Vector2(mouse_position.x - 0.5 * brush_width, mouse_position.y - 0.5 * brush_height) / BLOB_SIZE).floor()
	var max_position = (Vector2(mouse_position.x + 0.5 * brush_width, mouse_position.y + 0.5 * brush_height) / BLOB_SIZE).floor()
	var min_location = Vector2(max(min_position.x,0), max(min_position.y,0))
	var max_location = Vector2(min(max_position.x, width), min(max_position.y, height))

	# For the splat locations within the brush range
	for _i in range(min_location.x, max_location.x, 1):
		for _j in range(min_location.y, max_location.y, 1):

			# Main change entry section
			#if first: print_complete_entry(_i, _j, "before change")
			var position_in_brush = (Vector2(_i, _j) - min_position) * BLOB_SIZE + BLOB_OFFSET * Vector2.ONE
			#if first: outputlog("position_in_brush: " + str(position_in_brush) + " brush_width: " + str(brush_width),2)
			var weighted_rate = rate * _get_weight_at_brush_position(brush_data, brush_width, position_in_brush)
			#outputlog("weighted_rate: " + str(_i) + "," + str(_j) + " : " + str(weighted_rate),2)
			#if first: outputlog("weighted_rate: " + str(weighted_rate),2)
			var change = _update_bytedata_with_blend(_i, _j, mouse_position / BLOB_SIZE, channel, weighted_rate)
			#if first:
			#	outputlog("change: at: " + str(_i) + ", " + str(_j) + " change: " + str(change),3)
			reduce_other_channels_by_value(_i, _j, channel, change)
			#if first: print_complete_entry(_i, _j, "final")
			if first:
				first = false
	
	# Take all the byte data and load it back into the splat image, then delete the byte data
	refresh_all_splats_images_from_byte_data()

# Gets the alpha value at the brush position 
func _get_weight_at_brush_position(brush_data: PoolByteArray, brush_width: int, position_in_brush: Vector2):

	if brush_data.size() == 0: return 1.0

	if position_in_brush.y < 0 || position_in_brush.x < 0: return 0.0

	var index = (int(position_in_brush.x) + int(position_in_brush.y) * brush_width) * 4 + 3
	if index < brush_data.size():
		return brush_data[index]/255.0
	return 0.0

# Update a single entry with a change. Rate is a value between 0 and 1.
func _update_bytedata_with_blend(_i: int, _j: int, tex_position: Vector2, channel: int, rate: float):

	var local_channel = channel % 4

	if first:
		outputlog("_update_data_with_blend: " + str(local_channel),3)
		print_entry(_i, _j)
	
	var target_splat = splatImages[int(channel/4.0)]

	var change = clamp(int(rate*255),0,255)

	if first: outputlog("rate: " + str(rate) + " int(rate*255): " + str(int(rate*255)) + " change: " + str(change),3)

	var overall_splat_total = get_overall_splat_total(_i, _j)
	if overall_splat_total < 255:
		change = max(255 - overall_splat_total, change)
		if first: outputlog("correct upwards change: " + str(change),3)

	var new_value = min(target_splat.get_byte_data_entry(_i,_j,local_channel) + change,255)
	var actual_change = new_value - target_splat.get_byte_data_entry(_i,_j,local_channel)
	if first: outputlog("new_value: " + str(new_value) + " actual_change: " + str(actual_change),3)
	target_splat.set_byte_data_entry(_i,_j,local_channel,new_value)

	if first: target_splat.print_entry(_i, _j)

	return actual_change

# Reduces the other channels by a value, ie the amount the main channel has increased
func reduce_other_channels_by_value(_i: int, _j: int, channel: int, reduce_value: int):

	if first:
		outputlog("reduce_other_channels_by_value: int_value: " + str(reduce_value),3)
	var changed_value = -1
	var target_splat = splatImages[int(channel/4.0)]

	# Make an array of all of the splat values at that _i, _j across all splats
	var complete_entry_array = []
	for _m in splatImages.size():
		if first: outputlog("making entry for splat: " + str(splatImages[_m].splat_number),3)
		var entry_array = splatImages[_m].make_array_of_splat_values(_i, _j)
		if first: outputlog("entry_array: " + str(entry_array),3)
		# Remove the channel that we are adding to
		if _m == target_splat.splat_number:
			# Store that the new value
			changed_value = entry_array[channel % 4]
			entry_array.remove(channel % 4)
		complete_entry_array.append_array(entry_array.duplicate())

	if first: outputlog("complete_entry_array prior to change: " + str(complete_entry_array),3)
	# Reduce by values
	reduce_array_in_place(complete_entry_array,reduce_value)
	# Put the entry back again
	complete_entry_array.insert(channel,changed_value)

	# Normalise the array so that it does not total to more than 255 due to the rounding errors in reduce in place
	normalise_entry_array(complete_entry_array, channel)

	if first: outputlog("complete_entry_array after change: " + str(complete_entry_array),3)

	# Fix for multiple spates
	for _k in complete_entry_array.size():
		if _k == channel: continue
		# Set the relevant byte to the right value
		if splatImages[int(_k / 4.0)].get_byte_data_entry(_i, _j, _k % 4) != complete_entry_array[_k]:
			splatImages[int(_k / 4.0)].set_byte_data_entry(_i, _j, _k % 4, complete_entry_array[_k])
			mark_splat_modified(int(_k / 4.0))

# Correct for any errors in the reduce algorithm. Noting there shouldn't be any. This iterates at 1 at the time rather than full steps.
func normalise_entry_array(array, channel: int):

	if first: outputlog("normalise_entry_array(): array: " + str(array) + " channel: " + str(channel),3)

	var total = 0
	var non_zero = []
	for _i in array.size():
		total += array[_i]
		if array[_i] > 0 && _i != channel:
			non_zero.append(_i)

	# If it is fine, then do nothing more.
	if total == 255: return

	# correction factor note that we need to account for positive and negative corrections
	var correction = total - 255
	var delta = 1
	# Reverse the correction
	if correction < 0:
		delta = -1
		correction = -correction
	
	var index = 0
	while correction > 0 && non_zero.size() > 0:
		index = index % non_zero.size()
		array[non_zero[index]] -= 1
		correction -= 1
		if non_zero[index] == 0:
			non_zero.remove(index)
		else:
			index += 1
	
	if correction > 0:
		if first: outputlog("unable to fully correct: " + str(correction),3)

# sorter for reducing array in place
class MyCustomSorter:
	static func sort_ascending(a, b):
		return a["value"] < b["value"]

# Function to reduce an array of integers by an amount
func reduce_array_in_place(array: Array, total_reduce: int) -> void:

	if first: outputlog("array: " + str(array),3)

	var n = array.size()
	if n == 0:
		return
	
	# Pair values with original indices
	var indexed = []
	for i in range(n):
		indexed.append({"index": i, "value": float(array[i])})
	
	# Sort ascending by value using a helper function
	indexed.sort_custom(MyCustomSorter, "sort_ascending")

	if first: outputlog("indexed sorted: " + str(indexed),3)
		
	var remaining = total_reduce
	var i = 0
	
	# Run while remaining is non-zero and while we are not on the final entry (which is invalid as it implies that we couldn't sufficiently reduce by looking ahead)
	while remaining > 0 and i + 1 < n:
		var count = n - i - 1 # elements remaining to reduce
		var current_value = indexed[i]["value"]
		var level = 0
		# If the current value is more than zero, then use that value. This should only be true for the first element.
		if current_value > 0:
			# Set the level to the current value
			level = max(current_value, 0)
			count += 1
		else:
			
			# Default the next opportunity to very large if there are no more elements, so total_step becomes remaining.
			var next_value = 99999
			if i + 1 >= n:
				next_value = 99999
			# Or get the difference between the next element and this one.
			else:
				next_value = indexed[i + 1]["value"]
			
			# Compute max we can subtract per element
			level = max(next_value - current_value, 0)
			if first: outputlog("level: " + str(i) + " value: " + str(level),2)
		
		var total_step = min(level * count, remaining)
		
		# Integer division per element
		var step_per_element = int(total_step / count)
		var leftover = int(total_step) % int(count)  # distribute remainder one by one
		if first: outputlog(str(i) + " level: " + str(level) + " step_per_element: " + str(step_per_element) + " leftover: " + str(leftover) + " count: " + str(count) + " total_step: " + str(total_step) ,3)
		
		# If there is anything to do iterate through each remaining element
		if remaining > 0 && (step_per_element > 0 || leftover > 0):
			for j in range(i, n, 1):
				if indexed[j]["value"] <= 0: continue
				var reduce_amount = step_per_element
				if leftover >= n - j:
					indexed[j]["value"] -= 1
					remaining -= 1
				indexed[j]["value"] -= reduce_amount
				remaining -= reduce_amount
				if remaining <= 0:
					break
		
		# Move past elements that hit zero
		while i < n:
			#if first: outputlog("skipping as zero: " + str(i) + " value: " + str(indexed[i]["value"]),2)
			if i + 1 < n:
				#if first: outputlog("i + 1 < n: " + str(i + 1 < n),2)
				if indexed[i+1]["value"] > 0:
					break
				i += 1
			else:
				break
			
	if first: outputlog("indexed after reduction: " + str(indexed),3)

	# Write results back
	for item in indexed:
		array[item["index"]] = int(item["value"])

	if first: outputlog("final array: " + str(array),3)

# NOT USED - New algorithm which may not be needed and is not fully tested.
func new_blend_into_channel(_i, _j, channel, rate):

	var complete_entry_array = []

	for _m in splatImages.size():
		if first: outputlog("making entry for splat: " + str(splatImages[_m].splat_number),2)
		var entry_array = splatImages[_m].make_array_of_splat_values(_i, _j)
		complete_entry_array.append_array(entry_array.duplicate())
	
	redistribute_values(complete_entry_array, channel, rate)

func redistribute_values(result: Array, increase_index: int, increase_amount: int):
	# Create a copy to avoid modifying the original
	var size = result.size()
	
	if size == 0 or increase_index < 0 or increase_index >= size:
		return
	
	# Calculate current total
	var current_total = 0
	for val in result:
		current_total += val
	
	# Handle case where total is less than 255
	if current_total < 255:
		var deficit = 255 - current_total
		var to_add_to_target = min(increase_amount, deficit, 255 - result[increase_index])
		result[increase_index] += to_add_to_target
		increase_amount -= to_add_to_target
		current_total += to_add_to_target
		
		# If target is at 255 and we still need to reach total of 255, distribute to others
		if result[increase_index] == 255 and current_total < 255:
			var others = []
			for i in range(size):
				if i != increase_index and result[i] < 255:
					others.append(i)
			
			var remaining_deficit = 255 - current_total
			while remaining_deficit > 0 and others.size() > 0:
				var per_element = max(1, int(ceil(float(remaining_deficit) / others.size())))
				var added = 0
				var i = 0
				while i < others.size():
					var idx = others[i]
					var room = 255 - result[idx]
					var to_add = min(per_element, room, remaining_deficit - added)
					result[idx] += to_add
					added += to_add
					if result[idx] >= 255:
						others.remove(i)
					else:
						i += 1
				remaining_deficit -= added
				if added == 0:
					break
		
		return
	
	# Normal case: total is 255, redistribute
	var actual_increase = min(increase_amount, 255 - result[increase_index])
	result[increase_index] += actual_increase
	
	var to_reduce = actual_increase
	
	# Build list of reducible indices
	var reducible = []
	for i in range(size):
		if i != increase_index and result[i] > 0:
			reducible.append(i)
	
	# Reduce other elements equally
	while to_reduce > 0 and reducible.size() > 0:
		var per_element = max(1, int(ceil(float(to_reduce) / reducible.size())))
		var reduced_this_round = 0
		
		var i = 0
		while i < reducible.size():
			var idx = reducible[i]
			var can_reduce = min(per_element, result[idx], to_reduce - reduced_this_round)
			result[idx] -= can_reduce
			reduced_this_round += can_reduce
			
			if result[idx] <= 0:
				reducible.remove(i)
			else:
				i += 1
		
		to_reduce -= reduced_this_round
		
		if reduced_this_round == 0:
			break

func get_overall_splat_total(_i: int, _j: int):

	if first: outputlog("get_overall_splat_total",3)
	var total = 0

	for _m in splatImages.size():
		total += splatImages[_m].get_splat_total(_i, _j)
	
	if first: outputlog("total: "+ str(total),3)
	return total

func print_complete_entry(_i, _j, extra_desc: String = ""):

	outputlog("print_complete_entry: " + str(_i) + ", " + str(_j),3)

	var output_str = str(extra_desc) + " entry: "

	for _m in splatImages.size():
		for _k in 4:
			output_str += str(splatImages[_m].get_byte_data_entry(_i,_j,_k)) + " "
	
	outputlog(output_str,3)

# Function to cycle through each splatimage and set its byte data from the image value
func refresh_all_splats_byte_data():

	outputlog("refresh_all_splats_byte_data",3)

	for _i in splatImages.size():
		splatImages[_i].load_byte_data()

# Update all of the splats image based on the byte data
func refresh_all_splats_images_from_byte_data():

	for _i in splatImages.size():
		splatImages[_i].create_from_data(splatImages[_i].get_width(), splatImages[_i].get_height(), false, Image.FORMAT_RGBA8, splatImages[_i].byte_data)
		splatImages[_i].byte_data.empty()

#########################################################################################################
##
## SPLATIMAGE CLASS
##
#########################################################################################################

# Note it doesn't feel like we get any value from putting blend_towards_channel and associated data in the splatimage as it is all just references.
# We now seem to be loading all the data and affecting all the data anyway

class SplatImage extends Image:
	const BLOB_SIZE = 64.0
	# Logging Functions
	const ENABLE_LOGGING = true
	var logging_level = 2
	var first
	var byte_data: PoolByteArray
	var splat_number = -1

	func _init(num: int):
		splat_number = num

	#########################################################################################################
	##
	## UTILITY FUNCTIONS
	##
	#########################################################################################################

	func outputlog(msg,level=0):
		if ENABLE_LOGGING:
			if level <= logging_level:
				printraw("(%d) <SplatImage>: " % OS.get_ticks_msec())
				print(msg)
		else:
			pass

	func get_byte_data_entry(_i: int, _j: int, local_channel: int):

		if byte_data.size() == 0: return 0
		return byte_data[(_i + _j * self.get_width()) * 4 + local_channel]

	func set_byte_data_entry(_i: int, _j: int, local_channel: int, value: int):

		if byte_data.size() == 0: return
		byte_data[(_i + _j * self.get_width()) * 4 + local_channel] = value

	func load_byte_data():

		byte_data = self.get_data()

	func fill_channel(channel: int):

		outputlog("fill_channel: " + str(channel),2)

		if is_channel_local(channel):
			outputlog("channel is in this splat",2)
			match channel % 4:
				0:
					self.fill(Color(1.0, 0.0, 0.0, 0.0))
				1:
					self.fill(Color(0.0, 1.0, 0.0, 0.0))
				2:
					self.fill(Color(0.0, 0.0, 1.0, 0.0))
				3:
					self.fill(Color(0.0, 0.0, 0.0, 1.0))
		else:
			self.fill(Color(0.0, 0.0, 0.0, 0.0))

	func is_channel_local(channel: int):

		return int(channel/4.0) == splat_number

		# Gets an array of splat values from this splat image
	func make_array_of_splat_values(_i: int, _j: int):

		return [get_byte_data_entry(_i, _j, 0),get_byte_data_entry(_i, _j, 1),get_byte_data_entry(_i, _j, 2),get_byte_data_entry(_i, _j, 3)]

	func print_entry(_i, _j, extra_desc: String = ""):

		outputlog(str(extra_desc) + " entry: " + str(get_byte_data_entry(_i,_j,0)) + " " + str(get_byte_data_entry(_i,_j,1))+ " " + str(get_byte_data_entry(_i,_j,2))+ " " + str(get_byte_data_entry(_i,_j,3)),3)

	func get_splat_total(_i: int, _j: int):

		var total = 0
		for _k in 4:
			total += get_byte_data_entry(_i, _j, _k)
		return total

#########################################################################################################
##
## DATA FUNCTIONS
##
#########################################################################################################

# Function to create a data record that represents the class data
func get_data_record() -> Dictionary:

	outputlog("create_get_data_record",2)

	var time_record = time_function_start("get_data_record")

	var data_record = {
		"visible": self.visible,
		"smooth_blending": smoothblending,
		"textures": [],
		"num_splats": num_splats,
		"splats": {}
	}

	for tex in textures:
		data_record["textures"].append(tex.resource_path)

	# If we need to update the splat records then create them from the splat images
	for _i in num_splats:
		if splat_is_modified[_i]:
			data_record["splats"]["splat"+str(_i)] = poolbytearray_to_string(splatImages[_i].get_data())
				
	time_function_end(time_record)
	
	return data_record

# Function to load the data record into the this class
func load_from_data_record(data_record: Dictionary):

	outputlog("load_from_data_record",2)

	var time_record = time_function_start("load_from_data_record")

	self.visible = data_record["visible"]
	self.smoothblending = data_record["smooth_blending"]
	self.set_splat_number(data_record["num_splats"])

	# Set the terrain but don't trigger a rebuild of the altas images
	for _i in data_record["textures"].size():
		self.set_terrain_texture(data_record["textures"][_i],_i, false)
	
	for entry in data_record["splats"].keys():

		var splat_idx = int(entry.replace("splat",""))
		splatImages[splat_idx].create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, string_to_poolbytearray(data_record["splats"][entry]))
	
	build_all_atlases()
	update_splats()
	# Mark the splats as unmodified as we have just loaded them so they haven't changed
	mark_all_splats_modified(false)

	time_function_end(time_record)








