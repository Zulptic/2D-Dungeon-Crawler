extends Control
## Hit regions use the original PNG's native pixels. Only the panel scales.
signal opened_changed(open: bool)

@export var player_path: NodePath = NodePath("../../../Player")
@export var hotbar_path: NodePath = NodePath("../Hotbar")
@export_range(1, 6, 1) var pixel_scale: int = 3
@export_range(0.05, 1.0, 0.01) var open_duration: float = 0.18
@export_range(0.05, 1.0, 0.01) var close_duration: float = 0.14

const PICKUP := preload("res://scenes/world/item_pickup.tscn")
const STARTING_BACKPACK_TOOLS: Array[InventoryItem] = [
    preload("res://scenes/items/copper_pickaxe.tres"),
    preload("res://scenes/items/copper_sword.tres"),
    preload("res://scenes/items/copper_axe.tres"),
    preload("res://scenes/items/iron_pickaxe.tres"),
    preload("res://scenes/items/iron_sword.tres"),
    preload("res://scenes/items/iron_axe.tres"),
    preload("res://scenes/items/gold_pickaxe.tres"),
    preload("res://scenes/items/gold_sword.tres"),
    preload("res://scenes/items/gold_axe.tres"),
    preload("res://scenes/items/echryte_pickaxe.tres"),
    preload("res://scenes/items/echryte_sword.tres"),
    preload("res://scenes/items/echryte_axe.tres"),
    preload("res://scenes/items/aetherite_pickaxe.tres"),
    preload("res://scenes/items/aetherite_sword.tres"),
    preload("res://scenes/items/aetherite_axe.tres"),
    preload("res://scenes/items/ashenite_pickaxe.tres"),
    preload("res://scenes/items/ashenite_sword.tres"),
    preload("res://scenes/items/ashenite_axe.tres")
]
const STACK_COUNT := preload("res://scenes/item_stack_count.gd")
const ART_SIZE := Vector2(231, 151)
const CLOSE_RECT := Rect2(218, 7, 13, 13)
const CURSORS := {
    &"default": preload("res://assets/hud/player_hud/cursor_default.png"),
    &"hand": preload("res://assets/hud/player_hud/cursor_hand.png"),
    &"pressed": preload("res://assets/hud/player_hud/cursor_hand_pressed.png")
}

@onready var panel: Control = $Panel
@onready var close_pressed: TextureRect = $Panel/ClosePressed
@onready var drag_icon: TextureRect = $DragIcon
@onready var preview: SubViewport = $PreviewViewport
@onready var preview_image: TextureRect = $Panel/Preview
@onready var player: CharacterBody2D = get_node_or_null(player_path)
@onready var hotbar: Control = get_node_or_null(hotbar_path)

var model := PlayerInventoryModel.new()
var is_open: bool = false
var cursor_state: StringName = &"default"
var _slots: Array[Dictionary] = []
var _drag: Dictionary = {}
var _committing_drag: bool = false
var _close_held: bool = false
var _pointer := Vector2.ZERO
var _cursor: TextureRect
var _cursor_in_window: bool = true
var _cursor_scale: int = 0
var _previous_mouse_mode: int
var _previous_movement_lock: bool = false
var _transition_tween: Tween
var _reveal_progress: float = 1.0
var _closing: bool = false
var _layout_scale: int = 3
var _drag_count: Control

func _ready() -> void:
    _previous_mouse_mode = Input.mouse_mode
    _pointer = get_viewport().get_mouse_position()
    _create_cursor()
    visible = false
    preview.world_2d = World2D.new()
    preview_image.texture = preview.get_texture()
    _build_slots()
    _drag_count = STACK_COUNT.new()
    drag_icon.add_child(_drag_count)
    model.changed.connect(_refresh_icons)
    model.set_item(&"hotbar", 0, preload("res://scenes/items/wood_pickaxe.tres"))
    model.set_item(&"hotbar", 1, preload("res://scenes/items/wood_sword.tres"))
    model.set_item(&"hotbar", 2, preload("res://scenes/items/wood_axe.tres"))
    for index in range(STARTING_BACKPACK_TOOLS.size()):
        model.set_item(&"backpack", index, STARTING_BACKPACK_TOOLS[index])
    if hotbar != null:
        hotbar.bind_inventory(model)
    get_viewport().size_changed.connect(_update_layout)
    _update_layout()

