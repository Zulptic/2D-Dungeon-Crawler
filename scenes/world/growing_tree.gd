extends "res://scenes/world/breakable_rock.gd"
## The five light-green stages share one trunk tile, collider, and axe target.
signal growth_stage_changed(stage: int)
signal felled(tree: Node2D, direction: Vector2)
@export_enum("Brown bud", "Leaf bud", "Medium", "Large medium", "Mature") var starting_stage: int = 0
@export_range(0.1, 600.0, 0.1) var growth_seconds: float = 10.0
@export var growth_enabled: bool = true
@export_range(1, 10000, 1) var tree_health: int = 35
@export_range(1, 100, 1) var stump_health: int = 3
@export_range(1, 99, 1) var stump_drop_min: int = 1
@export_range(1, 99, 1) var stump_drop_max: int = 2
@export_range(0.1, 3.0, 0.05) var fall_seconds: float = 0.75
const GROWTH_SHEET := preload("res://assets/tiles/Size_02.png")
const MATURE_SHEET := preload("res://assets/tiles/Size_03.png")
const CHOPPED_SHEET := preload("res://assets/tiles/Size_03_Chopped.png")
const FALLING_TOP := preload("res://scenes/world/tree_fall.gd")
const GROWTH_REGIONS := [Rect2(0, 48, 16, 16), Rect2(0, 32, 16, 16), Rect2(16, 32, 16, 32), Rect2(32, 0, 32, 64)]
const FALL_DIRECTIONS := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
@onready var stump: Sprite2D = $Stump
@onready var growth_timer: Timer = $GrowthTimer
var growth_stage: int = 0
var is_stump: bool = false
var _growth_due: bool = false
var _stump_origin := Vector2.ZERO

func _ready() -> void:
    growth_stage = clampi(starting_stage, 0, 4)
    max_health = maxi(1, tree_health)
    super._ready()
    growth_timer.timeout.connect(_queue_growth)
    _apply_stage(growth_stage)

func take_hit(damage: int = 1, hit_direction: Vector2 = Vector2.ZERO) -> bool:
    if _breaking or health <= 0 or damage <= 0:
        return false
    # Use the already-rolled axe damage once for both health and its number.
    # A world sibling survives the final hit and does not inherit tree shaking.
    var world := _world_parent()
    var origin := global_position + Vector2(0, -24)
    var applied := super.take_hit(damage, hit_direction)
    if applied:
        var number := TreeDamageNumber.new()
        number.setup(damage, hit_direction)
        world.add_child(number)
        number.global_position = origin
    return applied

func _atlas(sheet: Texture2D, region: Rect2) -> AtlasTexture:
    var texture := AtlasTexture.new()
    texture.atlas = sheet
    texture.region = region
    texture.filter_clip = true
    return texture

func _apply_stage(stage: int) -> void:
    if _shake != null and _shake.is_valid():
        _shake.kill()
    if _health_tween != null and _health_tween.is_valid():
        _health_tween.kill()
    growth_stage = clampi(stage, 0, 4)
    max_health = maxi(1, tree_health)
    # Growth changes the artwork, preserving damage already taken.
    health = clampi(health, 0, max_health)
    _display_health = health
    if growth_stage == 4:
        sprite.texture = _atlas(CHOPPED_SHEET, Rect2(0, 0, 48, 96))
        _sprite_origin = Vector2(-24, -88)
        stump.texture = _atlas(MATURE_SHEET, Rect2(192, 32, 16, 32))
        _stump_origin = Vector2(-8, -24)
        stump.visible = true
    else:
        var region: Rect2 = GROWTH_REGIONS[growth_stage]
        sprite.texture = _atlas(GROWTH_SHEET, region)
        _sprite_origin = Vector2(-region.size.x * 0.5, 8.0 - region.size.y)
        stump.texture = _atlas(GROWTH_SHEET, Rect2(region.position + Vector2(0, region.size.y - 8), Vector2(region.size.x, 8)))
        _stump_origin = Vector2(-region.size.x * 0.5, 0)
        stump.visible = false
    sprite.centered = false
    stump.centered = false
    sprite.visible = true
    _set_shake_offset(Vector2.ZERO)
    _show_health(float(health))
    health_bar.visible = health < max_health
    $CollisionShape2D.set_deferred("disabled", growth_stage < 2)
    _growth_due = false
    if growth_enabled and growth_stage < 4:
        growth_timer.start(growth_seconds)
    else:
        growth_timer.stop()
    growth_stage_changed.emit(growth_stage)

func _queue_growth() -> void:
    _growth_due = true

