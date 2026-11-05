extends Control
## Grow each compartment through its flat center, preserving every authored edge.

const FRAME := preload("res://assets/hud/player_hud/status_bar/frame.png")
const FILL := preload("res://assets/hud/player_hud/status_bar/fill.png")
const CLOCK_ICON := preload("res://assets/hud/player_hud/status_bar/clock.png")
const COIN_ICON := preload("res://assets/hud/player_hud/status_bar/coin.png")
const UI_THEME := preload("res://scenes/ui/pixel_theme.tres")
const LEFT_CAP: int = 11
const BASE_SECTION_WIDTH: int = 20
const STRETCH_COLUMNS := [21, 43, 65]
const CONTENT_TOP: int = 8
const CONTENT_HEIGHT: int = 9
const SECTION_PADDING: int = 4
const ICON_GAP: int = 3

var _time_text: String = "6:00 AM"
var _day_number: int = 1
var _coins: int = 0
var _level: int = 1
var _image: Image
var _texture: ImageTexture
var _font: FontFile = UI_THEME.default_font
var _font_size: int = UI_THEME.default_font_size
var _font_atlases: Dictionary = {}
var _section_widths: Array[int] = []
var _sections: Array[Rect2i] = []
var _separators: Array[Rect2i] = []
var _text_rects: Array[Rect2i] = []
var _icon_rects: Array[Rect2i] = []

func _init() -> void:
	name = "StatusBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 10

func _ready() -> void:
	_build_texture()

func set_values(time_text: String, day_number: int, coins: int, level: int) -> void:
	var day := maxi(1, day_number)
	var balance := maxi(0, coins)
	var player_level := maxi(1, level)
	if _texture != null and _time_text == time_text and _day_number == day and _coins == balance and _level == player_level:
		return
	_time_text = time_text
	_day_number = day
	_coins = balance
	_level = player_level
	_build_texture()

func get_display_text() -> String:
	return "%s Day %d | %s | Lvl. %d" % [_time_text, _day_number, format_coins(_coins), _level]

func format_coins(amount: int) -> String:
	var digits := str(maxi(0, amount))
	var formatted := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += ","
		formatted += digits[index]
	return formatted

func _draw() -> void:
	if _texture != null:
		draw_texture(_texture, Vector2.ZERO)

func _build_texture() -> void:
	var labels: Array[String] = ["%s Day %d" % [_time_text, _day_number], format_coins(_coins), "Lvl. %d" % _level]
	var cache_size := Vector2i(_font_size, 0)
	for character in "".join(labels):
		_font.render_glyph(0, cache_size, _font.get_glyph_index(_font_size, character.unicode_at(0), 0))
	_font_atlases.clear()
	var text_images: Array[Image] = []
	var icons: Array[Texture2D] = [CLOCK_ICON, COIN_ICON, null]
	_section_widths.clear()
	_sections.clear()
	_separators.clear()
	_text_rects.clear()
	_icon_rects.clear()
	for index in range(labels.size()):
		var text := _text_image(labels[index])
		text_images.append(text)
		var icon_width := icons[index].get_width() + ICON_GAP if icons[index] != null else 0
		_section_widths.append(maxi(BASE_SECTION_WIDTH, icon_width + text.get_width() + 2 * SECTION_PADDING))
	_image = _frame_image(_section_widths)
	var x := LEFT_CAP
	for index in range(labels.size()):
		var section := Rect2i(x, CONTENT_TOP, _section_widths[index], CONTENT_HEIGHT)
		_sections.append(section)
		var text := text_images[index]
		var icon: Texture2D = icons[index]
		var icon_width := icon.get_width() + ICON_GAP if icon != null else 0
		var ink_x := section.position.x + (section.size.x - icon_width - text.get_width()) / 2
		var icon_rect := Rect2i()
		if icon != null:
			var pixels := icon.get_image()
			pixels.convert(Image.FORMAT_RGBA8)
			icon_rect = Rect2i(Vector2i(ink_x, CONTENT_TOP + (CONTENT_HEIGHT - pixels.get_height()) / 2), pixels.get_size())
			_image.blend_rect(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), icon_rect.position)
		var text_y := CONTENT_TOP + (CONTENT_HEIGHT - text.get_height()) / 2
		# Center the five-pixel character bodies; Day's y descender adds two rows.
		if index == 0:
			text_y += 1
		var text_rect := Rect2i(Vector2i(ink_x + icon_width, text_y), text.get_size())
		_image.blend_rect(text, Rect2i(Vector2i.ZERO, text.get_size()), text_rect.position)
		_icon_rects.append(icon_rect)
		_text_rects.append(text_rect)
		x = section.end.x
		if index < labels.size() - 1:
			var divider := _divider_image()
			var area := Rect2i(Vector2i(x, CONTENT_TOP), divider.get_size())
			_image.blit_rect(divider, Rect2i(Vector2i.ZERO, divider.get_size()), area.position)
			_separators.append(area)
			x += divider.get_width()
	_texture = ImageTexture.create_from_image(_image)
	size = _image.get_size()
	queue_redraw()

