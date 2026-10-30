extends "res://scenes/world/growing_tree.gd"
## The ordinary growth/chopping lifecycle with renewable fruit on its mature crown.
var fruit_growth_seconds: float = 20.0
var starting_fruit: int = 0
var fruit_stages: Array[Texture2D] = []
var fruit_pickup_scene: PackedScene
const MAX_FRUIT: int = 4
const FRUIT_SPACING: float = 16.0
const INTERACT_ICON := preload("res://assets/hud/environmental_hud/input_keyboard_e.png")
var fruits: Array[Sprite2D] = []
var fruit_timer: Timer
var outline: Sprite2D
var interact_prompt: Sprite2D
var interaction_selected: bool = false
var _fruit_sites: Array[Vector2] = []
var _fruit_slots: Array[Vector2] = []
var _outline_origin := Vector2.ZERO
var _outline_pulse: Tween
var _outline_frames: Array[ImageTexture] = []
var _outline_pixel_offset: int = 0

func _ready() -> void:
    super._ready()
    add_to_group(&"fruit_trees")
    fruit_timer = Timer.new()
    fruit_timer.name = "FruitGrowthTimer"
    fruit_timer.one_shot = true
    fruit_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
    fruit_timer.timeout.connect(_grow_next_fruit)
    add_child(fruit_timer)
    outline = Sprite2D.new()
    outline.name = "InteractionOutline"
    outline.centered = false
    outline.visible = false
    var unlit := CanvasItemMaterial.new()
    unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
    outline.material = unlit
    # Draw over the tree edge and under its fruits so inward motion stays visible.
    sprite.add_child(outline)
    sprite.move_child(outline, 0)
    interact_prompt = Sprite2D.new()
    interact_prompt.name = "InteractPrompt"
    interact_prompt.texture = INTERACT_ICON
    interact_prompt.material = unlit
    interact_prompt.scale = Vector2.ONE * 0.5
    interact_prompt.position = Vector2(0, -10)
    interact_prompt.z_index = 7
    interact_prompt.visible = false
    add_child(interact_prompt)
    growth_stage_changed.connect(_on_fruit_stage_changed)
    felled.connect(_on_fruit_tree_felled)
    _on_fruit_stage_changed(growth_stage)
    if growth_stage == 4:
        for index in range(starting_fruit):
            _add_fruit()
        _schedule_fruit()

func can_harvest() -> bool:
    return growth_stage == 4 and not is_stump and not _breaking and health > 0 and not fruits.is_empty() and not _has_growing_fruits()

func _has_growing_fruits() -> bool:
    for fruit in fruits:
        if int(fruit.get_meta(&"growth_stage", 0)) < (fruit_stages.size() - 1):
            return true
    return false

func _set_fruit_stage(fruit: Sprite2D, stage: int) -> void:
    var current := clampi(stage, 0, (fruit_stages.size() - 1))
    fruit.set_meta(&"growth_stage", current)
    fruit.texture = fruit_stages[current]

