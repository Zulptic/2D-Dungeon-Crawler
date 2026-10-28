extends Area2D
@export var item: InventoryItem
@export_range(1, 999999, 1) var quantity: int = 1
@export var toss_distance := Vector2(8.0, 13.0)
var _blocked_collector: Node2D
@export_range(0.5, 4.0, 0.25) var pickup_radius_tiles: float = 1.5
@export_range(0.08, 0.5, 0.01) var pull_duration: float = 0.18
@export_range(1.0, 6.0, 0.5) var shadow_radius: float = 2.5
@onready var sprite: Sprite2D = $Sprite2D
var _collected: bool = false
var _retry: float = 0.0
var _rng := RandomNumberGenerator.new()
var _hover_phase: float = 0.0
var _tossing: bool = false
var _launch_pending: bool = false
var _launch_from := Vector2.ZERO
var _land_at := Vector2.ZERO
var _toss_elapsed: float = 0.0
var _toss_duration: float = 0.26
var _arc_height: float = 10.0
var _pulling: bool = false
var _returning: bool = false
var _pull_target: Node2D
var _pull_start := Vector2.ZERO
var _pull_elapsed: float = 0.0
var _pull_lift: float = 4.0
var _return_from := Vector2.ZERO
var _return_elapsed: float = 0.0
var _return_lift: float = 4.0
var _rest_z: int = 0
const RETURN_DURATION: float = 0.12

func _ready() -> void:
    var pickup_shape := CircleShape2D.new()
    pickup_shape.radius = pickup_radius_tiles*16.0
    $CollisionShape2D.shape = pickup_shape
    _rest_z = sprite.z_index
    _rng.randomize()
    _hover_phase = _rng.randf_range(0.0,TAU)
    sprite.texture = item.icon if item != null else null
    _update_visual()

func dropped_by(collector: Node2D) -> void:
    # A deliberate drop stays on the ground until its owner leaves pickup range.
    _blocked_collector = collector

func launch(origin: Vector2) -> void:
    _pulling = false
    _returning = false
    _pull_target = null
    sprite.z_index = _rest_z
    global_position = origin
    _launch_from = origin
    _land_at = origin
    _toss_elapsed = 0.0
    _toss_duration = _rng.randf_range(0.23,0.3)
    _arc_height = _rng.randf_range(8.0,12.0)
    _tossing = true
    _launch_pending = true
    _retry = 0.0
    _update_visual()

func _choose_landing() -> void:
    # Choose the landing point during physics processing, away from solid bodies.
    var query := PhysicsPointQueryParameters2D.new()
    query.collision_mask = 1
    query.collide_with_areas = false
    query.collide_with_bodies = true
    for attempt in range(8):
        var angle := _rng.randf_range(0.0,TAU)
        var candidate := (_launch_from + Vector2.from_angle(angle)*_rng.randf_range(minf(toss_distance.x,toss_distance.y),maxf(toss_distance.x,toss_distance.y))).round()
        query.position = candidate
        if get_world_2d().direct_space_state.intersect_point(query,1).is_empty():
            _land_at = candidate
            return
    _land_at = _launch_from

func _process(delta: float) -> void:
    _hover_phase = fmod(_hover_phase + delta*TAU*0.75,TAU)
    _update_visual()

func _update_visual() -> void:
    var lift := 4.0 + sin(_hover_phase)*0.75
    if _pulling:
        var progress := clampf(_pull_elapsed/pull_duration,0.0,1.0)
        lift = lerpf(_pull_lift,10.0,progress*progress)
    elif _returning:
        var progress := clampf(_return_elapsed/RETURN_DURATION,0.0,1.0)
        lift = lerpf(_return_lift,lift,smoothstep(0.0,1.0,progress))
    elif _tossing:
        var progress := clampf(_toss_elapsed/_toss_duration,0.0,1.0)
        lift += sin(progress*PI)*_arc_height
    sprite.position = Vector2(0.0,-lift)

func _draw() -> void:
    # The root follows the ground point; only the item sprite rises above this circle.
    draw_circle(Vector2.ZERO,shadow_radius,Color(0,0,0,0.26),true,-1.0,true)

func _physics_process(delta: float) -> void:
    if _collected:
        return
    if _tossing:
        if _launch_pending:
            _launch_pending = false
            _choose_landing()
        _toss_elapsed = minf(_toss_duration,_toss_elapsed+delta)
        var progress := _toss_elapsed/_toss_duration
        var eased := 1.0-(1.0-progress)*(1.0-progress)
        global_position = _launch_from.lerp(_land_at,eased)
        if progress >= 1.0:
            global_position = _land_at
            _tossing = false
        _update_visual()
        return
    if _pulling:
        _advance_pull(delta)
        return
    if _returning:
        _advance_return(delta)
        return
    _retry -= delta
    if _retry > 0.0 or item == null:
        return
    _retry = 0.05
    var radius_squared := pow(pickup_radius_tiles*16.0,2.0)
    if is_instance_valid(_blocked_collector) and global_position.distance_squared_to(_blocked_collector.global_position) > radius_squared:
        _blocked_collector = null
    for body in get_overlapping_bodies():
        if is_instance_valid(_blocked_collector) and body == _blocked_collector:
            continue
        if not body.has_method("get_inventory_model") or global_position.distance_squared_to(body.global_position)>radius_squared:
            continue
        var inventory: PlayerInventoryModel = body.get_inventory_model()
        if inventory != null and quantity > 0 and inventory.available_capacity(item) > 0:
            _begin_pull(body)
            return

func _begin_pull(target: Node2D) -> void:
    _pulling = true
    _pull_target = target
    _pull_start = global_position
    _pull_elapsed = 0.0
    _pull_lift = -sprite.position.y
    # Keep the traveling item visible when approaching from behind the player.
    sprite.z_index = 4
    _update_visual()

func _advance_pull(delta: float) -> void:
    if not is_instance_valid(_pull_target) or _pull_target.is_queued_for_deletion() or not _pull_target.is_inside_tree():
        _return_to_ground()
        return
    var inventory: PlayerInventoryModel = _pull_target.get_inventory_model()
    if inventory == null or inventory.available_capacity(item) < 1:
        _return_to_ground()
        return
    _pull_elapsed = minf(pull_duration,_pull_elapsed+delta)
    var progress := _pull_elapsed/pull_duration
    global_position = _pull_start.lerp(_pull_target.global_position,progress*progress)
    _update_visual()
    if progress >= 1.0:
        # Storage changes only on arrival. Another pickup may have used the last slot.
        var collected := mini(quantity, inventory.available_capacity(item))
        if collected > 0 and inventory.collect_item(item, collected):
            quantity -= collected
            if quantity == 0:
                _collected = true
                queue_free()
            else:
                # Leave the uncollected remainder in this same world node.
                _return_to_ground()
        else:
            _return_to_ground()

func _return_to_ground() -> void:
    _pulling = false
    _pull_target = null
    _returning = true
    _return_from = global_position
    _return_elapsed = 0.0
    _return_lift = -sprite.position.y

func _advance_return(delta: float) -> void:
    _return_elapsed = minf(RETURN_DURATION,_return_elapsed+delta)
    var progress := _return_elapsed/RETURN_DURATION
    global_position = _return_from.lerp(_pull_start,smoothstep(0.0,1.0,progress))
    _update_visual()
    if progress >= 1.0:
        global_position = _pull_start
        _returning = false
        sprite.z_index = _rest_z
        _retry = 0.15
        _update_visual()
