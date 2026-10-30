extends Node2D
## Mouse/facing harvest assist selects rocks for pickaxes and tree trunks for axes.
@export_range(1, 8, 1) var reach_tiles: int = 3
@export_range(0.0, 0.15, 0.005) var impact_pause_duration: float = 0.04
@export_range(0.0, 24.0, 1.0) var mouse_snap_distance: float = 8.0
@export_range(1.0, 89.0, 1.0) var facing_half_angle: float = 45.0
const TILE_SIZE: int = 16
const IMPACT_FRAME: int = 4
const AXE_IMPACT_FRAME: int = 3
const HARVEST_GROUPS := {&"pickaxe": &"mineable_rocks", &"axe": &"choppable_trees"}
const TOOL_ANIMATIONS := {&"pickaxe": &"crush", &"sword": &"pierce", &"axe": &"slice"}
const SELECTOR_SHEETS := {
	&"small": preload("res://assets/hud/player_hud/sheet_cursor_hovered_tile16.png"),
	&"large": preload("res://assets/hud/player_hud/sheet_cursor_hovered_tile32.png")
}
@onready var player: CharacterBody2D = get_parent()
@onready var sprite: AnimatedSprite2D = get_node("../AnimatedSprite2D")
@onready var inventory: Control = get_node_or_null("../../PlayerHUD/Screen/Inventory")
@onready var hotbar: Control = get_node_or_null("../../PlayerHUD/Screen/Hotbar")
@onready var ground: TileMapLayer = get_node_or_null("../../Ground")
var selector: AnimatedSprite2D
var target_cell := Vector2i.ZERO
var target_position := Vector2.ZERO
var target_in_reach: bool = false
var target_rock: Node2D
var _busy: bool = false
var _hit_applied: bool = false
var _swing_rock: Node2D
var _swing_cell := Vector2i.ZERO
var _impact_resume_usec: int = 0
var _swing_item: InventoryItem
var _swing_animation: StringName = &""
var _mining_held: bool = false
var _held_item: InventoryItem
var _next_swing_usec: int = 0

func _ready() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for animation: StringName in SELECTOR_SHEETS:
		var sheet: Texture2D = SELECTOR_SHEETS[animation]
		frames.add_animation(animation)
		frames.set_animation_speed(animation, 4.0)
		frames.set_animation_loop(animation, true)
		for index in range(2):
			var frame := AtlasTexture.new()
			frame.atlas = sheet
			frame.region = Rect2(index * 48, 0, 48, 48)
			frame.filter_clip = true
			frames.add_frame(animation, frame)
	selector = AnimatedSprite2D.new()
	selector.name = "HoveredTile"
	selector.sprite_frames = frames
	selector.z_index = 5
	add_child(selector)
	selector.play(&"small")
	visible = false
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	call_deferred("_connect_inventory")

func equipped_item() -> InventoryItem:
	if inventory == null or hotbar == null or hotbar.selected_slot < 1:
		return null
	return inventory.model.get_item(&"hotbar", hotbar.selected_slot - 1)

func has_usable_tool() -> bool:
	var item := equipped_item()
	return item != null and item.is_action_item() and TOOL_ANIMATIONS.has(item.subtype)

func has_harvest_tool() -> bool:
	var item := equipped_item()
	return item != null and HARVEST_GROUPS.has(item.subtype)

func has_pickaxe() -> bool:
	var item := equipped_item()
	return item != null and item.subtype == &"pickaxe"

func _connect_inventory() -> void:
	if inventory != null:
		inventory.model.changed.connect(_sync_equipped_state)
		inventory.opened_changed.connect(_sync_equipped_state)
	if hotbar != null:
		hotbar.selection_changed.connect(_on_hotbar_selection_changed)
	_sync_equipped_state()

func _sync_equipped_state(_value: Variant = null) -> void:
	var usable: bool = has_usable_tool() and not player.movement_locked
	if _mining_held and (not usable or equipped_item() != _held_item):
		_stop_holding()
	if _busy and (not usable or equipped_item() != _swing_item):
		cancel_swing()
	visible = has_harvest_tool() and usable
	if not visible:
		_clear_target()

func _process(_delta: float) -> void:
	_sync_equipped_state()
	if not has_usable_tool() or player.movement_locked:
		return
	if _impact_resume_usec > 0 and Time.get_ticks_usec() >= _impact_resume_usec:
		_impact_resume_usec = 0
		if _busy and sprite.animation == _swing_animation:
			sprite.play()
	update_target(get_global_mouse_position())
	_try_held_swing()

