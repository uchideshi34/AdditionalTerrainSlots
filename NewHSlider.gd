class_name NewHSlider

var script_class = "tool"

var hslider: HSlider
var spinbox: SpinBox
var hbox: HBoxContainer
var timer: Timer
var slider_wait_time = 1.0
var value = 0.0

signal emit_history_event_signal
signal value_changed

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
			printraw("(%d) <NewHSlider>: " % OS.get_ticks_msec())
			print(msg)
	else:
		pass

# Create a linked slider because the standard one whinges about property values not being set
func _init(vbox: Container = null, default: float = 0.0, minimum: float = 0.0, maximum: float = 1.0, step: float = 0.1, exp_edit: bool = false, log_level: int = 0):

	logging_level = log_level

	hbox = HBoxContainer.new()
	hbox.size_flags_vertical = 1
	hbox.size_flags_horizontal = 3

	outputlog("make_hslider",2)

	hslider = HSlider.new()
	hslider.max_value = maximum
	hslider.min_value = minimum
	
	hslider.step = step
	hslider.size_flags_horizontal = 3
	hslider.size_flags_vertical = 3
	hslider.exp_edit = exp_edit

	timer = Timer.new()
	timer.one_shot = true
	timer.auto_start = false
	timer.wait_time = slider_wait_time
	timer.connect("timeout", self, "_on_timer_timeout")
	
	spinbox = SpinBox.new()
	spinbox.max_value = maximum
	spinbox.min_value = minimum
	spinbox.value = default
	spinbox.step = step
	spinbox.align = 1
	spinbox.connect("value_changed",self,"slider_change",[hslider,false])
	hslider.connect("value_changed",self,"slider_change",[spinbox,true])
	hslider.connect("value_changed",self,"core_value_changed")
	hslider.connect("value_changed",self,"start_slider_timer")
	
	hbox.add_child(hslider)
	hbox.add_child(spinbox)
	hbox.add_child(timer)

	spinbox.get_line_edit().expand_to_text_length = true

	# Silly work around to get the default value to display properly
	hslider.value = default
	if default != minimum:
		hslider.value = minimum
	elif default != maximum:
		hslider.value = maximum
	hslider.value = default
	
	value = default

	if vbox != null:
		vbox.add_child(hbox)

func _on_timer_timeout():

	emit_signal("emit_history_event_signal")

func core_value_changed(value):

	outputlog("core_value_changed",2)

	self.emit_signal("value_changed",value)

# Link spinbox and slider
func slider_change(new_value: float, target, suppress_signal: bool):

	outputlog("slider changed: " + str(value),2)

	value = new_value

	if suppress_signal:
		target.set_block_signals(true)
		target.value = new_value
		target.set_block_signals(false)
	else:
		target.value = new_value
		
	
# Function to update the values of a slider and its spinbox without triggering further signals
func slider_and_spinbox_change(new_value: float, suppress_signal: bool):

	outputlog("slider_and_spinbox_change",2)

	value = new_value

	if suppress_signal:
		slider_change(new_value, hslider, suppress_signal)
		slider_change(new_value, spinbox, suppress_signal)		
	else:
		# Note that this should automatically update the spinbox via signals
		hslider.value = new_value
	
# Function to start or reset the slider timer. Once the timer completes we call a function to emit the record history event.
func start_slider_timer(value: float = -1.0):

	outputlog("start_slider_timer",2)

	if value < 0.0:
		timer.start(slider_wait_time)
	else:
		timer.start(value)