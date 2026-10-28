extends Node2D
## A detached crown owns its landing loot, even if the stump is removed first.
const PICKUP := preload("res://scenes/world/item_pickup.tscn")
const DEBRIS := preload("res://scenes/world/rock_debris.gd")
var fall_direction := Vector2.RIGHT
var duration: float = 0.75
var elapsed: float = 0.0
var _texture: Texture2D
var _texture_offset := Vector2.ZERO
var _drop_item: InventoryItem
var _drop_count: int = 0
var _ground_origin := Vector2.ZERO
var _landed: bool = false
var crown: Sprite2D

func setup(texture: Texture2D, texture_offset: Vector2, item: InventoryItem, amount: int, direction: Vector2, ground_origin: Vector2, fall_seconds: float) -> void:
    _texture = texture
    _texture_offset = texture_offset
    _drop_item = item
    _drop_count = amount
    fall_direction = direction
    _ground_origin = ground_origin
    duration = maxf(0.05, fall_seconds)

func _ready() -> void:
    name = "FallingTreetop"
    add_to_group(&"falling_treetops")
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    # The cut crown must remain over the stump while their pixels overlap.
    z_index = 1
    crown = Sprite2D.new()
    crown.centered = false
    crown.texture = _texture
    crown.position = _texture_offset
    add_child(crown)

func _process(delta: float) -> void:
    if _landed:
        return
    elapsed = minf(duration, elapsed + delta)
    _apply_fall(elapsed / duration)
    if elapsed >= duration:
        _land()

func _fall_angle() -> float:
    if absf(fall_direction.x) > 0.5:
        return fall_direction.x * PI * 0.5
    # Depth falls use distinct diagonal poses, keeping the cut fixed and the
    # sprite rigid instead of sliding or flattening it toward the camera.
    return -PI * 0.375 if fall_direction.y < 0.0 else PI * 0.625

func _apply_fall(progress: float) -> void:
    var time := clampf(progress, 0.0, 1.0)
    # Rotate only: the severed trunk stays at its original cut point.
    transform = Transform2D(_fall_angle() * time * time, position)

func landing_position() -> Vector2:
    # Put the loot beneath the landed canopy, close to the original trunk.
    var distance := clampf(-_texture_offset.y * 0.45, 8.0, 40.0)
    var direction := Vector2.UP.rotated(_fall_angle())
    return (_ground_origin + direction * distance).round()

func _land() -> void:
    if _landed:
        return
    _landed = true
    var world := get_parent()
    var landing := landing_position()
    var debris := DEBRIS.new()
    debris.setup(_texture, true, fall_direction)
    world.add_child(debris)
    debris.global_position = landing
    if _drop_item != null:
        for index in range(_drop_count):
            var pickup := PICKUP.instantiate()
            pickup.item = _drop_item
            pickup.get_node("Sprite2D").scale = Vector2(0.5, 0.5)
            world.add_child(pickup)
            pickup.launch(landing)
    visible = false
    queue_free()
