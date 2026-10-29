extends Control
## One source pixel stays one UI pixel before the shared integer HUD scale.

var _item: InventoryItem

const MAIN_FRAME := preload("res://assets/hud/environmental_hud/Tooltip_Main_Hud.png")
const TITLE_FRAME := preload("res://assets/hud/environmental_hud/Tooltip_Main_Title_Block.png")
const COIN_SHEET := preload("res://assets/items/Coin_Tileset.png")
const DAMAGE_ICON := preload("res://assets/hud/environmental_hud/Dmanage_Indicator.png")
const UI_THEME := preload("res://scenes/ui/pixel_theme.tres")
const TITLE_TOP_PADDING: int = 2
const TITLE_BOTTOM_PADDING: int = 2
# The shaded row just inside the top outline counts as empty title space.
const TITLE_CONTENT_TOP: int = 3
const TITLE_SIDE_PADDING: int = 5
const TITLE_BORDER := Vector2i(3, 4)
const SCREEN_MARGIN: int = 8
const TITLE_LEFT: int = 10
const CATEGORY_GAP: int = 2
const CATEGORY_RIGHT_MARGIN: int = 4
# The inner right outline is six native pixels from the image's right edge.
const FRAME_RIGHT_BORDER: int = 6
const COIN_CELL := Vector2i(16, 16)
const CARD_ICON_GAP: int = 2
const CARD_SIDE_PADDING: int = 2
const CARD_GAP: int = 4
const FOOTER_CONTENT_GAP: int = 4
const FOOTER_BOTTOM_MARGIN: int = 4
# The inner bottom outline is above the frame's pointed ornament.
const FRAME_BOTTOM_BORDER: int = 16
const CATEGORY_BADGES := {
    InventoryItem.Category.RESOURCE: preload("res://assets/hud/environmental_hud/Resource_Tooltip.png"),
    InventoryItem.Category.TOOL: preload("res://assets/hud/environmental_hud/Tool_Tooltip.png"),
    InventoryItem.Category.WEAPON: preload("res://assets/hud/environmental_hud/Weapon_Tooltip.png"),
    InventoryItem.Category.ARMOR: preload("res://assets/hud/environmental_hud/Armor_Tooltip.png"),
    InventoryItem.Category.ACCESSORY: preload("res://assets/hud/environmental_hud/Accessory_Tooltip.png"),
    InventoryItem.Category.CONSUMABLE: preload("res://assets/hud/environmental_hud/Consumable_Tooltip.png"),
    InventoryItem.Category.PLACEABLE: preload("res://assets/hud/environmental_hud/Placeable_Tooltip.png"),
    InventoryItem.Category.QUEST_ITEM: preload("res://assets/hud/environmental_hud/Quest_Tooltip.png")
}

@onready var inventory: Control = get_node("../Inventory")
@onready var hotbar: Control = get_node("../Hotbar")
var _image: Image
var _texture: ImageTexture
var _font: FontFile = UI_THEME.default_font
var _font_size: int = UI_THEME.default_font_size
var _font_atlases: Dictionary = {}
var _title_rect := Rect2i()
var _category_rect := Rect2i()
var _title_ink_rect := Rect2i()
var _body_ink_rect := Rect2i()
var _body_lines: Array[String] = []
var _sale_value: int = -1
var _swing_speed: int = -1
var _damage_range := Vector2i.ZERO
var _damage_text: String = ""
var _footer_rect := Rect2i()
var _damage_rect := Rect2i()
var _damage_icon_rect := Rect2i()
var _damage_number_rect := Rect2i()
var _sale_rect := Rect2i()
var _sale_coin_rect := Rect2i()
var _sale_number_rect := Rect2i()
var _sale_coin_source_rect := Rect2i()
var _speed_rect := Rect2i()
var _speed_number_rect := Rect2i()

func _init() -> void:
    name = "ItemTooltip"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    z_index = 50
    visible = false

func _ready() -> void:
    size = MAIN_FRAME.get_size()

func _process(_delta: float) -> void:
    var mouse := get_viewport().get_mouse_position()
    var hovered := _hovered_slot(mouse)
    if hovered.is_empty():
        hide()
        return
    _set_item(hovered.item)
    _position_at_mouse(mouse)
    show()

