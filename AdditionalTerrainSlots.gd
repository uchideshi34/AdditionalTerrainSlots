#########################################################################################################
##
## EXPANDED TERRAIN MOD
##
#########################################################################################################

var script_class = "tool"

# Variables
var _lib_mod_config = null
var store_last_valid_selection = []

var ExtraTerrain

var SplatPainter
var splatpainter = null

var extraterrainui
var tool_panel = null
var activate_terrain_button = null
var store_level_ids = {}
var store_current_level = null

var areabrush
var tool_is_active = false
var is_painting = false
var has_started_painting = false
var has_any_painting_occurred = false

var enable_baking = true
var enable_bake_while_painting = false

var paint_on_frame_number = 1
var frame_count = 0

const NODE_NAME = "ExtraTerrain987234"
const INTENSITY_CONSTANT = 0.25

const COMBINED_DATA_STORE = "UchideshiNodeData"
const EXTRATERRAINDATA = "extraterrain_data"

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 4

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <AdditionalTerrainSlots>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Function to see if a structure that looks like a copied dd data entry is the same
func is_the_same(a, b) -> bool:

	if a is Dictionary:
		if not b is Dictionary:
			return false
		if a.keys().size() != b.keys().size():
			return false
		for key in a.keys():
			if not b.has(key):
				return false
			if not is_the_same(a[key], b[key]):
				return false
	elif a is Array:
		if not b is Array:
			return false
		if a.size() != b.size():
			return false
		for _i in a.size():
			if not is_the_same(a[_i], b[_i]):
				return false
	elif a != b:
		return false

	return true

# Function to look at a node and determine what type it is based on its properties
func get_node_type(node):

	if node.get("WallID") != null:
		return "portals"

	# Note this is also true of portals but we caught those with WallID
	elif node.get("Sprite") != null:
		return "objects"
	elif node.get("FadeIn") != null:
		return "paths"
	elif node.get("HasOutline") != null:
		return "pattern_shapes"
	elif node.get("Joint") != null:
		return "walls"

	return null

# Make a button and return it
func make_button(parent_node, icon_path: String, hint_tooltip: String, toggle_mode: bool) -> Button:

	var button = Button.new()
	button.toggle_mode = toggle_mode
	button.icon = load_image_texture(icon_path)
	button.hint_tooltip = hint_tooltip
	parent_node.add_child(button)
	return button

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

func time_function_start(function_name: String) -> Dictionary:
	return {
		"name": function_name,
		"start": OS.get_ticks_msec()
	}

func time_function_end(data: Dictionary):
	var print_this ="%s took: %.1f ms" % [data["name"], OS.get_ticks_msec() - data["start"]]
	outputlog(print_this,2)


# Function to merge dictionaries, dictionary b overwrites duplicate key values in the result
func merge_dict(dict_a: Dictionary, dict_b: Dictionary, merge_arrays: bool = false) -> Dictionary:

	var new_dict = dict_a.duplicate(true)
	for key in dict_b:
		if key in new_dict:
			if dict_a[key] is Dictionary and dict_b[key] is Dictionary:
				new_dict[key] = merge_dict(dict_a[key], dict_b[key])
			elif dict_a[key] is Array and dict_b[key] is Array and merge_arrays:
				new_dict[key] = merge_array(dict_a[key], dict_b[key])
			else:
				new_dict[key] = dict_b[key]
		else:
			new_dict[key] = dict_b[key]
	return new_dict

# Function to merge arrays
func merge_array(array_1: Array, array_2: Array) -> Array:
	var new_array = array_1.duplicate(true)
	var compare_array = new_array
	var item_exists

	compare_array = []
	for item in new_array:
		if item is Dictionary or item is Array:
			compare_array.append(JSON.print(item))
		else:
			compare_array.append(item)

	for item in array_2:
		item_exists = item
		if item is Dictionary or item is Array:
			item = item.duplicate(true)
			item_exists = JSON.print(item)

		if not item_exists in compare_array:
			new_array.append(item)
	
	return new_array

# Function to set a property on an object but block any signals for it
func set_property_but_block_signals(obj: Object, property: String, value):

	outputlog("set_property_but_block_signals: " + str(obj) + " property: " + str(property) + " value: " + str(value),3)

	obj.set_block_signals(true)
	if obj.get(property) != null:
		obj.set(property,value)
	obj.set_block_signals(false)


#########################################################################################################
##
## CORE FUNCTIONS
##
#########################################################################################################

func initialise_extraterrain(level):

	outputlog("initialise_extraterrain")

	var extraterrain = level.get_node_or_null(NODE_NAME)

	if extraterrain == null:
		outputlog("ExtraTerrain definution: " + str(ExtraTerrain),2)
		extraterrain = ExtraTerrain.new(level, Global.World.WoxelDimensions)
		extraterrain.global = Global
		outputlog("extraterrain created: " + str(extraterrain),2)

		extraterrain.material.shader = ResourceLoader.load(Global.Root + "shaders/terrain.shader","Shader",true)
		extraterrain.textures = []
		for _i in extraterrainui.vbox.get_child_count():
			outputlog("_i: " + str(_i),2)
			extraterrain.textures.append(null)
			if extraterrainui.get_terrain_entry(_i) != null:
				extraterrain.set_terrain_texture(extraterrainui.get_terrain_entry(_i).texture_path, _i, false)
		extraterrain.set_active_blocks_number(extraterrainui.vbox.get_child_count()/4)
		extraterrain.build_all_atlases()
		extraterrain.update_splat_textures_from_images()
		extraterrain.connect("record_history", self, "create_update_custom_history")

		outputlog("initialise_extraterrain: complete",2)
		outputlog("level.get_node_or_null(NODE_NAME)" + str(level.get_node_or_null(NODE_NAME)),2)

