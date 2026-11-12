extends ColorRect

const INTERIOR := preload("res://scenes/Cabin_Interior.tscn")
const WIPE := preload("res://scenes/world/cabin_wipe.gdshader")
const INTERACT_ICON := preload("res://assets/hud/environmental_hud/input_keyboard_e.png")
const INTERIOR_LOCATION := Vector2(8192, 8192)
const EXIT_REACH := 24.0

var player: CharacterBody2D
@onready var _inventory: Control = $"../Inventory"
@onready var _hotbar: Control = $"../Hotbar"
var _interior: Node2D
var _exit: Marker2D
var _exit_prompt: Sprite2D
var _exit_pulse: Tween
var _wipe: ShaderMaterial
var _inside := false
var _return_point: Vector2

func _ready() -> void:
	name = "CabinWipe"
	z_index = 120
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wipe = ShaderMaterial.new()
	_wipe.shader = WIPE
	material = _wipe
	hide()
	set_process(false)

func try_enter() -> bool:
	if _inside or not _can_travel():
		return false
	_return_point = player.global_position
	_play_wipe(true)
	return true

func try_exit() -> bool:
	if not _inside or not _can_travel() or not _is_near_exit():
		return false
	_play_wipe(false)
	return true

func _can_travel() -> bool:
	return not visible and is_instance_valid(player) and not player.movement_locked and not player.is_using_tool and not get_viewport().gui_is_dragging()

func _is_near_exit() -> bool:
	return player.global_position.distance_squared_to(_exit.global_position) <= EXIT_REACH * EXIT_REACH

func _play_wipe(entering: bool) -> void:
	var inventory_had_input := _inventory.is_processing_input()
	var hotbar_was_locked: bool = _hotbar.input_locked
	_inventory.set_process_input(false)
	_hotbar.input_locked = true
	player.movement_locked = true
	_wipe.set_shader_parameter("covering", true)
	_wipe.set_shader_parameter("progress", 0.0)
	show()

	var tween := create_tween()
	tween.tween_property(_wipe, "shader_parameter/progress", 1.0, 0.28)
	tween.tween_callback(_move_player.bind(entering))
	tween.tween_interval(0.06)
	tween.tween_property(_wipe, "shader_parameter/progress", 1.0, 0.28)
	tween.tween_callback(func():
		hide()
		player.movement_locked = false
		_hotbar.input_locked = hotbar_was_locked
		_inventory.set_process_input(inventory_had_input)
	)

func _move_player(entering: bool) -> void:
	if entering and _interior == null:
		_create_interior()
	_inside = entering
	var arrival: Marker2D = _interior.get_node("Arrival")
	player.global_position = arrival.global_position if entering else _return_point
	player.reset_physics_interpolation()
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera.reset_smoothing()
		camera.force_update_scroll()
	set_process(_inside)
	_wipe.set_shader_parameter("covering", false)
	_wipe.set_shader_parameter("progress", 0.0)

func _create_interior() -> void:
	# Keep the outdoor world and player alive while the interior is in use.
	_interior = INTERIOR.instantiate()
	_interior.position = INTERIOR_LOCATION
	player.get_parent().add_child(_interior)
	_exit = _interior.get_node("Exit")
	_exit_prompt = Sprite2D.new()
	_exit_prompt.texture = INTERACT_ICON
	_exit_prompt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_exit_prompt.position.y = -8.0
	_exit_prompt.z_index = 7
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_exit_prompt.material = unlit
	_exit_prompt.hide()
	_exit.add_child(_exit_prompt)

func _process(_delta: float) -> void:
	var show_prompt: bool = not player.movement_locked and _is_near_exit()
	if _exit_prompt.visible == show_prompt:
		return
	_exit_prompt.visible = show_prompt
	if _exit_pulse != null:
		_exit_pulse.kill()
		_exit_pulse = null
	_exit_prompt.scale = Vector2.ONE * 0.5
	if show_prompt:
		_exit_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_exit_pulse.tween_property(_exit_prompt, "scale", Vector2.ONE * 0.625, 0.6)
		_exit_pulse.tween_property(_exit_prompt, "scale", Vector2.ONE * 0.5, 0.6)
