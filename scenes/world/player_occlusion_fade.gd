extends Node
## Add to a Y-sorted prop and list its separate sprite roots, excluding its HUD.
## Pixel checks follow the current texture, growth stage, and visual shake.
@export var visual_paths: Array[NodePath] = [NodePath("../Sprite2D")]
@export_range(0.1, 1.0, 0.05) var faded_opacity: float = 0.45
@export_range(0.05, 1.0, 0.01) var fade_seconds: float = 0.18

# Head, torso, and legs; tool swing artwork alone should not fade nearby props.
const PLAYER_PROBES := [
    Vector2(-4, -22), Vector2(0, -22), Vector2(4, -22),
    Vector2(-4, -14), Vector2(0, -14), Vector2(4, -14),
    Vector2(-4, -6), Vector2(0, -6), Vector2(4, -6)
]
var _visuals: Array[Sprite2D] = []
var _original_alphas: Array[float] = []
var _player: Node2D
var _occluded: bool = false
var _fade: Tween
@onready var _prop: Node2D = get_parent() as Node2D

func _ready() -> void:
    for path in visual_paths:
        var visual := get_node_or_null(path) as Sprite2D
        if visual != null:
            _visuals.append(visual)
            _original_alphas.append(visual.modulate.a)

func _process(_delta: float) -> void:
    if not is_instance_valid(_player):
        _player = null
        for candidate in get_tree().get_nodes_in_group(&"player"):
            if candidate is Node2D and candidate.get_viewport() == get_viewport():
                _player = candidate
                break
    var covered := _player_is_covered()
    if covered == _occluded:
        return
    _occluded = covered
    if _fade != null and _fade.is_valid():
        _fade.kill()
    _fade = create_tween().set_parallel()
    for index in range(_visuals.size()):
        var visual := _visuals[index]
        if not is_instance_valid(visual):
            continue
        var alpha := _original_alphas[index] * (faded_opacity if covered else 1.0)
        _fade.tween_property(visual, "modulate:a", alpha, fade_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _player_is_covered() -> bool:
    if not is_instance_valid(_player) or not is_instance_valid(_prop):
        return false
    if not _player.is_visible_in_tree() or not _prop.is_visible_in_tree():
        return false
    var player_z := _effective_z(_player)
    for visual in _visuals:
        if not is_instance_valid(visual) or not visual.is_visible_in_tree() or visual.texture == null:
            continue
        var visual_z := _effective_z(visual)
        if visual_z < player_z:
            continue
        if visual_z == player_z and _player.global_position.y >= _prop.global_position.y:
            continue
        for probe in PLAYER_PROBES:
            var point := visual.to_local(_player.to_global(probe))
            if visual.is_pixel_opaque(point):
                return true
    return false

func _effective_z(item: CanvasItem) -> int:
    var value := item.z_index
    while item.z_as_relative:
        item = item.get_parent() as CanvasItem
        if item == null:
            break
        value += item.z_index
    return value