func _on_activate_terrain_button_pressed(button_pressed: bool):

	outputlog("_on_activate_terrain_button_pressed: " + str(button_pressed))

	# Show all the right ui elements
	for child in tool_panel.Align.get_children():
		if child != activate_terrain_button:
			child.visible = button_pressed

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	# If there is an existing extraterrain 
	if extraterrain != null:
		# If this function call was driven by a user function press then button_pressed is false and we are removing the active terrain
		if not button_pressed:
			Global.World.GetCurrentLevel().remove_child(extraterrain)
			extraterrain.queue_free()
		
		# If button_pressed is true this came from a load event so don't delete it and do no more here

	# If there is no current extra terrain then create one
	elif button_pressed:

		initialise_extraterrain(Global.World.GetCurrentLevel())

func on_brush_size_slider_changed(value: float):

	outputlog("on_brush_size_slider_changed: " + str(value),2)

	# Update the areabrush display
	areabrush.hide_brush_stroke_preview()
	areabrush.radius_in_pixels = 256.0 * value * 0.5
	areabrush.show_brush_stroke_preview(Global.WorldUI.get_MousePosition())

func make_expandedterrain_ui():

	# Make a new tool under the Objects menu option
	var category = "Terrain"
	var id = "AdditionalTerrainSlots"
	var name = "Additional Terrain Tool"
	var icon = "res://ui/icons/tools/terrain_brush.png"
	tool_panel = Global.Editor.Toolset.CreateModTool(self, category, id, name, icon)
	tool_panel.UsesObjectLibrary = false

	activate_terrain_button = make_button(tool_panel.Align, "res://ui/icons/tools/terrain_brush.png", "no hint", true)
	activate_terrain_button.text = "Activate Extra Terrain"
	activate_terrain_button.pressed = false
	activate_terrain_button.connect("toggled", self, "_on_activate_terrain_button_pressed")

	var ExtraTerrainUI = ResourceLoader.load(Global.Root + "ExtraTerrainUI.gd", "GDScript", true)
	extraterrainui = ExtraTerrainUI.new(tool_panel.Align, Global)
	extraterrainui.reference_to_script = Script
	
	extraterrainui.add_terrain_entries(12)
	for _i in 12:
		extraterrainui.set_terrain_entry(_i, Script.GetAssetList("Terrain")[_i])
	
	extraterrainui.set_active_terrain(0)
	extraterrainui.terrain_slots_button.connect("item_selected", self, "on_terrain_slots_number_selected")
	extraterrainui.fill_button.connect("pressed", self, "on_fill_button_pressed")
	extraterrainui.brush_size_slider.connect("value_changed", self, "on_brush_size_slider_changed")
	extraterrainui.connect("launch_terrain_window", self, "on_launch_terrain_window")
	extraterrainui.connect("terrain_changed", self, "on_terrainui_terrain_changed")
	extraterrainui.smoothblending_button.connect("toggled", self, "on_smoothblending_toggled")
	extraterrainui.show_hide_button.connect("toggled", self, "on_show_hide_button_toggled")
	extraterrainui.sync_from_dd_terrain_button.connect("pressed", self, "on_sync_from_dd_terrain_button_pressed")
	extraterrainui.sync_to_dd_terrain_button.connect("pressed", self, "on_sync_to_dd_terrain_button_pressed")

func on_show_hide_button_toggled(button_pressed: bool):

	outputlog("on_show_hide_button_toggled: " + str(button_pressed),2)
	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null:
		extraterrain.is_hidden = not button_pressed
		extraterrain.visible = button_pressed
		if not button_pressed:
			extraterrain.unbake_terrain()

func on_smoothblending_toggled(button_pressed: bool):

	outputlog("on_smoothblending_toggled",2)

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)

	if extraterrain != null:
		extraterrain.unbake_terrain()
		extraterrain.set_smoothblending(button_pressed)
		if enable_baking:
			extraterrain.bake_terrain_to_texture()

func on_terrainui_terrain_changed(texture_path: String, index: int):

	outputlog("on_terrainui_terrain_changed",2)

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)

	if extraterrain != null:
		extraterrain.unbake_terrain()
		extraterrain.set_terrain_texture(texture_path, index, true)
		if enable_baking:
			extraterrain.bake_terrain_to_texture()

func on_fill_button_pressed():

	outputlog("on_fill_button_pressed: " + str(extraterrainui.active_terrain_index),2)

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)

	if extraterrain != null:
		extraterrain.unbake_terrain()
		extraterrain.record_history_start_state()
		extraterrain.fill_channel(extraterrainui.active_terrain_index)
		extraterrain.record_history_end_state()
		if enable_baking:
			extraterrain.bake_terrain_to_texture()

func on_launch_terrain_window(index: int):

	extraterrainui.terrainwindow.popup_centered_ratio(0.5)

