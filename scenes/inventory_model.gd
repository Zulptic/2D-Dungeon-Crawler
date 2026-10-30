class_name PlayerInventoryModel
extends RefCounted
## Item definitions are shared; quantities belong to individual slots.
signal changed
signal item_collected(item: InventoryItem, quantity: int)

const COUNTS := {&"backpack": 25, &"hotbar": 9, &"equipment": 5, &"accessories": 4}
const EQUIPMENT_TYPES := ["helmet", "chestplate", "leggings", "boots", "heirloom"]
const PICKUP_ORDER: Array[StringName] = [&"hotbar", &"backpack"]
var _containers: Dictionary = {}
var _quantities: Dictionary = {}

func _init() -> void:
    for group: StringName in COUNTS:
        var entries: Array[InventoryItem] = []
        entries.resize(COUNTS[group])
        _containers[group] = entries
        var amounts: Array[int] = []
        amounts.resize(COUNTS[group])
        _quantities[group] = amounts

func _valid_slot(group: StringName, index: int) -> bool:
    return COUNTS.has(group) and index >= 0 and index < int(COUNTS[group])

func get_item(group: StringName, index: int) -> InventoryItem:
    if not _valid_slot(group, index):
        return null
    return _containers[group][index] as InventoryItem

func get_quantity(group: StringName, index: int) -> int:
    if not _valid_slot(group, index):
        return 0
    return int(_quantities[group][index])

func _slot_limit(group: StringName, item: InventoryItem) -> int:
    if item == null:
        return 0
    return 1 if group == &"equipment" or group == &"accessories" else maxi(1, item.max_stack)

func _same_item(first: InventoryItem, second: InventoryItem) -> bool:
    return first != null and second != null and (first == second or (first.id != &"" and first.id == second.id))

func _can_stack(first: InventoryItem, second: InventoryItem) -> bool:
    return _same_item(first, second) and first.max_stack > 1 and second.max_stack > 1

func _pickup_order(item: InventoryItem) -> Array[StringName]:
    var order: Array[StringName] = []
    # Keep new stacks with their existing items, including full stacks and tools.
    for group in PICKUP_ORDER:
        for index in range(COUNTS[group]):
            if _same_item(get_item(group, index), item):
                order.append(group)
                break
    for group in PICKUP_ORDER:
        if not order.has(group):
            order.append(group)
    return order

func accepts(group: StringName, index: int, item: InventoryItem) -> bool:
    if not _valid_slot(group, index):
        return false
    if item == null:
        return true
    if group == &"equipment":
        return item.fits_equipment_slot(EQUIPMENT_TYPES[index])
    if group == &"accessories":
        return item.category == InventoryItem.Category.ACCESSORY and item.equipment_slot != "heirloom"
    return true

func _write_slot(group: StringName, index: int, item: InventoryItem, quantity: int) -> void:
    _containers[group][index] = item
    _quantities[group][index] = quantity if item != null else 0

func set_item(group: StringName, index: int, item: InventoryItem, quantity: int = 1) -> bool:
    if not accepts(group, index, item):
        return false
    if item != null and (quantity < 1 or quantity > _slot_limit(group, item)):
        return false
    _write_slot(group, index, item, quantity)
    changed.emit()
    return true

func move_item(source_group: StringName, source_index: int, target_group: StringName, target_index: int) -> bool:
    if get_item(source_group, source_index) == null:
        return false
    if source_group == target_group and source_index == target_index:
        return true
    return move_quantity(source_group, source_index, target_group, target_index, get_quantity(source_group, source_index)) > 0

func move_quantity(source_group: StringName, source_index: int, target_group: StringName, target_index: int, quantity: int) -> int:
    var source := get_item(source_group, source_index)
    var source_amount := get_quantity(source_group, source_index)
    if source == null or quantity < 1 or quantity > source_amount or not _valid_slot(target_group, target_index):
        return 0
    if source_group == target_group and source_index == target_index:
        return 0
    if not accepts(target_group, target_index, source):
        return 0
    var target := get_item(target_group, target_index)
    var target_amount := get_quantity(target_group, target_index)
    var moved: int = 0
    if target == null or _can_stack(source, target):
        moved = mini(quantity, maxi(0, _slot_limit(target_group, source if target == null else target) - target_amount))
        if moved == 0:
            return 0
        _write_slot(target_group, target_index, source if target == null else target, target_amount + moved)
        _write_slot(source_group, source_index, source if source_amount > moved else null, source_amount - moved)
    else:
        # Only whole stacks may swap; a split stack must keep its remainder owned.
        if quantity != source_amount or not accepts(source_group, source_index, target):
            return 0
        if quantity > _slot_limit(target_group, source) or target_amount > _slot_limit(source_group, target):
            return 0
        _write_slot(target_group, target_index, source, quantity)
        _write_slot(source_group, source_index, target, target_amount)
        moved = quantity
    changed.emit()
    return moved

