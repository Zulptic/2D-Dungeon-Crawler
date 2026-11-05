extends Node2D
## Leaves detach across the actual canopy, flutter downward, then fade away.
const MAX_LEAVES_PER_TREE: int = 12
const MAX_LEAVES_PER_VIEWPORT: int = 40
var _texture: Texture2D
var _canopy_transform := Transform2D.IDENTITY
var _tree_transform := Transform2D.IDENTITY
var _count: int = 10
var _pieces: Array[Dictionary] = []
var _elapsed: float = 0.0
var _duration: float = 0.0
var _rng := RandomNumberGenerator.new()

func setup(texture: Texture2D, canopy_transform: Transform2D, tree_transform: Transform2D, count: int = 10) -> void:
    _texture = texture
    _canopy_transform = canopy_transform
    _tree_transform = tree_transform
    _count = count

func _ready() -> void:
    name = "FallingLeaves"
    add_to_group(&"tree_leaves")
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    z_index = 3
    # Keep the effect independent of subsequent shaking, growth, and tree removal.
    global_transform = _tree_transform
    _rng.randomize()
    if _texture == null:
        queue_free()
        return
    var count := _available_leaf_count()
    if count <= 0:
        queue_free()
        return
    var image := _texture.get_image()
    var sites: Array[Vector2i] = []
    for y in range(image.get_height() - 1):
        for x in range(image.get_width() - 1):
            if _is_leaf(image.get_pixel(x, y)) and _is_leaf(image.get_pixel(x + 1, y)) and _is_leaf(image.get_pixel(x, y + 1)) and _is_leaf(image.get_pixel(x + 1, y + 1)):
                sites.append(Vector2i(x, y))
    if sites.is_empty():
        queue_free()
        return
    var canopy_to_effect := global_transform.affine_inverse() * _canopy_transform
    var breeze := _rng.randf_range(-2.0, 2.0)
    var spacing := clampf(image.get_width() / 6.0, 3.0, 8.0)
    for index in range(count):
        var site := sites[_rng.randi_range(0, sites.size() - 1)]
        var origin := canopy_to_effect * Vector2(site)
        # Retry crowded release points so one rattle sprinkles the whole crown.
        for attempt in range(16):
            var crowded := false
            for other in _pieces:
                if origin.distance_squared_to(other.origin) < spacing * spacing:
                    crowded = true
                    break
            if not crowded:
                break
            site = sites[_rng.randi_range(0, sites.size() - 1)]
            origin = canopy_to_effect * Vector2(site)
        var piece := {
            "source": Rect2(Vector2(site), Vector2(2, 2)),
            "origin": origin,
            "delay": _rng.randf_range(0.0, 0.42),
            "lifetime": _rng.randf_range(2.1, 2.9),
            "speed": _rng.randf_range(8.0, 14.0),
            "acceleration": _rng.randf_range(16.0, 24.0),
            "terminal": _rng.randf_range(24.0, 32.0),
            "drift": breeze + _rng.randf_range(-2.5, 2.5),
            "sway": _rng.randf_range(2.0, 5.0),
            "frequency": _rng.randf_range(3.0, 5.5),
            "phase": _rng.randf_range(0.0, TAU),
            "tumble": _rng.randf_range(6.0, 10.0),
            "floor_y": maxf(origin.y, _rng.randf_range(-2.0, 5.0))
        }
        piece["fall_time"] = _fall_time(piece)
        _pieces.append(piece)
        _duration = maxf(_duration, float(piece.delay) + float(piece.lifetime))
    queue_redraw()

func get_live_leaf_count() -> int:
    var count: int = 0
    for piece in _pieces:
        # Reserve delayed leaves too, and release each slot once that leaf fades.
        if _elapsed < float(piece.delay) + float(piece.lifetime):
            count += 1
    return count

func _available_leaf_count() -> int:
    var total: int = 0
    var same_tree: int = 0
    for effect in get_tree().get_nodes_in_group(&"tree_leaves"):
        if effect == self or effect.get_viewport() != get_viewport():
            continue
        var count: int = effect.get_live_leaf_count()
        total += count
        # Standing-tree rattles and the detached crown share the trunk origin.
        if effect._tree_transform.origin.is_equal_approx(_tree_transform.origin):
            same_tree += count
    # Each leaf occupies at most four native pixels, including its flutter.
    return maxi(0, mini(_count, mini(MAX_LEAVES_PER_TREE - same_tree, MAX_LEAVES_PER_VIEWPORT - total)))

func _is_leaf(color: Color) -> bool:
    return color.a > 0.8 and color.g > color.r * 1.08 and color.g > color.b * 1.12

func _fall_distance(piece: Dictionary, age: float) -> float:
    var accelerating := minf(age, (float(piece.terminal) - float(piece.speed)) / float(piece.acceleration))
    return float(piece.speed) * accelerating + 0.5 * float(piece.acceleration) * accelerating * accelerating + float(piece.terminal) * (age - accelerating)

func _fall_time(piece: Dictionary) -> float:
    var height := float(piece.floor_y) - Vector2(piece.origin).y
    var accelerating := (float(piece.terminal) - float(piece.speed)) / float(piece.acceleration)
    var distance := _fall_distance(piece, accelerating)
    if height <= distance:
        return (sqrt(float(piece.speed) * float(piece.speed) + 2.0 * float(piece.acceleration) * height) - float(piece.speed)) / float(piece.acceleration)
    return accelerating + (height - distance) / float(piece.terminal)

func _piece_position(piece: Dictionary, age: float) -> Vector2:
    var falling := minf(maxf(0.0, age), float(piece.fall_time))
    var sideways := float(piece.drift) * falling + (sin(float(piece.phase) + falling * float(piece.frequency)) - sin(float(piece.phase))) * float(piece.sway)
    return Vector2(piece.origin) + Vector2(sideways, _fall_distance(piece, falling))

func _piece_alpha(piece: Dictionary, age: float) -> float:
    if age < 0.0:
        return 0.0
    return clampf((float(piece.lifetime) - age) / 0.7, 0.0, 1.0)

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed >= _duration:
        queue_free()
        return
    queue_redraw()

func _draw() -> void:
    if _texture == null:
        return
    for piece in _pieces:
        var age := _elapsed - float(piece.delay)
        var alpha := _piece_alpha(piece, age)
        if alpha <= 0.0:
            continue
        var point := _piece_position(piece, age).round()
        # Alternating broad and edge-on silhouettes suggests a tumbling leaf.
        var turn := cos(float(piece.phase) + minf(age, float(piece.fall_time)) * float(piece.tumble))
        var dimensions := Vector2(1 if absf(turn) < 0.35 else 2, 2)
        draw_texture_rect_region(_texture, Rect2(point, dimensions), piece.source, Color(1, 1, 1, alpha))
