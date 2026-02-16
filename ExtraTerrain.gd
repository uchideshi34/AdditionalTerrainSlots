extends MeshInstance2D

var level = null
var splatImages = []
var splatTextures = []


var textures = []
var width = 0
var height = 0

var first = true

var normalshader = null
var smoothshader = null

var terrain_atlases = []  # Array of 4 atlases (one per splat)
var terrain_atlas_tile_sizes = [] # tile size for the atlas allowing it to vary by atlas

var terrain_atlas_grid = Vector2.ZERO
var terrain_scales = []
var active_blocks = 0

var smoothblending = false
var num_splats = 0
var global = null

var is_hidden = false

const BLOB_SIZE = 64.0
const BLOB_OFFSET = 32.0
const MAX_TEXTURE_PIXEL_SIZE = 4096 # Strictly speaking this isn't a hard max but 4096 is for 4 columns
const NODE_NAME = "ExtraTerrain987234"
const MAX_SPLATS = 6

signal record_history

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
	img.set_pixel(0, 0, Color(0,0,0,1))
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

# Encode PoolByteArray to base64 string
func poolbytearray_to_base64string(arr: PoolByteArray) -> String:
	return Marshalls.raw_to_base64(arr)

# Decode base64 string back to PoolByteArray
func base64string_to_poolbytearray(s: String) -> PoolByteArray:
	return Marshalls.base64_to_raw(s)

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

	outputlog("_init: level: " + str(parent_level) + " size: " + str(woxelDimensions),1)

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
	var new_material = ShaderMaterial.new()
	self.material = new_material
	self.material.set_shader_param("map_size",woxelDimensions)
	update_splat_textures_from_images()

