class_name AreaBrush

#Global.World.GetCurrentLevel()
var parent_node_for_display = null
var brush_strokes_data = {"has_changed": false, "convex": [], "holes": []}
var last_mouse_position = null
var last_preview_position = null
var distance_sq_to_draw_new_polygon = 525 * 4.0
var radius_in_pixels = 256 * 2.0
var display_strokes = []
# Valid brush_type are "brush_circle" or "drag_rectangle"
var brush_type = "brush_circle"
var initial_mouse_position = null
var is_showing_brush_preview = false
var is_active = false
# Can be type = "line" or "polygon"
var circle_brush_preview_type = "line"
var display_preview_as_line = null

# Logging Functions
const ENABLE_LOGGING = true
const LOGGING_LEVEL = 3

func outputlog(msg,level=0):
	if ENABLE_LOGGING:
		if level <= LOGGING_LEVEL:
			printraw("(%d) <AreaBrush>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Function to create a dotted line texture
func create_dotted_texture(width: int, height: int, dotted_height: int, dotted_spacing: int, dotted_length: int) -> Texture:
	var img = Image.new()
	img.create(width, height, false, Image.FORMAT_RGBA8)
	img.lock()

	# Fill the background transparent
	img.fill(Color(1, 1, 1, 0))  # Transparent white background
	var data = img.get_data()
	var index

	# Draw horizontal dots (actually tiny rectangles)
	for x in range(0, width, dotted_spacing + dotted_length):
		for i in range(dotted_length):
			if (x + i) >= width:
				break
			for y in range(height / 2 - dotted_height / 2, height / 2 + dotted_height / 2):
				if y >= 0 and y < height:
					index = (y * width + (x+i)) * 4 + 3
					data[index] = 255

	img.unlock()
	img.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	
	var tex = ImageTexture.new()
	tex.create_from_image(img)
	return tex


# Function to set or update the parent node
func set_update_parent_node(parent_node):

	# Check if the parent node has changed
	if parent_node != parent_node_for_display:

		outputlog("set_update_parent_node: parent node changed: " + str(parent_node),2)

		for stroke in display_strokes:
			if parent_node_for_display != null:
				parent_node_for_display.remove_child(stroke)
			parent_node.add_child(stroke)
		parent_node_for_display = parent_node

# Function called when a brush stroke has finished
# Creates 
func end_brush_stroke():

	outputlog("end_brush_stroke",2)
	var output = {}

	last_mouse_position = null
	for entry in display_strokes:
		entry.visible = false
		entry.polygon = []
	
	output = {"has_changed": false, "convex": brush_strokes_data["convex"], "holes": brush_strokes_data["holes"]}
	
	brush_strokes_data = {"has_changed": false, "convex": [], "holes": []}

	if not is_active:
		return null

	return output

# Function to create a circle of points
func create_circle(centre: Vector2, radius_in_pixels: float):

	outputlog("create_circle",2)

	outputlog("centre: " + str(centre) + " x,y: " + str(centre/256.0) + " radius_in_pixels: " + str(radius_in_pixels),3)


	var points = []
	var num_per_square = 5
	var theta

	var num_points = max(int(radius_in_pixels * num_per_square / 256.0),30)
	theta = TAU / num_points

	for _i in range(0,num_points,1):
		points.append(Vector2.RIGHT.rotated(_i * theta) * radius_in_pixels + centre)

	return points

# Function to take a list of holes and return a list of new holes once a convex polygon has been applied
func update_stored_holes_with_new_polygon(stored_holes: Array, polygon):

	outputlog("update_stored_holes_with_new_polygon", 3)

	outputlog("stored_holes.size()" + str(stored_holes.size()), 3)

	var add_holes = []

	var _i = 0
	while _i < stored_holes.size():
		# Clip the hole against the shadow, ie finding all polygons of the hole that are not covered by the shadow
		# This should return the hole unchanged if there is no overlap or and empty arry if the shadow completely covers the hole
		var result = Geometry.clip_polygons_2d(stored_holes[_i],polygon)
		# If the shadow completely covers the hole then delete the hole from the stored_hole list
		if result.size() == 0:
			# Remove this entry
			stored_holes.remove(_i)
		else:
			stored_holes[_i] = result[0]
			for _j in range(1,result.size(),1):
				add_holes.append(result[_j])
			# Move to the next entry
			_i += 1
	
	stored_holes.append_array(add_holes)

	return stored_holes

# Function to merge the various polygons into as few polygons as possible.
# Note that it is assumed that the new brush stroke which is convex has been added to the first index of "convex" using push_front
func merge_brush_polygons(display_brush_strokes: Dictionary):

	var result = []
	var convex = []
	var holes = []
	var has_changed = false
	var holes_count
	var convex_count
	var index

	outputlog("merge_brush_polygons",2)
	outputlog("display_brush_strokes: " + str(display_brush_strokes),2)
	outputlog("display_brush_strokes['convex'].size(): " + str(display_brush_strokes["convex"].size()),2)
	outputlog("display_brush_strokes['holes'].size(): " + str(display_brush_strokes["holes"].size()),2)

	# If there are less than two convex brushstrokes, we haven't added any so return no change
	if display_brush_strokes["convex"].size() < 2:
		return {"has_changed": false, "convex": display_brush_strokes["convex"], "holes": display_brush_strokes["holes"]}
	
	for _i in range(1, display_brush_strokes["convex"].size(), 1):
		outputlog("_i: " + str(_i),2)
		holes_count = 0
		convex_count = 0
		# Return a result of merged polygons, noting this either means two unconnected polygons
		result = Geometry.merge_polygons_2d(display_brush_strokes["convex"][_i],display_brush_strokes["convex"][0])
		outputlog("result: " + str(result),2)
		for entry in result:
			# If this is a hole then add it to holes list
			if Geometry.is_polygon_clockwise(entry):
				holes.append(entry)
				holes_count += 1
			else:
				convex.append(entry)
				convex_count += 1
		# If there were no holes created and two convex, these are the same as before, so no change and we are done with this merge
		if holes_count == 0:
			# If there is one convex shape then this is a true merge, so log it as a change and break
			if convex_count == 1:
				has_changed = true
				index = _i
				break
			# If there are two then keep going noting that any of the holes must be part of one of the convex polygons so can't be affected by this
			if convex_count == 2:
				# reset the convex list as there is no change to _i or 0 so keep going until we get to the end of list
				convex = []
				continue
		# If we have made a hole, then we have to log it noting that these holes can not by definition overlap with any existing ones (as they are contained within convex shapes)
		if holes_count > 0:
			has_changed = true
			index = _i
			break
	
	# If nothing has changed then return the entry values
	if not has_changed:
		{"has_changed": has_changed, "convex": display_brush_strokes["convex"], "holes": display_brush_strokes["holes"]}

	outputlog("convex_count: " + str(convex_count) + "holes_count: " + str(holes_count),3)
	if convex_count == 1:
		# Compare the two active polygons to the existing holes and add any residual holes to the list. Note we need to do this twice because we haven't stored which hole belongs to which convex polygon
		# Note that polygon 0 can only affect holes within polygon _i and vice versa
		outputlog("index: " +str(index),3)
		display_brush_strokes["holes"] = update_stored_holes_with_new_polygon(display_brush_strokes["holes"], display_brush_strokes["convex"][0])
		#display_brush_strokes["holes"] = update_stored_holes_with_new_polygon(display_brush_strokes["holes"], display_brush_strokes["convex"][index])
		# Remove the current comparison polygon
		display_brush_strokes["convex"].remove(index)
		# Remove the original/new polygon
		display_brush_strokes["convex"].remove(0)
		# Add the newly created polygon
		display_brush_strokes["convex"].append(convex[0])
		# If we have created one of more new holes then add them to the list of holes, noting they can't overlap with anything else
		if holes_count > 0:
			outputlog("adding holes: holes_count: " + str(holes_count),3)
			# For each entry in the newly made holes list, add them to the master list of holes
			for entry in holes:
				display_brush_strokes["holes"].append(entry)

	return {"has_changed": has_changed, "convex": display_brush_strokes["convex"], "holes": display_brush_strokes["holes"]}

# Function to look at the mouse poistion and if it has changed enough then add a new polygon
func update_scatter_brush(mouseposition: Vector2):

	if not is_active:
		return

	outputlog("update_scatter_brush()",2)
	hide_brush_stroke_preview()

	if last_mouse_position != null:
		if brush_type == "brush_circle":
			if last_mouse_position.distance_squared_to(mouseposition) < distance_sq_to_draw_new_polygon:
				return
		elif brush_type == "drag_rectangle":
			# If we have moved less than 4 pixels don't draw
			if last_mouse_position.distance_squared_to(mouseposition) < 16.0:
				return
		else:
			return
	else:
		# Set the initial position for a drag rectangle
		if brush_type == "drag_rectangle":
			initial_mouse_position = mouseposition

	last_mouse_position = mouseposition

	var points

	if brush_type == "brush_circle":
		points = create_circle(mouseposition, radius_in_pixels)
		# Push front as that is where the merge_brush_polygons function expects the new brush polygon to be
		brush_strokes_data["convex"].push_front(points)
		brush_strokes_data["has_changed"] = true
		while brush_strokes_data["has_changed"]:
			brush_strokes_data = merge_brush_polygons(brush_strokes_data)
			
	elif brush_type == "drag_rectangle":
		brush_strokes_data["holes"] = []
		brush_strokes_data["has_changed"] = false
		brush_strokes_data["convex"] = [[initial_mouse_position, Vector2(mouseposition.x,initial_mouse_position.y), mouseposition, Vector2(initial_mouse_position.x,mouseposition.y)]]
	
	show_brush_strokes()

# Show a preview of a brush stroke before we start drawing
func show_brush_stroke_preview(mouseposition: Vector2):

	if not is_active:
		return

	# Don't show a preview if this a drag rectangle brush
	if brush_type == "drag_rectangle":
		return
	
	# If we are not already showing a brush preview then create one
	if not is_showing_brush_preview:

		var points
		points = create_circle(Vector2(0,0), radius_in_pixels)
		# If we are showing the brush stroke as a filled circle
		if circle_brush_preview_type == "polygon":
			# If the are no display strokes visible then
			if display_strokes.size() < 1:
				var polygon2d = Polygon2D.new()
				parent_node_for_display.add_child(polygon2d)
				parent_node_for_display.move_child(polygon2d,0)
				display_strokes.append(polygon2d)
				polygon2d.z_index = 2000
			display_strokes[0].polygon = points
			display_strokes[0].visible = true
			display_strokes[0].color = Color.yellow
		# If we are showing it as a circular line
		else:
			if display_preview_as_line == null:
				display_preview_as_line = make_preview_line2d()
				outputlog("display_preview_as_line")
			display_preview_as_line.visible = true
			points.append(points[0])
			display_preview_as_line.points = points
			display_preview_as_line.z_index = 2000
			if display_preview_as_line.get_parent() == null:
				parent_node_for_display.add_child(display_preview_as_line)
				parent_node_for_display.move_child(display_preview_as_line,0)
			else:
				if display_preview_as_line.get_parent() != parent_node_for_display:
					display_preview_as_line.get_parent().remove_child(display_preview_as_line)
					parent_node_for_display.add_child(display_preview_as_line)
					parent_node_for_display.move_child(display_preview_as_line,0)

		last_preview_position = mouseposition
		is_showing_brush_preview = true
	else:
		if last_preview_position.distance_squared_to(mouseposition) < 16.0:
			return
		else:
			last_preview_position = mouseposition
	
	if circle_brush_preview_type == "polygon":
		display_strokes[0].position = mouseposition
	else:
		display_preview_as_line.position = mouseposition

func make_preview_line2d():

	outputlog("make_preview_line2d",2)

	var line2d = Line2D.new()
	#var texture := load_image_texture(dotted_line_texture_path)
	var texture := create_dotted_texture(256, 16, 8, 64, 64) 
	texture.flags = 2
	line2d.texture = texture
	line2d.default_color = Color("ffd700")
	line2d.texture_mode = Line2D.LINE_TEXTURE_TILE
	line2d.width = 8
	line2d.z_index = 2000
	return line2d

# Function to hide the brush stroke preview
func hide_brush_stroke_preview():

	outputlog("areabrush.hide_brush_stroke_preview()",3)

	if last_preview_position != null:
		if circle_brush_preview_type == "polygon":
			if display_strokes.size() > 0:
				display_strokes[0].visible = false
		else:
			display_preview_as_line.visible = false
		
		is_showing_brush_preview = false
		last_preview_position = null

# Function to read the brush_strokes_data dictionary and update the display_strokes polygons to reflect that dictionary
func show_brush_strokes():

	outputlog("show_brush_strokes",2)

	var count_of_polygons = brush_strokes_data["convex"].size() + brush_strokes_data["holes"].size()
	var polygon2d

	outputlog("display_strokes.size(): " + str(display_strokes.size()),3)
	outputlog("count_of_polygons: " + str(count_of_polygons),3)

	# If we need to add any entries to the display_strokes list then do so
	for _i in brush_strokes_data["convex"].size() + brush_strokes_data["holes"].size() - display_strokes.size():
		outputlog("adding polygon: " + str(_i),3)
		polygon2d = Polygon2D.new()
		parent_node_for_display.add_child(polygon2d)
		parent_node_for_display.move_child(polygon2d,0)
		display_strokes.append(polygon2d)
	# If not then remove the unneeded ones
	for _i in display_strokes.size() - (brush_strokes_data["convex"].size() + brush_strokes_data["holes"].size()):
		outputlog("removing polygon: " + str(_i),3)
		polygon2d = display_strokes.pop_back()
		outputlog("pop_back successful")
		outputlog("polygon2d: " + str(polygon2d))
		if polygon2d != null:
			outputlog("polygon2d.get_parent(): " + str(polygon2d.get_parent()))
			if polygon2d.get_parent() != null:
				polygon2d.get_parent().remove_child(polygon2d)
			polygon2d.queue_free()
	
	# Add the convex polygons as green
	for _i in brush_strokes_data["convex"].size():
		outputlog("display_strokes[_i]: " + str(display_strokes[_i]),3)
		outputlog("display_strokes[_i].get_parent(): " + str(display_strokes[_i].get_parent()),3)
		
		if display_strokes[_i].get_parent() != parent_node_for_display:
			if display_strokes[_i].get_parent() != null:
				display_strokes[_i].get_parent().remove_child(display_strokes[_i])
			parent_node_for_display.add_child(display_strokes[_i])
			parent_node_for_display.move_child(display_strokes[_i],0)
		display_strokes[_i].polygon = brush_strokes_data["convex"][_i]
		display_strokes[_i].color = Color.yellow
		display_strokes[_i].visible = true
		display_strokes[_i].z_index = 2000
		display_strokes[_i].position = Vector2(0,0)
	
	# Add the holes as blue
	for _i in range(brush_strokes_data["convex"].size(),brush_strokes_data["holes"].size()+brush_strokes_data["convex"].size(),1):
		if display_strokes[_i].get_parent() != parent_node_for_display:
			display_strokes[_i].get_parent().remove_child(display_strokes[_i])
			parent_node_for_display.add_child(display_strokes[_i])
			parent_node_for_display.move_child(display_strokes[_i],0)
		
		display_strokes[_i].polygon = brush_strokes_data["holes"][_i - brush_strokes_data["convex"].size()]
		display_strokes[_i].color = Color.blue
		display_strokes[_i].visible = true