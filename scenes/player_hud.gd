extends CanvasLayer
## Original HUD artwork. Health and mana stay full until their systems exist.

@export var player_path: NodePath = NodePath("../Player")
@export_range(1, 6, 1) var pixel_scale: int = 3
@export_range(0, 100, 1) var left_margin: int = 16
@export_range(0, 100, 1) var top_margin: int = 16
@export_range(0, 100, 1) var right_margin: int = 16
@export_group("Status Display")
@export_range(0, 999999999, 1) var coins: int = 0:
	set(value):
		coins = maxi(0, value)
		_refresh_status_bar()
@export_range(1, 9999, 1) var level: int = 1:
	set(value):
		level = maxi(1, value)
		_refresh_status_bar()

@onready var player: CharacterBody2D = get_node_or_null(player_path)
@onready var sleep_fade: ColorRect = $Screen/SleepFade
@onready var art: Control = $Screen/Art
@onready var stamina_clip: Control = $Screen/Art/StaminaClip
@onready var stamina_fill: TextureRect = $Screen/Art/StaminaClip/Fill
@onready var stamina_value: Label = $Screen/Art/StaminaValue
@onready var day_night_cycle: CanvasModulate = get_node_or_null("../DayNightCycle")
const ITEM_TOOLTIP := preload("res://scenes/item_tooltip.gd")
const SMELTRY_UI := preload("res://scenes/smeltry_ui.tscn")
const STATUS_BAR := preload("res://scenes/status_bar.gd")
const BAR_WIDTH: int = 70
const BAR_HEIGHT: int = 3
const BAR_PATTERN_WIDTH: int = 3
const ART_SIZE := Vector2(129, 44)
const HUD_GAP: int = 8
var smeltry_ui: Control
var status_bar: Control

func _ready() -> void:
	_prepare_bar_fills()
	_create_status_bar()
	_update_layout()
	var inventory: PlayerInventoryModel = $Screen/Inventory.model
	inventory.item_collected.connect($Screen/ItemPickupNotice.show_pickup)
	smeltry_ui = SMELTRY_UI.instantiate()
	smeltry_ui.preview_on_start = false
	smeltry_ui.show_reference_queue = false
	$Screen.add_child(smeltry_ui)
	$Screen.add_child(ITEM_TOOLTIP.new())
	get_viewport().size_changed.connect(_update_layout)
	if player != null and player.has_signal("stamina_changed"):
		player.connect("stamina_changed", _on_stamina_changed)
		_on_stamina_changed(float(player.get("stamina")), float(player.get("max_stamina")), bool(player.get("stamina_exhausted")))
	if day_night_cycle != null:
		day_night_cycle.connect("time_changed", _on_time_changed)
		day_night_cycle.connect("time_advanced", _on_time_advanced)
		_on_time_changed(day_night_cycle.get_display_minutes())

func _create_status_bar() -> void:
	status_bar = STATUS_BAR.new()
	$Screen.add_child(status_bar)
	_refresh_status_bar()

func _on_time_changed(_display_minutes: int) -> void:
	_refresh_status_bar()

func _on_time_advanced(_elapsed_minutes: float) -> void:
	status_bar.set_clock_time(day_night_cycle.get_minutes_of_day())

func _refresh_status_bar() -> void:
	if not is_instance_valid(status_bar):
		return
	var time_text := "6:00 AM"
	var minutes_of_day := 6.0 * 60.0
	var day: int = 1
	if day_night_cycle != null:
		time_text = day_night_cycle.get_clock_text()
		minutes_of_day = day_night_cycle.get_minutes_of_day()
		day = day_night_cycle.get_day_number()
	status_bar.set_values(time_text, day, coins, level, minutes_of_day)
	_update_layout()

