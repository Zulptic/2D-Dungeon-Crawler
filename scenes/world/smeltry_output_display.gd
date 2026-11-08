extends Node2D
## Finished goods remain visible above the Smeltry until the player presses E.
const FRAME := preload("res://assets/hud/smeltry/Smeltry_FinishedItemFrame.png")
const STACK_COUNT := preload("res://scenes/item_stack_count.gd")
const BOB_AMPLITUDE: float = 0.75
const BOB_FREQUENCY: float = 0.75
const CYCLE_SECONDS: float = 2.5
const DISPLAY_SCALE: float = 0.5

var _base_position := Vector2.ZERO
var _phase: float = 0.0
var _cycle_time: float = 0.0
var _shown_index: int = 0
var _outputs: Array[Dictionary] = []
var _icon: Sprite2D
var _count: Control

func _ready() -> void:
    scale = Vector2.ONE * DISPLAY_SCALE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    z_index = 8
    var unlit := CanvasItemMaterial.new()
    unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
    material = unlit
    var frame := Sprite2D.new()
    frame.name = "Frame"
    frame.texture = FRAME
    add_child(frame)
    _icon = Sprite2D.new()
    _icon.name = "Item"
    add_child(_icon)
    _count = STACK_COUNT.new()
    _count.name = "StackCount"
    _count.suffix = "x"
    _count.position = Vector2(-14, 3)
    _count.size = Vector2(24, 7)
    add_child(_count)
    hide()

func set_anchor(anchor: Vector2) -> void:
    _base_position = anchor.round()
    position = _base_position

func set_outputs(outputs: Array[Dictionary]) -> void:
    _outputs = outputs
    visible = not outputs.is_empty()
    if not visible:
        _shown_index = 0
        _cycle_time = 0.0
        return
    _shown_index %= _outputs.size()
    _show_current()

func _show_current() -> void:
    var output: Dictionary = _outputs[_shown_index]
    _icon.texture = output.item.icon
    _count.amount = int(output.quantity)

func _process(delta: float) -> void:
    if not visible:
        return
    _phase = fmod(_phase + delta * TAU * BOB_FREQUENCY, TAU)
    position = _base_position + Vector2(0.0, sin(_phase) * BOB_AMPLITUDE)
    if _outputs.size() > 1:
        _cycle_time += delta
        if _cycle_time >= CYCLE_SECONDS:
            _cycle_time = fmod(_cycle_time, CYCLE_SECONDS)
            _shown_index = (_shown_index + 1) % _outputs.size()
            _show_current()