func _make_slot(group: StringName, index: int, rect: Rect2) -> void:
    var icon := TextureRect.new()
    icon.name = str(group) + str(index + 1)
    icon.position = rect.position + Vector2(2, 2)
    icon.size = Vector2(16, 16)
    icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(icon)
    var count := STACK_COUNT.new()
    count.position = Vector2(0, 9)
    icon.add_child(count)
    _slots.append({"group": group, "index": index, "rect": rect, "icon": icon, "count": count})

func _build_slots() -> void:
    for index in range(25):
        _make_slot(&"backpack", index, Rect2(105 + (index % 5) * 22, 26 + (index / 5) * 22, 20, 20))
    for index in range(5):
        _make_slot(&"equipment", index, Rect2(73, 26 + index * 22, 20, 20))
    for index in range(4):
        _make_slot(&"accessories", index, Rect2(19 + (index % 2) * 22, 92 + (index / 2) * 22, 20, 20))

func _update_layout() -> void:
    var screen := get_viewport_rect().size
    var fit := floori(minf((screen.x - 32.0) / ART_SIZE.x, (screen.y - 32.0) / ART_SIZE.y))
    var amount := mini(pixel_scale, maxi(1, fit))
    _layout_scale = amount
    panel.size = ART_SIZE
    _apply_reveal_progress(_reveal_progress)
    drag_icon.size = Vector2(16, 16) * amount
    _drag_count.scale = Vector2.ONE * amount
    _drag_count.position = Vector2(0, 9) * amount
    _update_drag_position()
    _prepare_cursors(amount)
    _update_cursor()

func _apply_reveal_progress(progress: float) -> void:
    _reveal_progress = progress
    modulate.a = progress
    panel.scale = Vector2.ONE * _layout_scale * lerpf(0.94, 1.0, progress)
    var centered := (get_viewport_rect().size - ART_SIZE * panel.scale) * 0.5
    # Settle onto exact screen pixels after the short zoom finishes.
    panel.position = centered.floor() if is_equal_approx(progress, 1.0) else centered
    if is_open:
        _update_cursor()

func _stop_transition() -> void:
    if _transition_tween != null and _transition_tween.is_valid():
        _transition_tween.kill()
    _transition_tween = null

func _animate_reveal(opening: bool) -> void:
    _stop_transition()
    var target := 1.0 if opening else 0.0
    # Reverse an interrupted animation from its current appearance without snapping.
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

func _finish_close() -> void:
    if is_open:
        return
    visible = false
    _closing = false
    if player != null:
        player.movement_locked = _previous_movement_lock
    if hotbar != null:
        hotbar.input_locked = false
    preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
    preview.process_mode = Node.PROCESS_MODE_DISABLED
    _update_cursor()

func _create_cursor() -> void:
    # Share Screen's canvas and viewport stretch with the other UI. A hardware
    # cursor uses OS display units, which can multiply Retina/window scaling.
    _cursor = TextureRect.new()
    _cursor.name = "PixelCursor"
    _cursor.texture = CURSORS[&"default"]
    _cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _cursor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _cursor.size = Vector2(16, 16)
    _cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _cursor.z_index = 100
    _cursor.visible = false
    # Inventory itself is hidden while closed, so the cursor is a UI sibling.
    get_parent().add_child.call_deferred(_cursor)

func _prepare_cursors(amount: int) -> void:
    _cursor_scale = amount
    _cursor.scale = Vector2.ONE * amount