func _frame_image(section_widths: Array[int]) -> Image:
	var source := FRAME.get_image()
	source.convert(Image.FORMAT_RGBA8)
	var width := source.get_width()
	for section_width in section_widths:
		width += section_width - BASE_SECTION_WIDTH
	var result := Image.create_empty(width, source.get_height(), false, Image.FORMAT_RGBA8)
	var fill := FILL.get_image()
	fill.convert(Image.FORMAT_RGBA8)
	var source_x: int = 0
	var target_x: int = 0
	for index in range(STRETCH_COLUMNS.size()):
		var cut: int = STRETCH_COLUMNS[index]
		var unchanged := cut - source_x
		result.blit_rect(source, Rect2i(source_x, 0, unchanged, source.get_height()), Vector2i(target_x, 0))
		target_x += unchanged
		for column in range(section_widths[index] - BASE_SECTION_WIDTH):
			result.blit_rect(source, Rect2i(cut, 0, 1, source.get_height()), Vector2i(target_x, 0))
			result.blit_rect(fill, Rect2i(column % fill.get_width(), 0, 1, CONTENT_HEIGHT), Vector2i(target_x, CONTENT_TOP))
			target_x += 1
		source_x = cut
	result.blit_rect(source, Rect2i(source_x, 0, source.get_width() - source_x, source.get_height()), Vector2i(target_x, 0))
	return result

func _divider_image() -> Image:
	var result := Image.create_empty(2, CONTENT_HEIGHT, false, Image.FORMAT_RGBA8)
	var highlight := FRAME.get_image().get_pixel(FRAME.get_width() / 2, 3)
	# The reference uses one highlight column and one dark trailing column.
	result.fill_rect(Rect2i(0, 0, 1, CONTENT_HEIGHT), highlight)
	result.fill_rect(Rect2i(1, 0, 1, CONTENT_HEIGHT), Color(50.0 / 255.0, 56.0 / 255.0, 78.0 / 255.0))
	return result

func _text_image(text: String) -> Image:
	# Use the existing font's rasterized glyphs for exact source-pixel placement.
	var dimensions := Vector2i(ceili(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x) + 4, ceili(_font.get_height(_font_size)) + 4)
	var result := Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	var pen := Vector2i(2, 2 + ceili(_font.get_ascent(_font_size)))
	var previous: int = 0
	var cache_size := Vector2i(_font_size, 0)
	for character in text:
		var glyph := _font.get_glyph_index(_font_size, character.unicode_at(0), 0)
		if previous != 0:
			pen += Vector2i(_font.get_kerning(0, _font_size, Vector2i(previous, glyph)))
		var atlas_index := _font.get_glyph_texture_idx(0, cache_size, glyph)
		if atlas_index >= 0:
			if not _font_atlases.has(atlas_index):
				_font_atlases[atlas_index] = _font.get_texture_image(0, cache_size, atlas_index)
			var atlas: Image = _font_atlases[atlas_index]
			var region := Rect2i(_font.get_glyph_uv_rect(0, cache_size, glyph))
			var origin := pen + Vector2i(_font.get_glyph_offset(0, cache_size, glyph))
			for y in range(region.size.y):
				for x in range(region.size.x):
					var alpha := atlas.get_pixelv(region.position + Vector2i(x, y)).a
					if alpha > 0.0:
						result.set_pixelv(origin + Vector2i(x, y), Color(1, 1, 1, alpha))
		pen.x += roundi(_font.get_glyph_advance(0, _font_size, glyph).x)
		previous = glyph
	var used := result.get_used_rect()
	return result.get_region(used) if used.has_area() else Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
