extends MeshInstance2D

var extraterrain = null
var size = Vector2.ONE
var splat_shader = null
var texture_to_use
var terrain_viewport
var terrain_viewports = []
var terrain_meshes = []
var base_brush: Image
var scaled_brush: Image
var brush_tex: ImageTexture

const BLOB_OFFSET = 32.0
const BLOB_SIZE = 64.0
const MAX_SPLATS = 6

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 0

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <SplatPainter>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Makes a dummy texture for the splatTextures so they are never not populated
func make_dummy_texture() -> ImageTexture:
	var img = Image.new()
	img.create(1, 1, false, Image.FORMAT_RGBA8)
	img.lock()
	img.set_pixel(0, 0, Color(1,0,0,1))
	img.unlock()

	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex

#########################################################################################################
##
## CORE SET UP FUNCTIONS
##
#########################################################################################################

func _init(parent: Node2D, initial_size: Vector2, shader):

	if parent != null:
		parent.add_child(self)

	size = initial_size / BLOB_SIZE
	update_mesh(size)

	self.splat_shader = shader

	var mat = ShaderMaterial.new()
	mat.shader = splat_shader.duplicate() # duplicate ensures fresh instance
	self.material = mat
	self.z_index = 0
	self.visible = false

	for _i in MAX_SPLATS:
		var vp = Viewport.new()
		vp.size = size
		vp.usage = Viewport.USAGE_2D
		vp.render_target_update_mode = Viewport.UPDATE_DISABLED
		vp.hdr = false
		vp.render_target_v_flip = true
		vp.transparent_bg = false
		vp.clear_mode = Viewport.CLEAR_MODE_ALWAYS
		vp.clear_color = Color(0,0,0,1)
		add_child(vp)

		var mesh_instance = MeshInstance2D.new()
		mesh_instance.mesh = self.mesh
		mesh_instance.material = ShaderMaterial.new()
		mesh_instance.material.shader = splat_shader.duplicate()

		vp.add_child(mesh_instance)

		terrain_viewports.append(vp)
		terrain_meshes.append(mesh_instance)

# Function to resize the splatpainter
func resize(new_world_size: Vector2):

	size = new_world_size / BLOB_SIZE
	update_mesh(size)

	for _i in MAX_SPLATS:
		terrain_viewports[_i].size = size
		terrain_meshes[_i].mesh = self.mesh


# Update the current active terrain
func update_active_extraterrain(new_extraterrain: MeshInstance2D):

	outputlog("update_active_extraterrain: " + str(new_extraterrain), 3)
	if new_extraterrain == self.extraterrain: return

	self.extraterrain = new_extraterrain

	# Change the level this painter lives on to match the extra terrain
	if self.get_parent() != null:
		self.get_parent().remove_child(self)

	extraterrain.level.add_child(self)

# Function to update the mesh to the World size
func update_mesh(woxelDimensions: Vector2):

	outputlog("update_mesh: " + str(woxelDimensions),2)

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

#########################################################################################################
##
## BRUSH FUNCTIONS
##
#########################################################################################################

# Function to update the brush data to reflect the brush and its size
func update_brush_data(scale: float):

	outputlog("update_brush_data: " + str(scale),3)

	var base_size = base_brush.get_size()
	var scaled_brush = Image.new()

	scaled_brush.copy_from(base_brush)
	scaled_brush.resize(base_size.x * scale * 2.0 / BLOB_SIZE, base_size.y * scale * 2.0 / BLOB_SIZE, Image.INTERPOLATE_LANCZOS)
	brush_tex = ImageTexture.new()
	brush_tex.create_from_image(scaled_brush,0)

#########################################################################################################
##
## PAINT FUNCTIONS
##
#########################################################################################################

func blend_towards_channel(mouse_position: Vector2, channel: int, rate: float):

	outputlog("blend_towards_channel: " + str(channel) + " mouse_position: " + str(mouse_position),2)

	var prof_start = OS.get_ticks_msec()

	var local_mouse = mouse_position / BLOB_SIZE
	self.visible = false

	# For each of the splats, enter in the right values
	for _i in extraterrain.num_splats:

		var mesh_instance = terrain_meshes[_i]

		# Set up the splat images
		for _j in extraterrain.num_splats:
			mesh_instance.material.set_shader_param("splat" + str(_j), extraterrain.splatTextures[_j])
		for _j in range(extraterrain.num_splats, MAX_SPLATS, 1):
			mesh_instance.material.set_shader_param("splat" + str(_j), make_dummy_texture())

		mesh_instance.material.set_shader_param("brush_texture", brush_tex)
		mesh_instance.material.set_shader_param("brush_size", brush_tex.get_size())
		mesh_instance.material.set_shader_param("splat_map_size", terrain_viewports[_i].size)
		mesh_instance.material.set_shader_param("paint_rate", rate)
		mesh_instance.material.set_shader_param("target_channel", channel)
		mesh_instance.material.set_shader_param("brush_position", local_mouse)
		mesh_instance.material.set_shader_param("output_splat", _i)
		mesh_instance.material.set_shader_param("num_active_terrain_slots", extraterrain.num_splats*3)

		terrain_viewports[_i].render_target_update_mode = Viewport.UPDATE_ONCE
		terrain_viewports[_i].update()

	# Yield frames to let the render happen
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	# Collect the outputs from the viewports
	var output_splat_images = []
	for _i in extraterrain.num_splats:

		# Create texture from tile
		var tex = terrain_viewports[_i].get_texture()
		var img = tex.get_data()
		output_splat_images.append(img)

	for _i in extraterrain.num_splats:
		extraterrain.splatImages[_i] = output_splat_images[_i]
	var finish_time = OS.get_ticks_msec()
	outputlog("time taken: " + str(finish_time-prof_start),2)

