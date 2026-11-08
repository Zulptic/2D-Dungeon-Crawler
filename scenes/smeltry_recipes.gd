extends RefCounted
## The UI and furnace use the same recipe costs and in-game durations.

const COAL := preload("res://scenes/items/crushed_coal.tres")
const COPPER := preload("res://scenes/items/copper_bar.tres")
const OAK_LOG := preload("res://scenes/items/oak_log.tres")
const COPPER_ORE := preload("res://scenes/items/crushed_copper.tres")

static func get_recipes() -> Array[Dictionary]:
    return [{
        "output": COAL, "title": "Crushed Coal", "duration_minutes": 45.0,
        "fuel": OAK_LOG, "fuel_required": 10, "ore": OAK_LOG, "ore_required": 10
    }, {
        "output": COPPER, "title": "Copper Ingot", "duration_minutes": 60.0,
        "fuel": COAL, "fuel_required": 2, "ore": COPPER_ORE, "ore_required": 3
    }]

static func find_recipe(output: InventoryItem) -> Dictionary:
    if output != null:
        for recipe in get_recipes():
            if recipe.output.id == output.id:
                return recipe
    return {}

static func get_ingredients(recipe: Dictionary) -> Array[Dictionary]:
    return [
        {"item": recipe.get("fuel"), "quantity": int(recipe.get("fuel_required", 0))},
        {"item": recipe.get("ore"), "quantity": int(recipe.get("ore_required", 0))}
    ]
