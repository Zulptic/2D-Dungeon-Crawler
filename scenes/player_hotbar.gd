extends Control
## One slot layout aligns artwork, highlight, item icons, and inventory interactions.
signal selection_changed(slot: int)

@export_range(1, 9, 1) var starting_slot: int = 1
@export_range(1, 4, 1) var pixel_scale: int = 3
@export_range(0, 100, 1) var bottom_margin: int = 16

const STACK_COUNT := preload("res://scenes/item_stack_count.gd")
const SLOT_COUNT: int = 9
const ART_SIZE := Vector2(210, 53)
const SLOT_ORIGIN := Vector2(11, 20)
const SLOT_SIZE := Vector2(20, 20)
const SLOT_STRIDE: int = 21

@onready var highlight: TextureRect = $Selection
var selected_slot: int = 0
var input_locked: bool = false
var _inventory: PlayerInventoryModel
var _item_icons: Array[TextureRect] = []
var _key_labels: Array[Label] = []
var _dragged_slot: int = -1
var _dragged_quantity: int = 0

func _ready() -> void:
    _update_layout()
    get_viewport().size_changed.connect(_update_layout)
    gui_input.connect(_on_gui_input)
    _build_key_labels()
    select_slot(starting_slot)

func _update_layout() -> void:
    var viewport_width := get_viewport_rect().size.x
    var effective_scale := mini(pixel_scale, maxi(1, floori((viewport_width - 32.0) / ART_SIZE.x)))
    scale = Vector2.ONE * effective_scale
    # Keep the artwork on whole screen pixels, including at odd window widths.
    var left := floorf(viewport_width * 0.5 - ART_SIZE.x * effective_scale * 0.5)
    offset_left = left - viewport_width * 0.5
    offset_right = offset_left + ART_SIZE.x
    offset_top = -bottom_margin - ART_SIZE.y * effective_scale
    offset_bottom = offset_top + ART_SIZE.y

func select_slot(slot: int) -> void:
    var next_slot := wrapi(slot - 1, 0, SLOT_COUNT) + 1
    if next_slot == selected_slot:
        return
    selected_slot = next_slot
    highlight.position = slot_rect(selected_slot - 1).position
    for index in range(_key_labels.size()):
        _key_labels[index].modulate = Color.WHITE if index == selected_slot - 1 else Color(0.72, 0.75, 0.84, 1)
    selection_changed.emit(selected_slot)

func slot_rect(index: int) -> Rect2:
    return Rect2(SLOT_ORIGIN + Vector2(index * SLOT_STRIDE, 0), SLOT_SIZE)

func _slot_at_local(point: Vector2) -> int:
    for index in range(SLOT_COUNT):
        if slot_rect(index).has_point(point):
            return index
    return -1

func slot_at_screen(point: Vector2) -> int:
    return _slot_at_local(get_global_transform_with_canvas().affine_inverse() * point)

func _build_key_labels() -> void:
    for index in range(SLOT_COUNT):
        var label := Label.new()
        label.name = "Key" + str(index + 1)
        label.text = str(index + 1)
        # The font draws five visible pixel rows. Starting one pixel below the
        # slots leaves one native pixel above and below in the seven-pixel strip.
        label.position = slot_rect(index).position + Vector2(0, SLOT_SIZE.y + 1)
        label.size = Vector2(SLOT_SIZE.x, 7)
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", 7)
        label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(label)
        _key_labels.append(label)

func _cycle_from_wheel(event: InputEventMouseButton) -> bool:
    if not event.pressed:
        return false
    if event.button_index == MOUSE_BUTTON_WHEEL_UP:
        select_slot(selected_slot - 1)
        return true
    if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        select_slot(selected_slot + 1)
        return true
    return false

func _unhandled_input(event: InputEvent) -> void:
    if input_locked:
        return
    if event is InputEventKey:
        if not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
            return
        var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
        if key >= KEY_1 and key <= KEY_9:
            select_slot(key - KEY_1 + 1)
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and _cycle_from_wheel(event):
        get_viewport().set_input_as_handled()

func _on_gui_input(event: InputEvent) -> void:
    if input_locked:
        return
    if not event is InputEventMouseButton:
        return
    if _cycle_from_wheel(event):
        accept_event()
        return
    if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var index := _slot_at_local(event.position)
        if index >= 0:
            select_slot(index + 1)
            accept_event()

func bind_inventory(inventory: PlayerInventoryModel) -> void:
    if _inventory != null and _inventory.changed.is_connected(_refresh_items):
        _inventory.changed.disconnect(_refresh_items)
    _inventory = inventory
    if _item_icons.is_empty():
        for index in range(SLOT_COUNT):
            var icon := TextureRect.new()
            icon.name = "Item" + str(index + 1)
            icon.position = slot_rect(index).position + (SLOT_SIZE - Vector2(16, 16)) * 0.5
            icon.size = Vector2(16, 16)
            icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
            add_child(icon)
            move_child(icon, highlight.get_index())
            var count := STACK_COUNT.new()
            count.name = "Count"
            count.position = Vector2(0, 9)
            icon.add_child(count)
            _item_icons.append(icon)
    _inventory.changed.connect(_refresh_items)
    _refresh_items()

func set_dragged_slot(index: int, quantity: int = -1) -> void:
    _dragged_slot = index
    _dragged_quantity = quantity
    _refresh_items()

func _refresh_items() -> void:
    if _inventory == null:
        return
    for index in range(_item_icons.size()):
        var item := _inventory.get_item(&"hotbar", index)
        _item_icons[index].texture = item.icon if item != null else null
        var remaining := _inventory.get_quantity(&"hotbar", index)
        if index == _dragged_slot:
            remaining = maxi(0, remaining - _dragged_quantity) if _dragged_quantity >= 0 else 0
        _item_icons[index].get_node("Count").amount = remaining
        _item_icons[index].visible = item != null and remaining > 0
