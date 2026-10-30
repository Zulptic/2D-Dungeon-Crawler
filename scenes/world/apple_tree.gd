extends "res://scenes/world/fruit_tree.gd"
## Apple fruit settings; growth, harvesting, and chopping share the same lifecycle.
@export_range(1.0, 600.0, 1.0) var apple_growth_seconds: float = 20.0:
    set(value):
        fruit_growth_seconds = value
    get:
        return fruit_growth_seconds
@export_range(0, 4, 1) var starting_apples: int = 0:
    set(value):
        starting_fruit = value
    get:
        return starting_fruit

func _init() -> void:
    fruit_stages.assign([
        preload("res://assets/items/Apple_Stage1.png"),
        preload("res://assets/items/Apple_Stage2.png"),
        preload("res://assets/items/Apple_Stage3.png")
    ])
    fruit_pickup_scene = preload("res://scenes/world/apple_pickup.tscn")

func _ready() -> void:
    super._ready()
    add_to_group(&"apple_trees")
    fruit_timer.name = "AppleGrowthTimer"
