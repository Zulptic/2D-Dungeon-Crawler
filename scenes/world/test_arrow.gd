extends Node2D
## Moves along the aim guide while sweeping the ground path for obstacles.

const SPEED := 300.0
const TRAIL_SECONDS := 0.085
const TRAIL_SEGMENTS := 10

var _direction := Vector2.RIGHT
var _shot := Vector2.ZERO
var _bend := Vector2.ZERO
var _range := 0.0
var _distance := 0.0
var _elapsed := 0.0
var _stopped := false
var _ray := PhysicsRayQueryParameters2D.new()

static func arc_bend(shot: Vector2) -> Vector2:
    # Ease the lift to zero at vertical aim, with no sideways displacement.
    var sideways := shot.normalized().x
    var height := minf(shot.length() * 0.22, 92.0)
    return Vector2.UP * height * sideways * sideways

static func arc_offset(shot: Vector2, bend: Vector2, progress: float) -> Vector2:
    return shot * progress + bend * (4.0 * progress * (1.0 - progress))

static func arc_tangent(shot: Vector2, bend: Vector2, progress: float) -> Vector2:
    return shot + bend * (4.0 - 8.0 * progress)

func launch(origin: Vector2, shot: Vector2, shooter: RID) -> void:
    global_position = origin
    z_index = 5
    _shot = shot
    _direction = shot.normalized()
    _range = shot.length()
    _bend = arc_bend(shot)
    _ray.collision_mask = 1
    _ray.exclude = [shooter]
    queue_redraw()

func _physics_process(delta: float) -> void:
    _elapsed += delta
    if not _stopped:
        var next_distance := minf(_range, _distance + SPEED * delta)
        _ray.from = global_position + _direction * _distance
        _ray.to = global_position + _direction * next_distance
        var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
        if hit.is_empty():
            _distance = next_distance
        else:
            _distance = global_position.distance_to(hit.position)
        _stopped = not hit.is_empty() or _distance >= _range

    if _stopped and _elapsed >= _distance / SPEED + TRAIL_SECONDS:
        queue_free()
        return
    queue_redraw()

func _draw() -> void:
    if _range <= 0.0:
        return
    var progress := _distance / _range
    var tip := arc_offset(_shot, _bend, progress)
    var tail_distance := maxf(0.0, (_elapsed - TRAIL_SECONDS) * SPEED)
    var trail_length := maxf(0.0, _distance - tail_distance)
    if trail_length > 0.0:
        for index in range(TRAIL_SEGMENTS):
            var from_distance := tail_distance + trail_length * float(index) / TRAIL_SEGMENTS
            var to_distance := tail_distance + trail_length * float(index + 1) / TRAIL_SEGMENTS
            var age := (_elapsed - to_distance / SPEED) / TRAIL_SECONDS
            var opacity := 0.70 * pow(clampf(1.0 - age, 0.0, 1.0), 2.0)
            var tail := arc_offset(_shot, _bend, from_distance / _range)
            var head := arc_offset(_shot, _bend, to_distance / _range)
            draw_line(tail, head, Color(1.0, 1.0, 1.0, opacity), 1.15, true)

    var fade := clampf(1.0 - (_elapsed - _distance / SPEED) / TRAIL_SECONDS, 0.0, 1.0) if _stopped else 1.0
    draw_set_transform(tip, arc_tangent(_shot, _bend, progress).angle())
    draw_line(Vector2(-8, 0), Vector2(-1, 0), Color(0.79, 0.63, 0.39, fade), 1.0)
    draw_line(Vector2(-9, -1), Vector2(-7, 0), Color(0.87, 0.84, 0.77, fade), 1.0)
    draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(-3, -1.5), Vector2(-3, 1.5)]), Color(0.94, 0.96, 1.0, fade))
