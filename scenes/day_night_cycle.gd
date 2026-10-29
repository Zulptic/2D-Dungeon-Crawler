extends CanvasModulate
## Time advances continuously; the text clock shows five-minute intervals.

signal time_changed(display_minutes: int)

const MINUTES_PER_DAY: float = 1440.0
const START_MINUTES: float = 360.0
const CLOCK_STEP: int = 5

@export_range(60.0, 3600.0, 1.0) var full_day_seconds: float = 600.0
@export var day_colors: Gradient

var _minutes_of_day: float = START_MINUTES
var _last_display_minutes: int = -1

func _ready() -> void:
    _minutes_of_day = START_MINUTES
    _last_display_minutes = -1
    if day_colors == null:
        day_colors = _default_day_colors()
    _refresh_time()

func _process(delta: float) -> void:
    advance_time(delta)

func advance_time(real_seconds: float) -> void:
    if real_seconds <= 0.0:
        return
    _minutes_of_day = fposmod(_minutes_of_day + real_seconds * MINUTES_PER_DAY / maxf(1.0, full_day_seconds), MINUTES_PER_DAY)
    _refresh_time()

func get_minutes_of_day() -> float:
    return _minutes_of_day

func get_display_minutes() -> int:
    # The tiny epsilon keeps exact five-minute boundaries stable after rounding.
    return posmod(floori(_minutes_of_day / CLOCK_STEP + 0.00000001) * CLOCK_STEP, int(MINUTES_PER_DAY))

func get_clock_text() -> String:
    var displayed := get_display_minutes()
    var hour24 := floori(displayed / 60.0)
    var hour12 := hour24 % 12
    if hour12 == 0:
        hour12 = 12
    return "%d:%02d %s" % [hour12, displayed % 60, "AM" if hour24 < 12 else "PM"]

func _refresh_time() -> void:
    # Perceptual color interpolation can leave the display gamut near white.
    color = day_colors.sample(_minutes_of_day / MINUTES_PER_DAY).clamp()
    var displayed := get_display_minutes()
    if displayed != _last_display_minutes:
        _last_display_minutes = displayed
        time_changed.emit(displayed)

func _default_day_colors() -> Gradient:
    var gradient := Gradient.new()
    gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
    gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_OKLAB
    gradient.offsets = PackedFloat32Array([0.0, 4.0 / 24.0, 6.0 / 24.0, 8.0 / 24.0, 10.0 / 24.0, 16.0 / 24.0, 18.0 / 24.0, 20.0 / 24.0, 1.0])
    var night := Color(0.30, 0.34, 0.50)
    gradient.colors = PackedColorArray([
        night,
        night,
        Color(0.80, 0.74, 0.72),
        Color(1.0, 0.96, 0.88),
        Color.WHITE,
        Color.WHITE,
        Color(0.92, 0.68, 0.55),
        night,
        night
    ])
    return gradient