func set_open(value: bool) -> void:
    if is_open == value:
        return
    is_open = value
    _cancel_drag()
    if value and hotbar != null:
        hotbar.cancel_drag()
    _close_held = false
    close_pressed.visible = false
    if value:
        # A reversal keeps the original movement-lock state until the modal fully closes.
        if not visible:
            _apply_reveal_progress(0.0)
            if player != null:
                _previous_movement_lock = player.movement_locked
        visible = true
        _closing = false
        _pointer = get_viewport().get_mouse_position()
        if player != null:
            player.movement_locked = true
        if hotbar != null:
            hotbar.input_locked = true
        _refresh_preview()
        preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        preview.process_mode = Node.PROCESS_MODE_INHERIT
        cursor_state = &""
        _update_cursor()
        _animate_reveal(true)
    else:
        _closing = true
        _update_cursor()
        _animate_reveal(false)
    opened_changed.emit(value)

func _refresh_preview() -> void:
    for child in preview.get_children():
        preview.remove_child(child)
        child.queue_free()
    if player == null:
        return
    # A separate canvas previews the current landscape without changing the live player.
    for layer in player.get_parent().find_children("*", "TileMapLayer", true, false):
        var copy := layer.duplicate(0) as TileMapLayer
        copy.set_script(null)
        # Portraits copy static tiles, without instantiating gameplay scenes or collisions.
        for child in copy.get_children():
            child.free()
        for cell in copy.get_used_cells():
            if copy.tile_set.get_source(copy.get_cell_source_id(cell)) is TileSetScenesCollectionSource:
                copy.erase_cell(cell)
        copy.collision_enabled = false
        copy.navigation_enabled = false
        copy.occlusion_enabled = false
        copy.transform = layer.global_transform
        preview.add_child(copy)
    var source: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
    var avatar := AnimatedSprite2D.new()
    avatar.name = "FrontFacingPlayer"
    avatar.sprite_frames = source.sprite_frames
    avatar.transform = source.global_transform
    avatar.offset = source.offset
    avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    avatar.flip_h = false
    preview.add_child(avatar)
    avatar.play(&"idle_down")
    preview.canvas_transform = Transform2D(0.0, Vector2(24, 39) - player.global_position)

func _slot_at(screen_position: Vector2) -> Dictionary:
    var local := panel.get_global_transform_with_canvas().affine_inverse() * screen_position
    for slot in _slots:
        if slot.rect.has_point(local):
            return slot
    if hotbar != null:
        var index: int = hotbar.slot_at_screen(screen_position)
        if index >= 0:
            return {"group": &"hotbar", "index": index}
    return {}

func _is_over_close(screen_position: Vector2) -> bool:
    return CLOSE_RECT.has_point(panel.get_global_transform_with_canvas().affine_inverse() * screen_position)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion or event is InputEventMouseButton:
        _pointer = event.position
        if not is_open:
            _update_cursor()
    if event.is_action_pressed(&"inventory_toggle", false, true):
        set_open(not is_open)
        get_viewport().set_input_as_handled()
        return
    if not is_open:
        if _closing:
            get_viewport().set_input_as_handled()
        return
    if event.is_action_pressed(&"ui_cancel"):
        set_open(false)
    elif event is InputEventMouseMotion:
        _pointer = event.position
        _update_drag_position()
        _update_cursor()
    elif event is InputEventMouseButton:
        _pointer = event.position
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _press_at(_pointer, event.shift_pressed)
            else:
                _release_at(_pointer)
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            if event.pressed:
                _pick_split(_pointer, event.shift_pressed)
            else:
                _release_split(_pointer)
        _update_cursor()
    # The modal owns UI input, while the world and stamina continue processing.
    get_viewport().set_input_as_handled()

func _same_slot(first: Dictionary, second: Dictionary) -> bool:
    return not first.is_empty() and not second.is_empty() and first.group == second.group and first.index == second.index

