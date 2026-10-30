extends "res://scenes/world/item_pickup.gd"
## Fall from the crown, bounce once on the ground, then use the normal hover/pull pickup.
const FRUIT_GRAVITY: float = 180.0
var falling: bool = false
var bouncing: bool = false
var _fruit_height: float = hover_height
var _vertical_speed: float = 0.0
var _ground_velocity := Vector2.ZERO
var _fall_ground_start := Vector2.ZERO
var _fall_elapsed: float = 0.0
var _fall_seconds: float = 1.0
var _landing_pending: bool = false

func _ready() -> void:
    super._ready()
    add_to_group(&"falling_fruit")
    if item != null:
        add_to_group(StringName("falling_" + String(item.id) + "s"))

func fall_from(crown_point: Vector2, trunk_point: Vector2) -> void:
    _pulling = false
    _returning = false
    _tossing = false
    sprite.z_index = 4
    falling = true
    bouncing = false
    _landing_pending = true
    _fall_ground_start = Vector2(crown_point.x, trunk_point.y)
    global_position = _fall_ground_start
    _launch_from = trunk_point
    _land_at = trunk_point
    toss_distance = Vector2(10, 23)
    _fruit_height = maxf(hover_height, trunk_point.y - crown_point.y)
    _vertical_speed = 0.0
    _fall_elapsed = 0.0
    _fall_seconds = sqrt(2.0 * maxf(0.0, _fruit_height - hover_height) / FRUIT_GRAVITY)
    _update_visual()

func _update_visual() -> void:
    if falling:
        sprite.position = Vector2(0, -_fruit_height)
    else:
        super._update_visual()

func _physics_process(delta: float) -> void:
    if not falling:
        super._physics_process(delta)
        return
    if _landing_pending:
        _landing_pending = false
        _choose_landing()
    _fall_elapsed += delta
    _fruit_height -= _vertical_speed * delta + 0.5 * FRUIT_GRAVITY * delta * delta
    _vertical_speed += FRUIT_GRAVITY * delta
    if not bouncing:
        var progress := clampf(_fall_elapsed / maxf(0.01, _fall_seconds), 0.0, 1.0)
        global_position = _fall_ground_start.lerp(_land_at, progress)
    else:
        var candidate := global_position + _ground_velocity * delta
        var query := PhysicsPointQueryParameters2D.new()
        query.position = candidate
        query.collision_mask = 1
        query.collide_with_areas = false
        if get_world_2d().direct_space_state.intersect_point(query,1).is_empty():
            global_position = candidate
        else:
            _ground_velocity = Vector2.ZERO
    if _fruit_height <= hover_height and _vertical_speed >= 0.0:
        _fruit_height = hover_height
        if not bouncing:
            global_position = _land_at
            bouncing = true
            _vertical_speed = -_rng.randf_range(28.0, 36.0)
            _ground_velocity = Vector2.from_angle(_rng.randf_range(0.0,TAU)) * _rng.randf_range(10.0,18.0)
        else:
            falling = false
            sprite.z_index = _rest_z
            _retry = 0.12
    _update_visual()