func _position_at_mouse(mouse: Vector2) -> void:
    # Use the inventory's pixel ratio even when hovering the closed hotbar.
    # During its brief reveal, follow the same panel transform exactly.
    scale = inventory.panel.scale if inventory.is_open else Vector2.ONE * inventory._layout_scale
    var screen := get_viewport_rect().size
    var display_size := size * scale
    var point := Vector2(mouse.x - display_size.x * 0.5, mouse.y - display_size.y - SCREEN_MARGIN)
    if point.y < SCREEN_MARGIN:
        point.y = mouse.y + SCREEN_MARGIN
    var maximum := (screen - display_size - Vector2.ONE * SCREEN_MARGIN).max(Vector2.ONE * SCREEN_MARGIN)
    position = point.clamp(Vector2.ONE * SCREEN_MARGIN, maximum).floor()

func _hovered_slot(point: Vector2) -> Dictionary:
    # Dragging and the modal's closing animation own the pointer until finished.
    if get_viewport().gui_is_dragging() or not inventory._drag.is_empty() or (inventory.visible and not inventory.is_open):
        return {}
    var slot: Dictionary
    if inventory.is_open:
        slot = inventory._slot_at(point)
    else:
        var index: int = hotbar.slot_at_screen(point)
        if index >= 0:
            slot = {"group": &"hotbar", "index": index}
    if slot.is_empty():
        return {}
    var item: InventoryItem = inventory.model.get_item(slot.group, slot.index)
    if item == null:
        return {}
    return {"item": item}

func _draw() -> void:
    if _texture != null:
        draw_texture(_texture, Vector2.ZERO)

func _set_item(item: InventoryItem) -> void:
    if item != null and item == _item and _texture != null and _sale_value == item.get_sale_price() and _damage_range == _display_damage_range(item) and _swing_speed == item.swing_speed:
        return
    _item = item
    _build_texture()

func _display_damage_range(item: InventoryItem) -> Vector2i:
    if item == null:
        return Vector2i.ZERO
    var target := InventoryItem.DamageTarget.MONSTER
    if item.category == InventoryItem.Category.TOOL:
        if item.subtype == &"pickaxe":
            target = InventoryItem.DamageTarget.ROCK
        elif item.subtype == &"axe":
            target = InventoryItem.DamageTarget.TREE
    var damage := item.get_damage_range(target)
    if damage.y > 0:
        return damage
    # Other damaging items (for example, a consumable) can still show their
    # configured effect even when they do not use a standard action subtype.
    for other_target in [InventoryItem.DamageTarget.ROCK, InventoryItem.DamageTarget.TREE, InventoryItem.DamageTarget.MONSTER]:
        var other := item.get_damage_range(other_target)
        if other.y > damage.y:
            damage = other
    return damage

