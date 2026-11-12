extends CharacterBody2D
## The Tavern Maid's commute, interaction prompt, and dialogue.

enum DialogueState { CLOSED, OPENING, TYPING, READY, CLOSING }

const MORNING_DEPARTURE := 8 * 60
const EVENING_DEPARTURE := 20 * 60
const ARRIVAL_DISTANCE_SQUARED := 0.01
const ROUTE_RETRY_SECONDS := 1.0
const NPC_NAME := "Tavern Maid"
const DIALOGUE_PAGES := [
	"Hello there!\nFancy a seat at the tavern?",
	"If you pass the orchard,\nbring me a crisp apple.",
]
const INTERACT_ICON := preload("res://assets/hud/environmental_hud/input_keyboard_e.png")
const PORTRAIT_SHEET := preload("res://assets/characters/npcs/Idle_Side-Sheet.png")
const DIALOGUE_FRAME := preload("res://assets/hud/dialogue/Dialogue_Frame.png")
const NAMEPLATE := preload("res://assets/hud/dialogue/Dialogue_Nameplate.png")
const ARROWS := preload("res://assets/hud/dialogue/Dialogue_Arrows.png")
const UI_THEME := preload("res://scenes/ui/pixel_theme.tres")
const PANEL_SIZE := Vector2(240, 64)
# The flat text field spans x = 64 through 231. Inset two pixels per side.
const TEXT_AREA := Rect2(66, 29, 164, 28)
const NAMEPLATE_TOP := 11.0
const NAMEPLATE_FILL_WIDTH := 36.0
const NAMEPLATE_NAME_PADDING := 4.0
const INTERACTION_RADIUS := 40.0
const PROMPT_REST_SCALE := Vector2(0.5, 0.5)
const PROMPT_PULSE_SCALE := Vector2(0.625, 0.625)
const CHARACTERS_PER_SECOND := 36.0

@export var seed_stop: Vector2i
@export var apple_stop: Vector2i
@export var walk_speed: float = 64.0

@onready var _ground: TileMapLayer = get_node_or_null("../Ground")
@onready var _clock: CanvasModulate = get_node_or_null("../DayNightCycle")
@onready var _player: CharacterBody2D = get_node_or_null("../Player")
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _screen: Control = get_node_or_null("../PlayerHUD/Screen")
@onready var _hotbar: Control = get_node_or_null("../PlayerHUD/Screen/Hotbar")
@onready var _inventory_dim: ColorRect = get_node_or_null("../PlayerHUD/Screen/Inventory/Dim")
@onready var _fruit_interaction: Node = get_node_or_null("../Player/FruitInteraction")

var _destination: Vector2i
var _route: Array[Vector2i] = []
var _next_cell := 0
var _retry_remaining := 0.0
var _outline: Sprite2D
var _outline_frames: Dictionary[Texture2D, ImageTexture] = {}
var _prompt: Sprite2D
var _prompt_pulse: Tween
var _dialogue: Control
var _panel: Control
var _body: Label
var _continue_button: TextureButton
var _next_arrow: AtlasTexture
var _end_arrow: AtlasTexture
var _state := DialogueState.CLOSED
var _page := 0
var _reveal := 0.0
var _transition: Tween
var _typing: Tween
var _previous_movement_lock := false
var _previous_hotbar_lock := false
var _previous_hotbar_visible := false
var _previous_hotbar_alpha := 1.0
var _clock_was_processing := false

func _ready() -> void:
	_idle()
	if _player != null and _screen != null:
		_build_interaction_prompt()
		_build_dialogue()
	if _ground == null or _clock == null:
		set_physics_process(false)
		return
	_destination = _scheduled_stop(_clock.get_display_minutes())
	global_position = _world_point(_destination)
	if _player != null:
		add_collision_exception_with(_player)
	_clock.time_changed.connect(_on_time_changed)

func _scheduled_stop(minutes: int) -> Vector2i:
	if minutes >= MORNING_DEPARTURE and minutes < EVENING_DEPARTURE:
		return apple_stop
	return seed_stop