func _stop_holding() -> void:
	_mining_held = false
	_held_item = null

func _on_hotbar_selection_changed(_slot: int) -> void:
	_stop_holding()
	_sync_equipped_state()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_MOUSE_EXIT:
		_stop_holding()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# See releases even when a GUI control consumes them. Only an unhandled
		# world press below may arm continuous mining again.
		_stop_holding()

func _try_held_swing() -> void:
	if not _mining_held:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_stop_holding()
		return
	if not _busy and get_viewport().gui_get_hovered_control() == null:
		try_swing(get_global_mouse_position())

func _clear_target() -> void:
	target_rock = null
	target_in_reach = false
	if is_instance_valid(selector):
		selector.visible = false

func _is_targetable(rock: Variant) -> bool:
	# A broken node can be freed before the current swing finishes.
	if not is_instance_valid(rock) or rock.get_viewport() != get_viewport() or rock.is_queued_for_deletion() or not rock.is_visible_in_tree() or rock._breaking or rock.health <= 0:
		return false
	var item := equipped_item()
	return item != null and HARVEST_GROUPS.has(item.subtype) and rock.is_in_group(HARVEST_GROUPS[item.subtype])

func _rock_cells(rock: Node2D) -> Rect2i:
	var anchor := ground.local_to_map(ground.to_local(rock.global_position))
	return Rect2i(anchor + rock.mining_footprint.position, rock.mining_footprint.size)

func _cell_position(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))

func _show_target(rock: Node2D, cell: Vector2i) -> void:
	target_rock = rock
	target_cell = cell
	target_position = _cell_position(cell)
	target_in_reach = true
	var cells := _rock_cells(rock)
	var center := ground.map_to_local(cells.position) + (Vector2(cells.size) - Vector2.ONE) * TILE_SIZE * 0.5
	selector.global_position = ground.to_global(center)
	selector.global_scale = ground.global_scale
	var animation: StringName = &"small" if cells.size == Vector2i.ONE else &"large"
	if selector.animation != animation:
		# Both sheets share the same two-frame timing, so size changes stay smooth.
		var frame := selector.frame
		var progress := selector.frame_progress
		selector.play(animation)
		selector.set_frame_and_progress(frame, progress)
	selector.modulate = Color.WHITE
	selector.visible = true

func update_target(world_position: Vector2) -> void:
	_clear_target()
	if ground == null or not has_harvest_tool() or player.movement_locked or get_viewport().gui_get_hovered_control() != null:
		return
	var reach_squared := pow(reach_tiles * TILE_SIZE + 0.001, 2.0)
	# The marker stays with the rock being struck until this swing ends.
	if _busy and _is_targetable(_swing_rock) and _swing_rock.covers_tile(ground, _swing_cell) and player.global_position.distance_squared_to(_cell_position(_swing_cell)) <= reach_squared:
		_show_target(_swing_rock, _swing_cell)
		return
	var mouse_local := ground.to_local(world_position)
	var facing: Vector2 = player.facing.normalized()
	var facing_threshold := cos(deg_to_rad(facing_half_angle))
	var mouse_rock: Node2D
	var mouse_cell := Vector2i.ZERO
	var mouse_score: float = INF
	var mouse_cell_score: float = INF
	var facing_rock: Node2D
	var facing_cell := Vector2i.ZERO
	var facing_distance: float = INF
	var facing_alignment: float = -1.0
	var group: StringName = HARVEST_GROUPS[equipped_item().subtype]
	for rock: Node2D in get_tree().get_nodes_in_group(group):
		if not _is_targetable(rock):
			continue
		var cells := _rock_cells(rock)
		var local_bounds := Rect2(ground.map_to_local(cells.position) - Vector2.ONE * TILE_SIZE * 0.5, Vector2(cells.size) * TILE_SIZE)
		var closest_local := mouse_local.clamp(local_bounds.position, local_bounds.end)
		var cursor_distance := world_position.distance_squared_to(ground.to_global(closest_local))
		for y in range(cells.position.y, cells.end.y):
			for x in range(cells.position.x, cells.end.x):
				var cell := Vector2i(x, y)
				var point := _cell_position(cell)
				var offset := point - player.global_position
				var player_distance := offset.length_squared()
				if player_distance > reach_squared:
					continue
				var cursor_cell_distance := world_position.distance_squared_to(point)
				if cursor_distance <= mouse_snap_distance * mouse_snap_distance and (cursor_distance < mouse_score or (is_equal_approx(cursor_distance, mouse_score) and cursor_cell_distance < mouse_cell_score)):
					mouse_rock = rock
					mouse_cell = cell
					mouse_score = cursor_distance
					mouse_cell_score = cursor_cell_distance
				if offset.is_zero_approx():
					continue
				var alignment := offset.normalized().dot(facing)
				if alignment + 0.00001 >= facing_threshold and (player_distance < facing_distance or (is_equal_approx(player_distance, facing_distance) and alignment > facing_alignment)):
					facing_rock = rock
					facing_cell = cell
					facing_distance = player_distance
					facing_alignment = alignment
	if mouse_rock != null:
		_show_target(mouse_rock, mouse_cell)
	elif facing_rock != null:
		_show_target(facing_rock, facing_cell)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if has_usable_tool() and not player.movement_locked:
			_mining_held = true
			_held_item = equipped_item()
		var world_position: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
		if try_swing(world_position):
			get_viewport().set_input_as_handled()