func _begin_drag(slot: Dictionary, quantity: int, sticky: bool) -> void:
    var item := model.get_item(slot.group, slot.index)
    if item == null or quantity < 1:
        return
    # Reserve a fixed amount in its source until placement succeeds. Pickups can
    # still add to that stack, and cancellation always returns the exact amount.
    _drag = {"group": slot.group, "index": slot.index, "item": item, "quantity": quantity, "sticky": sticky, "right_release_pending": sticky}
    drag_icon.texture = item.icon
    drag_icon.visible = true
    _drag_count.amount = quantity
    _update_drag_position()
    _refresh_icons()

func _press_at(point: Vector2, quick_move: bool = false) -> void:
    if _is_over_close(point):
        _close_held = true
        close_pressed.visible = true
        return
    if not _drag.is_empty():
        _place_drag(point, true)
        return
    var slot := _slot_at(point)
    if not slot.is_empty():
        if quick_move and slot.group in [&"hotbar", &"backpack"]:
            model.quick_transfer(slot.group, slot.index)
            return
        _begin_drag(slot, model.get_quantity(slot.group, slot.index), false)

func _pick_split(point: Vector2, half: bool) -> void:
    var slot := _slot_at(point)
    if slot.is_empty() or model.get_item(slot.group, slot.index) == null:
        return
    var available := model.get_quantity(slot.group, slot.index)
    if not _drag.is_empty():
        if not _same_slot(_drag, slot):
            return
        available -= int(_drag.quantity)
    var amount := ceili(available * 0.5) if half else mini(1, available)
    if amount < 1:
        return
    if _drag.is_empty():
        _begin_drag(slot, amount, true)
    else:
        _drag.quantity += amount
        _drag.right_release_pending = true
        _refresh_icons()

func _release_split(point: Vector2) -> void:
    if _drag.is_empty() or not bool(_drag.right_release_pending):
        return
    _drag.right_release_pending = false
    if not _same_slot(_drag, _slot_at(point)):
        _place_drag(point, true)

func _release_at(point: Vector2) -> void:
    if _close_held:
        _close_held = false
        close_pressed.visible = false
        if _is_over_close(point):
            set_open(false)
        return
    if not _drag.is_empty() and not bool(_drag.sticky):
        _place_drag(point, false)

func _world_drop_point(point: Vector2) -> bool:
    if not get_viewport_rect().has_point(point) or panel.get_global_rect().has_point(point):
        return false
    return hotbar == null or not hotbar.get_global_rect().has_point(point)

func _place_drag(point: Vector2, keep_on_invalid: bool) -> void:
    if _drag.is_empty():
        return
    if model.get_item(_drag.group, _drag.index) != _drag.item or model.get_quantity(_drag.group, _drag.index) < int(_drag.quantity):
        _cancel_drag()
        return
    var target := _slot_at(point)
    if _same_slot(_drag, target):
        _cancel_drag()
        return
    if not target.is_empty():
        var requested: int = _drag.quantity
        _committing_drag = true
        var moved := model.move_quantity(_drag.group, _drag.index, target.group, target.index, requested)
        _committing_drag = false
        if moved >= requested:
            _cancel_drag()
        elif moved > 0:
            _drag.quantity = requested - moved
            _drag.sticky = true
            _drag.right_release_pending = false
            _refresh_icons()
        elif not keep_on_invalid:
            _cancel_drag()
    elif _world_drop_point(point):
        _drop_to_world()
    elif not keep_on_invalid:
        _cancel_drag()

func _drop_to_world() -> void:
    if player == null or not player.is_inside_tree() or _drag.is_empty():
        return
    var item: InventoryItem = _drag.item
    var amount: int = _drag.quantity
    var pickup := PICKUP.instantiate()
    pickup.item = item
    pickup.quantity = amount
    pickup.get_node("Sprite2D").scale = Vector2(0.5, 0.5)
    pickup.dropped_by(player)
    # Drop near the player. Its owner must leave and re-enter range to reclaim it.
    _committing_drag = true
    var removed := model.remove_quantity(_drag.group, _drag.index, amount)
    _committing_drag = false
    if not removed:
        pickup.free()
        return
    _cancel_drag()
    player.get_parent().add_child(pickup)
    pickup.launch(player.global_position)