# Function when a new value for terrain slots is selected
func on_terrain_slots_number_selected(item_selected: int):

	outputlog("on_terrain_slots_number_selected: " + str(item_selected),2)

	var current_count = extraterrainui.vbox.get_child_count()
	var slots_number = item_selected * 4 + extraterrainui.MIN_SPLATS * 4

	extraterrainui.set_number_terrain_entries(slots_number)

	outputlog("current_count: " + str(current_count))
		
	for _i in range(current_count,slots_number,1):
		outputlog("_i: " + str(_i))
		extraterrainui.set_terrain_entry(_i, Script.GetAssetList("Terrain")[(_i) % Script.GetAssetList("Terrain").size()])
	
	update_terrain_from_ui()

# Function to update the terrain to reflect the UI state
func update_terrain_from_ui():

	outputlog("update_terrain_from_ui",2)

	# Check that the entries are divisible by 4
	if extraterrainui.vbox.get_child_count() % 4 != 0:
		outputlog("error in extraterrainui entries: " + str(extraterrainui.vbox.get_child_count()),2)
		return
	
	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null:
	
		extraterrain.set_active_blocks_number(int(extraterrainui.vbox.get_child_count()/4.0))

		for _i in extraterrainui.vbox.get_child_count():
			outputlog("setting terrain at: " + str(_i),2)
			var entry = extraterrainui.get_terrain_entry(_i)
			outputlog("entry: " + str(entry),2)
			if entry != null:
				extraterrain.set_terrain_texture(entry.texture_path, _i, false)
		
		extraterrain.update_terrain_atlas()
		extraterrain.update_splat_textures_from_images()

		if extraterrainui.active_terrain_index > (extraterrainui.terrain_slots_button.selected * 4 + 12):
			extraterrainui.set_active_terrain(0)
		
		extraterrain.is_hidden = extraterrainui.show_hide_button.pressed
		extraterrain.visible = not extraterrain.is_hidden
		on_smoothblending_toggled(extraterrainui.smoothblending_button.pressed)

# Function to update the ui to reflect the current level's values
func update_ui_from_terrain(level):

	outputlog("update_ui_from_terrain: " + str(level) + " level.ID " + str(level.ID),2)

	var extraterrain = level.get_node_or_null(NODE_NAME)

	if extraterrain != null:
		outputlog("extraterrain is not null: " + str(extraterrain),2)

		activate_terrain_button.pressed = true

		extraterrainui.set_block_signals(true)
		extraterrainui.terrain_slots_button.select(extraterrain.active_blocks-1-2)
		extraterrainui.set_number_terrain_entries(extraterrain.active_blocks * 4)

		for _i in extraterrain.active_blocks * 4:
			extraterrainui.set_terrain_entry(_i, extraterrain.textures[_i].resource_path)
		
		extraterrainui.set_active_terrain(0)
		extraterrainui.smoothblending_button.pressed = extraterrain.smoothblending
		extraterrainui.show_hide_button.pressed = not extraterrain.is_hidden
		extraterrainui.set_block_signals(false)

	else:
		outputlog("extraterrain: " + str(extraterrain),2)
		activate_terrain_button.pressed = false

# When a level is changed
func on_level_change(_ignore_this):

	outputlog("on_level_change",2)

	var level = Global.World.GetCurrentLevel()

	update_ui_from_terrain(level)

	if level != store_current_level:
		outputlog("this is a new level from the stored one",2)
		var extraterrain = level.get_node_or_null(NODE_NAME)
		# Bake the new level's terrain if it has one
		if extraterrain != null:
			extraterrain.update_splat_textures_from_images()
			if not tool_is_active && enable_baking:
				extraterrain.bake_terrain_to_texture()

		store_current_level = level

# Function to bake all terrain
func bake_all_terrain():

	outputlog("bake_all_terrain: enable_baking" + str(enable_baking),2)

	if not enable_baking: return

	for level in Global.World.levels:
		var extraterrain = level.get_node_or_null(NODE_NAME)
		if extraterrain != null:
			extraterrain.bake_terrain_to_texture()

func update_brush_size_slider(steps: int):

	outputlog("update_brush_size_slider: " + str(steps),3)

	extraterrainui.brush_size_slider.slider_and_spinbox_change(extraterrainui.brush_size_slider.value + steps * extraterrainui.brush_size_slider.step,false)


#########################################################################################################
##
## SYNC WITH DD DATA FUNCTIONS
##
#########################################################################################################

# Function to syn from DD terrain data
func on_sync_from_dd_terrain_button_pressed():

	outputlog("on_sync_from_dd_terrain_button_pressed",2)

	# Sync terrain textures
	var terrain = Global.World.GetCurrentLevel().Terrain
	if terrain == null: return

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain == null: return

	# Get the textures
	for _i in terrain.textures.size():
		extraterrain.set_terrain_texture(terrain.textures[_i].resource_path, _i, false)

	# Get the smoothblending status
	extraterrain.smoothblending = terrain.SmoothBlending
	extraterrain.fill_channel(0)

	if terrain.ExpandedSlots:
		sync_from_rgba_splats_to_rgb_splats([terrain.splatImage, terrain.splatImage2],extraterrain.splatImages)
	else:
		sync_from_rgba_splats_to_rgb_splats([terrain.splatImage],extraterrain.splatImages)
	
	extraterrain.update_splat_textures_from_images()
	extraterrain.update_terrain_atlas()
	update_ui_from_terrain()

