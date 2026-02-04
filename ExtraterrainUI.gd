class_name ExtraTerrainUI

var scrollcontainer
var vbox
var active_terrain_index = 0
var show_hide_button = null
var fill_button = null
var terrain_slots_button = null
var brush_size_slider = null
var intensity_slider = null
var terrainwindow = null
var global
var reference_to_script
var terrainwindow_terrain_index_selected = 0
var smoothblending_button = null

# Logging Functions
const ENABLE_LOGGING = true
var logging_level = 2

signal launch_terrain_window
signal terrain_changed

#########################################################################################################
##
## UTILITY FUNCTIONS
##
#########################################################################################################

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= logging_level:
			printraw("(%d) <ExtraTerrainUI>: " % OS.get_ticks_msec())
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

# Return the name of the texture and the pack it is in from the resource path string as a dictionary
func find_texture_name_and_pack(texture_string):

	var texture_name
	var pack_name
	var pack_id
	var array: Array

	# If this is a custom pack then find the pack name and split out the 
	if texture_string.left(12) == "res://packs/":
		array = texture_string.right(12).split("/")
		pack_id = array[0]
		texture_name = array[-1].split(".")[0]
		for pack in global.Header.AssetManifest:
			if pack.ID == pack_id:
				pack_name = pack.Name
	# If this is a native DD pack, then return the name
	elif texture_string.left(15) == "res://textures/":
		array = texture_string.right(6).split("/")
		texture_name = array[-1].split(".")[0]
		pack_id = "nativeDD"
		pack_name = "Default"
	# Otherwise return a "Not Set" string
	else:
		texture_name = "Not Set"
		pack_id = "n/a"
		pack_name = "Not Set"
	
	return {"texture_name": texture_name,"pack_name": pack_name, "pack_id": pack_id}

#########################################################################################################
##
## INIT FUNCTIONS
##
#########################################################################################################

# Init functions - not requiring any parameters. Note this is mostly ui creation
func _init(parent: Control = null, global_ref = null, index: int = -1):

	if parent == null: return
	global = global_ref

	show_hide_button = CheckButton.new()
	show_hide_button.pressed = true
	show_hide_button.text = "Show Terrain"
	parent.add_child(show_hide_button)

	var NewHSlider = ResourceLoader.load(global.Root + "NewHSlider.gd", "GDScript", true)
	var slider_label = Label.new()
	slider_label.text = "Brush Size"
	parent.add_child(slider_label)
	brush_size_slider = NewHSlider.new(parent, 8, 1, 25, 1, false, 0)

	var intensity_label = Label.new()
	intensity_label.text = "Intensity"
	parent.add_child(intensity_label)
	intensity_slider = NewHSlider.new(parent, 4.0, 0.2, 8.0, 0.1, false, 0)

	var hbox = HBoxContainer.new()
	var slots_label = Label.new()
	slots_label.text = "Slots Number"
	terrain_slots_button = OptionButton.new()
	terrain_slots_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for _i in range(1,5,1):
		terrain_slots_button.add_item(str(_i * 4))
	parent.add_child(hbox)
	hbox.add_child(slots_label)
	hbox.add_child(terrain_slots_button)

	var label = Label.new()
	label.text = "Terrain List"
	parent.add_child(label)

	# Make a scroll container and add a vbox to it
	scrollcontainer = ScrollContainer.new()
	scrollcontainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	parent.add_child(scrollcontainer)
	if index > -1:
		parent.move_child(scrollcontainer, index)

	vbox = VBoxContainer.new()
	scrollcontainer.add_child(vbox)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scrollcontainer.rect_min_size = Vector2(0,0)

	fill_button = Button.new()
	fill_button.text = "Fill"
	parent.add_child(fill_button)

	smoothblending_button = CheckButton.new()
	smoothblending_button.text = "Smooth Blending"
	smoothblending_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(smoothblending_button)

	var terrainwindow_template = ResourceLoader.load(global.Root + "ui/terrainwindow.tscn", "", true)
	terrainwindow = terrainwindow_template.instance()
	global.Editor.get_child("Windows").add_child(terrainwindow)
	terrainwindow.connect("about_to_show", self, "on_terrainwindow_about_to_show")
	terrainwindow.find_node("PackList").connect("item_selected", self, "on_terrainwindow_pack_list_item_selected")
	terrainwindow.find_node("TextureMenu").connect("item_selected", self, "on_terrainwindow_terrain_item_selected")

