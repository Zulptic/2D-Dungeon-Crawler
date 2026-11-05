extends Control
## One item type owns its count, expiry, and popup while the stack moves its row.
signal finished(entry: Control)
const ART_SIZE := Vector2(103, 36)
const FRAME_TEXTURE := preload("res://assets/hud/environmental_hud/Item_Hud.png")
const FRAME_SPLIT_X: int = 66
const TEXT_LEFT: int = 35
const BASE_TEXT_WIDTH: int = 62
const TEXT_PADDING: int = 2
@onready var panel: Control = $Panel
@onready var frame: TextureRect = $Panel/Frame
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
var _art_size := ART_SIZE

func _ready() -> void:
    frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    item_name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
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
    _fit_name()
    lifetime.start(display_duration)
    if not visible:
        show()
        _animate_reveal(true)
    elif _closing:
        _animate_reveal(true)

func get_art_size() -> Vector2:
    return _art_size

func _fit_name() -> void:
    var font := item_name.get_theme_font("font")
    var font_size := item_name.get_theme_font_size("font_size")
    var text_width := ceili(font.get_string_size(item_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
    var text_box_width := maxi(BASE_TEXT_WIDTH, text_width + TEXT_PADDING * 2)
    var width := int(ART_SIZE.x) + text_box_width - BASE_TEXT_WIDTH
    if int(_art_size.x) != width:
        _art_size.x = width
        frame.texture = FRAME_TEXTURE if width == int(ART_SIZE.x) else ImageTexture.create_from_image(_frame_image(width))
    size = _art_size
    panel.size = _art_size
    frame.size = _art_size
    item_name.position.x = TEXT_LEFT
    item_name.size.x = text_box_width
    _apply_reveal_progress(_reveal_progress)

func _frame_image(width: int) -> Image:
    var source := FRAME_TEXTURE.get_image()
    source.convert(Image.FORMAT_RGBA8)
    var extra := maxi(0, width - source.get_width())
    var result := Image.create_empty(source.get_width() + extra, source.get_height(), false, Image.FORMAT_RGBA8)
    # Insert only the flat center of the text box. The icon and both end caps
    # retain every original pixel, including the small divider decorations.
    result.blit_rect(source, Rect2i(0, 0, FRAME_SPLIT_X, source.get_height()), Vector2i.ZERO)
    for column in range(extra):
        result.blit_rect(source, Rect2i(FRAME_SPLIT_X, 0, 1, source.get_height()), Vector2i(FRAME_SPLIT_X + column, 0))
    result.blit_rect(source, Rect2i(FRAME_SPLIT_X, 0, source.get_width() - FRAME_SPLIT_X, source.get_height()), Vector2i(FRAME_SPLIT_X + extra, 0))
    return result

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
    var centered := _art_size * (Vector2.ONE - panel.scale) * 0.5
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