# function to synchronise the splat images
func sync_from_rgba_splats_to_rgb_splats(sources: Array, destinations: Array):

	outputlog("sync_from_rgba_splats_to_rgb_splats: ",2)

	if sources.size() == 0 || sources.size() > 2: return

	if sources.size() * 4 > destinations.size() * 3:
		outputlog("not enough space in the destination splats")
		return

	for img in sources:
		img.lock()
	for img in destinations:
		img.lock()
	
	for _j in sources[0].get_height():
		for _i in sources[0].get_width():

			var colour_0 = sources[0].get_pixel(_i,_j)
			destinations[0].set_pixel(_i, _j, Color(colour_0.r, colour_0.g, colour_0.b, 1.0))

			if sources.size() > 1:
				var colour_1 = sources[1].get_pixel(_i,_j)
				destinations[1].set_pixel(_i, _j, Color(colour_0.a, colour_1.r, colour_1.g, 1.0))
				destinations[2].set_pixel(_i, _j, Color(colour_1.b, colour_1.a, 0.0, 1.0))

			else:
				destinations[1].set_pixel(_i, _j, Color(colour_0.a, 0.0, 0.0, 1.0))
	
	for img in sources:
		img.unlock()
	for img in destinations:
		img.unlock()

func on_sync_to_dd_terrain_button_pressed():

	outputlog("on_sync_to_dd_terrain_button_pressed",2)

	# Sync terrain textures
	var terrain = Global.World.GetCurrentLevel().Terrain
	if terrain == null: return

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain == null: return

	# Set smooth blending
	Global.Editor.Tools["TerrainBrush"].SetSmoothBlending(extraterrain.smoothblending)

	# Set expanded slots
	Global.Editor.Tools["TerrainBrush"].ExpandSlots(true)

	for _i in 8:
		Global.Editor.Tools["TerrainBrush"].SetTextureFromWindow(safe_load_texture(extraterrain.textures[_i]), _i)
	
	sync_from_rgb_splats_to_rgab_splats(extraterrain.splatImages, [terrain.splatImage, terrain.splatImage2])
	terrain.UpdateSplat()

# function to synchronise the splat images
func sync_from_rgb_splats_to_rgab_splats(sources: Array, destinations: Array):

	outputlog("sync_from_rgb_splats_to_rgab_splats: ",2)

	for img in sources:
		img.lock()
	for img in destinations:
		img.lock()
	
	for _j in sources[0].get_height():
		for _i in sources[0].get_width():

			var colour_0 = sources[0].get_pixel(_i,_j)
			var colour_1 = sources[1].get_pixel(_i,_j)
			var colour_2 = sources[2].get_pixel(_i,_j)
			destinations[0].set_pixel(_i, _j, Color(colour_0.r, colour_0.g, colour_0.b, colour_1.r))
			destinations[1].set_pixel(_i, _j, Color(colour_1.g, colour_1.b, colour_2.r, colour_2.g))
	
	for img in sources:
		img.unlock()
	for img in destinations:
		img.unlock()

#########################################################################################################
##
## COPY LEVEL FUNCTIONS
##
#########################################################################################################

var cloneleveloptionbutton = null
var store_level_list = []
var updating_level_id_data = false

# Copy the colour data where required
func _copy_custom_data_to_new_level(source_level_index: int):

	outputlog("_copy_custom_data_to_new_level: " + str(source_level_index),2)

	var source_level = Global.World.TryGetLevel(source_level_index)
	if source_level == null: return

	var extraterrain = source_level.get_node_or_null(NODE_NAME)
	if extraterrain == null: return

	var new_level = find_new_level_created()
	if new_level == null: return

	initialise_extraterrain(new_level)

	# Get its extraterrain record
	var new_extraterrain = new_level.get_node_or_null(NODE_NAME)
	if new_extraterrain != null:
		new_extraterrain.load_from_data_record(extraterrain.get_data_record())
	
		update_ui_from_terrain()

		# Bake the terrain if needed
		if extraterrainui.show_hide_button.pressed && enable_baking:
			new_extraterrain.bake_terrain_to_texture()


# When create new level is pressed
func _on_create_new_level_pressed():

	outputlog("_on_create_new_level_pressed",2)

	# If we are cloning a level, ie selected index is more than zero, then do something but wait a bit first
	var copy_from_level_id = cloneleveloptionbutton.selected
	if copy_from_level_id > 0:

		outputlog("copy level active: " + str(copy_from_level_id),2)

		var timer = Timer.new()
		timer.autostart = false
		timer.one_shot = true
		Global.Editor.get_node("Windows").add_child(timer)

		# If we are updating the level id data wait for that to finish
		while updating_level_id_data:
			yield(timer.get_tree(), "idle_frame")
		
		timer.start(1.0)
		yield(timer,"timeout")
		_copy_custom_data_to_new_level(copy_from_level_id)
	
		Global.Editor.get_node("Windows").remove_child(timer)
		timer.queue_free()

# Find the new level window
func register_signals_for_copy_level():

	outputlog("register_signals_for_copy_level",2)

	var newlevelwindow = Global.Editor.Windows["NewLevel"]
	newlevelwindow.connect("about_to_show", self, "on_new_level_window_opened")

	var valign = newlevelwindow.get_node("Margins").get_node("VAlign")

	# If we have successfully found the Create Level window then connect to the "Create" button 
	if valign != null:
		if valign.get_node("Buttons") != null && valign.get_node("CloneLevel") != null:
			if valign.get_node("Buttons").get_node("OkayButton") != null && valign.get_node("CloneLevel").get_node("CloneLevelOptionButton") != null:
				valign.get_node("Buttons").get_node("OkayButton").connect("pressed", self, "_on_create_new_level_pressed")
				cloneleveloptionbutton = valign.get_node("CloneLevel").get_node("CloneLevelOptionButton")