#########################################################################################################
##
## TERRAIN WINDOW FUNCTIONS
##
#########################################################################################################

# Populate the terrain window
func on_terrainwindow_about_to_show():

	outputlog("on_terrainwindow_about_to_show",2)

	update_terrainwindow_pack_list()

# sorter for reducing array in place
class MyCustomSorter:
	static func sort_ascending_pack_name(a, b):
		return a["pack_name"] < b["pack_name"]
	
func update_terrainwindow_pack_list():

	outputlog("update_terrainwindow_pack_list",2)

	var terrain_list = reference_to_script.GetAssetList("Terrain")
	if terrain_list == null: return

	var pack_list = []
	var pack_id_list = []
	
	for terrain_path in terrain_list:
		var entry = find_texture_name_and_pack(terrain_path)
		if not entry["pack_id"] in pack_id_list && entry["pack_id"] != "nativeDD":
			pack_id_list.append(entry["pack_id"])
			pack_list.append(entry.duplicate(true))
	
	pack_list.sort_custom(MyCustomSorter,"sort_ascending_pack_name")

	if global.Header.UsesDefaultAssets:
		pack_list.push_front({"pack_id": "nativeDD", "pack_name": "Default"})

	var packListPath = terrainwindow.find_node("PackList")

	packListPath.clear()
	for pack_entry in pack_list:
		packListPath.add_item(pack_entry["pack_name"])
		packListPath.set_item_metadata(packListPath.get_item_count()-1,pack_entry["pack_id"])
		packListPath.set_item_tooltip(packListPath.get_item_count()-1,pack_entry["pack_name"])
	
	if packListPath.get_item_count() > 0:
		packListPath.select(0)
		on_terrainwindow_pack_list_item_selected(0)

func on_terrainwindow_pack_list_item_selected(index: int):

	var terrain_list = reference_to_script.GetAssetList("Terrain")
	var pack_id = terrainwindow.find_node("PackList").get_item_metadata(index)

	var textureMenu = terrainwindow.find_node("TextureMenu") 

	textureMenu.clear()
	for terrain_path in terrain_list:
		var entry = find_texture_name_and_pack(terrain_path)
		if entry["pack_id"] == pack_id:
			textureMenu.add_item(entry["texture_name"], safe_load_texture(terrain_path))
			textureMenu.set_item_metadata(textureMenu.get_item_count()-1, terrain_path)

func on_terrainwindow_terrain_item_selected(index: int):

	var textureMenu = terrainwindow.find_node("TextureMenu")

	self.set_terrain_entry(terrainwindow_terrain_index_selected, textureMenu.get_item_metadata(index))
	self.emit_signal("terrain_changed", textureMenu.get_item_metadata(index), terrainwindow_terrain_index_selected)
	terrainwindow.hide()

#########################################################################################################
##
## CORE FUNCTIONS
##
#########################################################################################################

func set_active_terrain(index: int):

	if index < vbox.get_child_count():
		vbox.get_child(index).active_button.pressed = true

func get_terrain_entry(index):

	if index < vbox.get_child_count():
		return vbox.get_child(index)
	else:
		return null

func add_terrain_entry():

	outputlog("add_terrain_entry",2)

	var entry = TerrainEntry.new()

	vbox.add_child(entry)
	entry.connect("button_toggled", self, "_on_entry_button_toggled")
	entry.connect("choose_texture_button_pressed", self, "_on_entry_choose_texture_button_pressed")

# 
func _on_entry_choose_texture_button_pressed(index: int):

	terrainwindow_terrain_index_selected = index

	self.emit_signal("launch_terrain_window",index)

func set_number_terrain_entries(number: int):

	if number > vbox.get_child_count():
		add_terrain_entries(number - vbox.get_child_count())
	if number < vbox.get_child_count():
		remove_terrain_entries(vbox.get_child_count() - number)

func add_terrain_entries(number: int):

	for _i in number:
		add_terrain_entry()
	
	scrollcontainer.rect_min_size += Vector2(0,64*number + 8*number)

func remove_terrain_entries(number: int):

	for _i in number:
		remove_terrain_entry(vbox.get_child_count()-1)
	
	scrollcontainer.rect_min_size -= Vector2(0,64*number + 8*number)

func remove_terrain_entry(index: int):

	if index < vbox.get_child_count():
		var entry = vbox.get_child(index)
		vbox.remove_child(entry)
		entry.queue_free()

