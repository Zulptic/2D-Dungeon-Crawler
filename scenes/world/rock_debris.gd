extends Node2D
## Short-lived rock fragments use patches from the struck rock's own texture.
var _texture: Texture2D
var _shatter: bool = false
var _direction := Vector2.ZERO
var _pieces: Array[Dictionary] = []
var _elapsed: float = 0.0
var _duration: float = 0.4
var _rng := RandomNumberGenerator.new()

func setup(texture: Texture2D, shatter: bool, direction: Vector2) -> void:
    _texture = texture
    _shatter = shatter
    _direction = direction

func _ready() -> void:
    add_to_group(&"rock_debris")
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    z_index = 3
    _rng.randomize()
    _duration = 0.5 if _shatter else 0.36
    if _texture == null:
        queue_free()
        return
    var image := _texture.get_image()
    var patches: Array[Rect2] = []
    for y in range(image.get_height() - 2):
        for x in range(image.get_width() - 2):
            if image.get_pixel(x,y).a > 0.5 and image.get_pixel(x+1,y).a > 0.5 and image.get_pixel(x,y+1).a > 0.5 and image.get_pixel(x+1,y+1).a > 0.5:
                patches.append(Rect2(x,y,2,2))
    if patches.is_empty():
        queue_free()
        return
    var count := 14 if _shatter else 5
    for index in range(count):
        var source: Rect2 = patches[_rng.randi_range(0, patches.size()-1)]
        var angle := TAU * float(index) / count + _rng.randf_range(-0.35,0.35)
        var speed := _rng.randf_range(17.0,35.0) if _shatter else _rng.randf_range(10.0,22.0)
        _pieces.append({
            "source": source,
            "ground": Vector2(_rng.randf_range(-2.0,2.0),_rng.randf_range(-1.0,1.0)),
            "velocity": Vector2.from_angle(angle)*speed + _direction*6.0,
            "height": _rng.randf_range(4.0,6.0),
            "upward": _rng.randf_range(28.0,48.0) if _shatter else _rng.randf_range(26.0,40.0),
            "lifetime": _duration*_rng.randf_range(0.8,1.0)
        })
    queue_redraw()

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed >= _duration:
        queue_free()
        return
    for piece in _pieces:
        piece.ground += piece.velocity*delta
        piece.height += piece.upward*delta
        piece.upward -= 200.0*delta
        if piece.height <= 0.0:
            piece.height = 0.0
            piece.upward = maxf(0.0,-piece.upward*0.2)
            piece.velocity *= 0.45
    queue_redraw()

func _draw() -> void:
    if _texture == null:
        return
    for piece in _pieces:
        var alpha := clampf((float(piece.lifetime)-_elapsed)/0.12,0.0,1.0)
        if alpha <= 0.0:
            continue
        var point: Vector2 = (piece.ground + Vector2(0,-float(piece.height))).round()
        var source: Rect2 = piece.source
        draw_texture_rect_region(_texture,Rect2(point,source.size),source,Color(1,1,1,alpha))
