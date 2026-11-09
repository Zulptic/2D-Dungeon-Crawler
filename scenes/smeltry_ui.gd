extends Control
## Pixel-art workstation interface backed by the selected furnace's queue.
signal quantity_requested(output: InventoryItem, amount: int)
signal opened_changed(open: bool)

@export_range(1, 6, 1) var pixel_scale: int = 3
@export_range(0.05, 1.0, 0.01) var open_duration: float = 0.18
@export_range(0.05, 1.0, 0.01) var close_duration: float = 0.14
@export var preview_on_start: bool = false
@export var show_reference_queue: bool = false
const ART_SIZE := Vector2(345, 193)
const RECIPE_ROW := preload("res://scenes/smeltry_recipe_row.tscn")
const QUEUE_ROW := preload("res://scenes/smeltry_queue_row.tscn")
const ROW_BACKGROUND := preload("res://assets/hud/smeltry/Smeltry_RecipeRow.png")
const RECIPES := preload("res://scenes/smeltry_recipes.gd")
const COPPER := preload("res://scenes/items/copper_bar.tres")
const COPPER_ICON := preload("res://assets/hud/smeltry/Smeltry_CopperIngot.png")
const COAL := preload("res://scenes/items/crushed_coal.tres")
const OAK_LOG := preload("res://scenes/items/oak_log.tres")
const COPPER_ORE := preload("res://scenes/items/crushed_copper.tres")
const SCROLL_INSET: float = 10.0
const STACK_COUNT := preload("res://scenes/item_stack_count.gd")
const COUNT_SUFFICIENT := Color(0.45, 0.95, 0.55)
const COUNT_INSUFFICIENT := Color(1.0, 0.38, 0.38)

@onready var panel: Control = $Panel
@onready var recipe_scroll: ScrollContainer = $Panel/Recipes
@onready var recipe_list: VBoxContainer = $Panel/Recipes/Rows
@onready var queue_list: VBoxContainer = $Panel/QueueEntries/Rows
@onready var scroll_track: Control = $Panel/ScrollTrack
@onready var scroll_thumb: TextureRect = $Panel/ScrollTrack/Thumb
@onready var player: CharacterBody2D = get_node_or_null("../../../Player")
@onready var inventory: Control = get_node_or_null("../Inventory")
@onready var hotbar: Control = get_node_or_null("../Hotbar")

var is_open: bool = false
var furnace: Node2D
var _previous_movement_lock: bool = false
var _previous_hotbar_lock: bool = false
var _scroll_dragging: bool = false
var _scroll_offset: float = 0.0
var _layout_scale: int = 3
var _transition_tween: Tween
var _reveal_progress: float = 0.0
var _closing: bool = false
var _ingredient_counts: Array[Dictionary] = []
var _recipe_rows: Array[Dictionary] = []
var _queue: Node
var _queue_row_ids: Array[StringName] = []

func _ready() -> void:
    get_viewport().size_changed.connect(_update_layout)
    $Panel/Close.pressed.connect(close)
    scroll_track.gui_input.connect(_on_scroll_input)
    recipe_scroll.get_v_scroll_bar().value_changed.connect(_update_scroll_thumb)
    recipe_scroll.get_v_scroll_bar().changed.connect(_update_scroll_thumb)
    if inventory != null:
        inventory.model.changed.connect(_refresh_recipe_availability)
    set_recipes(RECIPES.get_recipes())
    set_queue_entries([{"output": COPPER, "duration_text": "60 Minutes"}] if show_reference_queue else [])
    _update_layout()
    hide()
    if preview_on_start:
        _open()

func open_for(owner_furnace: Node2D) -> bool:
    if not is_instance_valid(owner_furnace) or owner_furnace.is_queued_for_deletion():
        return false
    # Only one modal owns the player's movement and hotbar at a time.
    if inventory != null and inventory.visible:
        return false
    var owner_queue: Node = owner_furnace.get("smeltry_queue")
    var clock := get_node_or_null("../../../DayNightCycle")
    if owner_queue == null or inventory == null or not owner_queue.configure(inventory.model, clock):
        return false
    _disconnect_queue()
    _queue = owner_queue
    _queue.changed.connect(_refresh_queue)
    _refresh_queue()
    furnace = owner_furnace
    _open()
    return true

func _open() -> void:
    if is_open:
        return
    # Reversing a close retains the lock state captured on the first opening.
    if not visible:
        _apply_reveal_progress(0.0)
        if player != null:
            _previous_movement_lock = player.movement_locked
        if hotbar != null:
            _previous_hotbar_lock = hotbar.input_locked
    is_open = true
    _closing = false
    if player != null:
        var mining := player.get_node_or_null("Mining")
        if mining != null:
            mining.cancel_swing()
        player.movement_locked = true
    if hotbar != null:
        hotbar.cancel_drag()
        hotbar.input_locked = true
    if is_instance_valid(furnace):
        furnace.set_interaction_selected(false)
    _update_layout()
    show()
    _animate_reveal(true)
    opened_changed.emit(true)