func _cancel_drag() -> void:
    _drag.clear()
    if not is_node_ready():
        return
    drag_icon.visible = false
    drag_icon.texture = null
    _drag_count.amount = 0
    _refresh_icons()

func _update_drag_position() -> void:
    drag_icon.position = (_pointer - drag_icon.size * 0.5).floor()
    if _close_held:
        close_pressed.visible = _is_over_close(_pointer)

func _refresh_icons() -> void:
    if _committing_drag:
        return
    if not _drag.is_empty() and (model.get_item(_drag.group, _drag.index) != _drag.item or model.get_quantity(_drag.group, _drag.index) < int(_drag.quantity)):
        _drag.clear()
        drag_icon.visible = false
        drag_icon.texture = null
        _drag_count.amount = 0
    for slot in _slots:
        var icon: TextureRect = slot.icon
        var item := model.get_item(slot.group, slot.index)
        var remaining := model.get_quantity(slot.group, slot.index)
        if _same_slot(_drag, slot):
            remaining = maxi(0, remaining - int(_drag.quantity))
        icon.texture = item.icon if item != null else null
        slot.count.amount = remaining
        icon.visible = item != null and remaining > 0
    if not _drag.is_empty():
        _drag_count.amount = _drag.quantity
    if hotbar != null:
        hotbar.set_dragged_slot(int(_drag.index) if not _drag.is_empty() and _drag.group == &"hotbar" else -1, int(_drag.quantity) if not _drag.is_empty() else 0)
    if is_open:
        _update_cursor()

func _update_cursor() -> void:
    var next: StringName = &"default"
    if (is_open and not _drag.is_empty()) or get_viewport().gui_is_dragging():
        next = &"pressed"
    elif is_open:
        var slot := _slot_at(_pointer)
        if not slot.is_empty() and model.get_item(slot.group, slot.index) != null:
            next = &"hand"
    elif hotbar != null and not hotbar.input_locked:
        var index: int = hotbar.slot_at_screen(_pointer)
        if index >= 0 and model.get_item(&"hotbar", index) != null:
            next = &"hand"
    if not is_instance_valid(_cursor):
        return
    if next != cursor_state:
        cursor_state = next
        _cursor.texture = CURSORS[next]
    var hotspot := Vector2(2, 1) if next != &"default" else Vector2.ZERO
    _cursor.position = (_pointer - hotspot * _cursor_scale).floor()
    _cursor.visible = _cursor_in_window and get_viewport_rect().has_point(_pointer) and get_window().has_focus()
    if DisplayServer.get_name() != "headless":
        var mode := Input.MOUSE_MODE_HIDDEN if _cursor.visible else Input.MOUSE_MODE_VISIBLE
        if Input.mouse_mode != mode:
            Input.mouse_mode = mode

func _notification(what: int) -> void:
    if not is_node_ready():
        return
    if what == NOTIFICATION_DRAG_BEGIN or what == NOTIFICATION_DRAG_END:
        _update_cursor()
    elif what == NOTIFICATION_WM_MOUSE_ENTER or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
        _pointer = get_viewport().get_mouse_position()
        _cursor_in_window = get_viewport_rect().has_point(_pointer)
        _update_cursor()
    elif what == NOTIFICATION_WM_MOUSE_EXIT:
        _cursor_in_window = false
        _update_cursor()
    elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        _cursor_in_window = false
        if is_open:
            _close_held = false
            close_pressed.visible = false
            _cancel_drag()
        _update_cursor()

func _exit_tree() -> void:
    if (is_open or _closing) and is_instance_valid(player):
        player.movement_locked = _previous_movement_lock
    if is_instance_valid(hotbar):
        hotbar.input_locked = false
    if is_instance_valid(_cursor):
        _cursor.queue_free()
    if DisplayServer.get_name() != "headless":
        Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
    Input.mouse_mode = _previous_mouse_mode