# Function to capture when a new level window is opened so we can store the current level list
func on_new_level_window_opened():

	store_level_list = Global.World.levels.duplicate(true)

# Compare the current list of levels with the stored list and a level that is not in the stored list is the new one
func find_new_level_created():

	for level in Global.World.levels:
		if not level in store_level_list:
			return level
	return null

#########################################################################################################
##
## DATA FUNCTION
##
#########################################################################################################

func record_all_extraterrain_data():
	outputlog("record_all_extraterrain_data",2)

	for level in Global.World.levels:
		record_extraterrain_data(level)

func record_extraterrain_data(level):

	outputlog("record_extraterrain_data: " + str(level.ID),2)

	var extraterrain = level.get_node_or_null(NODE_NAME)

	if extraterrain != null:
		outputlog("extraterrain node found",2)
		var data = extraterrain.get_data_record()
		set_extraterrain_data(level.ID, data)

func set_extraterrain_data(level_id: int, config: Dictionary):

	outputlog("set_extraterrain_data",2)

	var time_record = time_function_start("set_extraterrain_data")

	# Copy the Dropshadow data into a separate record so we don't iterate over newly created records
	if not Global.ModMapData.has(COMBINED_DATA_STORE):
		Global.ModMapData[COMBINED_DATA_STORE] = {}
	if not Global.ModMapData[COMBINED_DATA_STORE].has(EXTRATERRAINDATA):
		Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA] = {}

	if Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA].has("level-"+str(level_id)):
		var level_data = Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA]["level-"+str(level_id)]
		Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA]["level-"+str(level_id)] = merge_dict(level_data, config.duplicate(true))
	else:
		Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA]["level-"+str(level_id)] = config.duplicate(true)

	outputlog(Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA])

	time_function_end(time_record)

func has_extraterrain_data(level_id: int):

	# Copy the Dropshadow data into a separate record so we don't iterate over newly created records
	if not Global.ModMapData.has(COMBINED_DATA_STORE):
		return false
	
	if not Global.ModMapData[COMBINED_DATA_STORE].has(EXTRATERRAINDATA):
		return false
	
	if not Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA].has("level-"+str(level_id)):
		return false

	return true

func get_extraterrain_data(level_id: int) -> Dictionary:

	# Copy the Dropshadow data into a separate record so we don't iterate over newly created records
	if not Global.ModMapData.has(COMBINED_DATA_STORE):
		return {}
	
	if not Global.ModMapData[COMBINED_DATA_STORE].has(EXTRATERRAINDATA):
		return {}
	
	if not Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA].has("level-"+str(level_id)):
		return {}
	
	return Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA]["level-"+str(level_id)]

func erase_extraterrain_data(level_id: int):

	# Copy the Dropshadow data into a separate record so we don't iterate over newly created records
	if not Global.ModMapData.has(COMBINED_DATA_STORE):
		return
	
	if not Global.ModMapData[COMBINED_DATA_STORE].has(EXTRATERRAINDATA):
		return
	
	if not Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA].has("level-"+str(level_id)):
		return
	
	Global.ModMapData[COMBINED_DATA_STORE][EXTRATERRAINDATA].erase("level-"+str(level_id))


# Function to load the terrain data from modmap and attach it to levels in the map
func load_extraterrain_data():

	outputlog("load_extraterrain_data",2)
	updating_level_id_data = true
	# For each level
	for level in Global.World.levels:
		outputlog("checking level for extraterrain data: " + str(level.ID),1)
		# Check if there is terrain data for it
		if has_extraterrain_data(level.ID):
			outputlog("data found on level: " + str(level.ID),1)
			# Initialise the level if so
			initialise_extraterrain(level)
			# Get its extraterrain record
			var extraterrain = level.get_node_or_null(NODE_NAME)
			if extraterrain != null:
				extraterrain.load_from_data_record(get_extraterrain_data(level.ID))
	
	updating_level_id_data = false


# Called when a new level might have been created or deleted. We need to move the data records as they are keyed off level.ID which can change
func on_possible_new_level():

	outputlog("on_possible_new_level: checking level id changes",2)

	var changes = {}
	var store_delta = 10000

	# Look through eacj level in the current set up
	for level in Global.World.levels:
		# See if there is a record in the stored levels
		if store_level_ids.has(level):
			# If the level id has changed, then log the changed
			if not store_level_ids[level] == level.ID:
				changes[level] = {"old_id": store_level_ids[level], "new_id": level.ID}
	
	if changes.keys().size() == 0:
		outputlog("no level id changes found",2)

	# Rename all the changes to -old and erase the old version
	for level in changes.keys():
		outputlog("moving: level: " + str(level) + " from ID: " + str(changes[level]["old_id"]) + " to ID: " + str(changes[level]["new_id"]), 2)
		set_extraterrain_data( int(changes[level]["old_id"]) + store_delta, get_extraterrain_data( int(changes[level]["old_id"]) ) )
		erase_extraterrain_data(int(changes[level]["old_id"]))

	# Rename all the -old values to the new values
	for level in changes.keys():
		set_extraterrain_data(int(changes[level]["new_id"]), get_extraterrain_data(int(changes[level]["old_id"])+store_delta)) 
		erase_extraterrain_data(int(changes[level]["old_id"])+store_delta)
	
	on_level_change(0)

