extends StaticBody2D
## A placed object can be recovered as the same item with one pickaxe hit.

const GROUP := &"placed_objects"
const INTERACTION_GROUP := &"furnace_interactables"
const INTERACT_ICON := preload("res://assets/hud/environmental_hud/input_keyboard_e.png")
const PROMPT_REST_SCALE := Vector2(0.5, 0.5)
const PROMPT_PULSE_SCALE := Vector2(0.625, 0.625)
const PICKUP := preload("res://scenes/world/item_pickup.tscn")
const FIRE_SHEET := preload("res://assets/items/Bricks_01-Sheet.png")
const FIRE_FRAME_SECONDS: float = 0.125
const SMELTRY_QUEUE := preload("res://scenes/smeltry_queue.gd")
const OUTPUT_DISPLAY := preload("res://scenes/world/smeltry_output_display.gd")
const LIGHT_SIZE := Vector2i(102, 78)
const LIGHT_PIXEL_SIZE: int = 3

static var _fire_frames: Array[AtlasTexture] = []
static var _light_texture: ImageTexture

var item: InventoryItem
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _artwork: Sprite2D = $Sprite2D

var _outline: Sprite2D
var _prompt: Sprite2D
var _prompt_pulse: Tween
var _off_texture: Texture2D
var _fire_timer: Timer
var _fire_frame: int = 0
var _fire_light: PointLight2D
var _light_tween: Tween
var smeltry_queue: Node
var _smelting_was_active: bool = false
var _output_display: Node2D

func _ready() -> void:
    if item == null or item.subtype != &"furnace":
        return
    add_to_group(INTERACTION_GROUP)
    var unlit := CanvasItemMaterial.new()
    unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

    _outline = Sprite2D.new()
    _outline.name = "InteractionOutline"
    _outline.centered = false
    _outline.texture = _make_outline(_artwork.texture.get_image())
    _outline.position = _artwork.offset - Vector2.ONE
    _outline.show_behind_parent = true
    _outline.material = unlit
    _outline.hide()
    _artwork.add_child(_outline)

    _prompt = Sprite2D.new()
    _prompt.name = "InteractPrompt"
    _prompt.texture = INTERACT_ICON
    _prompt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _prompt.material = unlit
    _prompt.position = Vector2(0, -25)
    _prompt.scale = PROMPT_REST_SCALE
    _prompt.z_index = 7
    _prompt.hide()
    add_child(_prompt)
    _setup_fire()
    smeltry_queue = SMELTRY_QUEUE.new()
    smeltry_queue.name = "SmeltryQueue"
    add_child(smeltry_queue)
    smeltry_queue.changed.connect(_update_smelting_fire)
    _output_display = OUTPUT_DISPLAY.new()
    _output_display.name = "FinishedItems"
    add_child(_output_display)
    # Keep the scaled frame centered, with a five-pixel gap above the artwork.
    var art_rect := _artwork.get_rect()
    var display_half_height: float = _output_display.FRAME.get_height() * _output_display.scale.y * 0.5
    _output_display.set_anchor(_artwork.position + Vector2(art_rect.get_center().x, art_rect.position.y - display_half_height - 5.0))
    smeltry_queue.changed.connect(_update_completed_display)

func _update_completed_display() -> void:
    _output_display.set_outputs(smeltry_queue.get_completed_outputs())

func has_completed_output() -> bool:
    return smeltry_queue != null and not smeltry_queue.get_completed_outputs().is_empty()

func eject_completed() -> bool:
    if not has_completed_output() or is_queued_for_deletion():
        return false
    var ejected := false
    for output: Dictionary in smeltry_queue.get_completed_outputs():
        var pickup := PICKUP.instantiate()
        pickup.item = output.item
        pickup.quantity = int(output.quantity)
        pickup.show_stack_count = true
        pickup.toss_distance = Vector2(14.0, 22.0)
        var world := get_parent()
        world.add_child(pickup)
        if pickup.get_parent() != world:
            pickup.queue_free()
            continue
        # Transfer ownership only after the world pickup exists successfully.
        if not smeltry_queue.remove_completed(output.item, int(output.quantity)):
            pickup.queue_free()
            continue
        pickup.launch_forward(to_global(Vector2(0, -4)), global_transform.y)
        ejected = true
    return ejected

func _update_smelting_fire() -> void:
    var active: bool = smeltry_queue.has_work()
    if active and _fire_timer.is_stopped():
        toggle_fire()
    elif not active and _smelting_was_active and not _fire_timer.is_stopped():
        toggle_fire()
    _smelting_was_active = active

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

func toggle_fire() -> bool:
    if _fire_timer == null or is_queued_for_deletion():
        return false
    if smeltry_queue != null and smeltry_queue.has_work() and not _fire_timer.is_stopped():
        return false
    if _fire_timer.is_stopped():
        _fire_light.enabled = true
        _fire_frame = -1
        _advance_fire()
        _fire_timer.start()
    else:
        _fire_timer.stop()
        _artwork.texture = _off_texture
        _fade_fire_light(0.0, 0.24)
    return true

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

func get_local_footprint() -> Rect2:
    var shape := _collision.shape as RectangleShape2D
    return Rect2(_collision.position - shape.size * 0.5, shape.size)

func take_pickaxe_hit(tool: InventoryItem, _hit_direction: Vector2 = Vector2.ZERO) -> bool:
    if is_queued_for_deletion() or item == null or tool == null or tool.subtype != &"pickaxe":
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