func close() -> void:
    if not is_open:
        return
    is_open = false
    _closing = true
    _scroll_dragging = false
    _animate_reveal(false)
    opened_changed.emit(false)

func _finish_close() -> void:
    if is_open:
        return
    hide()
    _closing = false
    if is_instance_valid(player):
        player.movement_locked = _previous_movement_lock
    if is_instance_valid(hotbar):
        hotbar.input_locked = _previous_hotbar_lock
    if is_instance_valid(inventory):
        inventory._prepare_cursors(inventory._layout_scale)
    furnace = null
    _disconnect_queue()

func _disconnect_queue() -> void:
    if is_instance_valid(_queue) and _queue.changed.is_connected(_refresh_queue):
        _queue.changed.disconnect(_refresh_queue)
    _queue = null
    _queue_row_ids.clear()

func _refresh_queue() -> void:
    if not is_instance_valid(_queue):
        return
    var entries: Array = _queue.get_entries()
    var ids: Array[StringName] = []
    for entry: Dictionary in entries:
        ids.append(entry.id)
    if ids != _queue_row_ids or queue_list.get_child_count() != entries.size():
        set_queue_entries(entries)
        _queue_row_ids = ids
    else:
        for index in range(entries.size()):
            _update_queue_row(queue_list.get_child(index), entries[index])

func _exit_tree() -> void:
    _disconnect_queue()
    _stop_transition()
    if is_open or _closing:
        is_open = false
        _finish_close()

func _process(_delta: float) -> void:
    if is_open and not preview_on_start and (not is_instance_valid(furnace) or furnace.is_queued_for_deletion()):
        close()

func _input(event: InputEvent) -> void:
    if (not is_open and not _closing) or not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"interact") or event.is_action_pressed(&"inventory_toggle"):
        close()
        get_viewport().set_input_as_handled()

func _update_layout() -> void:
    var screen := get_viewport_rect().size
    var requested: int = inventory.pixel_scale if inventory != null else pixel_scale
    var fit := floori(minf((screen.x - 32.0) / ART_SIZE.x, (screen.y - 32.0) / ART_SIZE.y))
    _layout_scale = mini(requested, maxi(1, fit))
    _apply_reveal_progress(_reveal_progress)
    if is_open and inventory != null:
        inventory._prepare_cursors(_layout_scale)

func _apply_reveal_progress(progress: float) -> void:
    _reveal_progress = progress
    modulate.a = progress
    panel.scale = Vector2.ONE * _layout_scale * lerpf(0.94, 1.0, progress)
    var centered := (get_viewport_rect().size - ART_SIZE * panel.scale) * 0.5
    # Match the inventory pop, then settle onto the exact reference pixel grid.
    panel.position = centered.floor() if is_equal_approx(progress, 1.0) else centered

func _stop_transition() -> void:
    if _transition_tween != null and _transition_tween.is_valid():
        _transition_tween.kill()
    _transition_tween = null

func _animate_reveal(opening: bool) -> void:
    _stop_transition()
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

func _clear_rows(container: VBoxContainer) -> void:
    for child in container.get_children():
        container.remove_child(child)
        child.queue_free()

func set_recipes(recipes: Array) -> void:
    _ingredient_counts.clear()
    _recipe_rows.clear()
    _clear_rows(recipe_list)
    for recipe: Dictionary in recipes:
        var output := recipe.get("output") as InventoryItem
        if output == null:
            continue
        var row: Control = RECIPE_ROW.instantiate()
        row.name = "Recipe_" + String(output.id)
        recipe_list.add_child(row)
        row.get_node("OutputIcon").texture = COPPER_ICON if output.id == COPPER.id else output.icon
        row.get_node("Title").text = recipe.get("title", output.get_title())
        var duration_text: String = recipe.get("duration_text", "%d Minutes" % int(recipe.get("duration_minutes", 0)))
        row.get_node("Duration").text = duration_text
        row.get_node("Duration").visible = not duration_text.is_empty()
        row.get_node("Clock").visible = not duration_text.is_empty()
        var fuel := recipe.get("fuel") as InventoryItem
        var ore := recipe.get("ore") as InventoryItem
        row.get_node("FuelIcon").texture = fuel.icon if fuel != null else null
        row.get_node("OreIcon").texture = ore.icon if ore != null else null
        _add_ingredient_count(row, "FuelCount", fuel, int(recipe.get("fuel_required", 1)), "FuelIcon")
        _add_ingredient_count(row, "OreCount", ore, int(recipe.get("ore_required", 1)), "OreIcon")
        _recipe_rows.append({"row": row, "ingredients": RECIPES.get_ingredients(recipe)})
        for pair in [["Once", 1], ["Five", 5], ["Maximum", 0]]:
            var button: TextureButton = row.get_node(pair[0])
            button.pressed.connect(_request_quantity.bind(output, int(pair[1]), button))
    # Keep the five-row layout from the reference as recipes are added.
    for index in range(maxi(0, 5 - recipe_list.get_child_count())):
        var blank := TextureRect.new()
        blank.name = "EmptyRow_" + str(index + 1)
        blank.texture = ROW_BACKGROUND
        blank.custom_minimum_size = Vector2(228, 30)
        blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
        recipe_list.add_child(blank)
    _refresh_recipe_availability()
    recipe_scroll.scroll_vertical = 0
    _update_scroll_thumb.call_deferred()

