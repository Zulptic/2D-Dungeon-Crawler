extends RefCounted
## The UI and furnace use the same recipe costs and in-game durations.

const COAL := preload("res://scenes/items/crushed_coal.tres")
const COPPER := preload("res://scenes/items/copper_bar.tres")
const IRON := preload("res://scenes/items/iron_bar.tres")
const GOLD := preload("res://scenes/items/gold_bar.tres")
const ECHRYTE := preload("res://scenes/items/echryte_bar.tres")
const AETHERITE := preload("res://scenes/items/aetherite_bar.tres")
const ASHENITE := preload("res://scenes/items/ashenite_bar.tres")
const OAK_LOG := preload("res://scenes/items/oak_log.tres")
const COPPER_ORE := preload("res://scenes/items/crushed_copper.tres")
const IRON_ORE := preload("res://scenes/items/crushed_iron.tres")
const GOLD_ORE := preload("res://scenes/items/crushed_gold.tres")
const ECHRYTE_ORE := preload("res://scenes/items/crushed_echryte.tres")
const AETHERITE_ORE := preload("res://scenes/items/crushed_aetherite.tres")
const ASHENITE_ORE := preload("res://scenes/items/crushed_ashenite.tres")

static func get_recipes() -> Array[Dictionary]:
    return [{
        "output": COAL, "title": "Crushed Coal", "duration_minutes": 45.0,
        "fuel": OAK_LOG, "fuel_required": 10, "ore": OAK_LOG, "ore_required": 10
    }, {
        "output": COPPER, "title": "Copper Ingot", "duration_minutes": 60.0,
        "fuel": COAL, "fuel_required": 2, "ore": COPPER_ORE, "ore_required": 3
    }, {
        "output": IRON, "title": "Iron Ingot", "duration_minutes": 70.0,
        "fuel": COAL, "fuel_required": 2, "ore": IRON_ORE, "ore_required": 3
    }, {
        "output": GOLD, "title": "Gold Ingot", "duration_minutes": 80.0,
        "fuel": COAL, "fuel_required": 3, "ore": GOLD_ORE, "ore_required": 3
    }, {
        "output": ECHRYTE, "title": "Echryte Ingot", "duration_minutes": 90.0,
        "fuel": COAL, "fuel_required": 4, "ore": ECHRYTE_ORE, "ore_required": 4
    }, {
        "output": AETHERITE, "title": "Aetherite Ingot", "duration_minutes": 100.0,
        "fuel": COAL, "fuel_required": 4, "ore": AETHERITE_ORE, "ore_required": 5
    }, {
        "output": ASHENITE, "title": "Ashenite Ingot", "duration_minutes": 120.0,
        "fuel": COAL, "fuel_required": 5, "ore": ASHENITE_ORE, "ore_required": 6
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
