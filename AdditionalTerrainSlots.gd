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

var extraterrainui
var tool_panel = null
var activate_terrain_button = null
var store_level_ids = {}

var areabrush
var tool_is_active = false
var is_painting = false

const NODE_NAME = "ExtraTerrain987234"
const INTENSITY_CONSTANT = 0.25

const COMBINED_DATA_STORE = "UchideshiNodeData"
const EXTRATERRAINDATA = "extraterrain_data"

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
		outputlog("ExtraTerrain: " + str(ExtraTerrain),2)
		extraterrain = ExtraTerrain.new(level, Global.World.WoxelDimensions)
		extraterrain.Global = Global
		outputlog("extraterrain is null",2)
		outputlog("extraterrain: " + str(extraterrain),2)
		extraterrain.material.shader = ResourceLoader.load(Global.Root + "shaders/terrain.shader","Shader",true)
		extraterrain.textures = []
		for _i in extraterrainui.vbox.get_child_count():
			extraterrain.textures.append(null)
			extraterrain.set_terrain_texture(extraterrainui.get_terrain_entry(_i).texture_path,_i, false)
		extraterrain.build_all_atlases()
		extraterrain.update_splats()
		extraterrain.brush_image = safe_load_texture("res://textures/brushes/soft_circle.png")
		extraterrain.update_brush_data(8 * 0.5)

func _on_activate_terrain_button_pressed(button_pressed: bool):

	outputlog("_on_activate_terrain_button_pressed: " + str(button_pressed))

	for child in tool_panel.Align.get_children():
		if child != activate_terrain_button:
			child.visible = button_pressed

	# If there is an active extraterrain then show/hide it
	if Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME) != null:
		Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME).visible = button_pressed
	# Otherwise initialise it
	elif button_pressed:
		initialise_extraterrain(Global.World.GetCurrentLevel())

func on_brush_size_slider_changed(value: float):

	outputlog("on_brush_size_slider_changed: " + str(value),2)

	# Update the areabrush display
	areabrush.hide_brush_stroke_preview()
	areabrush.radius_in_pixels = 256.0 * value * 0.5

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
	
	extraterrainui.add_terrain_entries(4)
	for _i in 4:
		extraterrainui.set_terrain_entry(_i, Script.GetAssetList("Terrain")[_i])
	
	extraterrainui.set_active_terrain(0)

	extraterrainui.terrain_slots_button.connect("item_selected", self, "on_terrain_slots_number_selected")
	extraterrainui.fill_button.connect("pressed", self, "on_fill_button_pressed")
	extraterrainui.brush_size_slider.connect("value_changed", self, "on_brush_size_slider_changed")
	extraterrainui.connect("launch_terrain_window", self, "on_launch_terrain_window")
	extraterrainui.connect("terrain_changed", self, "on_terrainui_terrain_changed")
	extraterrainui.smoothblending_button.connect("toggled", self, "on_smoothblending_toggled")
	extraterrainui.show_hide_button.connect("toggled", self, "on_show_hide_button_toggled")

func on_show_hide_button_toggled(button_pressed: bool):

	outputlog("on_show_hide_button_toggled: " + str(button_pressed),2)
	if Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME) != null:
		Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME).visible = button_pressed


func on_smoothblending_toggled(button_pressed: bool):

	outputlog("on_smoothblending_toggled",2)
	if Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME) != null:
		Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME).set_smoothblending(button_pressed)

func on_terrainui_terrain_changed(texture_path: String, index: int):

	outputlog("on_terrainui_terrain_changed",2)

	if Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME) != null:
		Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME).set_terrain_texture(texture_path, index, true)

func on_launch_terrain_window(index: int):

	extraterrainui.terrainwindow.popup_centered_ratio(0.5)

func on_fill_button_pressed():

	outputlog("on_fill_button_pressed: " + str(extraterrainui.active_terrain_index),2)

	if Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME) != null:
		Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME).fill_channel(extraterrainui.active_terrain_index)

func on_terrain_slots_number_selected(item_selected: int):

	outputlog("on_terrain_slots_number_selected: " + str(item_selected),2)

	var current_count = extraterrainui.vbox.get_child_count()

	extraterrainui.set_number_terrain_entries(item_selected * 4 + 4)

	outputlog("current_count: " + str(current_count))
		
	for _i in range(current_count,item_selected * 4 + 4,1):
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
	
		extraterrain.set_splat_number(int(extraterrainui.vbox.get_child_count()/4.0))

		for _i in extraterrainui.vbox.get_child_count():
			outputlog("setting terrain at: " + str(_i),2)
			var entry = extraterrainui.get_terrain_entry(_i)
			outputlog("entry: " + str(entry),2)
			if entry != null:
				extraterrain.set_terrain_texture(entry.texture_path, _i, false)
		
		extraterrain.update_terrain_atlas()
		extraterrain.update_splats()

		if extraterrainui.active_terrain_index > (extraterrainui.terrain_slots_button.selected * 4 + 4):
			extraterrainui.set_active_terrain(0)

