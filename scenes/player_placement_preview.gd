extends Node2D
## Previews and places the selected hotbar object on the ground grid.

enum PreviewState { HIDDEN, CLEAR, BLOCKED }

@export_range(1, 16, 1) var reach_tiles: int = 6

const SNAP_SUBDIVISIONS: int = 4
const GRID_COLOR := Color(1.0, 1.0, 1.0, 0.19)
const VALID_COLOR := Color(1.0, 1.0, 1.0, 0.48)
const BLOCKED_COLOR := Color(1.0, 0.03, 0.08, 0.56)
const PLACED_ITEM := preload("res://scenes/world/placed_item.gd")
const RESOURCE_GROUPS := [&"mineable_rocks", &"choppable_trees"]
const GHOST_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec4 tint : source_color;
uniform float tint_strength;

void fragment() {
    vec4 art = texture(TEXTURE, UV);
    COLOR = vec4(mix(art.rgb, tint.rgb, tint_strength), art.a * tint.a);
}
"""

@onready var _player: CharacterBody2D = get_parent()
@onready var _mining: Node2D = $"../Mining"
@onready var _hotbar: Control = get_node_or_null("../../PlayerHUD/Screen/Hotbar")
@onready var _ground: TileMapLayer = get_node_or_null("../../Ground")

var placement_enabled := true

var _blocking_layers: Array[TileMapLayer] = []
var _shape := RectangleShape2D.new()
var _query := PhysicsShapeQueryParameters2D.new()
var _grid: Node2D
var _grid_bounds := Rect2i()
var _blocked_cells: Dictionary[Vector2i, bool] = {}
var _placed_footprints: Array[Rect2] = []
var _requested_item: InventoryItem
var _requested_slot: int
var _requested_mouse := Vector2.ZERO
var _ghost: Sprite2D
var _ghost_material := ShaderMaterial.new()

func _ready() -> void:
    if _ground == null or _ground.tile_set == null:
        set_physics_process(false)
        return
    for child in _ground.get_parent().get_children():
        if child is TileMapLayer and child != _ground:
            _blocking_layers.append(child)

    _grid = Node2D.new()
    _grid.name = "PlacementGrid"
    _grid.hide()
    _ground.add_child(_grid)
    _grid.draw.connect(_draw_grid)

    var shader := Shader.new()
    shader.code = GHOST_SHADER
    _ghost_material.shader = shader
    _ghost = Sprite2D.new()
    _ghost.name = "Ghost"
    _ghost.centered = false
    _ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _ghost.z_index = 5
    _ghost.material = _ghost_material
    add_child(_ghost)

    _query.shape = _shape
    _query.collide_with_areas = false

func _exit_tree() -> void:
    if is_instance_valid(_grid):
        _grid.queue_free()

func _selected_placeable() -> InventoryItem:
    if not placement_enabled or _hotbar == null or _hotbar.input_locked or _player.movement_locked or get_viewport().gui_is_dragging():
        return null
    var item: InventoryItem = _mining.equipped_item()
    if item != null and item.category == InventoryItem.Category.PLACEABLE and item.placement_texture != null:
        return item
    return null

func _unhandled_input(event: InputEvent) -> void:
    if _grid == null or _requested_item != null or not event is InputEventMouseButton:
        return
    if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
        return
    var viewport := get_viewport()
    if viewport.gui_get_hovered_control() != null or not viewport.get_visible_rect().has_point(event.position):
        return
    var item := _selected_placeable()
    if item == null:
        return
    # Preserve the click location and selected stack until the physics check.
    _requested_item = item
    _requested_slot = _hotbar.selected_slot - 1
    _requested_mouse = _ground.get_global_transform_with_canvas().affine_inverse() * event.position
    viewport.set_input_as_handled()

func _physics_process(_delta: float) -> void:
    var item := _selected_placeable()
    visible = item != null
    _grid.visible = visible
    if not visible:
        _requested_item = null
        return

    var cell_size := Vector2(_ground.tile_set.tile_size)
    var step := cell_size / SNAP_SUBDIVISIONS
    var grid_origin := _ground.map_to_local(Vector2i.ZERO) - cell_size * 0.5
    _update_grid(grid_origin, step)

    if _requested_item != null:
        var requested := _requested_item
        _requested_item = null
        if item == requested and _hotbar.selected_slot - 1 == _requested_slot:
            var clicked_bounds := _snapped_bounds(_requested_mouse, item.get_placement_size(cell_size), grid_origin, step)
            if _placement_state(item, clicked_bounds, cell_size, step) == PreviewState.CLEAR:
                _place_item(item, clicked_bounds, cell_size)
                item = _selected_placeable()
                visible = item != null
                _grid.visible = visible
                if not visible:
                    return

    var viewport := get_viewport()
    if viewport.gui_get_hovered_control() != null or not viewport.get_visible_rect().has_point(viewport.get_mouse_position()):
        _ghost.hide()
        return

    var size := item.get_placement_size(cell_size)
    var bounds := _snapped_bounds(_ground.to_local(get_global_mouse_position()), size, grid_origin, step)
    var state := _placement_state(item, bounds, cell_size, step)
    _ghost.visible = state != PreviewState.HIDDEN
    if not _ghost.visible:
        return

    _ghost.texture = item.placement_texture
    var sprite_offset := _ghost.texture.get_size() * Vector2(0.5, 1.0)
    _ghost.global_transform = _ground.global_transform * Transform2D(0.0, _base_center(bounds) - sprite_offset)
    var valid := state == PreviewState.CLEAR
    _ghost_material.set_shader_parameter("tint", VALID_COLOR if valid else BLOCKED_COLOR)
    _ghost_material.set_shader_parameter("tint_strength", 0.36 if valid else 0.55)

func _snapped_bounds(mouse: Vector2, size: Vector2, origin: Vector2, step: Vector2) -> Rect2:
    var mouse_on_grid := (mouse - origin) / step
    # Center on the nearest vertical grid line and keep the sprite above the pointer.
    var base := origin + Vector2(roundf(mouse_on_grid.x), floorf(mouse_on_grid.y)) * step
    return Rect2(base - Vector2(size.x * 0.5, size.y), size)

func _base_center(bounds: Rect2) -> Vector2:
    return Vector2(bounds.get_center().x, bounds.end.y)

func _covering_cells(bounds: Rect2, origin: Vector2, step: Vector2) -> Rect2i:
    var first := Vector2i(((bounds.position - origin) / step).floor())
    var last := Vector2i(((bounds.end - origin) / step).ceil())
    return Rect2i(first, last - first)

func _place_item(item: InventoryItem, bounds: Rect2, cell_size: Vector2) -> void:
    var model: PlayerInventoryModel = _player.get_inventory_model()
    if model == null or model.get_item(&"hotbar", _requested_slot) != item:
        return

    var world := _ground.get_parent() as Node2D
    var body := PLACED_ITEM.new()
    body.item = item
    body.placement_cell_size = cell_size
    body.name = item.get_title()
    var sort_offset := Vector2(0, item.placement_sort_offset)
    body.transform = world.global_transform.affine_inverse() * _ground.global_transform * Transform2D(0.0, _base_center(bounds) + sort_offset)
    world.add_child(body, true)
    if body.get_parent() != world or not model.remove_quantity(&"hotbar", _requested_slot, 1):
        body.queue_free()
        return

    _placed_footprints.append(bounds)
    _grid.queue_redraw()
    var sprite := body.get_node("Sprite2D") as Sprite2D
    sprite.scale = Vector2.ONE * 0.90
    var pop := sprite.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    pop.tween_property(sprite, "scale", Vector2.ONE * 1.035, 0.10)
    pop.tween_property(sprite, "scale", Vector2.ONE, 0.08)

func _update_grid(origin: Vector2, step: Vector2) -> void:
    var screen_to_ground := _ground.get_global_transform_with_canvas().affine_inverse()
    var bounds := _covering_cells(screen_to_ground * get_viewport_rect(), origin, step)
    var blocked := _collect_blocked_cells()
    var placed: Array[Rect2] = []
    var world := _ground.get_parent() as Node2D
    var to_ground := _ground.global_transform.affine_inverse()
    for prop: Node2D in get_tree().get_nodes_in_group(PLACED_ITEM.GROUP):
        if prop.get_parent() == world and not prop.is_queued_for_deletion():
            placed.append(to_ground * prop.global_transform * prop.get_local_placement_bounds())
    if bounds != _grid_bounds or blocked != _blocked_cells or placed != _placed_footprints:
        _grid_bounds = bounds
        _blocked_cells = blocked
        _placed_footprints = placed
        _grid.queue_redraw()

func _collect_blocked_cells() -> Dictionary[Vector2i, bool]:
    var cells: Dictionary[Vector2i, bool] = {}
    for layer in _blocking_layers:
        if not layer.enabled:
            continue
        for cell in layer.get_used_cells():
            var center := layer.to_global(layer.map_to_local(cell))
            cells[_ground.local_to_map(_ground.to_local(center))] = true

    # Reserve each resource's full footprint, including parts beyond its collider.
    for group in RESOURCE_GROUPS:
        for prop: Node2D in get_tree().get_nodes_in_group(group):
            if prop.get_viewport() != get_viewport() or not prop.is_visible_in_tree() or prop.is_queued_for_deletion():
                continue
            var occupied: Rect2i = prop.mining_footprint
            occupied.position += _ground.local_to_map(_ground.to_local(prop.global_position))
            for y in range(occupied.position.y, occupied.end.y):
                for x in range(occupied.position.x, occupied.end.x):
                    cells[Vector2i(x, y)] = true
    return cells

func _draw_grid() -> void:
    if not _grid_bounds.has_area():
        return
    var cell_size := Vector2(_ground.tile_set.tile_size)
    var step := cell_size / SNAP_SUBDIVISIONS
    var origin := _ground.map_to_local(Vector2i.ZERO) - cell_size * 0.5
    var blockers: Array[Rect2i] = []
    for footprint in _placed_footprints:
        blockers.append(_covering_cells(footprint, origin, step))
    for cell in _blocked_cells:
        blockers.append(Rect2i(cell * SNAP_SUBDIVISIONS, Vector2i.ONE * SNAP_SUBDIVISIONS))
    var lines := PackedVector2Array()
    _append_blocked_grid_lines(lines, blockers, 0)
    _append_blocked_grid_lines(lines, blockers, 1)
    if lines.is_empty():
        return
    for index in range(lines.size()):
        lines[index] = origin + lines[index] * step
    _grid.draw_multiline(lines, GRID_COLOR, 0.4, true)

func _append_blocked_grid_lines(lines: PackedVector2Array, blockers: Array[Rect2i], axis: int) -> void:
    var along := 1 - axis
    blockers.sort_custom(func(a: Rect2i, b: Rect2i) -> bool: return a.position[along] < b.position[along])

    var direction := Vector2.ZERO
    direction[along] = 1.0
    var span_start := _grid_bounds.position[along]
    var span_end := _grid_bounds.end[along]
    for line in range(_grid_bounds.position[axis], _grid_bounds.end[axis] + 1):
        var line_origin := Vector2.ZERO
        line_origin[axis] = line
        var run_start := span_start
        var run_end := span_start
        for blocker in blockers:
            if blocker.position[along] >= span_end:
                break
            if line < blocker.position[axis] or line > blocker.end[axis]:
                continue
            var start := maxi(span_start, blocker.position[along])
            var end := mini(span_end, blocker.end[along])
            if end <= run_end:
                continue
            # Merge touching and overlapping spans so each line is drawn once.
            if start > run_end:
                if run_start < run_end:
                    lines.append(line_origin + direction * run_start)
                    lines.append(line_origin + direction * run_end)
                run_start = start
            run_end = end
        if run_start < run_end:
            lines.append(line_origin + direction * run_start)
            lines.append(line_origin + direction * run_end)

func _placement_state(item: InventoryItem, bounds: Rect2, cell_size: Vector2, step: Vector2) -> PreviewState:
    if not bounds.has_area():
        return PreviewState.HIDDEN

    var reach_squared := pow(float(reach_tiles) * cell_size.x + 0.001, 2.0)
    if _player.global_position.distance_squared_to(_ground.to_global(_base_center(bounds))) > reach_squared:
        return PreviewState.HIDDEN

    # Large props with custom outlines use the clicked base point for reach.
    if item.placement_collision_polygon.size() < 3:
        var inset := (cell_size * 0.5).min(bounds.size * 0.5)
        var first_center := bounds.position + inset
        var last_center := bounds.end - inset
        for x: float in [first_center.x, last_center.x]:
            for y: float in [first_center.y, last_center.y]:
                var point := _ground.to_global(Vector2(x, y))
                if _player.global_position.distance_squared_to(point) > reach_squared:
                    return PreviewState.HIDDEN

    var terrain_state := _terrain_state(bounds, step)
    if terrain_state != PreviewState.CLEAR:
        return terrain_state

    for occupied in _placed_footprints:
        if bounds.intersects(occupied):
            return PreviewState.BLOCKED

    # An inset lets bases touch at an edge without treating that as an overlap.
    _shape.size = bounds.size - Vector2(0.1, 0.1)
    _query.transform = _ground.global_transform * Transform2D(0.0, bounds.get_center())
    if _ground.get_world_2d().direct_space_state.intersect_shape(_query, 1).is_empty():
        return PreviewState.CLEAR
    return PreviewState.BLOCKED

func _terrain_state(bounds: Rect2, step: Vector2) -> PreviewState:
    # A shifted base can overlap extra terrain tiles. Sample just inside its edges.
    var first_cell := _ground.local_to_map(bounds.position + step * 0.5)
    var last_cell := _ground.local_to_map(bounds.end - step * 0.5)
    var footprint := Rect2i(first_cell, last_cell - first_cell + Vector2i.ONE)
    var blocked := false
    for y in range(footprint.position.y, footprint.end.y):
        for x in range(footprint.position.x, footprint.end.x):
            var cell := Vector2i(x, y)
            if _ground.get_cell_source_id(cell) == -1:
                return PreviewState.HIDDEN
            if _blocked_cells.has(cell):
                blocked = true
    return PreviewState.BLOCKED if blocked else PreviewState.CLEAR