# When you see a signal that prompts save end, write any modified data to modmapdata and resave
func on_save_end():

	outputlog("on_save_end",2)

	record_all_extraterrain_data()

	if Global.Editor.CurrentMapFile != null:
		# Make a timer to delay the re-save prompt 
		var timer = Timer.new()
		timer.autostart = false
		timer.one_shot = true
		Global.Editor.get_node("Windows").add_child(timer)

		# Wait a couple of seconds to ensure everything has been drawn, the delay value has been set.
		timer.start(1.0)	
		yield(timer,"timeout")
		
		outputlog("Global.Editor.saveButton",2)
		Global.Editor.saveButton.emit_signal("pressed")
		Global.Editor.get_node("Windows").remove_child(timer)
		timer.queue_free()

#########################################################################################################
##
## UPDATE FUNCTION
##
#########################################################################################################

var paint_button_pressed: bool = false

# this method is automatically called every frame. delta is a float in seconds. can be removed from script.
func update(delta : float):

	if tool_is_active && paint_button_pressed:
		# If this is the first frame of painting, then
		if not has_started_painting:
			start_of_painting()
			has_started_painting = true
		paint_terrain(0.05 * extraterrainui.intensity_slider.value)
		
	else:
		# If we had started a painting event and now the painting button isn't pressed and the painting function has completed. Possibly overkill on statuses
		# This ensures that we aren't finishing actually painting when we bake the terrain
		if has_started_painting && not is_painting:
			end_of_painting()
			has_started_painting = false


# this method is called whenever a mod created tool detects a user input on the canvas
func on_content_input(event):

	# do something after a mouse click is detected after the object tool created a new preview
	if event is InputEventMouseButton:
		# Start painting
		if event.button_index == BUTTON_LEFT:
			paint_button_pressed = event.pressed
				
	if event is InputEventMouseMotion:
		areabrush.set_update_parent_node(Global.World.GetCurrentLevel())
		areabrush.show_brush_stroke_preview(Global.WorldUI.get_MousePosition())

# Function called when the tool is enabled.
func on_tool_enable(tool_id):

	outputlog("on_tool_enable: " + str(tool_id),2)

	tool_is_active = true
	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null:
		update_ui_from_terrain(Global.World.GetCurrentLevel())
		extraterrain.unbake_terrain()

# FUnction called when the tool is disabled
func on_tool_disable(tool_id):

	outputlog("on_tool_disable: " + str(tool_id),2)

	tool_is_active = false
	areabrush.hide_brush_stroke_preview()
	paint_button_pressed = false

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)

	if extraterrain != null && extraterrainui.show_hide_button.pressed && enable_baking && has_any_painting_occurred:
		extraterrain.bake_terrain_to_texture()
	
	has_any_painting_occurred = false

#########################################################################################################
##
## HISTORY FUNCTIONS
##
#########################################################################################################

# Create custom history record, called when a colour preset is selected, the color picker is closed, or a slider timer finishes
func create_update_custom_history(extraterrain, history_record: Dictionary):

	var record_script
	outputlog("create_update_custom_history",2)

	# If there is no data in the record dictionary, then do nothing. This might fired from the "main" location
	if not (history_record["before_splats_data"].size() > 0 && history_record["after_splats_data"].size() > 0):
		outputlog("no history data available",2)
		return

	# Create a new record if one is needed or simply update the existing one
	record_script = Script.InstanceReference("library/custom_history_record.gd")

	# If this is null for any reason then return to avoid a crash
	if record_script == null:
		outputlog("record_script is null",2)
		return

	record_script.main_script = self
	record_script.history_record = history_record.duplicate(true)

	# If this is a new action then create a new custom record
	var record = Global.Editor.History.CreateCustomRecord(record_script)

	extraterrain.history_record = {"level": null, "splat_size": Vector2.ZERO, "before_splats_data": [], "after_splats_data": []}
	

#########################################################################################################
##
## PAINT FUNCTION
##
#########################################################################################################

# Core paint function
func paint_terrain(rate: float):

	outputlog("paint_terrain: rate: " + str(rate),2)

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)

	if extraterrain != null && extraterrainui.show_hide_button.pressed && splatpainter != null:

		# Register that the paint function has started
		is_painting = true
		# Actually do the painting waiting until all the yielding has completed
		yield(extraterrain.paint_terrain(splatpainter, Global.WorldUI.get_MousePosition(), extraterrainui.active_terrain_index, rate, extraterrainui.brush_size_slider.value),"completed")

		# Register that the paint function has completed
		is_painting = false
		
func start_of_painting():

	outputlog("start_of_painting",2)

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null:
		
		extraterrain.unbake_terrain()
		has_any_painting_occurred = true

func end_of_painting():

	outputlog("end_of_painting",2)

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null:

		if enable_bake_while_painting && enable_baking:
			outputlog("enable_baking: " + str(enable_baking),2)
			extraterrain.bake_terrain_to_texture()
		
		# Record history
		extraterrain.end_painting()

#########################################################################################################
##
## PAN CONTROLS FUNCTION
##
#########################################################################################################

var trackpanmanager = null

func on_pan_action(value):

	outputlog("on_pan_action: " + str(value))

	update_brush_size_slider(int(value))

# Set up the trackpad monitoring class
func setup_trackpad_monitoring():

	trackpanmanager = TrackpadManager.new()
	trackpanmanager.connect("pan_event_y_direction", self, "on_pan_action")

