extends Node2D
## The closest ripe tree or interactable prop owns the outline and E prompt.
const PLACED_ITEM := preload("res://scenes/world/placed_item.gd")
@export_range(0.5, 4.0, 0.25) var reach_tiles: float = 1.5
@export_range(0.5, 4.0, 0.25) var placed_item_reach_tiles: float = 2.5
@onready var player: CharacterBody2D = get_parent()
var target: Node2D

func _process(_delta: float) -> void:
    _update_target()

func _update_target() -> void:
    var closest: Node2D
    var best_distance := INF
    if not player.movement_locked and not player.is_using_tool and not get_viewport().gui_is_dragging():
        var candidates := get_tree().get_nodes_in_group(&"fruit_trees")
        candidates.append_array(get_tree().get_nodes_in_group(PLACED_ITEM.INTERACTION_GROUP))
        for candidate: Node2D in candidates:
            if not is_instance_valid(candidate) or candidate.is_queued_for_deletion() or candidate.get_viewport() != get_viewport() or not candidate.is_visible_in_tree():
                continue
            var point := candidate.global_position
            var candidate_reach := reach_tiles
            if candidate is PLACED_ITEM:
                if not candidate.can_interact_from(player.global_position):
                    continue
                point = candidate.get_interaction_point()
                candidate_reach = placed_item_reach_tiles
            elif not candidate.can_harvest():
                continue
            var distance := player.global_position.distance_squared_to(point)
            if distance < best_distance and distance < pow(candidate_reach * 16.0, 2.0) + 0.001:
                best_distance = distance
                closest = candidate
    if closest == target:
        return
    if is_instance_valid(target):
        target.set_interaction_selected(false)
    target = closest
    if is_instance_valid(target):
        target.set_interaction_selected(true)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
        return
    if not event.is_action_pressed(&"interact"):
        return
    var hud := player.get_parent().get_node_or_null("PlayerHUD")
    _update_target()
    if not is_instance_valid(target):
        return
    var interacted: bool
    if target is PLACED_ITEM:
        if target.item.subtype == &"bed":
            interacted = hud != null and hud.sleep_until_morning()
        elif event.shift_pressed:
            return
        elif target.item.subtype == &"house":
            interacted = hud != null and hud.cabin_travel.try_enter()
        elif target.has_completed_output():
            interacted = target.eject_completed()
        else:
            interacted = hud != null and hud.open_smeltry(target)
    else:
        interacted = target.harvest()
    if interacted:
        _update_target()
        get_viewport().set_input_as_handled()

func _exit_tree() -> void:
    if is_instance_valid(target) and not target.is_queued_for_deletion():
        target.set_interaction_selected(false)