func set_interaction_selected(selected: bool) -> void:
    var active := selected and can_harvest()
    var changed := active != interaction_selected
    interaction_selected = active
    if is_instance_valid(outline):
        outline.visible = interaction_selected
        if changed:
            if _outline_pulse != null and _outline_pulse.is_valid():
                _outline_pulse.kill()
            _outline_pulse = null
            outline.modulate.a = 1.0
            _set_outline_offset(0.0)
            if interaction_selected:
                # Breathe by exactly one source pixel; never scale the tree or blur its edge.
                _outline_pulse = create_tween().set_loops()
                _outline_pulse.tween_method(_set_outline_offset, 0.0, -1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
                _outline_pulse.tween_method(_set_outline_offset, -1.0, 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    if is_instance_valid(interact_prompt):
        interact_prompt.visible = interaction_selected

func _set_outline_offset(value: float) -> void:
    _outline_pixel_offset = clampi(roundi(value), -1, 0)
    if is_instance_valid(outline) and _outline_frames.size() == 2:
        var frame := _outline_frames[_outline_pixel_offset + 1]
        if outline.texture != frame:
            outline.texture = frame

func harvest() -> bool:
    if not can_harvest():
        return false
    _drop_fruit()
    _play_hit_shake()
    var leaves := DEBRIS.new()
    leaves.setup(_atlas(CHOPPED_SHEET, Rect2(0, 0, 48, 48)), false, Vector2.DOWN)
    _world_parent().add_child(leaves)
    leaves.global_position = global_position + Vector2(0, -40)
    _schedule_fruit()
    return true

func _on_fruit_stage_changed(stage: int) -> void:
    if stage != 4 or is_stump:
        fruit_timer.stop()
        for fruit in fruits:
            fruit.queue_free()
        fruits.clear()
        _fruit_slots.clear()
        set_interaction_selected(false)
        return
    _build_mature_visuals()
    _schedule_fruit()

func _schedule_fruit() -> void:
    if growth_stage == 4 and not is_stump and not _breaking and (fruits.size() < MAX_FRUIT or _has_growing_fruits()):
        fruit_timer.start(fruit_growth_seconds)
    else:
        fruit_timer.stop()

func _grow_next_fruit() -> void:
    if growth_stage == 4 and not is_stump and not _breaking:
        for fruit in fruits:
            _set_fruit_stage(fruit, int(fruit.get_meta(&"growth_stage", 0)) + 1)
        _add_fruit()
    _schedule_fruit()

func _plan_fruit_slots() -> void:
    _fruit_slots.clear()
    # Plan all four full-size fruits together so random placement cannot crowd
    # the remaining slots out. Start randomly, then spread across the leaves.
    for attempt in range(32):
        var planned: Array[Vector2] = []
        if _fruit_sites.is_empty():
            return
        planned.append(_fruit_sites[_rng.randi_range(0, _fruit_sites.size() - 1)])
        while planned.size() < MAX_FRUIT:
            var farthest: float = -1.0
            var choices: Array[Vector2] = []
            for point in _fruit_sites:
                var nearest: float = INF
                for placed in planned:
                    nearest = minf(nearest, point.distance_squared_to(placed))
                if nearest > farthest:
                    farthest = nearest
                    choices = [point]
                elif is_equal_approx(nearest, farthest):
                    choices.append(point)
            if farthest < FRUIT_SPACING * FRUIT_SPACING:
                break
            planned.append(choices[_rng.randi_range(0, choices.size() - 1)])
        if planned.size() == MAX_FRUIT:
            _fruit_slots = planned
            return

func _add_fruit() -> bool:
    if fruits.size() >= MAX_FRUIT or _fruit_sites.is_empty():
        return false
    if _fruit_slots.is_empty():
        _plan_fruit_slots()
    if fruits.size() >= _fruit_slots.size():
        return false
    var fruit := Sprite2D.new()
    fruit.name = "Fruit"
    fruit.scale = Vector2.ONE
    fruit.position = _fruit_slots[fruits.size()]
    _set_fruit_stage(fruit, 0)
    sprite.add_child(fruit)
    fruits.append(fruit)
    set_interaction_selected(false)
    return true

func _drop_fruit() -> void:
    var world := _world_parent()
    for fruit in fruits:
        if int(fruit.get_meta(&"growth_stage", 0)) == (fruit_stages.size() - 1):
            var point := fruit.global_position
            var pickup := fruit_pickup_scene.instantiate()
            world.add_child(pickup)
            pickup.fall_from(point, global_position)
        fruit.queue_free()
    fruits.clear()
    _fruit_slots.clear()
    set_interaction_selected(false)

func _on_fruit_tree_felled(_tree: Node2D, _direction: Vector2) -> void:
    fruit_timer.stop()
    # Chopping releases ripe fruits; growing fruit does not become an edible pickup.
    _drop_fruit()

func _build_mature_visuals() -> void:
    var crown := sprite.texture.get_image()
    crown.convert(Image.FORMAT_RGBA8)
    _fruit_sites.clear()
    # Sample green leaf pixels, with room around the fruit and away from the trunk.
    for y in range(7, mini(60, crown.get_height() - 7)):
        for x in range(7, crown.get_width() - 7):
            var leafy: bool = true
            for offset in [Vector2i.ZERO, Vector2i(-6,0), Vector2i(6,0), Vector2i(0,-6), Vector2i(0,6)]:
                var color := crown.get_pixelv(Vector2i(x,y) + offset)
                if color.a < 0.9 or color.g < color.r * 1.1 or color.g < color.b * 1.15:
                    leafy = false
                    break
            if leafy:
                _fruit_sites.append(Vector2(x,y))
    _plan_fruit_slots()
    # Cache the normal outline and its one-pixel inward contour.
    var crown_rect := Rect2i(Vector2i(_sprite_origin), crown.get_size())
    var stump_image := stump.texture.get_image()
    stump_image.convert(Image.FORMAT_RGBA8)
    var stump_rect := Rect2i(Vector2i(_stump_origin), stump_image.get_size())
    var bounds := crown_rect.merge(stump_rect).grow(1)
    var mask := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
    mask.blend_rect(stump_image, Rect2i(Vector2i.ZERO, stump_image.get_size()), stump_rect.position - bounds.position)
    mask.blend_rect(crown, Rect2i(Vector2i.ZERO, crown.get_size()), crown_rect.position - bounds.position)
    var inner := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
    var resting := Image.create_empty(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
    var limits := Rect2i(Vector2i.ZERO, bounds.size)
    for y in range(bounds.size.y):
        for x in range(bounds.size.x):
            var occupied := mask.get_pixel(x,y).a > 0.1
            var solid_within_one: bool = false
            var clear_within_one: bool = false
            for dy in range(-1,2):
                for dx in range(-1,2):
                    var neighbor := Vector2i(x+dx,y+dy)
                    var solid := limits.has_point(neighbor) and mask.get_pixelv(neighbor).a > 0.1
                    solid_within_one = solid_within_one or solid
                    clear_within_one = clear_within_one or not solid
            if occupied and clear_within_one:
                inner.set_pixel(x,y,Color.WHITE)
            elif not occupied and solid_within_one:
                resting.set_pixel(x,y,Color.WHITE)
    _outline_frames.clear()
    for frame in [inner, resting]:
        _outline_frames.append(ImageTexture.create_from_image(frame))
    _set_outline_offset(0.0)
    _outline_origin = Vector2(bounds.position) - _sprite_origin
    outline.position = _outline_origin
