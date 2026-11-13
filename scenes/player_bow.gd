extends Node2D
## Hold to extend the aim guide, then release to launch a test arrow.

const ARROW := preload("res://scenes/world/test_arrow.gd")
const DRAW_SECONDS := 0.55
const MIN_SHOT_RANGE := 20.0
const DASH_SPACING := 8.5
const DASH_LENGTH := 3.4
const DASH_WIDTH := 0.4
const AIM_ORIGIN := Vector2(0, -11)

@onready var _player: CharacterBody2D = get_parent()
@onready var _mining: Node2D = $"../Mining"
@onready var _hotbar: Control = get_node_or_null("../../PlayerHUD/Screen/Hotbar")

var _held_bow: InventoryItem
var _draw_time := 0.0
var _aim := Vector2.ZERO

func _ready() -> void:
    if _hotbar != null:
        _hotbar.selection_changed.connect(_on_slot_changed)
    set_process(false)

func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
        return
    var item: InventoryItem = _mining.equipped_item()
    if item == null or item.subtype != &"bow" or not _can_aim() or not _points_into_world(event.position):
        return
    _held_bow = item
    _draw_time = 0.0
    _aim = _aim_from_screen(event.position)
    set_process(true)
    queue_redraw()
    get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
    if _held_bow == null or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
        return
    if _can_aim() and _points_into_world(event.position):
        var shot := _shot_offset(_aim_from_screen(event.position))
        if not shot.is_zero_approx():
            var arrow := ARROW.new()
            _player.get_parent().add_child(arrow)
            arrow.launch(to_global(AIM_ORIGIN), shot, _player.get_rid())
        get_viewport().set_input_as_handled()
    _clear_aim()

func _process(delta: float) -> void:
    if not _can_aim():
        _clear_aim()
        return
    _draw_time = minf(DRAW_SECONDS, _draw_time + delta)
    _aim = _aim_from_screen(get_viewport().get_mouse_position())
    queue_redraw()

func _draw() -> void:
    if _held_bow == null:
        return
    var shot := _shot_offset(_aim)
    if shot.is_zero_approx():
        return
    var bend := ARROW.arc_bend(shot)
    var progress := DASH_SPACING / ARROW.arc_tangent(shot, bend, 0.0).length()
    var fade_in := minf(1.0, _draw_time / 0.10)
    while progress < 1.0:
        var tangent := ARROW.arc_tangent(shot, bend, progress)
        var dash := tangent.normalized() * (DASH_LENGTH * 0.5)
        var point := AIM_ORIGIN + ARROW.arc_offset(shot, bend, progress)
        var end_fade := clampf((1.0 - progress) * tangent.length() / DASH_SPACING, 0.0, 1.0)
        draw_line(point - dash, point + dash, Color(1.0, 1.0, 1.0, 0.88 * fade_in * end_fade), DASH_WIDTH, true)
        progress += DASH_SPACING / tangent.length()

func _shot_offset(aim: Vector2) -> Vector2:
    var reach := aim.length()
    return aim.normalized() * lerpf(minf(MIN_SHOT_RANGE, reach), reach, _draw_ratio())

func _aim_from_screen(screen_position: Vector2) -> Vector2:
    var cursor := get_global_transform_with_canvas().affine_inverse() * screen_position
    return cursor - AIM_ORIGIN

func _draw_ratio() -> float:
    return ease(_draw_time / DRAW_SECONDS, 0.75)

func _can_aim() -> bool:
    return _hotbar != null and not _hotbar.input_locked and not _player.movement_locked and not _player.is_using_tool and not get_viewport().gui_is_dragging() and (_held_bow == null or _mining.equipped_item() == _held_bow)

func _points_into_world(point: Vector2) -> bool:
    return get_viewport().gui_get_hovered_control() == null and get_viewport_rect().has_point(point)

func _on_slot_changed(_slot: int) -> void:
    _clear_aim()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
        _clear_aim()

func _clear_aim() -> void:
    _held_bow = null
    set_process(false)
    queue_redraw()