# Function to update the mesh to the World size
func update_mesh(woxelDimensions: Vector2):

	var pixel_width = woxelDimensions.x
	var pixel_height = woxelDimensions.y

	var new_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	# Vertices (top-left origin)
	arrays[Mesh.ARRAY_VERTEX] = PoolVector2Array([
		Vector2(0, 0),           # Top-left
		Vector2(pixel_width, 0),       # Top-right
		Vector2(pixel_width, pixel_height),  # Bottom-right
		Vector2(0, pixel_height)       # Bottom-left
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
	self.material.set_shader_param("map_size",woxelDimensions)


#########################################################################################################
##
## SPLAT FUNCTIONS
##
#########################################################################################################

func add_splat():

	outputlog("add_splat",2)

	splatImages.append(Image.new())
	splatImages[num_splats].create(width, height, false, Image.FORMAT_RGBA8)
	if num_splats == 0:
		splatImages[num_splats].fill(Color(1.0, 0.0, 0.0, 1.0))
	else:
		splatImages[num_splats].fill(Color(0.0, 0.0, 0.0, 1.0))
	splatTextures.append(ImageTexture.new())
	splatTextures[num_splats].create_from_image(splatImages[num_splats], 4)
	textures.append_array([null,null,null])
	num_splats += 1
	
func remove_splat():

	outputlog("remove_splat",2)

	splatImages.remove(splatImages.size()-1)
	splatTextures.remove(splatTextures.size()-1)

	for _i in 4:
		textures.remove(textures.size()-1)
	
	num_splats -= 1

func set_active_blocks_number(target_number: int):

	set_splat_number(ceil(target_number * 4 / 3.0))

	active_blocks = target_number
	self.material.set_shader_param("active_blocks", active_blocks)

func set_splat_number(target_number: int):

	outputlog("set_splat_number: " + str(target_number) + " current number: " + str(num_splats),2)

	if num_splats < target_number:
		for _i in target_number-num_splats:
			add_splat()
	if num_splats > target_number:
		for _i in num_splats-target_number:
			remove_splat()
	
	update_splat_textures_from_images()

# Updates the splat texture from the spla
func update_splat_textures_from_images():

	outputlog("update_splat_textures_from_images",3)

	for _i in num_splats:
		update_splat_texture_from_image(_i)
	for _i in range(num_splats,MAX_SPLATS,1):
		material.set_shader_param("splat"+ str(_i), make_dummy_texture())

# Function to update only a single splat
func update_splat_texture_from_image(index: int):

	outputlog("update_splat_texture_from_image: " + str(index),3)
	var time_record = time_function_start("update_splat_texture_from_image")

	if index < num_splats:
		
		splatTextures[index].create_from_image(splatImages[index], 4)
		self.material.set_shader_param("splat"+ str(index),splatTextures[index])
	
	time_function_end(time_record, 3)

func update_splat_images_from_textures():

	outputlog("update_splat_images_from_textures",3)

	for _i in num_splats:
		update_splat_image_from_texture(_i)

# Function to update only a single splat
func update_splat_image_from_texture(index: int):

	outputlog("update_splat_image_from_texture: " + str(index),3)
	var time_record = time_function_start("update_splat_image_from_texture")

	if index < num_splats && index < splatTextures.size():
		if splatTextures[index] != null:
			splatImages[index] = splatTextures[index].get_data()
	
	time_function_end(time_record, 3)


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

	for _i in splatImages.size():
		fill_channel_on_splat(splatImages[_i], _i, channel)

	update_splat_textures_from_images()

func fill_channel_on_splat(original: Image, splat_idx: int, channel: int):

	outputlog("fill_channel_on_splat: " + str(channel),2)

	if int(channel/3.0) == splat_idx:
		outputlog("channel is in this splat",2)
		match channel % 3:
			0:
				original.fill(Color(1.0, 0.0, 0.0, 0.0))
			1:
				original.fill(Color(0.0, 1.0, 0.0, 0.0))
			2:
				original.fill(Color(0.0, 0.0, 1.0, 0.0))
	else:
		original.fill(Color(0.0, 0.0, 0.0, 0.0))

# Function to paint terrain
func paint_terrain(splatpainter, mouse_position: Vector2, terrain_index: int, rate: float, brush_size: float):

	outputlog("paint_terrain: index " + str(terrain_index) + " target_splat: " + str(int(terrain_index/3.0)) + " rate: " + str(rate),3)

	if not painting_active:
		start_painting(splatpainter, brush_size)

	yield(splatpainter.blend_towards_channel(mouse_position, terrain_index, rate),"completed")

	update_splat_textures_from_images()

func set_smoothblending(button_pressed: bool):

	outputlog("set_smoothblending: " + str(button_pressed),2)

	smoothblending = button_pressed
	material.set_shader_param("smoothblending", smoothblending)

# Add these class variables
var painting_active: bool = false
var history_record = {"level": null, "splat_size": Vector2.ZERO, "before_splats_data": [], "after_splats_data": []}

# Call this when user starts painting (mouse down)
func start_painting(splatpainter, brush_size: float):
	
	if painting_active:
		return
	
	outputlog("start_painting", 2)
	splatpainter.update_active_extraterrain(self)
	splatpainter.update_brush_data(brush_size)

	painting_active = true
	record_history_start_state()

# Record a the 
func record_history_start_state():

	outputlog("record_history_start_state", 2)

	var time_record = time_function_start("record_history_start_state")

	history_record = {"level": null, "splat_size": Vector2.ZERO, "before_splats_data": [], "after_splats_data": []}
	history_record["splat_size"] = Vector2(width, height)
	history_record["level"] = level
	for _i in num_splats:
		history_record["before_splats_data"].append(splatTextures[_i].get_data().get_data())
	
	time_function_end(time_record)

# Call this when user stops painting (mouse up)
func end_painting():

	if not painting_active:
		return
	
	outputlog("end_painting", 2)

	record_history_end_state()

	painting_active = false

# Record a history event and fire the notification signal to the main script
func record_history_end_state():

	outputlog("record_history_end_state", 2)

	if history_record["before_splats_data"].size() > 0:
		for _i in num_splats:
			history_record["after_splats_data"].append(splatTextures[_i].get_data().get_data())
	
	self.emit_signal("record_history", self, history_record.duplicate(true))


#########################################################################################################
##
## RESIZE FUNCTIONS
##
#########################################################################################################

func resize( up_delta_sq: int, down_delta_sq: int, right_delta_sq: int, left_delta_sq: int):

	outputlog("resize: up_delta_sq: " + str(up_delta_sq) + " down_delta_sq: " + str(up_delta_sq) + " right_delta_sq: " + str(right_delta_sq) + " left_delta_sq: " + str(left_delta_sq),2)

	# Update splats
	for _i in num_splats:
		resize_splat(splatImages[_i], _i, Vector2(width, height),  up_delta_sq * 4, down_delta_sq * 4, right_delta_sq * 4, left_delta_sq * 4)

	width += right_delta_sq * 4 + left_delta_sq * 4
	height += up_delta_sq * 4 + down_delta_sq * 4

	update_mesh(Vector2(width, height)*BLOB_SIZE)
	update_splat_textures_from_images()

func resize_splat(original: Image, splat_idx: int, original_size: Vector2, up_delta: int, down_delta: int, right_delta: int, left_delta: int):

	outputlog("resize_splat",2)

	var new_size = Vector2(original_size.x + right_delta + left_delta, original_size.y + up_delta + down_delta)

	var img = Image.new()
	img.create(new_size.x, new_size.y, false, Image.FORMAT_RGBA8 )
	if splat_idx == 0:
		img.fill(Color(1.0, 0.0, 0.0, 0.0))
	else:
		img.fill(Color(0.0, 0.0, 0.0, 0.0))
	
	img.blit_rect(original, Rect2(0.0, 0.0, original_size.x, original_size.y), Vector2(left_delta, up_delta))

	original.create_from_data(new_size.x, new_size.y, false, Image.FORMAT_RGBA8, img.get_data())

#########################################################################################################
##
## FLAT IMAGE FUNCTIONS
##
#########################################################################################################

var terrain_viewport: Viewport
var terrain_sprites: Array
var is_terrain_baked: bool = false
var is_baking: bool = false

func bake_terrain_to_texture():

	if is_baking: return
	
	is_baking = true
	
	outputlog("Baking terrain to static texture", 2)

	if is_terrain_baked || not self.visible:
		outputlog("Baking aborted: is_terrain_baked: " + str(is_terrain_baked) + " self.visible: " + str(self.visible), 2)
		return
	
	var time_record = time_function_start("bake_terrain_to_texture")
	
	var full_size = Vector2(width * BLOB_SIZE, height * BLOB_SIZE)
	var tile_size = 8192  # Render in 8192x8192 chunks
	var tiles_x = int(ceil(full_size.x / tile_size))
	var tiles_y = int(ceil(full_size.y / tile_size))
	
	outputlog("Rendering " + str(tiles_x) + "x" + str(tiles_y) + " tiles", 2)
	
	# Create viewport for tiled rendering
	terrain_viewport = Viewport.new()
	terrain_viewport.size = Vector2(tile_size, tile_size)
	terrain_viewport.hdr = false
	terrain_viewport.usage = Viewport.USAGE_2D
	terrain_viewport.render_target_v_flip = true
	terrain_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS

	# If this is the first time using the terrain_viewport
	if terrain_viewport.get_parent() == null:
		add_child(terrain_viewport)
	else:
		# This should be unnecessary as the viewport should only be a child of the eztraterrain
		if terrain_viewport.get_parent() != self:
			terrain_viewport.get_parent().remove_child(terrain_viewport)
			self.add_child(terrain_viewport)

	
	# Clone mesh WITH material
	var mesh_copy = MeshInstance2D.new()
	mesh_copy.mesh = self.mesh
	
	# IMPORTANT: Duplicate the material so we don't affect the original
	var bake_material = self.material.duplicate()
	mesh_copy.material = bake_material
	
	# Make sure all shader params are current
	bake_material.set_shader_param("map_size", Vector2(width * BLOB_SIZE, height * BLOB_SIZE))
	bake_material.set_shader_param("active_blocks", active_blocks)
	
	# Set all splat textures
	for i in range(num_splats):
		bake_material.set_shader_param("splat" + str(i), splatTextures[i])
	for i in range(num_splats, MAX_SPLATS):
		bake_material.set_shader_param("splat" + str(i), make_dummy_texture())
	
	# Set all terrain atlases
	for i in range(active_blocks):
		if i < terrain_atlases.size() and terrain_atlases[i]:
			bake_material.set_shader_param("terrain_atlas" + str(i), terrain_atlases[i])
		else:
			bake_material.set_shader_param("terrain_atlas" + str(i), make_dummy_texture())
	for i in range(active_blocks, 4):
		bake_material.set_shader_param("terrain_atlas" + str(i), make_dummy_texture())
	
	# Set other params
	bake_material.set_shader_param("atlas_grid", terrain_atlas_grid)
	bake_material.set_shader_param("tile_scale_tex", material.get_shader_param("tile_scale_tex"))
	bake_material.set_shader_param("tile_scale_count", material.get_shader_param("tile_scale_count"))
	bake_material.set_shader_param("blend_step", material.get_shader_param("blend_step"))
	
	mesh_copy.visible = true
	terrain_viewport.add_child(mesh_copy)
	
	# Array to store tile sprites for cleanup
	var tile_sprites = []

	# If this is too big to render as a single image then tile is
	if full_size.x > (16384 - 256) || full_size.x > (16384 - 256):

		var base_warn_string = "Baking terrain for level, " + str(level.Label) + ", this may take a few seconds."

		global.Editor.Warn("Baking Terrain", base_warn_string)
	
		# Render each tile
		for ty in range(tiles_y):
			for tx in range(tiles_x):

				global.Editor.Windows["Accept"].dialog_text = base_warn_string + "\n" + "Baking tile " + str(tx + 1 + ty * tiles_x) + " out of " + str(tiles_x * tiles_y) + "."
				var offset_x = tx * tile_size
				var offset_y = ty * tile_size
				
				# Calculate actual tile dimensions (may be smaller at edges)
				var actual_width = min(tile_size, full_size.x - offset_x)
				var actual_height = min(tile_size, full_size.y - offset_y)
				var is_edge_tile = actual_width < tile_size or actual_height < tile_size
				
				# Position mesh to render this tile
				mesh_copy.position = Vector2(-offset_x, -offset_y)

				terrain_viewport.update()
				
				yield(get_tree(), "idle_frame")
				yield(get_tree(), "idle_frame")
				
				# Get tile image
				var tile_img = terrain_viewport.get_texture().get_data()

				# Only crop if this is an edge tile
				if is_edge_tile:
					var cropped = Image.new()
					cropped.create(int(actual_width), int(actual_height), false, Image.FORMAT_RGBA8)
					cropped.lock()
					tile_img.lock()
					cropped.blit_rect(tile_img, Rect2(0, 0, actual_width, actual_height), Vector2.ZERO)
					tile_img.unlock()
					cropped.unlock()
					tile_img = cropped
				
				# Create texture from tile
				var tile_tex = ImageTexture.new()
				tile_tex.create_from_image(tile_img)
				
				# Create sprite for this tile
				var tile_sprite = Sprite.new()
				tile_sprite.texture = tile_tex
				tile_sprite.centered = false
				tile_sprite.position = self.position + Vector2(offset_x, offset_y)
				tile_sprite.z_index = self.z_index
				tile_sprite.name = "BakedTerrainTile_" + str(tx) + "_" + str(ty)
				
				level.add_child(tile_sprite)
				tile_sprites.append(tile_sprite)
				
				outputlog("Rendered tile " + str(tx) + "," + str(ty) + " size: " + str(actual_width) + "x" + str(actual_height), 2)
	
	# Otherwise just create a single image which is much faster
	else:
		terrain_viewport.update()

		yield(get_tree(), "idle_frame")
		yield(get_tree(), "idle_frame")

		var tile_img = terrain_viewport.get_texture().get_data()

		# CREATE A NEW TEXTURE FROM THE IMAGE
		var baked_texture = ImageTexture.new()
		baked_texture.create_from_image(tile_img, 0)
	
		# Create a simple sprite to display it
		var terrain_sprite = Sprite.new()
		terrain_sprite.texture = baked_texture
		terrain_sprite.centered = false
		terrain_sprite.position = self.position
		terrain_sprite.z_index = self.z_index
		terrain_sprite.name = "BakedTerrain"
		# After creating tile_sprite
		terrain_sprite.modulate = Color(1, 1, 1, 1)  # Full opacity
		terrain_sprite.visible = true

		level.add_child(terrain_sprite)
		tile_sprites.append(terrain_sprite)

	# Store tile sprites for cleanup
	terrain_sprites = tile_sprites.duplicate(true)

	# Remove the meshcopy and hide the viewport
	terrain_viewport.remove_child(mesh_copy)
	mesh_copy.queue_free()
	mesh_copy = null

	#terrain_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	self.visible = false

	is_terrain_baked = true
	is_baking = false

	# If the warning is active then remove it
	if global.Editor.Windows["Accept"].visible:
		global.Editor.Quickswitch(global.Editor.ActiveToolname)
		global.Editor.Windows["Accept"].visible = false

	time_function_end(time_record)

func unbake_terrain():

	outputlog("unbake_terrain", 2)

	if not is_terrain_baked:
		return
	
	# Wait until the bake has completed before unbaking
	while is_baking:
		yield(get_tree(), "idle_frame")
	
	# terrain_sprite is now an array of sprites
	if terrain_sprites and terrain_sprites is Array:
		for sprite in terrain_sprites:
			if sprite:
				get_parent().remove_child(sprite)
				sprite.queue_free()
		terrain_sprites = []
	
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
	
	for block_idx in range(active_blocks):
		build_single_atlas(block_idx)
	
	# Set dummy textures for unused splats
	for block_idx in range(active_blocks, 4):
		terrain_atlases[block_idx] = make_dummy_texture()
		material.set_shader_param("terrain_atlas" + str(block_idx), terrain_atlases[block_idx])
	
	# Update the terrain scales
	update_terrain_scales()

# Find the tile_size of an atlas
func get_atlas_tile_size(block_idx: int) -> Vector2:

	outputlog("get_atlas_tile_size: " + str(block_idx), 2)

	var max_size = Vector2.ZERO
	for local_idx in range(4):
		var tex_idx = block_idx * 4 + local_idx
		if tex_idx >= textures.size() or textures[tex_idx] == null:
			continue
		var tex = textures[tex_idx]
		if tex.get_size().x > max_size.x:
			max_size.x = tex.get_size().x
		if tex.get_size().y > max_size.y:
			max_size.y = tex.get_size().y
	
	return max_size

# Build a single atlas
func build_single_atlas(block_idx: int):

	outputlog("build_single_atlas: " + str(block_idx), 2)

	var tile_size = get_atlas_tile_size(block_idx)
	terrain_atlas_tile_sizes[block_idx] = tile_size

	var atlas_image = Image.new()
	atlas_image.create(int(tile_size.x) * 2, int(tile_size.y) * 2, false, Image.FORMAT_RGBA8)
	atlas_image.lock()
	
	# 2x2 grid for 4 textures
	for local_idx in range(4):
		var tex_idx = block_idx * 4 + local_idx
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
	terrain_atlases[block_idx] = atlas_texture
	material.set_shader_param("terrain_atlas" + str(block_idx), atlas_texture)

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
		if _i < active_blocks:
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
## DATA FUNCTIONS
##
#########################################################################################################

# Function to create a data record that represents the class data
func get_data_record() -> Dictionary:

	outputlog("create_get_data_record",2)

	var time_record = time_function_start("get_data_record")

	var data_record = {
		"is_hidden": self.is_hidden,
		"smooth_blending": smoothblending,
		"textures": [],
		"num_splats": num_splats,
		"active_blocks": active_blocks,
		"splats": {}
	}

	for tex in textures:
		data_record["textures"].append(tex.resource_path)

	# If we need to update the splat records then create them from the splat images
	for _i in num_splats:
		outputlog("creating record for splat id: " + str(_i),2)
		data_record["splats"]["splat"+str(_i)] = poolbytearray_to_base64string(splatImages[_i].get_data())
				
	time_function_end(time_record)
	
	return data_record

# Function to load the data record into the this class
func load_from_data_record(data_record: Dictionary):

	outputlog("load_from_data_record",2)

	var time_record = time_function_start("load_from_data_record")

	self.is_hidden = data_record["is_hidden"]
	self.visible = not data_record["is_hidden"]
	self.smoothblending = data_record["smooth_blending"]
	self.set_active_blocks_number(data_record["active_blocks"])

	# Set the terrain but don't trigger a rebuild of the altas images
	for _i in data_record["textures"].size():
		self.set_terrain_texture(data_record["textures"][_i],_i, false)
	
	for entry in data_record["splats"].keys():

		var splat_idx = int(entry.replace("splat",""))
		
		splatImages[splat_idx].create_from_data(self.width, self.height, false, Image.FORMAT_RGBA8, base64string_to_poolbytearray(data_record["splats"][entry]))
	
	build_all_atlases()
	update_splat_textures_from_images()

	time_function_end(time_record)








