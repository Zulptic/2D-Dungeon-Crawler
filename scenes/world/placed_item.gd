extends StaticBody2D
## Recoverable objects return as the same item with one pickaxe hit.

const GROUP := &"placed_objects"
const OCCLUSION_FADE := preload("res://scenes/world/player_occlusion_fade.gd")
const INTERACTION_GROUP := &"placed_item_interactables"
const INTERACT_ICON := preload("res://assets/hud/environmental_hud/input_keyboard_e.png")
const PROMPT_REST_SCALE := Vector2(0.5, 0.5)
const PROMPT_PULSE_SCALE := Vector2(0.625, 0.625)
const CABIN_DOOR := Rect2i(88, 92, 25, 35)
const CABIN_THRESHOLD := Vector2(100, 132)
const CABIN_REACH := 24.0
const PICKUP := preload("res://scenes/world/item_pickup.tscn")
const FIRE_SHEET := preload("res://assets/items/Bricks_01-Sheet.png")
const FIRE_FRAME_SECONDS: float = 0.125
const SMELTRY_QUEUE := preload("res://scenes/smeltry_queue.gd")
const OUTPUT_DISPLAY := preload("res://scenes/world/smeltry_output_display.gd")
const PROGRESS_BAR := preload("res://scenes/world/smeltry_progress_bar.tscn")
const EJECT_INTERVAL: float = 0.12
const LIGHT_SIZE := Vector2i(102, 78)
const LIGHT_PIXEL_SIZE: int = 3

static var _fire_frames: Array[AtlasTexture] = []
static var _light_texture: ImageTexture

@export var item: InventoryItem
@export var fixed_in_place := false
var placement_cell_size := Vector2(16, 16)
var _collision: Node2D
var _artwork: Sprite2D

var _outline: Sprite2D
var _prompt: Sprite2D
var _prompt_pulse: Tween
var _off_texture: Texture2D
var _fire_timer: Timer
var _fire_frame: int = 0
var _fire_light: PointLight2D
var _light_tween: Tween
var smeltry_queue: Node
var _output_display: Node2D
var _progress_bar: Node2D
var _progress_fill: ColorRect
var _eject_timer: Timer
var _eject_outputs: Array[Dictionary] = []

func _ready() -> void:
    if item == null:
        return
    _setup_geometry()
    if not fixed_in_place:
        add_to_group(GROUP)
    if item.subtype not in [&"furnace", &"bed", &"house"]:
        return
    add_to_group(INTERACTION_GROUP)
    var unlit := CanvasItemMaterial.new()
    unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

    _outline = Sprite2D.new()
    _outline.name = "InteractionOutline"
    _outline.centered = false
    var is_cabin := item.subtype == &"house"
    var image := _artwork.texture.get_image()
    _outline.texture = _make_outline(image.get_region(CABIN_DOOR) if is_cabin else image)
    _outline.position = _artwork.offset - Vector2.ONE
    if is_cabin:
        _outline.position += Vector2(CABIN_DOOR.position)
    _outline.show_behind_parent = not is_cabin
    _outline.material = unlit
    _outline.hide()
    _artwork.add_child(_outline)

    _prompt = Sprite2D.new()
    _prompt.name = "InteractPrompt"
    _prompt.texture = INTERACT_ICON
    _prompt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _prompt.material = unlit
    _prompt.position = Vector2(0, -25)
    if is_cabin:
        _prompt.position = _artwork.position + _artwork.offset + Vector2(CABIN_THRESHOLD.x, CABIN_DOOR.position.y - 8)
    _prompt.scale = PROMPT_REST_SCALE
    _prompt.z_index = 7
    _prompt.hide()
    add_child(_prompt)

    if item.subtype != &"furnace":
        return
    _setup_fire()
    smeltry_queue = SMELTRY_QUEUE.new()
    smeltry_queue.name = "SmeltryQueue"
    add_child(smeltry_queue)
    _eject_timer = Timer.new()
    _eject_timer.name = "EjectTimer"
    _eject_timer.one_shot = true
    _eject_timer.timeout.connect(_eject_next)
    add_child(_eject_timer)
    _output_display = OUTPUT_DISPLAY.new()
    _output_display.name = "FinishedItems"
    add_child(_output_display)
    # Keep the scaled frame centered, with a five-pixel gap above the artwork.
    var art_rect := _artwork.get_rect()
    var display_half_height: float = _output_display.FRAME.get_height() * _output_display.scale.y * 0.5
    _output_display.set_anchor(_artwork.position + Vector2(art_rect.get_center().x, art_rect.position.y - display_half_height - 5.0))
    _progress_bar = PROGRESS_BAR.instantiate()
    _progress_bar.position = _artwork.position + art_rect.position + Vector2(31, 7)
    add_child(_progress_bar)
    _progress_fill = _progress_bar.get_node("Fill")
    smeltry_queue.changed.connect(_update_smeltry_visuals)