func _build_texture() -> void:
    if _item == null:
        return
    var title := _item.get_title()
    var description := _item.description
    _sale_value = _item.get_sale_price()
    _swing_speed = _item.swing_speed
    _damage_range = _display_damage_range(_item)
    var sale_number := str(_sale_value) if _sale_value > 0 else ""
    var speed_number := str(_swing_speed) if _item.get_swing_interval() > 0.0 and _swing_speed > 0 else ""
    _damage_text = ""
    if _damage_range.y > 0:
        _damage_text = str(_damage_range.y) if _damage_range.x == _damage_range.y else "%d-%d" % [_damage_range.x, _damage_range.y]
    _footer_rect = Rect2i()
    _sale_rect = Rect2i()
    _sale_coin_rect = Rect2i()
    _sale_number_rect = Rect2i()
    _sale_coin_source_rect = Rect2i()
    _damage_rect = Rect2i()
    _damage_icon_rect = Rect2i()
    _damage_number_rect = Rect2i()
    _speed_rect = Rect2i()
    _speed_number_rect = Rect2i()

    # Prewarm every visible glyph before copying the pixel font's texture cache.
    var cache_size := Vector2i(_font_size, 0)
    for character in title + description + sale_number + _damage_text + speed_number:
        _font.render_glyph(0, cache_size, _font.get_glyph_index(_font_size, character.unicode_at(0), 0))
    _font_atlases.clear()
    var title_image := _text_image(title)
    var badge: Texture2D = CATEGORY_BADGES.get(_item.category, CATEGORY_BADGES[InventoryItem.Category.RESOURCE])
    var badge_image := badge.get_image()
    badge_image.convert(Image.FORMAT_RGBA8)
    var badge_size := badge_image.get_size()
    var header_overhead := TITLE_LEFT + CATEGORY_GAP + badge_size.x + CATEGORY_RIGHT_MARGIN + FRAME_RIGHT_BORDER
    var needed_title_width := title_image.get_width() + 2 * (TITLE_BORDER.x + TITLE_SIDE_PADDING)

    var price_image: Image
    var coin_image: Image
    var damage_image: Image
    var damage_number: Image
    var speed_image: Image
    var sale_width: int = 0
    var damage_width: int = 0
    var speed_width: int = 0
    var content_height: int = 0
    var side_inset := TITLE_BORDER.x + CARD_SIDE_PADDING
    if _sale_value > 0:
        price_image = _text_image(sale_number)
        # Keep the left coin through 100 and the middle coin for larger prices.
        var coin_cell := Rect2i(Vector2i(16 if _sale_value > 100 else 0, 0), COIN_CELL)
        var cell_image := COIN_SHEET.get_image().get_region(coin_cell)
        cell_image.convert(Image.FORMAT_RGBA8)
        var coin_ink := cell_image.get_used_rect()
        _sale_coin_source_rect = Rect2i(coin_cell.position + coin_ink.position, coin_ink.size)
        coin_image = cell_image.get_region(coin_ink)
        sale_width = coin_image.get_width() + CARD_ICON_GAP + price_image.get_width() + 2 * side_inset
        content_height = maxi(coin_image.get_height(), price_image.get_height())
    if not _damage_text.is_empty():
        damage_image = DAMAGE_ICON.get_image()
        damage_image.convert(Image.FORMAT_RGBA8)
        damage_image = damage_image.get_region(damage_image.get_used_rect())
        damage_number = _text_image(_damage_text)
        damage_width = damage_image.get_width() + CARD_ICON_GAP + damage_number.get_width() + 2 * side_inset
        content_height = maxi(content_height, maxi(damage_image.get_height(), damage_number.get_height()))
    if not speed_number.is_empty():
        speed_image = _text_image(speed_number)
        speed_width = speed_image.get_width() + 2 * side_inset
        content_height = maxi(content_height, speed_image.get_height())
    var card_count := int(sale_width > 0) + int(damage_width > 0) + int(speed_width > 0)
    var footer_width := sale_width + damage_width + speed_width + maxi(0, card_count - 1) * CARD_GAP
    var frame_width := maxi(MAIN_FRAME.get_width(), header_overhead + needed_title_width)
    if footer_width > 0:
        frame_width = maxi(frame_width, footer_width + 2 * TITLE_LEFT)
    # Widen symmetrically to preserve the original frame's centered ornament.
    if (frame_width - MAIN_FRAME.get_width()) % 2 != 0:
        frame_width += 1
    if footer_width > 0 and (frame_width - footer_width) % 2 != 0:
        # A single extra pixel gives the whole row an exact native-pixel center.
        if speed_width > 0:
            speed_width += 1
        elif damage_width > 0:
            damage_width += 1
        else:
            sale_width += 1
        footer_width += 1

    var title_size := Vector2i(frame_width - header_overhead, TITLE_CONTENT_TOP + TITLE_BORDER.y + TITLE_TOP_PADDING + title_image.get_height() + TITLE_BOTTOM_PADDING)
    title_size.y = maxi(title_size.y, badge_size.y)
    _title_rect = Rect2i(Vector2i(TITLE_LEFT, 10), title_size)
    _category_rect = Rect2i(Vector2i(_title_rect.end.x + CATEGORY_GAP, _title_rect.position.y + (title_size.y - badge_size.y) / 2), badge_size)
    _title_ink_rect = Rect2i(_title_rect.position + Vector2i((title_size.x - title_image.get_width()) / 2, TITLE_CONTENT_TOP + TITLE_TOP_PADDING), title_image.get_size())
    var body_width := frame_width - 20
    _body_lines = _wrap_text(description, body_width)
    var body := _paragraph_image(_body_lines, body_width)
    _body_ink_rect = Rect2i(Vector2i((frame_width - body.get_width()) / 2, _title_rect.end.y + 2), body.get_size())
    var frame_height := maxi(MAIN_FRAME.get_height(), _body_ink_rect.end.y + 6 + 18)
    if footer_width > 0:
        var card_height := TITLE_CONTENT_TOP + TITLE_TOP_PADDING + content_height + TITLE_BOTTOM_PADDING + TITLE_BORDER.y
        frame_height = maxi(frame_height, _body_ink_rect.end.y + FOOTER_CONTENT_GAP + card_height + FRAME_BOTTOM_BORDER + FOOTER_BOTTOM_MARGIN)
        _footer_rect = Rect2i(Vector2i((frame_width - footer_width) / 2, frame_height - FRAME_BOTTOM_BORDER - FOOTER_BOTTOM_MARGIN - card_height), Vector2i(footer_width, card_height))
        var card_x := _footer_rect.position.x
        if sale_width > 0:
            _sale_rect = Rect2i(Vector2i(card_x, _footer_rect.position.y), Vector2i(sale_width, card_height))
            card_x += sale_width + CARD_GAP
        if damage_width > 0:
            _damage_rect = Rect2i(Vector2i(card_x, _footer_rect.position.y), Vector2i(damage_width, card_height))
            card_x += damage_width + CARD_GAP
        if speed_width > 0:
            _speed_rect = Rect2i(Vector2i(card_x, _footer_rect.position.y), Vector2i(speed_width, card_height))

    _image = _frame_image(frame_height, frame_width)
    _image.blend_rect(_title_plate(title_size), Rect2i(Vector2i.ZERO, title_size), _title_rect.position)
    _image.blend_rect(title_image, Rect2i(Vector2i.ZERO, title_image.get_size()), _title_ink_rect.position)
    _image.blend_rect(badge_image, Rect2i(Vector2i.ZERO, badge_size), _category_rect.position)
    _image.blend_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), _body_ink_rect.position)
    if _sale_rect.has_area():
        var sale_ink := _draw_footer_card(_sale_rect, coin_image, price_image)
        _sale_coin_rect = sale_ink[0]
        _sale_number_rect = sale_ink[1]
    if _damage_rect.has_area():
        var damage_ink := _draw_footer_card(_damage_rect, damage_image, damage_number)
        _damage_icon_rect = damage_ink[0]
        _damage_number_rect = damage_ink[1]
    if _speed_rect.has_area():
        var speed_ink := _draw_footer_card(_speed_rect, null, speed_image)
        _speed_number_rect = speed_ink[1]
    _texture = ImageTexture.create_from_image(_image)
    size = _image.get_size()
    queue_redraw()

