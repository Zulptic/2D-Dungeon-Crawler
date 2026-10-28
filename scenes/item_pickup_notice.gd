extends Control
## New item types enter at the bottom; matching pickups refresh their own row.
@export_range(1, 6, 1) var pixel_scale: int = 3
@export_range(0, 100, 1) var screen_margin: int = 16
@export_range(0.5, 10.0, 0.1) var display_duration: float = 3.0
@export_range(0.05, 1.0, 0.01) var open_duration: float = 0.18
@export_range(0.05, 1.0, 0.01) var close_duration: float = 0.14
@export_range(0.05, 1.0, 0.01) var scroll_duration: float = 0.22
@export_range(0, 16, 1) var entry_spacing: int = 4
@export var hotbar_path: NodePath = NodePath("../Hotbar")
@export var health_hud_path: NodePath = NodePath("../Art")
const ENTRY := preload("res://scenes/item_pickup_entry.tscn")
const ART_SIZE := Vector2(103, 36)
const MAX_ENTRIES: int = 5
# Chronological order: the oldest row is at the top, newest at the bottom.
var entries: Array[Control] = []
var _layout_scale: int = 3
var _rest_position := Vector2.ZERO

func _ready() -> void:
    hide()
    get_viewport().size_changed.connect(_update_layout)
    _update_layout()

func show_pickup(item: InventoryItem, quantity: int = 1) -> void:
    if item == null or quantity < 1:
        return
    for entry in entries:
        if entry.matches_item(item):
            entry.show_pickup(item, quantity)
            return
    # Retire before adding so even a rapid burst never draws a sixth row.
    while entries.size() >= MAX_ENTRIES:
        _remove_entry(entries[0], false)
    var entry: Control = ENTRY.instantiate()
    entry.display_duration = display_duration
    entry.open_duration = open_duration
    entry.close_duration = close_duration
    add_child(entry)
    entries.append(entry)
    entry.finished.connect(_on_entry_finished)
    entry.scale = Vector2.ONE * _layout_scale
    entry.position = _rest_position + Vector2(0.0, 6.0 * _layout_scale)
    show()
    entry.show_pickup(item, quantity)
    _arrange_entries(true)

func _bottom_position(amount: int) -> Vector2:
    var art_size := ART_SIZE * amount
    var bottom := Vector2(screen_margin, get_viewport_rect().size.y - screen_margin - art_size.y)
    var hotbar := get_node_or_null(hotbar_path) as Control
    if hotbar != null and hotbar.is_visible_in_tree():
        var bar_rect := hotbar.get_global_rect()
        if Rect2(bottom, art_size).grow(8.0).intersects(bar_rect):
            bottom.y = bar_rect.position.y - art_size.y - 8.0
    return bottom.floor()

func _update_layout() -> void:
    var screen := get_viewport_rect().size
    var width_fit := maxi(1, floori((screen.x - screen_margin * 2.0) / ART_SIZE.x))
    var top_limit := float(screen_margin)
    var health := get_node_or_null(health_hud_path) as Control
    if health != null and health.is_visible_in_tree():
        top_limit = maxf(top_limit, health.get_global_rect().end.y + 8.0)
    # Fit the full five-row stack at an integer scale before pickups arrive,
    # so notices do not suddenly shrink when another item type is collected.
    _layout_scale = 1
    for amount in range(mini(pixel_scale, width_fit), 0, -1):
        var bottom := _bottom_position(amount)
        var stack_top := bottom.y - (MAX_ENTRIES - 1) * (ART_SIZE.y + entry_spacing) * amount
        if stack_top >= top_limit:
            _layout_scale = amount
            break
    _rest_position = _bottom_position(_layout_scale)
    _arrange_entries(false)

func _arrange_entries(animated: bool) -> void:
    var step := (ART_SIZE.y + entry_spacing) * _layout_scale
    for index in range(entries.size()):
        var entry: Control = entries[index]
        entry.scale = Vector2.ONE * _layout_scale
        var target := _rest_position - Vector2(0.0, (entries.size() - 1 - index) * step)
        entry.move_to(target, scroll_duration if animated else 0.0)

func _on_entry_finished(entry: Control) -> void:
    _remove_entry(entry, true)

func _remove_entry(entry: Control, rearrange: bool) -> void:
    var index := entries.find(entry)
    if index < 0:
        return
    entries.remove_at(index)
    entry.dismiss()
    if entries.is_empty():
        hide()
    elif rearrange:
        _arrange_entries(true)