func _on_time_changed(minutes: int) -> void:
	var stop := _scheduled_stop(minutes)
	if stop != _destination:
		_destination = stop
		_route.clear()
		_retry_remaining = 0.0

func _physics_process(delta: float) -> void:
	if _state != DialogueState.CLOSED:
		return
	if _next_cell >= _route.size():
		if global_position.distance_squared_to(_world_point(_destination)) <= ARRIVAL_DISTANCE_SQUARED:
			_idle()
			return
		_retry_remaining -= delta
		if _retry_remaining > 0.0:
			return
		_route = _find_route()
		_next_cell = 0
		if _route.is_empty():
			_retry_remaining = ROUTE_RETRY_SECONDS
			_idle()
			return

	var offset := _world_point(_route[_next_cell]) - global_position
	if offset.length_squared() <= ARRIVAL_DISTANCE_SQUARED:
		_next_cell += 1
		if _next_cell == _route.size():
			_idle()
			return
		offset = _world_point(_route[_next_cell]) - global_position

	if absf(offset.x) > 0.1:
		_sprite.flip_h = offset.x < 0.0
		if _outline != null:
			_outline.flip_h = _sprite.flip_h
	_sprite.play(&"walk")
	velocity = offset.limit_length(walk_speed * delta) / delta
	move_and_slide()
	if get_slide_collision_count() > 0:
		# The world can change between departure and arrival.
		_route.clear()
		_retry_remaining = ROUTE_RETRY_SECONDS
		_idle()

func _find_route() -> Array[Vector2i]:
	var start := _ground.local_to_map(_ground.to_local(global_position))
	var region := _ground.get_used_rect()
	if not region.has_point(start) or not region.has_point(_destination):
		return []

	var grid := AStarGrid2D.new()
	grid.region = region
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()

	var shape := RectangleShape2D.new()
	shape.size = Vector2(_ground.tile_set.tile_size) - Vector2(0.1, 0.1)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = collision_mask
	if _player != null:
		query.exclude = [_player.get_rid()]
	var space := get_world_2d().direct_space_state
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var cell := Vector2i(x, y)
			if cell == start:
				continue
			if _ground.get_cell_source_id(cell) == -1:
				grid.set_point_solid(cell)
				continue
			# Reserve the full tile around solid scenery, leaving room for the NPC's feet.
			query.transform = _ground.global_transform * Transform2D(0.0, _ground.map_to_local(cell))
			if not space.intersect_shape(query, 1).is_empty():
				grid.set_point_solid(cell)

	if grid.is_point_solid(_destination):
		return []
	return grid.get_id_path(start, _destination)

func _world_point(cell: Vector2i) -> Vector2:
	return _ground.to_global(_ground.map_to_local(cell))

func _idle() -> void:
	velocity = Vector2.ZERO
	_sprite.play(&"idle")

func _process(_delta: float) -> void:
	if _prompt != null:
		_show_prompt(_state == DialogueState.CLOSED and _can_talk())

func _can_talk() -> bool:
	if not is_instance_valid(_player) or not is_visible_in_tree():
		return false
	if _player.movement_locked or _player.is_using_tool or get_viewport().gui_is_dragging():
		return false
	var distance := global_position.distance_squared_to(_player.global_position)
	if distance > INTERACTION_RADIUS * INTERACTION_RADIUS:
		return false
	# Leave E available for a closer tree or placed object.
	var other: Node2D = _fruit_interaction.target if _fruit_interaction != null else null
	if is_instance_valid(other) and not other.is_queued_for_deletion():
		var point := other.global_position
		if other.has_method("get_interaction_point"):
			point = other.get_interaction_point()
		return point.distance_squared_to(_player.global_position) >= distance
	return true

