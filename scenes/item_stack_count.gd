extends Control
## Use the same pixel font as the pickup HUD without changing slot or drag geometry.
const UI_THEME := preload("res://scenes/ui/pixel_theme.tres")
const OUTLINE_COLOR := Color(0.07, 0.04, 0.1, 1)
var show_single: bool = false:
	set(value):
		show_single = value
		_refresh_visibility()
		queue_redraw()
var suffix: String = "":
	set(value):
		suffix = value
		queue_redraw()
var font_color: Color = UI_THEME.get_color(&"font_color", &"Label"):
	set(value):
		font_color = value
		queue_redraw()
var amount: int = 0:
	set(value):
		amount = value
		_refresh_visibility()
		queue_redraw()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(16, 7)

func _refresh_visibility() -> void:
	visible = amount > 1 or (show_single and amount == 1)

func _draw() -> void:
	if amount < 1 or (amount == 1 and not show_single):
		return
	var font: Font = UI_THEME.default_font
	var font_size: int = UI_THEME.default_font_size
	var digits := str(amount) + suffix
	var width := font.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := Vector2(floorf(size.x - width - 1.0), floorf(1.0 + font.get_ascent(font_size)))
	draw_string_outline(font, origin, digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, OUTLINE_COLOR)
	draw_string(font, origin, digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, font_color)
