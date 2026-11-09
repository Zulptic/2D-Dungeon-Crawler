extends "res://scenes/world/growing_tree.gd"
## The ordinary growth/chopping lifecycle with renewable fruit on its mature crown.
var fruit_growth_seconds: float = 20.0
var starting_fruit: int = 0
var fruit_stages: Array[Texture2D] = []
var fruit_pickup_scene: PackedScene
const MAX_FRUIT: int = 4
const FRUIT_SPACING: float = 16.0
const INTERACT_ICON := preload("res://assets/hud/environmental_hud/input_keyboard_e.png")
const PROMPT_REST_SCALE := Vector2(0.5, 0.5)
const PROMPT_PULSE_SCALE := Vector2(0.625, 0.625)
var fruits: Array[Sprite2D] = []
var fruit_timer: Timer
var outline: Sprite2D
var interact_prompt: Sprite2D
var interaction_selected: bool = false
var _fruit_sites: Array[Vector2] = []
var _fruit_slots: Array[Vector2] = []
var _prompt_pulse: Tween

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
    outline.show_behind_parent = true
    sprite.add_child(outline)
    interact_prompt = Sprite2D.new()
    interact_prompt.name = "InteractPrompt"
    interact_prompt.texture = INTERACT_ICON
    interact_prompt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    interact_prompt.material = unlit
    interact_prompt.scale = PROMPT_REST_SCALE
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
    if interact_prompt == null or active == interaction_selected:
        return
    interaction_selected = active
    outline.visible = active
    interact_prompt.visible = active
    if _prompt_pulse != null:
        _prompt_pulse.kill()
        _prompt_pulse = null
    interact_prompt.scale = PROMPT_REST_SCALE
    if active:
        _prompt_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
        _prompt_pulse.tween_property(interact_prompt, "scale", PROMPT_PULSE_SCALE, 0.6)
        _prompt_pulse.tween_property(interact_prompt, "scale", PROMPT_REST_SCALE, 0.6)

func harvest() -> bool:
    if not can_harvest():
        return false
    _drop_fruit()
    _play_hit_shake()
    _shed_leaves(12)
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
    # The standing texture already includes the trunk.
    var edge := Image.create_empty(crown.get_width() + 2, crown.get_height() + 2, false, Image.FORMAT_RGBA8)
    for y in range(crown.get_height()):
        for x in range(crown.get_width()):
            if crown.get_pixel(x, y).a > 0.1:
                edge.fill_rect(Rect2i(x, y, 3, 3), Color.WHITE)
    for y in range(crown.get_height()):
        for x in range(crown.get_width()):
            if crown.get_pixel(x, y).a > 0.1:
                edge.set_pixel(x + 1, y + 1, Color.TRANSPARENT)
    outline.texture = ImageTexture.create_from_image(edge)
    outline.position = -Vector2.ONE
    interact_prompt.position = _sprite_origin + Vector2(crown.get_width() * 0.5, 32.0)