class TrackpadManager extends Node:

	var pan_value = 0.0
	var pan_y_direction = 1

	const PAN_INCREMENT = 0.5

	signal pan_event_y_direction

	func update_panning(event):
		# Check if the direction is still the same
		if -sign(event.delta.y) != pan_y_direction:
			pan_value = 0.0
			pan_y_direction = -sign(event.delta.y)
		pan_value += abs(event.delta.y)
		if pan_value > PAN_INCREMENT:
			self.emit_signal("pan_event_y_direction",pan_y_direction)
			pan_value = 0.0
	
	func reset_panning():
		pan_value = 0.0
		pan_y_direction = 0


# Register the actions for mouse wheel events
func register_mouse_wheel_events():

	if not InputMap.has_action("new_mouse_wheel_up"):
		var input_up = InputEventMouseButton.new()
		input_up.pressed = true
		input_up.button_index = BUTTON_WHEEL_UP

		InputMap.add_action("new_mouse_wheel_up")
		InputMap.action_add_event("new_mouse_wheel_up", input_up)

	if not InputMap.has_action("new_mouse_wheel_down"):
		var input_down = InputEventMouseButton.new()
		input_down.pressed = true
		input_down.button_index = BUTTON_WHEEL_DOWN

		InputMap.add_action("new_mouse_wheel_down")
		InputMap.action_add_event("new_mouse_wheel_down", input_down)


#########################################################################################################
##
## INPUT CAPTURE FUNCTIONS
##
#########################################################################################################

# Function to respond to unhandled mouse events
func on_unhandled_mouse_event(event):

	outputlog("on_unhandled_mouse_event",4)

	if tool_is_active:
		if Input.is_action_just_released("new_mouse_wheel_up",true):
			update_brush_size_slider(1)
		if Input.is_action_just_released("new_mouse_wheel_down",true):
			update_brush_size_slider(-1)

# Function to respond to unhandled key events
func on_unhandled_pan_event(event):

	outputlog("on_unhandled_pan_event",4)
	if tool_is_active:
		if trackpanmanager != null:
			trackpanmanager.update_panning(event)
		
# Function to respond to unhandled key events
func on_unhandled_key_event(event):

	outputlog("on_unhandled_key_event",4)

# Function to set up the 
func set_up_input_capture():

	outputlog("set_up_input_capture",0)
	var unhandledeventemitter = UnhandledEventEmitter.new()
	unhandledeventemitter.global = Global
	Global.World.add_child(unhandledeventemitter)
	unhandledeventemitter.connect("key_input", self, "on_unhandled_key_event")
	unhandledeventemitter.connect("mouse_input", self, "on_unhandled_mouse_event")
	unhandledeventemitter.connect("pan_input", self, "on_unhandled_pan_event")

# Class to emit unhandled events
class UnhandledEventEmitter extends Node:

	var global = null

	signal key_input
	signal mouse_input
	signal pan_input

	func _unhandled_input(event):

		if not global.Editor.SearchHasFocus:
			var focus = global.Editor.GetFocus()
			if focus == null || (not focus is LineEdit && not focus is Tree):
				if event is InputEventKey:
					self.emit_signal("key_input", event)

	func _input(event):

		if not global.Editor.SearchHasFocus:
			var focus = global.Editor.GetFocus()
			if focus == null || (not focus is LineEdit && not focus is Tree):
				if event is InputEventMouse:
					self.emit_signal("mouse_input", event)
				if event is InputEventPanGesture:
					self.emit_signal("pan_input", event)

#########################################################################################################
##
## RESIZE FUNCTIONS
##
#########################################################################################################

func resize_all_terrain( up_delta_sq: int, down_delta_sq: int, right_delta_sq: int, left_delta_sq: int):

	outputlog("resize_all_terrain",2)

	for level in Global.World.levels:
		var extraterrain = level.get_node_or_null(NODE_NAME)
		if extraterrain != null:
			extraterrain.resize(up_delta_sq, down_delta_sq, right_delta_sq, left_delta_sq)
	
	if splatpainter != null:
		splatpainter.resize(Global.World.WoxelDimensions)

	# Manage baking on the current level
	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null:
		extraterrain.unbake_terrain()
		if enable_baking && not tool_is_active:
			extraterrain.bake_terrain_to_texture()
			
func setup_resize_listener():

	outputlog("setup_resize_listener",1)
	Global.Editor.Windows["ChangeMapSize"].find_node("OkayButton").connect("pressed", self, "on_changemapsize_okay_button_pressed")

func on_changemapsize_okay_button_pressed():

	outputlog("on_changemapsize_okay_button_pressed",2)

	var window = Global.Editor.Windows["ChangeMapSize"]
	var up_delta_sq = window.find_node("TopSpinBox").value
	var down_delta_sq = window.find_node("BottomSpinBox").value
	var right_delta_sq = window.find_node("RightSpinBox").value
	var left_delta_sq = window.find_node("LeftSpinBox").value

	resize_all_terrain( up_delta_sq, down_delta_sq, right_delta_sq, left_delta_sq)

	# If the current terrain is baked then unbake and rebake it
	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null:
		if enable_baking:
			extraterrain.unbake_terrain()
			extraterrain.bake_terrain_to_texture()


#########################################################################################################
##
## VERSION CHECKER FUNCTIONS
##
#########################################################################################################

