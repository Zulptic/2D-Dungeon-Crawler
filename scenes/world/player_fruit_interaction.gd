extends Node2D
## One closest ripe tree owns the outline and E prompt in this player's viewport.
@export_range(0.5, 4.0, 0.25) var reach_tiles: float = 1.5
@onready var player: CharacterBody2D = get_parent()
var target_tree: Node2D

func _process(_delta: float) -> void:
    _update_target()

func _update_target() -> void:
    var closest: Node2D
    var best_distance := pow(reach_tiles * 16.0, 2.0) + 0.001
    if not player.movement_locked and not player.is_using_tool and not get_viewport().gui_is_dragging():
        for tree in get_tree().get_nodes_in_group(&"fruit_trees"):
            if not is_instance_valid(tree) or tree.is_queued_for_deletion() or tree.get_viewport() != get_viewport() or not tree.is_visible_in_tree() or not tree.can_harvest():
                continue
            var distance := player.global_position.distance_squared_to(tree.global_position)
            if distance < best_distance:
                best_distance = distance
                closest = tree
    if closest == target_tree:
        return
    if is_instance_valid(target_tree):
        target_tree.set_interaction_selected(false)
    target_tree = closest
    if is_instance_valid(target_tree):
        target_tree.set_interaction_selected(true)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
        return
    if not event.is_action_pressed(&"interact"):
        return
    _update_target()
    if is_instance_valid(target_tree) and target_tree.harvest():
        _update_target()
        get_viewport().set_input_as_handled()

func _exit_tree() -> void:
    if is_instance_valid(target_tree) and not target_tree.is_queued_for_deletion():
        target_tree.set_interaction_selected(false)