func _physics_process(_delta: float) -> void:
    if not _growth_due or is_stump or _breaking or growth_stage >= 4:
        return
    _growth_due = false
    # The first solid stage waits if a body is standing on the sapling.
    if growth_stage == 1 and not _trunk_space_clear():
        growth_timer.start(0.5)
        return
    _apply_stage(growth_stage + 1)

func _trunk_space_clear() -> bool:
    var query := PhysicsShapeQueryParameters2D.new()
    query.shape = $CollisionShape2D.shape
    query.transform = $CollisionShape2D.global_transform
    query.collision_mask = 1
    query.collide_with_areas = false
    query.collide_with_bodies = true
    query.exclude = [get_rid()]
    return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()

func _set_shake_offset(offset: Vector2) -> void:
    # Keep the overlapping crown and stump aligned while the body stays fixed.
    var pixels := offset.round()
    sprite.position = _sprite_origin + pixels
    stump.position = _stump_origin + pixels

func _spawn_chips(shatter: bool, direction: Vector2) -> void:
    var debris := DEBRIS.new()
    debris.setup(stump.texture if stump.texture != null else sprite.texture, shatter, direction)
    _world_parent().add_child(debris)
    debris.global_position = global_position + Vector2(0, -3)

func _break_rock() -> void:
    growth_timer.stop()
    _growth_due = false
    if is_stump:
        super._break_rock()
        return
    if growth_stage < 2:
        # Tiny sprouts can be cleared, but do not produce log placeholders.
        drop_item = null
        super._break_rock()
        return
    _fell_tree()

func _fell_tree() -> void:
    if _shake != null and _shake.is_valid():
        _shake.kill()
    _set_shake_offset(Vector2.ZERO)
    var top_texture: Texture2D = sprite.texture
    var pivot := Vector2(0, -10)
    if growth_stage < 4:
        var region: Rect2 = GROWTH_REGIONS[growth_stage]
        top_texture = _atlas(GROWTH_SHEET, Rect2(region.position, Vector2(region.size.x, region.size.y - 4)))
        pivot = Vector2(0, 4)
    var direction: Vector2 = FALL_DIRECTIONS[_rng.randi_range(0, 3)]
    var count := _rng.randi_range(mini(drop_min, drop_max), maxi(drop_min, drop_max))
    var falling := FALLING_TOP.new()
    falling.setup(top_texture, _sprite_origin - pivot, drop_item, count, direction, global_position, fall_seconds)
    _world_parent().add_child(falling)
    falling.global_position = to_global(pivot)
    sprite.visible = false
    stump.visible = true
    is_stump = true
    max_health = stump_health
    health = stump_health
    _display_health = stump_health
    drop_min = stump_drop_min
    drop_max = stump_drop_max
    _breaking = false
    _show_health(float(health))
    health_bar.visible = false
    felled.emit(self, direction)


class TreeDamageNumber extends Node2D:
    ## A short, independent arc keeps hit numbers readable as the tree falls.
    const UI_THEME := preload("res://scenes/ui/pixel_theme.tres")
    const LIFETIME: float = 1.0
    const FADE_START: float = 0.65
    const GRAVITY: float = 44.0
    var amount: int = 0
    var elapsed: float = 0.0
    var velocity := Vector2.ZERO
    var _offset := Vector2.ZERO
    var _label_origin := Vector2.ZERO
    var label: Label

    func setup(damage: int, hit_direction: Vector2 = Vector2.ZERO) -> void:
        amount = maxi(0, damage)
        velocity = Vector2(randf_range(-18.0, 18.0) + hit_direction.x * 4.0, randf_range(-36.0, -28.0))

    func _ready() -> void:
        name = "DamageNumber"
        add_to_group(&"damage_numbers")
        texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        z_index = 20
        label = Label.new()
        label.theme = UI_THEME
        label.text = str(amount)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
        label.add_theme_color_override("font_outline_color", Color(0.13, 0.08, 0.05))
        label.add_theme_constant_override("outline_size", 1)
        add_child(label)
        var font := label.get_theme_font("font")
        var font_size := label.get_theme_font_size("font_size")
        var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
        _label_origin = Vector2(-floorf(width * 0.5), -ceilf(font.get_height(font_size)))
        label.position = _label_origin

    func _process(delta: float) -> void:
        var step := minf(delta, maxf(0.0, LIFETIME - elapsed))
        elapsed += step
        _offset += velocity * step + Vector2(0, GRAVITY * step * step * 0.5)
        velocity.y += GRAVITY * step
        # Snap the text to source pixels while its flight follows a smooth arc.
        label.position = (_label_origin + _offset).round()
        modulate.a = 1.0 - clampf((elapsed - FADE_START) / (LIFETIME - FADE_START), 0.0, 1.0)
        if elapsed >= LIFETIME:
            queue_free()