func _add_ingredient_count(row: Control, node_name: String, ingredient: InventoryItem, required: int, icon_name: String) -> void:
    var icon: Control = row.get_node(icon_name)
    var count := STACK_COUNT.new()
    count.name = node_name
    # Use the inventory's exact stack-number renderer and icon-relative offset.
    count.position = icon.position + Vector2(0, 9)
    count.show_single = true
    row.add_child(count)
    _ingredient_counts.append({"count": count, "item": ingredient, "required": maxi(0, required), "recipe": row.get_instance_id()})

func _refresh_recipe_availability() -> void:
    var model: PlayerInventoryModel = inventory.model if inventory != null else null
    for recipe in _recipe_rows:
        var affordable := model.get_craftable_quantity(recipe.ingredients) if model != null else 0
        var row: Control = recipe.row
        row.get_node("Once").disabled = affordable < 1
        row.get_node("Five").disabled = affordable < 5
        # Max is a bulk action; use 1x for a single item.
        row.get_node("Maximum").disabled = affordable < 2

    var remaining_by_recipe: Dictionary = {}
    for binding in _ingredient_counts:
        var count = binding.count
        var ingredient: InventoryItem = binding.item
        var required: int = binding.required
        count.amount = required if ingredient != null else 0
        if not count.visible:
            continue
        if not remaining_by_recipe.has(binding.recipe):
            remaining_by_recipe[binding.recipe] = {}
        var remaining: Dictionary = remaining_by_recipe[binding.recipe]
        var item_key: Variant = ingredient.id if ingredient.id != &"" else ingredient
        if not remaining.has(item_key):
            remaining[item_key] = model.get_total_quantity(ingredient) if model != null else 0
        var owned: int = remaining[item_key]
        count.font_color = COUNT_SUFFICIENT if owned >= required else COUNT_INSUFFICIENT
        # Repeated ingredient slots share the available stock within this recipe.
        remaining[item_key] = maxi(0, owned - required)

func _request_quantity(output: InventoryItem, amount: int, button: TextureButton) -> void:
    if not is_open or button.disabled:
        return
    if is_instance_valid(_queue) and _queue.enqueue(output, amount) > 0:
        quantity_requested.emit(output, amount)

func set_queue_entries(entries: Array) -> void:
    _queue_row_ids.clear()
    _clear_rows(queue_list)
    for entry: Dictionary in entries:
        var output := entry.get("output") as InventoryItem
        if output == null:
            continue
        var row: Control = QUEUE_ROW.instantiate()
        queue_list.add_child(row)
        row.get_node("OutputIcon").texture = COPPER_ICON if output.id == COPPER.id else output.icon
        var count := STACK_COUNT.new()
        count.name = "Quantity"
        count.show_single = true
        count.position = row.get_node("OutputIcon").position + Vector2(0, 9)
        row.add_child(count)
        _update_queue_row(row, entry)

func _update_queue_row(row: Control, entry: Dictionary) -> void:
    row.get_node("Quantity").amount = int(entry.get("quantity", 1))
    var ready := bool(entry.get("ready", false))
    var duration := row.get_node("Duration") as Label
    duration.text = entry.get("duration_text", "")
    duration.position.y = 9.0 if ready else 15.0
    row.get_node("Clock").visible = not ready

func _update_scroll_thumb(_value: float = 0.0) -> void:
    var bar := recipe_scroll.get_v_scroll_bar()
    var maximum := maxf(0.0, bar.max_value - bar.page)
    var ratio := bar.value / maximum if maximum > 0.0 else 0.0
    var travel := scroll_track.size.y - SCROLL_INSET * 2.0 - scroll_thumb.size.y
    scroll_thumb.position.y = SCROLL_INSET + roundf(ratio * travel)

func _on_scroll_input(event: InputEvent) -> void:
    if not is_open:
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _scroll_dragging = event.pressed
        if event.pressed:
            _scroll_offset = event.position.y - scroll_thumb.position.y if scroll_thumb.get_rect().has_point(event.position) else scroll_thumb.size.y * 0.5
            _drag_scroll(event.position.y)
        scroll_track.accept_event()
    elif event is InputEventMouseMotion and _scroll_dragging:
        _drag_scroll(event.position.y)
        scroll_track.accept_event()
    elif event is InputEventMouseButton and event.pressed:
        var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0)
        if direction != 0:
            recipe_scroll.scroll_vertical += direction * 33
            scroll_track.accept_event()

func _drag_scroll(y: float) -> void:
    var travel := scroll_track.size.y - SCROLL_INSET * 2.0 - scroll_thumb.size.y
    var ratio := clampf((y - _scroll_offset - SCROLL_INSET) / travel, 0.0, 1.0)
    var bar := recipe_scroll.get_v_scroll_bar()
    recipe_scroll.scroll_vertical = roundi(ratio * maxf(0.0, bar.max_value - bar.page))