func has_completed_output() -> bool:
    return smeltry_queue != null and not smeltry_queue.get_completed_outputs().is_empty()

func eject_completed() -> bool:
    if smeltry_queue == null or is_queued_for_deletion():
        return false
    if not _eject_outputs.is_empty():
        return true
    _eject_outputs = smeltry_queue.get_completed_outputs()
    return _eject_next()

func _eject_next() -> bool:
    if _eject_outputs.is_empty() or is_queued_for_deletion():
        return false
    var output: Dictionary = _eject_outputs.front()
    var pickup := PICKUP.instantiate()
    pickup.item = output.item
    pickup.quantity = 1
    pickup.toss_distance = Vector2(14.0, 22.0)
    var world := get_parent()
    world.add_child(pickup)
    # Transfer one item only after its world pickup exists.
    if pickup.get_parent() != world or not smeltry_queue.remove_completed(pickup.item, 1):
        pickup.queue_free()
        _eject_outputs.clear()
        return false
    pickup.launch_forward(to_global(Vector2(0, -4)), global_transform.y)
    output.quantity -= 1
    if output.quantity == 0:
        _eject_outputs.pop_front()
    if not _eject_outputs.is_empty():
        _eject_timer.start(EJECT_INTERVAL)
    return true

func _update_smeltry_visuals() -> void:
    _output_display.set_outputs(smeltry_queue.get_completed_outputs())
    var remaining: float = smeltry_queue.get_work_remaining_ratio()
    var active := remaining > 0.0
    _progress_bar.visible = active
    if active:
        var rows := clampi(ceili(remaining * 15.0), 1, 15)
        # Keep the bottom of the 3×15 slot fixed as the green fill drains.
        _progress_fill.offset_top = 20.0 - rows
    _set_fire_active(active)

func _setup_fire() -> void:
    if _fire_frames.is_empty():
        var frame_size := FIRE_SHEET.get_size() * 0.5
        for row in range(2):
            for column in range(2):
                var frame := AtlasTexture.new()
                frame.atlas = FIRE_SHEET
                frame.region = Rect2(Vector2(column, row) * frame_size, frame_size)
                frame.filter_clip = true
                _fire_frames.append(frame)

    _off_texture = _artwork.texture
    _fire_timer = Timer.new()
    _fire_timer.name = "FireTimer"
    _fire_timer.wait_time = FIRE_FRAME_SECONDS
    _fire_timer.timeout.connect(_advance_fire)
    add_child(_fire_timer)

    if _light_texture == null:
        _light_texture = _make_light_texture()
    _fire_light = PointLight2D.new()
    _fire_light.name = "FireLight"
    _fire_light.texture = _light_texture
    _fire_light.position = Vector2(0, -9)
    _fire_light.color = Color(1.0, 0.60, 0.25)
    _fire_light.energy = 0.0
    _fire_light.enabled = false
    add_child(_fire_light)

func _set_fire_active(active: bool) -> void:
    var burning := not _fire_timer.is_stopped()
    if active == burning:
        return
    if active:
        _fire_light.enabled = true
        _fire_frame = -1
        _advance_fire()
        _fire_timer.start()
    else:
        _fire_timer.stop()
        _artwork.texture = _off_texture
        _fade_fire_light(0.0, 0.24)

func _advance_fire() -> void:
    _fire_frame = (_fire_frame + 1) % _fire_frames.size()
    _artwork.texture = _fire_frames[_fire_frame]
    _fade_fire_light(randf_range(0.54, 0.68), FIRE_FRAME_SECONDS)

