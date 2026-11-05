extends Control
## Menu controls remain scene nodes so the artwork can be replaced in the editor.
const CONTENT_SIZE := Vector2(320, 180)
const MAX_PIXEL_SCALE: int = 3
@export_file("*.tscn") var game_scene: String = "res://scenes/grasslands.tscn"

@onready var content: Control = $Content
@onready var menu: VBoxContainer = $Content/Menu
@onready var new_game: Button = $Content/Menu/NewGame
@onready var settings_button: Button = $Content/Menu/Settings
@onready var quit_button: Button = $Content/Menu/QuitGame
@onready var settings_panel: PanelContainer = $Content/SettingsPanel
@onready var fullscreen_button: CheckButton = $Content/SettingsPanel/Margin/Options/Fullscreen
@onready var vsync_button: CheckButton = $Content/SettingsPanel/Margin/Options/VSync
@onready var back_button: Button = $Content/SettingsPanel/Margin/Options/Back
@onready var settings_status: Label = $Content/SettingsPanel/Margin/Options/Status
@onready var menu_status: Label = $Content/Status

var _settings_path: String = "user://settings.cfg"
var _fullscreen: bool = false
var _vsync: bool = true
var _windowed_size := Vector2i.ZERO
var _starting: bool = false

func _ready() -> void:
	menu.show()
	settings_panel.hide()
	menu_status.hide()
	settings_status.hide()
	_windowed_size = get_window().size
	_load_preferences()
	fullscreen_button.set_pressed_no_signal(_fullscreen)
	vsync_button.set_pressed_no_signal(_vsync)
	_apply_fullscreen()
	_apply_vsync()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	new_game.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(_quit_game)
	fullscreen_button.toggled.connect(_on_fullscreen_toggled)
	vsync_button.toggled.connect(_on_vsync_toggled)
	back_button.pressed.connect(_close_settings)
	resized.connect(_update_layout)
	_update_layout()
	new_game.grab_focus.call_deferred()

func _update_layout() -> void:
	var fit := floori(minf((size.x - 32.0) / CONTENT_SIZE.x, (size.y - 32.0) / CONTENT_SIZE.y))
	var amount := maxi(1, mini(MAX_PIXEL_SCALE, fit))
	content.scale = Vector2.ONE * amount
	content.position = ((size - CONTENT_SIZE * amount) * 0.5).floor()

func _on_new_game_pressed() -> void:
	if _starting:
		return
	_starting = true
	new_game.disabled = true
	settings_button.disabled = true
	quit_button.disabled = true
	var error := get_tree().change_scene_to_file(game_scene)
	if error != OK:
		_starting = false
		new_game.disabled = false
		settings_button.disabled = false
		quit_button.disabled = false
		menu_status.text = "Unable to start the game."
		menu_status.show()
		new_game.grab_focus()
		push_error("Main menu could not load %s: %s" % [game_scene, error_string(error)])

func _open_settings() -> void:
	menu.hide()
	menu_status.hide()
	settings_panel.show()
	fullscreen_button.grab_focus()

func _close_settings() -> void:
	settings_panel.hide()
	menu.show()
	settings_button.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if settings_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()

func _on_fullscreen_toggled(value: bool) -> void:
	if value and DisplayServer.get_name() != "headless":
		_windowed_size = get_window().size
	_fullscreen = value
	_apply_fullscreen()
	_save_preferences()

func _on_vsync_toggled(value: bool) -> void:
	_vsync = value
	_apply_vsync()
	_save_preferences()

func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	var was_fullscreen := window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	window.mode = Window.MODE_FULLSCREEN if _fullscreen else Window.MODE_WINDOWED
	if was_fullscreen and not _fullscreen and _windowed_size.x > 0 and _windowed_size.y > 0:
		window.set_deferred("size", _windowed_size)

func _apply_vsync() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _vsync else DisplayServer.VSYNC_DISABLED)

func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(_settings_path) == OK:
		_fullscreen = bool(config.get_value("display", "fullscreen", false))
		_vsync = bool(config.get_value("display", "vsync", true))

func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.load(_settings_path)
	config.set_value("display", "fullscreen", _fullscreen)
	config.set_value("display", "vsync", _vsync)
	var error := config.save(_settings_path)
	settings_status.visible = error != OK
	settings_status.text = "Settings could not be saved." if error != OK else ""

func _quit_game() -> void:
	get_tree().quit()