func _draw_footer_card(card: Rect2i, icon: Image, number: Image) -> Array[Rect2i]:
    var icon_width := icon.get_width() + CARD_ICON_GAP if icon != null else 0
    var width := icon_width + number.get_width()
    var x := card.position.x + (card.size.x - width) / 2
    var icon_rect := Rect2i()
    if icon != null:
        icon_rect = Rect2i(Vector2i(x, card.position.y + (card.size.y - icon.get_height()) / 2), icon.get_size())
    var number_rect := Rect2i(Vector2i(x + icon_width, card.position.y + (card.size.y - number.get_height()) / 2), number.get_size())
    _image.blend_rect(_title_plate(card.size), Rect2i(Vector2i.ZERO, card.size), card.position)
    if icon != null:
        _image.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), icon_rect.position)
    _image.blend_rect(number, Rect2i(Vector2i.ZERO, number.get_size()), number_rect.position)
    return [icon_rect, number_rect]

func _frame_image(height: int, width: int) -> Image:
    var source := MAIN_FRAME.get_image()
    source.convert(Image.FORMAT_RGBA8)
    if width > source.get_width():
        source = _widen_frame(source, width)
    var extension := height - source.get_height()
    var middle: int = source.get_height() / 2
    var result := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
    # Insert only flat center rows; move the complete lower decorations together.
    result.blit_rect(source, Rect2i(0, 0, width, middle), Vector2i.ZERO)
    for row in range(extension):
        result.blit_rect(source, Rect2i(0, middle, width, 1), Vector2i(0, middle + row))
    result.blit_rect(source, Rect2i(0, middle, width, source.get_height() - middle), Vector2i(0, middle + extension))
    return result

