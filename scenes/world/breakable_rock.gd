extends StaticBody2D
signal broken(rock: Node2D)
@export_range(1, 100, 1) var max_health: int = 3
@export var drop_item: InventoryItem = preload("res://scenes/items/crushed_stone.tres")
@export_range(1, 99, 1) var drop_min: int = 1
@export_range(1, 99, 1) var drop_max: int = 3
@export var mining_footprint := Rect2i(0, 0, 1, 1)
@export var drop_offset := Vector2.ZERO
@export_range(0, 10, 1) var required_mining_tier: int = 0
const DEBRIS := preload("res://scenes/world/rock_debris.gd")
const PICKUP := preload("res://scenes/world/item_pickup.tscn")
@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: Node2D = $HealthBar
@onready var health_fill: Sprite2D = $HealthBar/Fill
var health: int = 3
var _display_health: float = 3.0
var _breaking: bool = false
var _health_tween: Tween
var _shake: Tween
var _sprite_origin := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
const SHAKE_DIRECTIONS := [Vector2.UP, Vector2(1,-1), Vector2.RIGHT, Vector2(1,1), Vector2.DOWN, Vector2(-1,1), Vector2.LEFT, Vector2(-1,-1)]

func _ready() -> void:
    health = max_health
    _display_health = max_health
    _sprite_origin = sprite.position
    _rng.randomize()
    health_fill.texture = health_fill.texture.duplicate()
    _show_health(float(health))
    health_bar.visible = false

func covers_tile(layer: TileMapLayer, cell: Vector2i) -> bool:
    var anchor := layer.local_to_map(layer.to_local(global_position))
    return Rect2i(anchor + mining_footprint.position, mining_footprint.size).has_point(cell)

func can_mine_with(tool: InventoryItem) -> bool:
    return tool != null and tool.category == InventoryItem.Category.TOOL and tool.subtype == &"pickaxe" and tool.mining_tier >= required_mining_tier

func take_pickaxe_hit(tool: InventoryItem, hit_direction: Vector2 = Vector2.ZERO) -> bool:
    if _breaking or health <= 0 or tool == null or tool.subtype != &"pickaxe":
        return false
    if not can_mine_with(tool):
        # A weak pickaxe still makes contact, but cannot damage or drop the ore.
        health_bar.visible = true
        _spawn_chips(false, hit_direction)
        _play_hit_shake()
        return false
    return take_hit(tool.roll_damage(InventoryItem.DamageTarget.ROCK), hit_direction)

func take_hit(damage: int = 1, hit_direction: Vector2 = Vector2.ZERO) -> bool:
    if _breaking or damage <= 0:
        return false
    health = maxi(0, health - damage)
    _breaking = health == 0
    health_bar.visible = true
    if _health_tween != null and _health_tween.is_valid():
        _health_tween.kill()
    _spawn_chips(_breaking,hit_direction)
    if _breaking:
        _break_rock()
        return true
    _health_tween = create_tween()
    _health_tween.tween_method(_show_health, _display_health, float(health), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    _play_hit_shake()
    return true

func _play_hit_shake() -> void:
    if _shake != null and _shake.is_valid():
        _shake.kill()
    _set_shake_offset(Vector2.ZERO)
    _shake = create_tween()
    var previous := Vector2.ZERO
    var last_direction: int = -1
    for step in range(3):
        var direction := _rng.randi_range(0, SHAKE_DIRECTIONS.size() - 1)
        if direction == last_direction:
            direction = (direction + _rng.randi_range(1, 7)) % SHAKE_DIRECTIONS.size()
        last_direction = direction
        var offset: Vector2 = SHAKE_DIRECTIONS[direction]
        _shake.tween_method(_set_shake_offset, previous, offset, 0.025)
        previous = offset
    _shake.tween_method(_set_shake_offset, previous, Vector2.ZERO, 0.035)

func _set_shake_offset(offset: Vector2) -> void:
    # A one-pixel visual shake keeps the health bar and physics body steady.
    var pixels := offset.round()
    sprite.position = _sprite_origin + pixels

func _show_health(value: float) -> void:
    _display_health = value
    var columns := clampi(ceili(value / max_health * 31.0 - 0.00001), 0, 31)
    var crop := health_fill.texture as AtlasTexture
    crop.region = Rect2(3, 2, maxi(1, columns), 2)
    health_fill.visible = columns > 0

func _world_parent() -> Node:
    var world: Node = get_tree().current_scene
    if world == null or world.get_viewport() != get_viewport():
        world = get_parent().get_parent() if get_parent() is TileMapLayer else get_parent()
    return world

func _spawn_chips(shatter: bool, direction: Vector2) -> void:
    var effect := DEBRIS.new()
    effect.setup(sprite.texture,shatter,direction)
    _world_parent().add_child(effect)
    effect.global_position = global_position + _sprite_origin

func _break_rock() -> void:
    if _shake != null and _shake.is_valid():
        _shake.kill()
    _set_shake_offset(Vector2.ZERO)
    health_bar.visible = false
    var world := _world_parent()
    if drop_item != null:
        var count := _rng.randi_range(mini(drop_min, drop_max), maxi(drop_min, drop_max))
        for index in range(count):
            var pickup := PICKUP.instantiate()
            pickup.item = drop_item
            pickup.get_node("Sprite2D").scale = Vector2(0.5,0.5)
            world.add_child(pickup)
            pickup.launch(to_global(drop_offset))
    broken.emit(self)
    visible = false
    $CollisionShape2D.set_deferred("disabled", true)
    if get_parent() is TileMapLayer:
        var layer := get_parent() as TileMapLayer
        layer.erase_cell(layer.local_to_map(layer.to_local(global_position)))
    else:
        queue_free()
