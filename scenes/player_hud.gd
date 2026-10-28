extends CanvasLayer
## Original HUD artwork. Health and mana stay full until their systems exist.

@export var player_path: NodePath = NodePath("../Player")
@export_range(1, 6, 1) var pixel_scale: int = 3
@export_range(0, 100, 1) var left_margin: int = 16
@export_range(0, 100, 1) var top_margin: int = 16

@onready var art: Control = $Screen/Art
@onready var stamina_clip: Control = $Screen/Art/StaminaClip
@onready var stamina_fill: TextureRect = $Screen/Art/StaminaClip/Fill
const ITEM_TOOLTIP := preload("res://scenes/item_tooltip.gd")
const STAMINA_WIDTH: int = 58
const ART_SIZE := Vector2(128, 48)
func _ready() -> void:
	_update_layout()
	var inventory: PlayerInventoryModel = $Screen/Inventory.model
	inventory.item_collected.connect($Screen/ItemPickupNotice.show_pickup)
	$Screen.add_child(ITEM_TOOLTIP.new())
	get_viewport().size_changed.connect(_update_layout)
	var player := get_node_or_null(player_path)
	if player != null and player.has_signal("stamina_changed"):
		player.connect("stamina_changed", _on_stamina_changed)
		_on_stamina_changed(float(player.get("stamina")), float(player.get("max_stamina")), bool(player.get("stamina_exhausted")))

func _update_layout() -> void:
	art.scale = Vector2.ONE * pixel_scale
	art.set_anchors_preset(Control.PRESET_TOP_LEFT)
	art.offset_left = left_margin
	art.offset_right = left_margin + ART_SIZE.x
	art.offset_top = top_margin
	art.offset_bottom = top_margin + ART_SIZE.y

func _on_stamina_changed(value: float, maximum: float, _exhausted: bool) -> void:
	var ratio := clampf(value / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	if maximum > 0.0 and is_equal_approx(value, maximum):
		ratio = 1.0
	var visible_columns := clampi(floori(ratio * STAMINA_WIDTH + 0.00001), 0, STAMINA_WIDTH)
	# Crop the source image itself; a scaled scissor can cut its last screen pixel.
	var crop := stamina_fill.texture as AtlasTexture
	crop.region = Rect2(0, 0, maxi(1, visible_columns), 2)
	stamina_fill.size = Vector2(visible_columns, 2)
	stamina_clip.size.x = visible_columns
	stamina_clip.visible = visible_columns > 0