func _fade_fire_light(energy: float, duration: float) -> void:
    if _light_tween != null:
        _light_tween.kill()
    _light_tween = create_tween()
    _light_tween.tween_property(_fire_light, "energy", energy, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    if energy == 0.0:
        _light_tween.tween_callback(func(): _fire_light.enabled = false)

static func _make_light_texture() -> ImageTexture:
    var image := Image.create_empty(LIGHT_SIZE.x, LIGHT_SIZE.y, false, Image.FORMAT_RGBA8)
    var radius := Vector2(LIGHT_SIZE) * 0.5
    var block := Vector2i.ONE * LIGHT_PIXEL_SIZE
    for y in range(0, LIGHT_SIZE.y, LIGHT_PIXEL_SIZE):
        for x in range(0, LIGHT_SIZE.x, LIGHT_PIXEL_SIZE):
            # Each world-pixel block samples the same softly falling light value.
            var center := Vector2(x, y) + Vector2(block) * 0.5
            var relative := (center - radius) / radius
            var strength := maxf(0.0, 1.0 - relative.length_squared())
            strength = floorf(strength * strength * 20.0) / 20.0
            image.fill_rect(Rect2i(Vector2i(x, y), block), Color(strength, strength, strength, 1.0))
    return ImageTexture.create_from_image(image)

func set_interaction_selected(selected: bool) -> void:
    if _prompt == null or _prompt.visible == selected:
        return
    _outline.visible = selected
    _prompt.visible = selected
    if _prompt_pulse != null:
        _prompt_pulse.kill()
        _prompt_pulse = null
    _prompt.scale = PROMPT_REST_SCALE
    if selected:
        _prompt_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        _prompt_pulse.tween_property(_prompt, "scale", PROMPT_PULSE_SCALE, 0.6)
        _prompt_pulse.tween_property(_prompt, "scale", PROMPT_REST_SCALE, 0.6)

func _make_outline(source: Image) -> ImageTexture:
    var edge := Image.create_empty(source.get_width() + 2, source.get_height() + 2, false, Image.FORMAT_RGBA8)
    # Extend the occupied pixels by one pixel, then clear the original silhouette.
    for y in range(source.get_height()):
        for x in range(source.get_width()):
            if source.get_pixel(x, y).a > 0.1:
                edge.fill_rect(Rect2i(x, y, 3, 3), Color.WHITE)
    for y in range(source.get_height()):
        for x in range(source.get_width()):
            if source.get_pixel(x, y).a > 0.1:
                edge.set_pixel(x + 1, y + 1, Color.TRANSPARENT)
    return ImageTexture.create_from_image(edge)

func _setup_geometry() -> void:
    _artwork = get_node_or_null("Sprite2D") as Sprite2D
    if _artwork == null:
        _artwork = Sprite2D.new()
        _artwork.name = "Sprite2D"
        _artwork.texture = item.placement_texture
        _artwork.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        _artwork.centered = false
        _artwork.position.y = -item.placement_sort_offset
        # Draw from the bottom center so the placement pop stays on the ground.
        _artwork.offset = -_artwork.texture.get_size() * Vector2(0.5, 1.0)
        add_child(_artwork)

    if item.placement_collision_polygon.size() >= 3:
        var outline := CollisionPolygon2D.new()
        outline.name = "CollisionPolygon2D"
        outline.position = _artwork.position + _artwork.offset
        outline.polygon = item.placement_collision_polygon
        _collision = outline
    else:
        var bounds := get_local_placement_bounds()
        var shape := RectangleShape2D.new()
        shape.size = bounds.size
        var box := CollisionShape2D.new()
        box.name = "CollisionShape2D"
        box.shape = shape
        box.position = bounds.get_center()
        _collision = box
    add_child(_collision)

    add_child(OCCLUSION_FADE.new())

func get_local_placement_bounds() -> Rect2:
    var size := item.get_placement_size(placement_cell_size)
    return Rect2(Vector2(-size.x * 0.5, -size.y - item.placement_sort_offset), size)

func get_local_footprint() -> Rect2:
    if _collision is CollisionPolygon2D:
        var points: PackedVector2Array = _collision.polygon
        var bounds := Rect2(points[0], Vector2.ZERO)
        for point in points:
            bounds = bounds.expand(point)
        bounds.position += _collision.position
        return bounds
    var shape := _collision.shape as RectangleShape2D
    return Rect2(_collision.position - shape.size * 0.5, shape.size)

func get_interaction_point() -> Vector2:
    if item.subtype == &"house":
        return _artwork.to_global(_artwork.offset + CABIN_THRESHOLD)
    return to_global(get_local_footprint().get_center())

func can_interact_from(point: Vector2) -> bool:
    if item.subtype != &"house":
        return true
    var image_point := _artwork.to_local(point) - _artwork.offset
    return image_point.y >= CABIN_DOOR.end.y and image_point.distance_squared_to(CABIN_THRESHOLD) <= CABIN_REACH * CABIN_REACH

func is_recoverable() -> bool:
    return not fixed_in_place and item != null and item.recoverable_when_placed

func take_pickaxe_hit(tool: InventoryItem, _hit_direction: Vector2 = Vector2.ZERO) -> bool:
    if is_queued_for_deletion() or not is_recoverable() or tool == null or tool.subtype != &"pickaxe":
        return false
    # Reserved materials and uncollected outputs stay owned by this furnace.
    if smeltry_queue != null and smeltry_queue.has_items():
        return false

    var pickup := PICKUP.instantiate()
    pickup.item = item
    pickup.get_node("Sprite2D").scale = Vector2.ONE * 0.5
    if item.icon != null:
        pickup.hover_height = maxf(pickup.hover_height, item.icon.get_height() * 0.25)
    var world := get_parent()
    world.add_child(pickup)
    if pickup.get_parent() != world:
        pickup.queue_free()
        return false

    hide()
    _collision.set_deferred("disabled", true)
    queue_free()
    pickup.launch(global_position)
    return true
