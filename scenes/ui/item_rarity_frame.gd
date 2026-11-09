extends TextureRect
## Both slot layouts have an 18×17 opening around a 16×16 item icon.

const COMMON := preload("res://assets/hud/player_hud/rarity_frames/common.png")
const FRAMES_BY_MATERIAL: Dictionary[StringName, Texture2D] = {
	&"wood": COMMON,
	&"coal": COMMON,
	&"copper": COMMON,
	&"iron": preload("res://assets/hud/player_hud/rarity_frames/uncommon.png"),
	&"gold": preload("res://assets/hud/player_hud/rarity_frames/rare.png"),
	&"echryte": preload("res://assets/hud/player_hud/rarity_frames/epic.png"),
	&"aetherite": preload("res://assets/hud/player_hud/rarity_frames/legendary.png"),
	&"ashenite": preload("res://assets/hud/player_hud/rarity_frames/mythic.png"),
}

func _init() -> void:
	name = "RarityFrame"
	position = Vector2(-1, 0)
	size = COMMON.get_size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true

func set_item(item: InventoryItem) -> void:
	texture = FRAMES_BY_MATERIAL.get(item.material) if item != null else null