func quick_transfer(source_group: StringName, source_index: int) -> int:
    if source_group not in [&"hotbar", &"backpack"] or not _valid_slot(source_group, source_index):
        return 0
    var item := get_item(source_group, source_index)
    var quantity := get_quantity(source_group, source_index)
    if item == null or quantity <= 0:
        return 0
    var target_group: StringName = &"backpack" if source_group == &"hotbar" else &"hotbar"
    var remaining := quantity
    # Match stacks throughout the destination before using its empty slots.
    for index in range(COUNTS[target_group]):
        var current := get_item(target_group, index)
        if not _can_stack(item, current):
            continue
        var amount := get_quantity(target_group, index)
        var moved := mini(remaining, maxi(0, _slot_limit(target_group, current) - amount))
        if moved > 0:
            _write_slot(target_group, index, current, amount + moved)
            remaining -= moved
        if remaining == 0:
            break
    if remaining > 0:
        for index in range(COUNTS[target_group]):
            if get_item(target_group, index) != null:
                continue
            var moved := mini(remaining, _slot_limit(target_group, item))
            _write_slot(target_group, index, item, moved)
            remaining -= moved
            if remaining == 0:
                break
    var transferred := quantity - remaining
    if transferred > 0:
        _write_slot(source_group, source_index, item if remaining > 0 else null, remaining)
        # One coherent update; moving owned items is not a world pickup.
        changed.emit()
    return transferred

func remove_quantity(group: StringName, index: int, quantity: int) -> bool:
    var item := get_item(group, index)
    var amount := get_quantity(group, index)
    if item == null or quantity < 1 or quantity > amount:
        return false
    _write_slot(group, index, item if amount > quantity else null, amount - quantity)
    changed.emit()
    return true

func available_capacity(item: InventoryItem) -> int:
    if item == null:
        return 0
    var capacity: int = 0
    for group in PICKUP_ORDER:
        for index in range(COUNTS[group]):
            var current := get_item(group, index)
            if current == null:
                capacity += _slot_limit(group, item)
            elif _can_stack(current, item):
                capacity += maxi(0, _slot_limit(group, current) - get_quantity(group, index))
    return capacity

func can_add_item(item: InventoryItem, quantity: int = 1) -> bool:
    # Check the entire batch before changing anything so a failed pickup cannot lose items.
    return item != null and quantity > 0 and available_capacity(item) >= quantity

func add_item(item: InventoryItem, quantity: int = 1) -> bool:
    if not can_add_item(item, quantity):
        return false
    var remaining := quantity
    var order := _pickup_order(item)
    # Fill all matching stacks before considering an empty slot in either place.
    for group in order:
        for index in range(COUNTS[group]):
            var current := get_item(group, index)
            if not _can_stack(current, item):
                continue
            var moved := mini(remaining, maxi(0, _slot_limit(group, current) - get_quantity(group, index)))
            _quantities[group][index] += moved
            remaining -= moved
            if remaining == 0:
                changed.emit()
                return true
    # Prefer the container already holding this item; new items use hotbar first.
    for group in order:
        for index in range(COUNTS[group]):
            if get_item(group, index) != null:
                continue
            var moved := mini(remaining, _slot_limit(group, item))
            _write_slot(group, index, item, moved)
            remaining -= moved
            if remaining == 0:
                changed.emit()
                return true
    return false

func collect_item(item: InventoryItem, quantity: int = 1) -> bool:
    # Only world collection emits this event; setup, slot moves, and swaps stay quiet.
    if not add_item(item, quantity):
        return false
    item_collected.emit(item, quantity)
    return true
