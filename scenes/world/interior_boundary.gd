extends CollisionPolygon2D
## Generates solid walls from a disabled CollisionPolygon2D used as an editable outline.

const WALL_PADDING := 16.0

func _ready() -> void:
    if polygon.size() < 3:
        return

    var bounds := Rect2(polygon[0], Vector2.ZERO)
    for point in polygon:
        bounds = bounds.expand(point)
    bounds = bounds.grow(WALL_PADDING)

    # Split the surrounding rectangle through the room so neither result contains a hole.
    var middle_y := bounds.get_center().y
    _add_walls(Rect2(bounds.position, Vector2(bounds.size.x, middle_y - bounds.position.y)))
    _add_walls(Rect2(Vector2(bounds.position.x, middle_y), Vector2(bounds.size.x, bounds.end.y - middle_y)))

func _add_walls(region: Rect2) -> void:
    var rectangle := PackedVector2Array([
        region.position,
        Vector2(region.end.x, region.position.y),
        region.end,
        Vector2(region.position.x, region.end.y)
    ])
    for wall_points in Geometry2D.clip_polygons(rectangle, polygon):
        var wall := CollisionPolygon2D.new()
        wall.polygon = wall_points
        wall.transform = transform
        get_parent().add_child.call_deferred(wall)