func _build_interaction_prompt() -> void:
	var unlit := CanvasItemMaterial.new()
	unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_outline = Sprite2D.new()
	_outline.name = "InteractionOutline"
	_outline.show_behind_parent = true
	_outline.material = unlit
	_outline.hide()
	_sprite.add_child(_outline)
	_sprite.frame_changed.connect(_refresh_outline)
	_sprite.animation_changed.connect(_refresh_outline)

	_prompt = Sprite2D.new()
	_prompt.name = "TalkPrompt"
	_prompt.texture = INTERACT_ICON
	_prompt.position = Vector2(0, -38)
	_prompt.scale = PROMPT_REST_SCALE
	_prompt.material = unlit
	_prompt.z_index = 7
	_prompt.hide()
	add_child(_prompt)

func _show_prompt(show_prompt: bool) -> void:
	if _prompt.visible == show_prompt:
		return
	_outline.visible = show_prompt
	_prompt.visible = show_prompt
	if _prompt_pulse != null:
		_prompt_pulse.kill()
		_prompt_pulse = null
	_prompt.scale = PROMPT_REST_SCALE
	if show_prompt:
		_refresh_outline()
		_prompt_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_prompt_pulse.tween_property(_prompt, "scale", PROMPT_PULSE_SCALE, 0.6)
		_prompt_pulse.tween_property(_prompt, "scale", PROMPT_REST_SCALE, 0.6)

func _refresh_outline() -> void:
	if not _outline.visible:
		return
	var frame := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if not _outline_frames.has(frame):
		var image := frame.get_image()
		var edge := Image.create_empty(image.get_width() + 2, image.get_height() + 2, false, Image.FORMAT_RGBA8)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.1:
					edge.fill_rect(Rect2i(x, y, 3, 3), Color.WHITE)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.1:
					edge.set_pixel(x + 1, y + 1, Color.TRANSPARENT)
		_outline_frames[frame] = ImageTexture.create_from_image(edge)
	_outline.texture = _outline_frames[frame]
	_outline.flip_h = _sprite.flip_h

func _build_dialogue() -> void:
	_dialogue = Control.new()
	_dialogue.name = "TavernMaidDialogue"
	_dialogue.z_index = 30
	_dialogue.theme = UI_THEME
	_dialogue.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dialogue.hide()
	_screen.add_child(_dialogue)
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = _inventory_dim.color if _inventory_dim != null else Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = Control.new()
	_panel.size = PANEL_SIZE
	_panel.pivot_offset = Vector2(PANEL_SIZE.x * 0.5, PANEL_SIZE.y)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue.add_child(_panel)
	_add_art(DIALOGUE_FRAME, Rect2(Vector2.ZERO, PANEL_SIZE))
	# A head-and-shoulders crop of the idle sprite fits the square portrait slot.
	_add_art(_atlas(PORTRAIT_SHEET, Rect2(23, 17, 18, 23)), Rect2(14, 9, 36, 46))
	_build_nameplate()

	_body = Label.new()
	_panel.add_child(_body)
	_body.position = TEXT_AREA.position
	_body.size = TEXT_AREA.size
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_next_arrow = _atlas(ARROWS, Rect2(16, 0, 6, 9))
	_end_arrow = _atlas(ARROWS, Rect2(47, 0, 8, 9))
	_continue_button = TextureButton.new()
	_continue_button.ignore_texture_size = true
	_continue_button.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	_continue_button.focus_mode = Control.FOCUS_NONE
	# Put both continuation glyphs alongside the second line.
	_continue_button.position = Vector2(220, 42)
	_continue_button.size = Vector2(14, 10)
	_continue_button.pressed.connect(_advance_dialogue)
	_panel.add_child(_continue_button)
	get_viewport().size_changed.connect(_apply_reveal)