func _widen_frame(source: Image, width: int) -> Image:
    # Extend only flat columns on either side of the central ornament. The
    # source corners, outlines, and pointed bottom keep their exact pixels.
    var height := source.get_height()
    var extra := width - source.get_width()
    var left_extra: int = extra / 2
    var right_extra := extra - left_extra
    var left_cut: int = 20
    var right_cut := source.get_width() - 20
    var result := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
    result.blit_rect(source, Rect2i(0, 0, left_cut, height), Vector2i.ZERO)
    for column in range(left_extra):
        result.blit_rect(source, Rect2i(left_cut, 0, 1, height), Vector2i(left_cut + column, 0))
    result.blit_rect(source, Rect2i(left_cut, 0, right_cut - left_cut, height), Vector2i(left_cut + left_extra, 0))
    for column in range(right_extra):
        result.blit_rect(source, Rect2i(right_cut - 1, 0, 1, height), Vector2i(right_cut + left_extra + column, 0))
    result.blit_rect(source, Rect2i(right_cut, 0, source.get_width() - right_cut, height), Vector2i(right_cut + extra, 0))
    return result

func _paragraph_image(lines: Array[String], width: int) -> Image:
    var step := ceili(_font.get_height(_font_size)) + 2
    var result := Image.create_empty(width, maxi(1, step * lines.size() + 4), false, Image.FORMAT_RGBA8)
    for index in range(lines.size()):
        var line := _text_image(lines[index])
        var baseline_y := 2 + ceili(_font.get_ascent(_font_size)) + index * step
        var at := Vector2i((width - line.get_width()) / 2, baseline_y + _last_text_ink_offset.y)
        result.blend_rect(line, Rect2i(Vector2i.ZERO, line.get_size()), at)
    var used := result.get_used_rect()
    return result.get_region(used) if used.has_area() else Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

func _title_plate(dimensions: Vector2i) -> Image:
    # Nine-slice the straight plate; its three-pixel sides and four-pixel caps stay intact.
    var source := TITLE_FRAME.get_image()
    var result := Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
    for y in range(dimensions.y):
        var sy := y if y < TITLE_BORDER.y else (source.get_height() - dimensions.y + y if y >= dimensions.y - TITLE_BORDER.y else TITLE_BORDER.y)
        for x in range(dimensions.x):
            var sx := x if x < TITLE_BORDER.x else (source.get_width() - dimensions.x + x if x >= dimensions.x - TITLE_BORDER.x else TITLE_BORDER.x)
            result.set_pixel(x, y, source.get_pixel(sx, sy))
    return result

func _wrap_text(text: String, width: int) -> Array[String]:
    var lines: Array[String] = []
    for paragraph in text.split("\n"):
        var current := ""
        for word in paragraph.split(" ", false):
            var candidate := word if current.is_empty() else current + " " + word
            if not current.is_empty() and _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x > width:
                lines.append(current)
                current = word
            else:
                current = candidate
        lines.append(current)
    return lines

var _last_text_ink_offset := Vector2i.ZERO

func _text_image(text: String) -> Image:
    # Use the existing font's real rasterized glyphs, including transparent glyph
    # padding. Cropping the ink gives exact visible-pixel centering and margins.
    var dimensions := Vector2i(ceili(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x) + 4, ceili(_font.get_height(_font_size)) + 4)
    var result := Image.create_empty(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
    var baseline := Vector2i(2, 2 + ceili(_font.get_ascent(_font_size)))
    var pen := baseline
    var previous: int = 0
    var cache_size := Vector2i(_font_size, 0)
    for character in text:
        var glyph := _font.get_glyph_index(_font_size, character.unicode_at(0), 0)
        _font.render_glyph(0, cache_size, glyph)
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
    _last_text_ink_offset = used.position - baseline
    return result.get_region(used) if used.has_area() else Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)

