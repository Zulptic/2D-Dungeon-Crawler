class_name InventoryItem
extends Resource
## Shared item data. Stack quantities belong to PlayerInventoryModel.

enum Category { RESOURCE, TOOL, WEAPON, ARMOR, ACCESSORY, CONSUMABLE, PLACEABLE, QUEST_ITEM }
enum DamageTarget { ROCK, TREE, MONSTER }
const CATEGORY_NAMES := ["Resource", "Tool", "Weapon", "Armor", "Accessory", "Consumable", "Placeable", "Quest Item"]
const CRITICAL_MULTIPLIERS := [1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0]
# Weights out of 10,000: 60%, 22%, 10%, 4%, 2.5%, 1%, and 0.5% of crits.
const CRITICAL_WEIGHTS := [6000, 2200, 1000, 400, 250, 100, 50]
const WOOD_SWING_SPEED: int = 4
const ASHENITE_SWING_SPEED: int = 28
const WOOD_SWING_SECONDS: float = 1.6
# Original action animations: eight frames at twelve frames per second.
const ASHENITE_SWING_SECONDS: float = 8.0 / 12.0

@export_group("Identity")
@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var category: Category = Category.RESOURCE
@export var subtype: StringName = &""
@export var material: StringName = &""
@export var tags: PackedStringArray = []
@export_enum("none", "helmet", "chestplate", "leggings", "boots", "heirloom", "ring", "necklace", "charm") var equipment_slot: String = "none"

@export_group("Inventory and Value")
@export_range(1, 999, 1) var max_stack: int = 1
@export_range(0, 1000000, 1) var sale_price: int = 1

@export_group("Damage")
@export_range(0, 10000, 1) var damage_min: int = 0
@export_range(0, 10000, 1) var damage_max: int = 0
@export_range(0.0, 100.0, 0.05) var damage_multiplier: float = 1.0
@export_range(0.0, 100.0, 0.05) var rock_damage_modifier: float = 0.0
@export_range(0.0, 100.0, 0.05) var tree_damage_modifier: float = 0.0
@export_range(0.0, 100.0, 0.05) var monster_damage_modifier: float = 0.0
@export_range(0, 10, 1) var mining_tier: int = 0

@export_group("Critical Hits")
@export_range(0.0, 1.0, 0.001) var critical_chance: float = 0.0

@export_group("Swing Timing")
@export_range(0, 28, 1) var swing_speed: int = 0

func get_title() -> String:
    return display_name if not display_name.is_empty() else String(id).capitalize()

func get_category_name() -> String:
    return CATEGORY_NAMES[category]

func is_action_item() -> bool:
    return category in [Category.TOOL, Category.WEAPON]

func get_swing_interval() -> float:
    if not is_action_item() or subtype not in [&"axe", &"pickaxe", &"sword"]:
        return 0.0
    var progress := clampf(float(swing_speed - WOOD_SWING_SPEED) / float(ASHENITE_SWING_SPEED - WOOD_SWING_SPEED), 0.0, 1.0)
    return lerpf(WOOD_SWING_SECONDS, ASHENITE_SWING_SECONDS, progress)

func fits_equipment_slot(slot: String) -> bool:
    if slot == "heirloom":
        return category == Category.ACCESSORY and equipment_slot == slot
    return category == Category.ARMOR and equipment_slot == slot

func can_sell() -> bool:
    return category != Category.QUEST_ITEM

func get_sale_price() -> int:
    # Every non-quest item is sellable, including a newly created definition.
    return maxi(1, sale_price) if can_sell() else 0

func get_sale_value(quantity: int = 1) -> int:
    return get_sale_price() * maxi(0, quantity)

func get_damage_modifier(target: DamageTarget) -> float:
    var target_modifier: float = 0.0
    match target:
        DamageTarget.ROCK:
            target_modifier = rock_damage_modifier
        DamageTarget.TREE:
            target_modifier = tree_damage_modifier
        DamageTarget.MONSTER:
            target_modifier = monster_damage_modifier
    return maxf(0.0, damage_multiplier) * maxf(0.0, target_modifier)

func get_damage_range(target: DamageTarget) -> Vector2i:
    var modifier := get_damage_modifier(target)
    var low := maxi(0, mini(damage_min, damage_max))
    var high := maxi(0, maxi(damage_min, damage_max))
    return Vector2i(maxi(0, roundi(low * modifier)), maxi(0, roundi(high * modifier)))

func roll_damage(target: DamageTarget) -> int:
    # Apply modifiers to the endpoints, then roll every integer in the displayed range.
    var damage := get_damage_range(target)
    return randi_range(damage.x, damage.y)

func roll_hit(target: DamageTarget) -> DamageRoll:
    var hit := DamageRoll.new()
    hit.base_damage = roll_damage(target)
    hit.damage = hit.base_damage
    if hit.base_damage > 0 and is_action_item() and randf() < clampf(critical_chance, 0.0, 1.0):
        hit.is_critical = true
        hit.multiplier = _roll_critical_multiplier()
        hit.damage = roundi(hit.base_damage * hit.multiplier)
    return hit

func _roll_critical_multiplier() -> float:
    var roll := randi_range(1, 10000)
    for index in range(CRITICAL_WEIGHTS.size()):
        roll -= CRITICAL_WEIGHTS[index]
        if roll <= 0:
            return CRITICAL_MULTIPLIERS[index]
    return CRITICAL_MULTIPLIERS[-1]

func get_stat_lines() -> Array[String]:
    var lines: Array[String] = []
    var targets := [DamageTarget.ROCK, DamageTarget.TREE, DamageTarget.MONSTER]
    var labels := ["Rock damage", "Tree damage", "Monster dmg"]
    for index in range(targets.size()):
        var damage := get_damage_range(targets[index])
        if damage.y > 0:
            lines.append("%s: %d-%d" % [labels[index], damage.x, damage.y])
    if is_action_item() and not is_equal_approx(damage_multiplier, 1.0):
        lines.append("Damage mod: x%.2f" % damage_multiplier)
    if category == Category.TOOL and subtype == &"pickaxe":
        lines.append("Mining tier: %d" % mining_tier)
    return lines

class DamageRoll extends RefCounted:
    var base_damage: int = 0
    var damage: int = 0
    var is_critical: bool = false
    var multiplier: float = 1.0