func try_swing(world_position: Vector2) -> bool:
	if _busy or Time.get_ticks_usec() < _next_swing_usec or player.movement_locked or not has_usable_tool():
		return false
	var item := equipped_item()
	var direction := world_position - player.global_position
	if HARVEST_GROUPS.has(item.subtype):
		update_target(world_position)
		if not target_in_reach or not _is_targetable(target_rock):
			return false
		direction = target_position - player.global_position
	else:
		_clear_target()
	if not direction.is_zero_approx():
		if absf(direction.x) >= absf(direction.y):
			player.facing = Vector2.LEFT if direction.x < 0.0 else Vector2.RIGHT
		else:
			player.facing = Vector2.UP if direction.y < 0.0 else Vector2.DOWN
	_swing_rock = target_rock if HARVEST_GROUPS.has(item.subtype) else null
	_swing_cell = target_cell
	_swing_item = item
	_impact_resume_usec = 0
	_hit_applied = false
	_busy = true
	player.is_using_tool = true
	player.velocity = Vector2.ZERO
	var suffix := "side" if not is_zero_approx(player.facing.x) else ("up" if player.facing.y < 0.0 else "down")
	sprite.flip_h = player.facing.x < 0.0
	_swing_animation = StringName(String(TOOL_ANIMATIONS[item.subtype]) + "_" + suffix)
	# Use a material-specific pickaxe sheet when that direction is available.
	# Other directions keep their existing animation until their art is ready.
	if item.subtype == &"pickaxe":
		var material_animation := StringName(String(_swing_animation) + "_" + String(item.material))
		if sprite.sprite_frames.has_animation(material_animation):
			_swing_animation = material_animation
	var interval := item.get_swing_interval()
	_next_swing_usec = Time.get_ticks_usec() + roundi(interval * 1000000.0)
	# Item speed controls the delay before another swing, keeping original playback.
	sprite.play(_swing_animation)
	return true

func _on_frame_changed() -> void:
	if not _busy or _hit_applied or _swing_item == null or not HARVEST_GROUPS.has(_swing_item.subtype) or sprite.animation != _swing_animation:
		return
	var impact_frame := AXE_IMPACT_FRAME if _swing_item.subtype == &"axe" else IMPACT_FRAME
	if sprite.frame < impact_frame:
		return
	_hit_applied = true
	# Large rocks can be struck on any occupied tile, within the same reach circle.
	var hit_position := ground.to_global(ground.map_to_local(_swing_cell))
	if not player.movement_locked and equipped_item() == _swing_item and _is_targetable(_swing_rock) and _swing_rock.covers_tile(ground, _swing_cell) and player.global_position.distance_to(hit_position) <= reach_tiles * TILE_SIZE + 0.001:
		var direction: Vector2 = (_swing_rock.global_position-player.global_position).normalized()
		var applied: bool
		if _swing_item.subtype == &"pickaxe":
			applied = _swing_rock.take_pickaxe_hit(_swing_item, direction)
		else:
			applied = _swing_rock.take_axe_hit(_swing_item, direction)
		if applied and impact_pause_duration > 0.0:
			# Hold only this swing at impact; normal world and UI processing continue.
			sprite.pause()
			_impact_resume_usec = Time.get_ticks_usec() + roundi(impact_pause_duration*1000000.0)

func _on_animation_finished() -> void:
	if _busy and sprite.animation == _swing_animation:
		cancel_swing(false)
		_try_held_swing()

func cancel_swing(stop_holding: bool = true) -> void:
	if stop_holding:
		_stop_holding()
	_impact_resume_usec = 0
	_busy = false
	_swing_rock = null
	_swing_item = null
	_swing_animation = &""
	player.is_using_tool = false
	if player.is_node_ready():
		player._play_animation("idle")
