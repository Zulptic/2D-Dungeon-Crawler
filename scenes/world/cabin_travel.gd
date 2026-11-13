extends ColorRect

const INTERIOR := preload("res://scenes/Cabin_Interior.tscn")
const WIPE := preload("res://scenes/world/cabin_wipe.gdshader")
const INTERIOR_LOCATION := Vector2(8192, 8192)
const INTERIOR_SAFE_MARGIN := 0.001

var player: CharacterBody2D
@onready var _inventory: Control = $"../Inventory"
@onready var _hotbar: Control = $"../Hotbar"
var _interior: Node2D
var _exit: Area2D
var _wipe: ShaderMaterial
var _inside := false
var _return_point: Vector2
var _outside_safe_margin: float

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

func _can_travel() -> bool:
	return not visible and is_instance_valid(player) and not player.movement_locked and not player.is_using_tool and not get_viewport().gui_is_dragging()

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
	# Keep collision recovery from alternating between nearby walls at cabin corners.
	if entering:
		_outside_safe_margin = player.safe_margin
		player.safe_margin = INTERIOR_SAFE_MARGIN
		player.facing = Vector2.UP
		player._play_animation("idle")
	else:
		player.safe_margin = _outside_safe_margin
	(_interior.get_node("Backdrop") as CanvasLayer).visible = entering
	player.get_node("PlacementPreview").placement_enabled = not entering
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

func _process(_delta: float) -> void:
	if _can_travel() and _exit.overlaps_body(player):
		_play_wipe(false)