func _on_entry_button_toggled(index: int):

	for _i in vbox.get_child_count():
		if _i != index:
			vbox.get_child(_i).set_active_button_false_without_signal()
	
	active_terrain_index = index

func set_terrain_entry(index: int, texture_path: String):

	outputlog("set_terrain_entry: " + str(index) + " texture_path: " + str(texture_path),2)

	if index < vbox.get_child_count():
		var entry = vbox.get_child(index)
		entry.set_texture(texture_path)

#########################################################################################################
##
## Terrain Entry Class
##
#########################################################################################################

class TerrainEntry extends HBoxContainer:

	var texture_rect = null
	var active_button = null
	var texture_path = ""
	var choose_texture_button = null

	signal button_toggled
	signal choose_texture_button_pressed

	# Logging Functions
	const ENABLE_LOGGING = true
	var logging_level = 2

	func outputlog(msg,level=0):
		if ENABLE_LOGGING:
			if level <= logging_level:
				printraw("(%d) <TerrainEntry>: " % OS.get_ticks_msec())
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
	
	# Function to return the custom asset thumbnail url from a resource path
	func find_thumbnail_url(resource_path: String):

		var thumbnail_extension = ".png"
		var thumbnail_url

		thumbnail_url = "user://.thumbnails/" + resource_path.md5_text() + thumbnail_extension

		# Check if the thumbnail url is valid, if not create a thumbnail url for the embedded thumbnail
		if not ResourceLoader.exists(thumbnail_url):
			thumbnail_url = "res://packs/" + resource_path.split('/')[3] + "/thumbnails/" + resource_path.md5_text() + thumbnail_extension
		# If the thumbnail can't be found then return null
		if not ResourceLoader.exists(thumbnail_url):
			thumbnail_url = null
			outputlog("thumbnail not found: " + str(thumbnail_url),2)

		return thumbnail_url

	func downscale_and_remove_alpha(tex: ImageTexture) -> ImageTexture:
		if tex == null:
			return null

		# Get CPU image
		var img: Image = tex.get_data()

		# Resize to 32x32
		img.resize(64, 64, Image.INTERPOLATE_LANCZOS)

		# Convert to RGB (drops alpha)
		img.convert(Image.FORMAT_RGB8)

		# Upload back to GPU
		var out := ImageTexture.new()
		out.create_from_image(img, Texture.FLAG_FILTER)

		return out
	
	func change_texture_size(tex: Texture, size: Vector2) -> ImageTexture:

		if tex == null:
			return null

		# Get CPU image
		var img: Image = tex.get_data()

		# Resize to 32x32
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)

		# Upload back to GPU
		var out := ImageTexture.new()
		out.create_from_image(img, Texture.FLAG_FILTER)
		return out


	func _init():

		self.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		texture_rect = TextureRect.new()
		texture_rect.size_flags_vertical = 3
		texture_rect.stretch_mode = 6
		self.add_child(texture_rect)

		active_button = Button.new()
		active_button.toggle_mode = true
		var icon = ResourceLoader.load("res://ui/icons/misc/checkbox_on.png")
		active_button.icon = change_texture_size(icon, Vector2(24,24))
		self.add_child(active_button)
		active_button.connect("toggled", self, "_on_active_button_toggled")
		active_button.hint_tooltip = "Toggle to activate this terrain slot for painting."

		choose_texture_button = Button.new()
		choose_texture_button.icon = ResourceLoader.load("res://ui/icons/buttons/texture_menu.png")
		self.add_child(choose_texture_button)
		choose_texture_button.connect("pressed", self, "_on_choose_texture_button_pressed")

	func set_texture(resource_path: String):

		outputlog("set_texture: " + str(resource_path),2)

		texture_path = resource_path
		texture_rect.texture = downscale_and_remove_alpha(safe_load_texture(find_thumbnail_url(resource_path)))
	
	func set_active_button_false_without_signal():

		active_button.set_block_signals(true)
		active_button.pressed = false
		active_button.set_block_signals(false)

	func _on_active_button_toggled(button_pressed: bool):

		if button_pressed:
			self.emit_signal("button_toggled", self.get_index())
		else:
			active_button.pressed = true
	
	func _on_choose_texture_button_pressed():

		self.emit_signal("choose_texture_button_pressed", self.get_index())