# Function to update the ui to reflect the current level's values
func update_ui_from_terrain(level):

	outputlog("update_ui_from_terrain: " + str(level) + " level.ID " + str(level.ID),2)

	var extraterrain = level.get_node_or_null(NODE_NAME)

	if extraterrain != null:
		outputlog("extraterrain: " + str(extraterrain),2)
		#set_property_but_block_signals(activate_terrain_button,"pressed",true)
		activate_terrain_button.pressed = true
		extraterrainui.set_block_signals(true)
		extraterrainui.terrain_slots_button.select(extraterrain.num_splats-1)
		extraterrainui.set_number_terrain_entries(extraterrain.num_splats * 4)
		for _i in extraterrain.num_splats * 4:
			extraterrainui.set_terrain_entry(_i, extraterrain.textures[_i].resource_path)
		extraterrainui.set_active_terrain(0)
		extraterrainui.smoothblending_button.pressed = extraterrain.smoothblending
		extraterrainui.show_hide_button.pressed = extraterrain.visible
		extraterrainui.set_block_signals(false)
	else:
		outputlog("extraterrain: " + str(extraterrain),2)
		activate_terrain_button.pressed = false

# When a level is changed
func on_level_change(_ignore_this):

	update_ui_from_terrain(Global.World.GetCurrentLevel())


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
		extraterrain.mark_all_splats_modified(false)

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
	# For each level
	for level in Global.World.levels:
		outputlog("check level",2)
		# Check if there is terrain data for it
		if has_extraterrain_data(level.ID):
			outputlog("there is data")
			# Initialise the level if so
			initialise_extraterrain(level)
			# Get its extraterrain record
			var extraterrain = level.get_node_or_null(NODE_NAME)
			outputlog("load_extraterrain_data: extraterrain: " + str(extraterrain))
			if extraterrain != null:
				extraterrain.load_from_data_record(get_extraterrain_data(level.ID))


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

# this method is automatically called every frame. delta is a float in seconds. can be removed from script.
func update(delta : float):

	if tool_is_active && is_painting:
		paint_terrain(delta * extraterrainui.intensity_slider.value)

# this method is called whenever a mod created tool detects a user input on the canvas
# This function is not used in this implementation as the active elements have moved to the Scatter Tool
func on_content_input(event):

	# do something after a mouse click is detected after the object tool created a new preview
	if event is InputEventMouseButton:
		# Start painting
		if event.button_index == BUTTON_LEFT:
			is_painting = event.pressed
				
	if event is InputEventMouseMotion:
		areabrush.set_update_parent_node(Global.World.GetCurrentLevel())
		areabrush.show_brush_stroke_preview(Global.WorldUI.get_MousePosition())

func on_tool_enable(tool_id):
	tool_is_active = true

func on_tool_disable(tool_id):
	tool_is_active = false
	areabrush.hide_brush_stroke_preview()
	is_painting = false

#########################################################################################################
##
## PAINT FUNCTION
##
#########################################################################################################

# Core paint function
func paint_terrain(rate: float):

	outputlog("paint_terrain: rate: " + str(rate),2)

	var extraterrain = Global.World.GetCurrentLevel().get_node_or_null(NODE_NAME)
	if extraterrain != null && extraterrainui.show_hide_button.pressed:
		extraterrain.paint_terrain(Global.WorldUI.get_MousePosition(),extraterrainui.active_terrain_index, rate, extraterrainui.brush_size_slider.value)

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
## MAIN FUNCTION
##
#########################################################################################################

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
			.build()

		var _lib_mod_meta = Global.API.ModRegistry.get_mod_info("CreepyCre._Lib").mod_meta
		if _lib_mod_meta != null:
			if compare_semver("1.1.2", _lib_mod_meta["version"]):
				var update_checker = Global.API.UpdateChecker
				
				update_checker.register(Global.API.UpdateChecker.builder()\
														.fetcher(update_checker.github_fetcher("uchideshi34", "ExpandedTerrain"))\
														.downloader(update_checker.github_downloader("uchideshi34", "ExpandedTerrain"))\
														.build())
		
		Global.API.ModSignalingApi.connect_deferred("save_end", self, "on_save_end")

	# Load script for the ExtraTerrain class
	ExtraTerrain = ResourceLoader.load(Global.Root + "ExtraTerrain.gd", "GDScript", true)

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
	
	update_ui_from_terrain(Global.World.GetCurrentLevel())
