extends CharacterBody2D
## Carry poses share the same movement, facing, and stamina rules as normal poses.

signal stamina_changed(value: float, maximum: float, exhausted: bool)

@export var move_speed: float = 80.0
@export var run_speed: float = 140.0
@export_range(1.0, 1000.0, 1.0) var max_stamina: float = 100.0
@export_range(1.0, 1000.0, 1.0) var stamina_drain_per_second: float = 20.0
@export_range(1.0, 1000.0, 1.0) var stamina_recharge_per_second: float = 25.0
@export_range(0.0, 5.0, 0.05) var stamina_recharge_delay: float = 0.75
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var carried_sprite: Sprite2D = $AnimatedSprite2D/CarriedItem
@onready var _carry_inventory: Control = get_node_or_null("../PlayerHUD/Screen/Inventory")
@onready var _carry_hotbar: Control = get_node_or_null("../PlayerHUD/Screen/Hotbar")

# Native-pixel hand movement, inspected from the 64x64 Carry sheet frames.
const CARRY_BOB := {
    &"carry_idle_down": [0, 1, 2, 1],
    &"carry_idle_side": [0, 1, 2, 1],
    &"carry_idle_up": [0, 1, 2, 1],
    &"carry_walk_down": [0, 1, 0, 0, 1, 0],
    &"carry_walk_side": [0, 1, 0, 0, 1, 0],
    &"carry_walk_up": [0, 1, 0, 0, 1, 0],
    &"carry_run_down": [0, 0, 1, 0, 0, 1],
    &"carry_run_side": [-1, 0, 0, -1, 0, 0],
    &"carry_run_up": [0, 1, 1, 0, 1, 1]
}
var carried_item: InventoryItem
var _carried_bounds := Rect2i()
var _locomotion_state: String = "idle"

var movement_locked: bool = false:
    set(value):
        movement_locked = value
        if value:
            velocity = Vector2.ZERO
            if is_node_ready():
                _play_animation("idle")

var is_using_tool: bool = false

var facing: Vector2 = Vector2.DOWN
var stamina: float = 100.0
var stamina_exhausted: bool = false
var _recharge_delay_left: float = 0.0

func _ready() -> void:
    add_to_group(&"player")
    stamina = max_stamina
    sprite.frame_changed.connect(_update_carried_visual)
    sprite.animation_changed.connect(_update_carried_visual)
    _play_animation("idle")
    call_deferred("_connect_carry_inventory")
    stamina_changed.emit(stamina, max_stamina, stamina_exhausted)

func _physics_process(delta: float) -> void:
    var direction := Vector2.ZERO if movement_locked or is_using_tool else Input.get_vector("move_left", "move_right", "move_up", "move_down")
    var moving := not direction.is_zero_approx()
    var running := moving and Input.is_action_pressed("run") and not stamina_exhausted and stamina > 0.0
    var previous_stamina := stamina
    var previous_exhausted := stamina_exhausted

    if running:
        stamina = maxf(0.0, stamina - stamina_drain_per_second * delta)
        _recharge_delay_left = stamina_recharge_delay
        if stamina <= 0.0:
            stamina_exhausted = true
            running = false
    else:
        _recharge_delay_left = maxf(0.0, _recharge_delay_left - delta)
        if _recharge_delay_left <= 0.0:
            stamina = minf(max_stamina, stamina + stamina_recharge_per_second * delta)
            if stamina_exhausted and stamina >= max_stamina:
                stamina_exhausted = false

    velocity = direction * (run_speed if running else move_speed)
    move_and_slide()
    if not is_using_tool:
        if moving:
            if not is_zero_approx(direction.x) and absf(direction.x) >= absf(direction.y):
                facing = Vector2.LEFT if direction.x < 0.0 else Vector2.RIGHT
            else:
                facing = Vector2.UP if direction.y < 0.0 else Vector2.DOWN
            _play_animation("run" if running else "walk")
        else:
            _play_animation("idle")

    if not is_equal_approx(stamina, previous_stamina) or stamina_exhausted != previous_exhausted:
        stamina_changed.emit(stamina, max_stamina, stamina_exhausted)

func _play_animation(state: String) -> void:
    _locomotion_state = state
    var suffix := "down"
    if not is_zero_approx(facing.x):
        suffix = "side"
    elif facing.y < 0.0:
        suffix = "up"
    sprite.flip_h = facing.x < 0.0
    var prefix := "carry_" if carried_item != null else ""
    sprite.play(StringName(prefix + state + "_" + suffix))
    _update_carried_visual()

func get_inventory_model() -> PlayerInventoryModel:
    var inventory := get_node_or_null("../PlayerHUD/Screen/Inventory")
    return inventory.model if inventory != null else null

func _connect_carry_inventory() -> void:
    if _carry_inventory != null:
        _carry_inventory.model.changed.connect(_sync_carried_item)
    if _carry_hotbar != null:
        _carry_hotbar.selection_changed.connect(_sync_carried_item)
    _sync_carried_item()

func _sync_carried_item(_value: Variant = null) -> void:
    var selected: InventoryItem
    if _carry_inventory != null and _carry_hotbar != null and _carry_hotbar.selected_slot > 0:
        selected = _carry_inventory.model.get_item(&"hotbar", _carry_hotbar.selected_slot - 1)
    # Tools and weapons use their own action animations; other selected items
    # are carried. Empty slots and unselected inventory items do not activate it.
    if selected != null and (selected.icon == null or selected.is_action_item()):
        selected = null
    if carried_item != selected:
        carried_item = selected
        carried_sprite.texture = carried_item.icon if carried_item != null else null
        _carried_bounds = Rect2i()
        if carried_item != null:
            var image := carried_item.icon.get_image()
            if image != null:
                _carried_bounds = image.get_used_rect()
    if not is_using_tool:
        _play_animation(_locomotion_state)
    _update_carried_visual()

func _update_carried_visual() -> void:
    if not is_node_ready():
        return
    carried_sprite.visible = carried_item != null and not is_using_tool and CARRY_BOB.has(sprite.animation)
    if not carried_sprite.visible:
        return
    var side := String(sprite.animation).ends_with("_side")
    var back := String(sprite.animation).ends_with("_up")
    var bob: int = CARRY_BOB[sprite.animation][sprite.frame]
    var hand_y := -12.0 if back else (-9.0 if side else -6.0)
    var anchor := Vector2(0.0, hand_y + bob)
    if sprite.animation == &"carry_run_side":
        anchor.x = -1.0 if sprite.flip_h else 1.0
    # Align the actual item pixels, ignoring transparent padding in its icon.
    var center_x := _carried_bounds.position.x + _carried_bounds.size.x * 0.5
    carried_sprite.position = (sprite.offset + anchor - Vector2(center_x, _carried_bounds.end.y)).round()
    # Inheriting the character sprite's transform makes one item pixel exactly
    # one player pixel, including through the camera zoom or parent scaling.
    carried_sprite.scale = Vector2.ONE
    # Keep it behind the back-facing head within the player's draw order,
    # without putting it underneath the ground's Z layer.
    carried_sprite.z_index = 0
    carried_sprite.show_behind_parent = back
