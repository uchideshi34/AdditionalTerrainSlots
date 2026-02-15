extends Reference

# Custom History Record for additional terrain slots
# v1.0.0
var type = "additionalterrain"
var main_script = null

var history_record: Dictionary

func set_splats(data: Array):

	if history_record["level"] in Global.World.levels:
		var extraterrain = history_record["level"].get_node_or_null(main_script.NODE_NAME)
		if extraterrain != null:
			if extraterrain.width == history_record["splat_size"].x && extraterrain.height == history_record["splat_size"].y:
				main_script.outputlog("valid extraterrain: ",2)
				# If this is the current level and we have baked the terrain, then unbake it
				if history_record["level"] == Global.World.GetCurrentLevel() && main_script.enable_baking:
					extraterrain.unbake_terrain()

				for _i in data.size():
					main_script.outputlog("data record for splats _i: " + str(_i),2)
					extraterrain.splatImages[_i].create_from_data(extraterrain.width, extraterrain.height, false, Image.FORMAT_RGBA8, data[_i])
				extraterrain.update_splat_textures_from_images()

				# If this is the current level and we want to bake the terrain, then do so
				if history_record["level"] == Global.World.GetCurrentLevel() && main_script.extraterrainui.show_hide_button.pressed && main_script.enable_baking:
					extraterrain.bake_terrain_to_texture()

func undo():

	main_script.outputlog("undo: " + str(history_record["level"]),2)

	set_splats(history_record["before_splats_data"])
	

func redo():

	main_script.outputlog("redo: " + str(history_record["level"]),2)

	set_splats(history_record["after_splats_data"])

	


