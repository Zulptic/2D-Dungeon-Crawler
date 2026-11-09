extends Node
## Owned by a furnace, so closing its UI never stops or resets its work.
signal changed

const RECIPES := preload("res://scenes/smeltry_recipes.gd")
const TIME_EPSILON: float = 0.000001

var _inventory: PlayerInventoryModel
var _clock: Node
var _jobs: Array[Dictionary] = []
var _updating: bool = false

func configure(inventory: PlayerInventoryModel, clock: Node) -> bool:
    if inventory == null or not is_instance_valid(clock) or not clock.has_signal("time_advanced"):
        return false
    if _inventory != inventory:
        _inventory = inventory
    if _clock != clock:
        if is_instance_valid(_clock):
            _clock.disconnect("time_advanced", advance_minutes)
        _clock = clock
        _clock.connect("time_advanced", advance_minutes)
    return true

func _exit_tree() -> void:
    if is_instance_valid(_clock) and _clock.is_connected("time_advanced", advance_minutes):
        _clock.disconnect("time_advanced", advance_minutes)

func enqueue(output: InventoryItem, requested: int) -> int:
    if _updating or _inventory == null or not is_instance_valid(_clock) or requested < 0:
        return 0
    var recipe := RECIPES.find_recipe(output)
    if recipe.is_empty():
        return 0
    var ingredients := RECIPES.get_ingredients(recipe)
    var affordable := _inventory.get_craftable_quantity(ingredients)
    var quantity := affordable if requested == 0 else requested
    if quantity < 1 or quantity > affordable:
        return 0
    # Reserve the entire batch atomically; repeated log slots share one stockpile.
    _updating = true
    if not _inventory.consume_ingredients(ingredients, quantity):
        _updating = false
        return 0
    _jobs.append({
        "output": recipe.output, "remaining": quantity,
        "completed": 0, "duration": float(recipe.duration_minutes),
        "remaining_minutes": float(recipe.duration_minutes)
    })
    _updating = false
    changed.emit()
    return quantity

func has_work() -> bool:
    for job in _jobs:
        if int(job.remaining) > 0:
            return true
    return false

func has_items() -> bool:
    return not _jobs.is_empty()

func get_work_remaining_ratio() -> float:
    for job in _jobs:
        if int(job.remaining) > 0:
            return clampf(float(job.remaining_minutes) / float(job.duration), 0.0, 1.0)
    return 0.0

func get_entries() -> Array[Dictionary]:
    var entries: Array[Dictionary] = []
    var by_output: Dictionary[StringName, Dictionary] = {}
    # Stack matching UI rows while the jobs themselves retain their queue order.
    for job in _jobs:
        var item: InventoryItem = job.output
        if not by_output.has(item.id):
            var row := {
                "id": item.id, "output": item, "quantity": 0, "completed": 0,
                "duration_text": "Ready", "ready": true, "remaining_minutes": 0.0,
            }
            by_output[item.id] = row
            entries.append(row)
        var entry := by_output[item.id]
        entry.quantity += int(job.remaining)
        entry.completed += int(job.completed)
        if entry.ready and int(job.remaining) > 0:
            var minutes := maxi(1, ceili(float(job.remaining_minutes) - TIME_EPSILON))
            entry.duration_text = "%d Minutes" % minutes
            entry.remaining_minutes = job.remaining_minutes
            entry.ready = false
    return entries

func advance_minutes(minutes: float) -> void:
    if _updating or minutes <= 0.0 or not has_work():
        return
    _updating = true
    var elapsed := minutes
    for job in _jobs:
        # Completed items wait for E collection without blocking later work.
        while int(job.remaining) > 0 and elapsed + TIME_EPSILON >= float(job.remaining_minutes):
            elapsed = maxf(0.0, elapsed - float(job.remaining_minutes))
            job.remaining = int(job.remaining) - 1
            job.completed = int(job.completed) + 1
            job.remaining_minutes = float(job.duration) if int(job.remaining) > 0 else 0.0
        if int(job.remaining) > 0:
            job.remaining_minutes = float(job.remaining_minutes) - elapsed
            break
    _updating = false
    changed.emit()

func get_completed_outputs() -> Array[Dictionary]:
    var outputs: Array[Dictionary] = []
    for job in _jobs:
        if int(job.completed) < 1:
            continue
        var matched := false
        for output in outputs:
            if output.item.id == job.output.id:
                output.quantity = int(output.quantity) + int(job.completed)
                matched = true
                break
        if not matched:
            outputs.append({"item": job.output, "quantity": int(job.completed)})
    return outputs

func remove_completed(output: InventoryItem, quantity: int) -> bool:
    if _updating or output == null or quantity < 1:
        return false
    var available: int = 0
    for job in _jobs:
        if job.output.id == output.id:
            available += int(job.completed)
    if available < quantity:
        return false
    var remaining := quantity
    for job in _jobs:
        if job.output.id != output.id:
            continue
        var taken := mini(remaining, int(job.completed))
        job.completed = int(job.completed) - taken
        remaining -= taken
        if remaining == 0:
            break
    for index in range(_jobs.size() - 1, -1, -1):
        if int(_jobs[index].remaining) == 0 and int(_jobs[index].completed) == 0:
            _jobs.remove_at(index)
    changed.emit()
    return true