func _update_layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	# Fit both top HUDs at the same whole-pixel scale on smaller viewports.
	var fit := floori((screen.x - left_margin - right_margin) / (ART_SIZE.x + HUD_GAP + status_bar.size.x))
	var amount := mini(pixel_scale, maxi(1, fit))
	art.scale = Vector2.ONE * amount
	art.set_anchors_preset(Control.PRESET_TOP_LEFT)
	art.offset_left = left_margin
	art.offset_right = left_margin + ART_SIZE.x
	art.offset_top = top_margin
	art.offset_bottom = top_margin + ART_SIZE.y
	status_bar.scale = Vector2.ONE * amount
	status_bar.position = Vector2(maxf(0.0, screen.x - right_margin - status_bar.size.x * amount), top_margin).floor()

func _prepare_bar_fills() -> void:
	var health_fill: TextureRect = $Screen/Art/Health
	var mana_fill: TextureRect = $Screen/Art/Mana
	health_fill.texture = _extend_bar_fill(health_fill.texture)
	mana_fill.texture = _extend_bar_fill(mana_fill.texture)
	var stamina_crop := stamina_fill.texture as AtlasTexture
	stamina_crop.atlas = _extend_bar_fill(stamina_crop.atlas)
	stamina_crop.region = Rect2(0, 0, BAR_WIDTH, BAR_HEIGHT)

func _extend_bar_fill(texture: Texture2D) -> ImageTexture:
	var source := texture.get_image()
	var copied := mini(source.get_width(), BAR_WIDTH)
	var result := Image.create_empty(BAR_WIDTH, BAR_HEIGHT, false, source.get_format())
	result.blit_rect(source, Rect2i(0, 0, copied, BAR_HEIGHT), Vector2i.ZERO)
	# Continue the last three-pixel repeat so the new width keeps the original pixel pattern.
	for x in range(copied, BAR_WIDTH, BAR_PATTERN_WIDTH):
		var width := mini(BAR_PATTERN_WIDTH, BAR_WIDTH - x)
		var segment := Rect2i(copied - BAR_PATTERN_WIDTH, 0, width, BAR_HEIGHT)
		result.blit_rect(source, segment, Vector2i(x, 0))
	return ImageTexture.create_from_image(result)

func _on_stamina_changed(value: float, maximum: float, _exhausted: bool) -> void:
	stamina_value.text = str(ceili(maxf(0.0, value)))
	var ratio := clampf(value / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	if maximum > 0.0 and is_equal_approx(value, maximum):
		ratio = 1.0
	var visible_columns := clampi(floori(ratio * BAR_WIDTH + 0.00001), 0, BAR_WIDTH)
	# Crop the source image itself; a scaled scissor can cut its last screen pixel.
	var crop := stamina_fill.texture as AtlasTexture
	crop.region = Rect2(0, 0, maxi(1, visible_columns), BAR_HEIGHT)
	stamina_fill.size = Vector2(visible_columns, BAR_HEIGHT)
	stamina_clip.size.x = visible_columns
	stamina_clip.visible = visible_columns > 0

func open_smeltry(furnace: Node2D) -> bool:
	return smeltry_ui.open_for(furnace)

func sleep_until_morning() -> bool:
	if sleep_fade.visible or player == null or day_night_cycle == null or player.movement_locked or player.is_using_tool:
		return false

	var inventory := $Screen/Inventory
	var hotbar := $Screen/Hotbar
	var inventory_had_input := inventory.is_processing_input()
	var hotbar_was_locked: bool = hotbar.input_locked
	var clock_was_running := day_night_cycle.is_processing()
	inventory.set_process_input(false)
	hotbar.input_locked = true
	player.movement_locked = true
	day_night_cycle.set_process(false)

	sleep_fade.modulate.a = 0.0
	sleep_fade.show()
	var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(sleep_fade, "modulate:a", 1.0, 0.40)
	fade.tween_callback(func(): day_night_cycle.advance_to_next_morning())
	fade.tween_interval(0.20)
	fade.tween_property(sleep_fade, "modulate:a", 0.0, 0.40)
	fade.tween_callback(func():
		sleep_fade.hide()
		day_night_cycle.set_process(clock_was_running)
		player.movement_locked = false
		hotbar.input_locked = hotbar_was_locked
		inventory.set_process_input(inventory_had_input)
	)
	return true