func _build_nameplate() -> void:
	var title := _name_texture()
	var extra_per_side := maxi(0, ceili((title.get_width() + 2.0 * NAMEPLATE_NAME_PADDING - NAMEPLATE_FILL_WIDTH) * 0.5))
	var size := NAMEPLATE.get_size() + Vector2(2 * extra_per_side, 0)
	var center_x := TEXT_AREA.get_center().x
	var plate := NinePatchRect.new()
	plate.texture = NAMEPLATE
	# Repeat the two flat middle columns so both decorated ends stay intact.
	plate.patch_margin_left = 39
	plate.patch_margin_right = 39
	plate.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	plate.position = Vector2(center_x - size.x * 0.5, NAMEPLATE_TOP)
	plate.size = size
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(plate)
	# Center the painted glyphs in the 10-pixel fill band, below the top border.
	var ink_position := Vector2(center_x - title.get_width() * 0.5, NAMEPLATE_TOP + 2.0 + (10.0 - title.get_height()) * 0.5)
	_add_art(title, Rect2(ink_position.floor(), title.get_size()))

func _name_texture() -> ImageTexture:
	var font: FontFile = UI_THEME.default_font
	var font_size := UI_THEME.default_font_size
	var cache_size := Vector2i(font_size, 0)
	var width := ceili(font.get_string_size(NPC_NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 4
	var ink := Image.create_empty(width, ceili(font.get_height(font_size)) + 4, false, Image.FORMAT_RGBA8)
	for character in NPC_NAME:
		font.render_glyph(0, cache_size, font.get_glyph_index(font_size, character.unicode_at(0), 0))
	var pen := Vector2i(2, 2 + ceili(font.get_ascent(font_size)))
	var previous := 0
	var atlases: Dictionary[int, Image] = {}
	for character in NPC_NAME:
		var glyph := font.get_glyph_index(font_size, character.unicode_at(0), 0)
		if previous != 0:
			pen += Vector2i(font.get_kerning(0, font_size, Vector2i(previous, glyph)))
		var atlas_index := font.get_glyph_texture_idx(0, cache_size, glyph)
		if atlas_index >= 0:
			if not atlases.has(atlas_index):
				atlases[atlas_index] = font.get_texture_image(0, cache_size, atlas_index)
			var region := Rect2i(font.get_glyph_uv_rect(0, cache_size, glyph))
			var origin := pen + Vector2i(font.get_glyph_offset(0, cache_size, glyph))
			for y in range(region.size.y):
				for x in range(region.size.x):
					var pixel := Vector2i(x, y)
					var alpha := atlases[atlas_index].get_pixelv(region.position + pixel).a
					if alpha > 0.0:
						ink.set_pixelv(origin + pixel, Color(1, 1, 0.94, alpha))
		pen.x += roundi(font.get_glyph_advance(0, font_size, glyph).x)
		previous = glyph
	return ImageTexture.create_from_image(ink.get_region(ink.get_used_rect()))

func _add_art(texture: Texture2D, rect: Rect2) -> void:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.position = rect.position
	art.size = rect.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(art)

func _atlas(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = region
	crop.filter_clip = true
	return crop

func _input(event: InputEvent) -> void:
	if _dialogue == null:
		return
	var talk := event.is_action_pressed(&"interact", false, true)
	if _state != DialogueState.CLOSED:
		if event.is_action_pressed(&"ui_cancel"):
			_close_dialogue()
		elif talk or event.is_action_pressed(&"ui_accept"):
			_advance_dialogue()
		elif not event.is_action_pressed(&"inventory_toggle"):
			return
		get_viewport().set_input_as_handled()
		return

	var clicked_prompt := false
	if _prompt.visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point: Vector2 = _prompt.get_global_transform_with_canvas().affine_inverse() * event.position
		clicked_prompt = _prompt.get_rect().has_point(point)
	if (talk or clicked_prompt) and _can_talk():
		_open_dialogue()
		get_viewport().set_input_as_handled()

func _open_dialogue() -> void:
	_state = DialogueState.OPENING
	_previous_movement_lock = _player.movement_locked
	_player.movement_locked = true
	if _clock != null:
		_clock_was_processing = _clock.is_processing()
		_clock.set_process(false)
	if _hotbar != null:
		_previous_hotbar_lock = _hotbar.input_locked
		_previous_hotbar_visible = _hotbar.visible
		_previous_hotbar_alpha = _hotbar.modulate.a
		_hotbar.cancel_drag()
		_hotbar.input_locked = true
	_sprite.flip_h = _player.global_position.x < global_position.x
	_idle()
	_show_prompt(false)
	_body.text = ""
	_continue_button.hide()
	_dialogue.show()
	_set_reveal(0.0)
	_transition = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_method(_set_reveal, 0.0, 1.0, 0.22)
	_transition.tween_callback(_start_page.bind(0))

func _apply_reveal() -> void:
	var screen := get_viewport().get_visible_rect().size
	var bottom_margin: float = _hotbar.bottom_margin if _hotbar != null else 16.0
	var bottom := screen.y - bottom_margin
	var preferred: int = _hotbar.pixel_scale if _hotbar != null else 3
	var fit := floori(minf((screen.x - 16.0) / PANEL_SIZE.x, (bottom - 8.0) / PANEL_SIZE.y))
	var pixels := mini(preferred, maxi(1, fit))
	var top_left := Vector2((screen.x - PANEL_SIZE.x * pixels) * 0.5, bottom - PANEL_SIZE.y * pixels + 8.0 * (1.0 - _reveal)).floor()
	_panel.position = top_left + _panel.pivot_offset * (pixels - 1)
	_panel.scale = Vector2.ONE * pixels * lerpf(0.88, 1.0, _reveal)
	_dialogue.modulate.a = _reveal
	if _state != DialogueState.CLOSED and is_instance_valid(_hotbar):
		_hotbar.modulate.a = _previous_hotbar_alpha * (1.0 - _reveal)
		_hotbar.visible = _previous_hotbar_visible and _reveal < 1.0

func _set_reveal(value: float) -> void:
	_reveal = value
	_apply_reveal()

func _start_page(index: int) -> void:
	_page = index
	_state = DialogueState.TYPING
	_continue_button.hide()
	_body.text = DIALOGUE_PAGES[index]
	_body.visible_characters = 0
	var letters := _body.text.length()
	_typing = create_tween()
	_typing.tween_property(_body, "visible_characters", letters, letters / CHARACTERS_PER_SECOND)
	_typing.tween_callback(_finish_page)

func _finish_page() -> void:
	_body.visible_characters = -1
	_state = DialogueState.READY
	_continue_button.texture_normal = _end_arrow if _page == DIALOGUE_PAGES.size() - 1 else _next_arrow
	_continue_button.show()

func _advance_dialogue() -> void:
	if _state == DialogueState.TYPING:
		_typing.kill()
		_finish_page()
	elif _state == DialogueState.READY:
		if _page + 1 < DIALOGUE_PAGES.size():
			_start_page(_page + 1)
		else:
			_close_dialogue()

func _close_dialogue() -> void:
	if _state == DialogueState.CLOSING:
		return
	_state = DialogueState.CLOSING
	_continue_button.hide()
	if _typing != null:
		_typing.kill()
	if _transition != null:
		_transition.kill()
	_transition = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition.tween_method(_set_reveal, _reveal, 0.0, 0.16)
	_transition.tween_callback(_finish_dialogue)

func _finish_dialogue() -> void:
	_dialogue.hide()
	_state = DialogueState.CLOSED
	_restore_controls()

func _restore_controls() -> void:
	if is_instance_valid(_player):
		_player.movement_locked = _previous_movement_lock
	if is_instance_valid(_clock):
		_clock.set_process(_clock_was_processing)
	if is_instance_valid(_hotbar):
		_hotbar.input_locked = _previous_hotbar_lock
		_hotbar.modulate.a = _previous_hotbar_alpha
		_hotbar.visible = _previous_hotbar_visible

func _exit_tree() -> void:
	if _state != DialogueState.CLOSED:
		_restore_controls()
	if is_instance_valid(_dialogue):
		_dialogue.queue_free()