# Check whether a semver strng 2 is greater than string one. Only works on simple comparisons - DO NOT USE THIS FUNCTION OUTSIDE THIS CONTEXT
func compare_semver(semver1: String, semver2: String) -> bool:

	outputlog("compare_semver: semver1: " + str(semver1) + " semver2" + str(semver2),2)
	var semver1data = get_semver_data(semver1)
	var semver2data = get_semver_data(semver2)

	if semver1data == null || semver2data == null : return false

	if semver1data["major"] != semver2data["major"]:
		return semver1data["major"] < semver2data["major"]
	if semver1data["minor"] != semver2data["minor"]:
		return semver1data["minor"] < semver2data["minor"]
	if semver1data["patch"] != semver2data["patch"]:
		return semver1data["major"] < semver2data["major"]
	
	return false

# Parse the semver string
func get_semver_data(semver: String):

	var data = {}

	if semver.split(".").size() < 3: return null

	return {
		"major": int(semver.split(".")[0]),
		"minor": int(semver.split(".")[1]),
		"patch": int(semver.split(".")[2].split("-")[0])
	}


#########################################################################################################
##
## APPLY PREFERENCES FUNCTION
##
#########################################################################################################

func on_preferences_apply_pressed():

	outputlog("on_preferences_apply_pressed")

	var timer = Timer.new()
	timer.autostart = false
	timer.one_shot = true
	Global.Editor.get_node("Windows").add_child(timer)

	timer.start(0.5)
	yield(timer,"timeout")
	
	enable_baking = _lib_mod_config.enable_baking
	logging_level = _lib_mod_config.logging_level
	enable_bake_while_painting = _lib_mod_config.enable_bake_while_painting

	Global.Editor.get_node("Windows").remove_child(timer)
	timer.queue_free()

#########################################################################################################
##
## MAIN FUNCTION
##
#########################################################################################################

# Function to update the config label
func update_config_label(value, label: Label):

	label.text =  "%0d" % value

# Main Script
func start() -> void:

	outputlog("ExpandedTerrain Mod Has been loaded.")

	# If _Lib is installed then register with it
	if Engine.has_signal("_lib_register_mod"):
		# Register this mod with _lib
		Engine.emit_signal("_lib_register_mod", self)
		# Create a config builder to ensure we can update the offset if needed
		var _lib_config_builder = Global.API.ModConfigApi.create_config()
		_lib_mod_config = _lib_config_builder\
			.h_box_container().enter()\
				.label("Core Log Level ")\
				.option_button("core_log_level", 0, ["0","1","2","3","4"])\
					.connect_to_prop("loaded", self, "logging_level")\
					.connect_to_prop("updated", self, "logging_level")\
			.exit()\
			.check_button("enable_baking", true, "Enable Image Baking")\
				.connect_to_prop("loaded", self, "enable_baking")\
				.connect_to_prop("toggled", self, "enable_baking")\
			.check_button("enable_baking_while_painting", false, "Enable Baking While Painting")\
				.connect_to_prop("loaded", self, "enable_bake_while_painting")\
				.connect_to_prop("toggled", self, "enable_bake_while_painting")\
			.build()

		var _lib_mod_meta = Global.API.ModRegistry.get_mod_info("CreepyCre._Lib").mod_meta
		if _lib_mod_meta != null:
			if compare_semver("1.1.2", _lib_mod_meta["version"]):
				var update_checker = Global.API.UpdateChecker
				
				update_checker.register(Global.API.UpdateChecker.builder()\
														.fetcher(update_checker.github_fetcher("uchideshi34", "AdditionalTerrainSlots"))\
														.downloader(update_checker.github_downloader("uchideshi34", "AdditionalTerrainSlots"))\
														.build())
		
		Global.API.ModSignalingApi.connect_deferred("save_end", self, "on_save_end")
		Global.API.PreferencesWindowApi.connect("apply_pressed", self, "on_preferences_apply_pressed")

	# Load script for the ExtraTerrain class
	ExtraTerrain = ResourceLoader.load(Global.Root + "ExtraTerrain.gd", "GDScript", true)

	SplatPainter = ResourceLoader.load(Global.Root + "SplatPainter.gd", "GDScript", true)
	var shader = ResourceLoader.load(Global.Root + "shaders/splat_painter.shader", "Shader", true)
	splatpainter = SplatPainter.new(null, Global.World.WoxelDimensions, shader)
	splatpainter.base_brush = safe_load_texture("res://textures/brushes/soft_circle.png")

	make_expandedterrain_ui()
	_on_activate_terrain_button_pressed(false)

	var AreaBrush = ResourceLoader.load(Global.Root + "AreaBrush.gd", "GDScript", true)
	areabrush = AreaBrush.new()
	areabrush.is_active = true
	areabrush.radius_in_pixels = 256.0 * 8 * 0.5

	load_extraterrain_data()

	Global.Editor.Windows["NewLevel"].connect("popup_hide", self, "on_possible_new_level")

	# Connect to signals when we might go up or down a level including in the exporter
	Global.Editor.LevelOptions.connect("item_selected", self, "on_level_change")
	if Global.Editor.LevelOptions.get_parent().find_node("LevelDown") != null:
		Global.Editor.LevelOptions.get_parent().find_node("LevelDown").connect("pressed", self, "on_level_change",[0])
	if Global.Editor.LevelOptions.get_parent().find_node("LevelUp") != null:
		Global.Editor.LevelOptions.get_parent().find_node("LevelUp").connect("pressed", self, "on_level_change",[0])

	store_current_level = null

	setup_resize_listener()
	register_signals_for_copy_level()

	bake_all_terrain()

	set_up_input_capture()

	register_mouse_wheel_events()
	setup_trackpad_monitoring()
	
