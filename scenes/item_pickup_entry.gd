extends Control
## One item type owns its count, expiry, and popup while the stack moves its row.
signal finished(entry: Control)
const ART_SIZE := Vector2(103, 36)
@onready var panel: Control = $Panel
@onready var icon: TextureRect = $Panel/Icon
@onready var item_name: Label = $Panel/ItemName
@onready var count_label: Label = $Panel/Quantity
@onready var lifetime: Timer = $Lifetime
var display_duration: float = 3.0
var open_duration: float = 0.18
var close_duration: float = 0.14
var current_item: InventoryItem
var pickup_count: int = 0
var _reveal_progress: float = 0.0
var _closing: bool = false
var _transition_tween: Tween
var _move_tween: Tween

func _ready() -> void:
    lifetime.timeout.connect(_on_lifetime_timeout)
    _apply_reveal_progress(0.0)

func matches_item(item: InventoryItem) -> bool:
    return current_item != null and (current_item == item or (item.id != &"" and current_item.id == item.id))

func show_pickup(item: InventoryItem, quantity: int) -> void:
    var continuing := matches_item(item) and not _closing and not lifetime.is_stopped() and lifetime.time_left > 0.0
    pickup_count = pickup_count + quantity if continuing else quantity
    current_item = item
    icon.texture = item.icon
    item_name.text = item.get_title()
    count_label.text = str(pickup_count) + "x"
    count_label.visible = pickup_count > 1
    lifetime.start(display_duration)
    if not visible:
        show()
        _animate_reveal(true)
    elif _closing:
        _animate_reveal(true)

func move_to(target: Vector2, duration: float) -> void:
    if _move_tween != null and _move_tween.is_valid():
        _move_tween.kill()
    _move_tween = null
    target = target.floor()
    if duration <= 0.0 or position.distance_squared_to(target) < 0.01:
        position = target
        return
    _move_tween = create_tween()
    _move_tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _apply_reveal_progress(progress: float) -> void:
    _reveal_progress = progress
    modulate.a = progress
    panel.scale = Vector2.ONE * lerpf(0.94, 1.0, progress)
    var centered := ART_SIZE * (Vector2.ONE - panel.scale) * 0.5
    panel.position = centered.floor() if is_equal_approx(progress, 1.0) else centered

func _animate_reveal(opening: bool) -> void:
    if _transition_tween != null and _transition_tween.is_valid():
        _transition_tween.kill()
    _transition_tween = null
    _closing = not opening
    var target := 1.0 if opening else 0.0
    var duration := (open_duration if opening else close_duration) * absf(target - _reveal_progress)
    if duration <= 0.001:
        _apply_reveal_progress(target)
        if not opening:
            _finish_close()
        return
    _transition_tween = create_tween()
    _transition_tween.tween_method(_apply_reveal_progress, _reveal_progress, target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    if not opening:
        _transition_tween.tween_callback(_finish_close)

func _on_lifetime_timeout() -> void:
    _animate_reveal(false)

func _finish_close() -> void:
    hide()
    finished.emit(self)

func dismiss() -> void:
    lifetime.stop()
    if _transition_tween != null and _transition_tween.is_valid():
        _transition_tween.kill()
    if _move_tween != null and _move_tween.is_valid():
        _move_tween.kill()
    hide()
    queue_free()
