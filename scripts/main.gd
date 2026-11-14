extends Node3D
## Scene construction and presentation. Game state lives in game.gd.

const Game = preload("res://scripts/game.gd")
const Rules = preload("res://scripts/rules.gd")
const Die = preload("res://scripts/die.gd")
const TRAY: PackedScene = preload("res://assets/kaykit/container_B.gltf")
const HOURGLASS: PackedScene = preload("res://assets/kaykit/hourglass.gltf")
const TOKENS: Array[PackedScene] = [
	preload("res://assets/kaykit/token_green.gltf"),
	preload("res://assets/kaykit/token_yellow.gltf"),
	preload("res://assets/kaykit/token_red.gltf"),
	preload("res://assets/kaykit/token_blue.gltf"),
]
const COINS: Array[PackedScene] = [
	preload("res://assets/kaykit/coin_gold.gltf"),
	preload("res://assets/kaykit/coin_silver.gltf"),
]
const FONT = preload("res://assets/fonts/Lato-Regular.ttf")
const BOLD = preload("res://assets/fonts/Lato-Bold.ttf")
const SERIF = preload("res://assets/fonts/DejaVuSerif.ttf")
const CREAM := Color("f4ebd9")
const MUTED := Color("94aaa4")
const GOLD := Color("e3b76d")
const GREEN := Color("8cd8b0")
const SAVE_PATH := "user://partida.json"
const SETTINGS_PATH := "user://preferencias.cfg"

var game: GeneralaGame
var dice: Array[GeneralaDie] = []
var rings: Array[MeshInstance3D] = []
var camera: Camera3D
var ui: Control
var sidebar: PanelContainer
var heading: Label
var subtitle: Label
var eyebrow: Label
var dice_hint: Label
var dice_buttons: Array[Button] = []
var dice_row: HBoxContainer
var controls: HBoxContainer
var roll_button: Button
var roll_counter: Label
var footer: Label
var menu_button: Button
var sound_button: Button
var dialog: Control
var audio: Dictionary = {}
var muted: bool = false
var best_score: int = 0
var _player_count: int = 2
var _player_names: Array[String] = ["Jugador 1", "Jugador 2", "Jugador 3", "Jugador 4"]
var _served_wins: bool = true
var _rolling: bool = false
var _roll_elapsed: float = 0.0
var _quiet_time: float = 0.0
var _collision_cooldown: float = 0.0
var _test_mode: bool = false
var _exiting: bool = false
var _save_path: String = SAVE_PATH

func _ready() -> void:
	_test_mode = OS.get_cmdline_user_args().has("--test-mode")
	get_tree().auto_accept_quit = false
	_load_settings()
	_build_world()
	_build_audio()
	_build_ui()
	_show_home()

func _physics_process(delta: float) -> void:
	_collision_cooldown = maxf(0.0, _collision_cooldown - delta)
	if not _rolling:
		return
	_roll_elapsed += delta
	var still := true
	for i in range(5):
		if game.held[i]:
			continue
		if dice[i].linear_velocity.length_squared() > 0.025 or dice[i].angular_velocity.length_squared() > 0.06:
			still = false
		# Safety net for a rare physics tunneling event.
		if dice[i].position.y < -1.5:
			dice[i].toss(Vector3((i - 2) * 1.6, 3.0, 0))
	_quiet_time = _quiet_time + delta if still else 0.0
	if (_roll_elapsed > 1.3 and _quiet_time > 0.45) or _roll_elapsed > 7.0:
		_finish_roll()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(dialog):
				_close_dialog()
			else:
				_show_pause()
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(dialog):
			return
		if event.keycode == KEY_F1:
			_show_help()
		elif event.keycode == KEY_M:
			_toggle_sound()
		elif event.keycode == KEY_SPACE and game != null:
			_roll()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_toggle_die(event.keycode - KEY_1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if game == null or _rolling or is_instance_valid(dialog):
			return
		var origin := camera.project_ray_origin(event.position)
		var end := origin + camera.project_ray_normal(event.position) * 100.0
		# Only dice are pickable; the invisible retaining walls are on layer 1.
		var query := PhysicsRayQueryParameters3D.create(origin, end, 2)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is GeneralaDie:
			_toggle_die(hit.collider.die_index)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_exiting = true
		if _rolling:
			_finish_roll()
		_save_game()
		get_tree().quit()

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0c171b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c6ded3")
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -35, 0)
	key.light_color = Color("fff0d2")
	key.light_energy = 1.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 40.0
	add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-4, 7, -3)
	fill.light_color = Color("a4dbcf")
	fill.light_energy = 0.8
	fill.omni_range = 15
	add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.2
	camera.v_offset = 1.0
	camera.position = Vector3(3.25, 15.5, 12.5)
	add_child(camera)
	camera.look_at(Vector3(3.25, 0, 0))
	camera.current = true
	_add_asset(TRAY, "BandejaKayKit", Vector3(0, -0.08, 0), Vector3(3.97, 0.8, 2.07))
	var felt := ShaderMaterial.new()
	felt.shader = preload("res://shaders/felt.gdshader")
	var felt_surface := MeshInstance3D.new()
	felt_surface.name = "Pano"
	felt_surface.mesh = _felt_mesh()
	felt_surface.material_override = felt
	add_child(felt_surface)
	_static_box(Vector3(11.1, 0.4, 5.8), Vector3(0, -0.2, 0))
	for side in [-1.0, 1.0]:
		# Invisible walls protect every throw without hiding the board.
		_static_box(Vector3(0.4, 5, 6.6), Vector3(side * 5.6, 2, 0))
		_static_box(Vector3(11.5, 5, 0.4), Vector3(0, 2, side * 2.8))
	_table_text("G E N E R A L A", Vector3(0, 0.016, -2.15), 58, Color("718c68"))
	_table_text("C L U B   D E   D A D O S", Vector3(0, 0.018, -1.63), 23, Color("658564"))
	_table_text("U N A   M Á S   Y   N O S   V A M O S", Vector3(0, 0.018, 2.5), 18, Color("658564"))
	for i in range(5):
		var die := Die.new()
		die.die_index = i
		die.name = "Dado%d" % (i + 1)
		add_child(die)
		die.body_entered.connect(_on_die_collision.bind(die))
		dice.append(die)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.66
		torus.outer_radius = 0.71
		torus.rings = 40
		torus.ring_segments = 8
		ring.mesh = torus
		var ring_material := _material(GOLD, 0.4, 0.3)
		ring_material.emission_enabled = true
		ring_material.emission = GOLD * 0.25
		ring.material_override = ring_material
		ring.visible = false
		add_child(ring)
		rings.append(ring)
	# Keep accessories on the tray rim, outside the playable physics area.
	for stack in range(TOKENS.size()):
		for chip in range(3 + stack):
			_add_asset(TOKENS[stack], "FichasKayKit%d_%d" % [stack, chip],
				Vector3(-6.2, 0.34 + chip * 0.058, -0.55 + stack * 0.72), Vector3.ONE * 0.55, chip * 0.28)
	for i in range(COINS.size()):
		_add_asset(COINS[i], "MonedaKayKit%d" % i,
			Vector3(-4.85 + i * 0.76, 0.34, 3.1), Vector3.ONE * 0.58, i * 0.3)
	_add_asset(HOURGLASS, "RelojKayKit", Vector3(6.2, 0.34, -1.75), Vector3.ONE * 0.5, 0.2)

func _add_asset(scene: PackedScene, asset_name: String, location: Vector3, asset_scale: Vector3, yaw: float = 0.0) -> Node3D:
	var asset := scene.instantiate() as Node3D
	asset.name = asset_name
	asset.position = location
	asset.scale = asset_scale
	asset.rotation.y = yaw
	add_child(asset)
	return asset

func _felt_mesh() -> ArrayMesh:
	# Follow the rounded floor of KayKit's container without covering its walls.
	var rim: Array[Vector3] = []
	var half_size := Vector2(5.54, 2.89)
	var radius := Vector2(1.08, 0.56)
	for corner in range(4):
		var sign_x: float = 1.0 if corner == 0 or corner == 3 else -1.0
		var sign_z: float = 1.0 if corner < 2 else -1.0
		var center := (half_size - radius) * Vector2(sign_x, sign_z)
		for step in range(9):
			var angle: float = corner * PI / 2.0 + step * PI / 16.0
			var point := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
			rim.append(Vector3(point.x, 0.012, point.y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(rim.size()):
		for point: Vector3 in [Vector3(0, 0.012, 0), rim[i], rim[(i + 1) % rim.size()]]:
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(point.x / (half_size.x * 2.0) + 0.5, point.z / (half_size.y * 2.0) + 0.5))
			surface.add_vertex(point)
	return surface.commit()

func _table_text(text: String, position_3d: Vector3, size_3d: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = BOLD
	label.font_size = size_3d
	label.pixel_size = 0.006
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.position = position_3d
	label.rotation_degrees.x = -90
	add_child(label)

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _static_box(size_3d: Vector3, position_3d: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_3d
	collision.shape = shape
	body.position = position_3d
	body.add_child(collision)
	add_child(body)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 16
	ui.theme = theme
	layer.add_child(ui)
	var margin := _margin(32, 25, 32, 24)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(margin)
	var layout := _vbox(22)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(layout)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.custom_minimum_size.y = 70
	layout.add_child(top)
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/icon.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(48, 48)
	top.add_child(icon)
	var brand := _vbox(4)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(_label("G E N E R A L A", 24, CREAM, BOLD))
	var build_version := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	brand.add_child(_label(tr("CLUB DE DADOS  /  EDICIÓN DE SOBREMESA") + "  ·  v" + build_version, 10, MUTED))
	top.add_child(brand)
	top.add_child(_spacer())
	var local_label := _label("●  LOCAL · 1–4 JUGADORES", 11, GREEN, BOLD)
	local_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(local_label)
	var gap := Control.new()
	gap.custom_minimum_size.x = 16
	top.add_child(gap)
	sound_button = _button("SONIDO", _toggle_sound)
	sound_button.tooltip_text = "Activar o silenciar · M"
	sound_button.custom_minimum_size = Vector2(98, 40)
	sound_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(sound_button)
	var help_button := _button("CÓMO JUGAR", _show_help)
	help_button.custom_minimum_size = Vector2(125, 40)
	help_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(help_button)
	menu_button = _button("MENÚ", _show_pause)
	menu_button.custom_minimum_size = Vector2(80, 40)
	menu_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(menu_button)
	layout.add_child(_separator())
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 30)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(content)
	var stage := _vbox(12)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(stage)
	var title_margin := _margin(12, 18, 0, 0)
	title_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(title_margin)
	var titles := _vbox(12)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_margin.add_child(titles)
	eyebrow = _label("", 12, GOLD, BOLD)
	titles.add_child(eyebrow)
	heading = _label("", 43, CREAM, SERIF)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(heading)
	subtitle = _label("", 16, MUTED)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(subtitle)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	air.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(air)
	dice_hint = _label("", 13, CREAM)
	dice_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(dice_hint)
	dice_row = HBoxContainer.new()
	dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_row.add_theme_constant_override("separation", 12)
	stage.add_child(dice_row)
	for i in range(5):
		var button := _button("", _toggle_die.bind(i))
		button.custom_minimum_size = Vector2(98, 58)
		button.tooltip_text = "Conservar o liberar dado %d · Tecla %d" % [i + 1, i + 1]
		dice_row.add_child(button)
		dice_buttons.append(button)
	controls = HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 20)
	stage.add_child(controls)
	roll_button = _button("", _roll, true)
	roll_button.custom_minimum_size = Vector2(300, 60)
	roll_button.add_theme_font_size_override("font_size", 16)
	controls.add_child(roll_button)
	roll_counter = _label("", 14, MUTED)
	roll_counter.custom_minimum_size.x = 160
	roll_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	controls.add_child(roll_counter)
	footer = _label("", 11, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.custom_minimum_size.y = 30
	stage.add_child(footer)
	sidebar = PanelContainer.new()
	sidebar.custom_minimum_size.x = 410
	sidebar.add_theme_stylebox_override("panel", _style(Color("12282a"), Color("314743"), 18))
	content.add_child(sidebar)
	sound_button.text = "SILENCIADO" if muted else "SONIDO ON"

func _show_home() -> void:
	_close_dialog()
	game = null
	_rolling = false
	camera.v_offset = 1.0
	for i in range(5):
		dice[i].position = Vector3((i - 2) * 1.52, 0.51, 0.25 + sin(i * 1.8) * 0.15)
		dice[i].show_value([5, 3, 1, 6, 2][i], (i - 2) * 0.12)
		rings[i].hide()
	eyebrow.text = "EL CLÁSICO DE SIEMPRE. OTRA DIMENSIÓN."
	heading.add_theme_font_size_override("font_size", 43)
	heading.text = "Cinco dados.\nMil posibilidades."
	subtitle.text = "Un poco de estrategia. Un poco de suerte. Una más."
	dice_hint.text = ""
	dice_row.hide()
	controls.hide()
	footer.text = "HECHO PARA COMPARTIR. JUGADO SIN APURO."
	menu_button.disabled = true
	_show_setup()

func _show_setup() -> void:
	_clear_sidebar()
	var box := _sidebar_box()
	box.add_child(_label("BIENVENIDO AL CLUB", 11, GOLD, BOLD))
	box.add_child(_label("Armá la mesa.", 30, CREAM, SERIF))
	var description := _label("De uno a cuatro jugadores.\nPasen los dados, compartan la suerte.", 15, MUTED)
	box.add_child(description)
	box.add_child(_separator())
	box.add_child(_label("JUGADORES", 11, MUTED, BOLD))
	var count := OptionButton.new()
	count.custom_minimum_size.y = 43
	count.add_theme_stylebox_override("normal", _style(Color("1b3635"), Color("3c5550"), 7))
	count.add_theme_color_override("font_color", CREAM)
	for title in ["1  ·  Solitario", "2  ·  Un mano a mano", "3  ·  Mesa de tres", "4  ·  Mesa completa"]:
		count.add_item(title)
	count.select(_player_count - 1)
	count.item_selected.connect(func(index: int) -> void:
		_player_count = index + 1
		_show_setup())
	box.add_child(count)
	for i in range(_player_count):
		var line := LineEdit.new()
		line.text = _player_names[i]
		line.placeholder_text = "Nombre del jugador %d" % (i + 1)
		line.max_length = 18
		line.custom_minimum_size.y = 42
		line.add_theme_stylebox_override("normal", _style(Color("0e2224"), Color("2d4541"), 7))
		line.add_theme_stylebox_override("focus", _style(Color("15312e"), GOLD, 7))
		line.add_theme_color_override("font_color", CREAM)
		line.text_changed.connect(func(value: String) -> void: _player_names[i] = value)
		box.add_child(line)
	var served := CheckBox.new()
	served.text = "Generala servida gana"
	served.button_pressed = _served_wins
	served.add_theme_font_size_override("font_size", 15)
	served.add_theme_color_override("font_color", CREAM)
	served.tooltip_text = "Cinco iguales en la primera tirada ganan al instante. Desactivado: siempre vale 50 puntos."
	served.toggled.connect(func(value: bool) -> void: _served_wins = value)
	box.add_child(served)
	var start_button := _button("EMPEZAR PARTIDA   →", _start_from_setup, true)
	start_button.custom_minimum_size.y = 54
	box.add_child(start_button)
	var saved := _read_saved_game()
	if saved != null and not saved.game_over:
		var resume := _button("CONTINUAR PARTIDA   ↗", _resume_game)
		resume.custom_minimum_size.y = 45
		resume.tooltip_text = "Ronda %d · %s" % [saved.round_number(), ", ".join(saved.names)]
		box.add_child(resume)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(_separator())
	var record_text := "RÉCORD DE LA MESA   %d PTS" % best_score if best_score > 0 else "10 RONDAS  ·  5 DADOS  ·  HASTA 3 TIRADAS"
	box.add_child(_label(record_text, 11, MUTED, BOLD))

func _start_from_setup() -> void:
	var saved := _read_saved_game()
	if saved != null and not saved.game_over:
		_show_dialog("¿Una mesa nueva?", "HAY UNA PARTIDA GUARDADA", "La nueva partida reemplazará el progreso guardado. También podés continuar donde lo dejaste.", [
			{"text": "CONTINUAR GUARDADA", "callback": _resume_game},
			{"text": "NUEVA PARTIDA", "callback": _new_game_from_names, "primary": true},
			{"text": "VOLVER", "callback": func() -> void: pass}])
	else:
		_new_game_from_names()

func _new_game_from_names() -> void:
	var names: Array[String] = []
	for i in range(_player_count):
		names.append(_player_names[i])
	_start_game(names, _served_wins)

func _start_game(names: Array[String], instant_win: bool = true) -> void:
	_close_dialog()
	game = Game.new()
	game.start(names, instant_win)
	camera.v_offset = 0.2
	_reset_dice_display()
	_refresh()
	_save_game()
	_play("select")

func _resume_game() -> void:
	var saved := _read_saved_game()
	if saved == null:
		_show_home()
		return
	game = saved
	camera.v_offset = 0.2
	_reset_dice_display()
	_refresh()

func _reset_dice_display() -> void:
	for i in range(5):
		dice[i].position = Vector3((i - 2) * 1.52, 0.51, 0.2)
		dice[i].show_value(game.dice[i] if game.dice[i] > 0 else [5, 3, 1, 6, 2][i], randf_range(-0.2, 0.2))

func _refresh() -> void:
	if game == null:
		return
	menu_button.disabled = _rolling
	dice_row.show()
	controls.show()
	eyebrow.text = "RONDA %02d / 10     ·     MESA LOCAL" % game.round_number()
	heading.text = "Tu turno, %s." % game.names[game.current_player]
	heading.add_theme_font_size_override("font_size", 36 if game.names[game.current_player].length() > 12 else 41)
	subtitle.text = "Hasta tres tiradas. Vos decidís cuándo plantarte."
	if _rolling:
		subtitle.text = "Que ruede la suerte…"
	elif game.rolls_used > 0:
		subtitle.text = _combination_text()
	if game.game_over:
		eyebrow.text = "LA MESA TIENE SU RESULTADO"
		heading.text = "Bien jugado. ¿Otra más?"
		subtitle.text = "Cada partida tiene su historia. Gracias por compartir esta mesa."
	for i in range(5):
		var held := game.held[i]
		dice_buttons[i].text = "%s   %d\n%s" % ["◆" if held else "·", game.dice[i], "GUARDADO" if held else "LIBRE"] if game.dice[i] > 0 else "—\nDADO %d" % (i + 1)
		dice_buttons[i].disabled = _rolling or game.rolls_used == 0 or game.rolls_used >= 3 or game.game_over
		_style_button(dice_buttons[i], held)
		rings[i].visible = held
		rings[i].position = Vector3(dice[i].position.x, 0.055, dice[i].position.z)
	if _rolling:
		dice_hint.text = "Los dados están en el aire…"
	elif game.rolls_used == 0:
		dice_hint.text = "Una nueva mano. Todas las posibilidades."
	elif game.rolls_used == 3:
		dice_hint.text = "Última tirada: elegí una categoría en la planilla."
	elif game.held.all(func(v: bool) -> bool: return v):
		dice_hint.text = "Todos guardados. Anotá tu jugada o liberá algún dado."
	else:
		dice_hint.text = "Clic en un dado para conservarlo. También podés anotar ahora."
	roll_button.disabled = _rolling or not game.can_roll()
	roll_button.text = "TIRAR LOS DADOS   →" if game.rolls_used == 0 else "VOLVER A TIRAR   →"
	if _rolling:
		roll_button.text = "RODANDO…"
	elif game.game_over:
		roll_button.text = "VER RESULTADO   →"
		roll_button.disabled = false
	elif game.rolls_used >= 3:
		roll_button.text = "ANOTÁ TU JUGADA   ↗"
	roll_counter.text = "%s   %d / 3\nTIRADAS USADAS" % ["●".repeat(game.rolls_used) + "○".repeat(3 - game.rolls_used), game.rolls_used]
	footer.text = "ESPACIO  Tirar     ·     1–5  Conservar dados     ·     ESC  Menú     ·     F1  Reglas"
	_show_scorecard()

func _combination_text() -> String:
	for category in [9, 8, 7, 6]:
		var score := Rules.score(game.dice, category, game.rolls_used == 1)
		if score > 0:
			var served_suffix := (" servida" if category == 6 or category == 9 else " servido") if game.rolls_used == 1 else ""
			return "%s%s · %d puntos posibles. Vos elegís." % [Rules.CATEGORIES[category], served_suffix, score]
	return "Conservá lo que te sirve. La próxima tirada puede cambiar todo."

func _show_scorecard() -> void:
	_clear_sidebar()
	var box := _sidebar_box(6)
	var title_row := HBoxContainer.new()
	title_row.add_child(_label("LA PLANILLA", 12, GOLD, BOLD))
	title_row.add_child(_spacer())
	title_row.add_child(_label("%02d / 10" % game.round_number(), 12, MUTED))
	box.add_child(title_row)
	box.add_child(_label("Cada punto cuenta.", 25, CREAM, SERIF))
	var caption := _label("Elegí dónde anotar tu jugada.", 13, MUTED)
	caption.custom_minimum_size.y = 30
	box.add_child(caption)
	var names_row := HBoxContainer.new()
	names_row.add_theme_constant_override("separation", 5)
	var category_label := _label("CATEGORÍA", 10, MUTED, BOLD)
	category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names_row.add_child(category_label)
	for player in range(game.names.size()):
		var name_label := _label(game.names[player].left(7), 11, GOLD if player == game.current_player else MUTED, BOLD)
		name_label.custom_minimum_size.x = _score_column_width()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.tooltip_text = game.names[player]
		names_row.add_child(name_label)
	box.add_child(names_row)
	box.add_child(_separator())
	for category in range(Rules.ROUND_COUNT):
		if category == 6:
			box.add_child(_separator())
		var row := Button.new()
		row.custom_minimum_size.y = 36
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = Rules.DESCRIPTIONS[category]
		var possible := game.preview(category)
		var selectable := possible >= 0 and not _rolling
		var base_color := Color("193832") if selectable and possible > 0 else Color("142c2b")
		row.add_theme_stylebox_override("normal", _style(base_color, Color.TRANSPARENT, 6))
		row.add_theme_stylebox_override("hover", _style(Color("28493c"), Color("5d7e58"), 6))
		row.add_theme_stylebox_override("pressed", _style(Color("3c5541"), GOLD, 6))
		row.add_theme_stylebox_override("disabled", _style(Color("12282a"), Color.TRANSPARENT, 6))
		row.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, GOLD, 6))
		row.disabled = not selectable
		row.pressed.connect(_request_score.bind(category))
		var row_margin := _margin(9, 0, 6, 0)
		row_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cells := HBoxContainer.new()
		cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cells.add_theme_constant_override("separation", 5)
		row_margin.add_child(cells)
		var category_name := _label(("%d   " % (category + 1) if category < 6 else "") + Rules.CATEGORIES[category], 14, CREAM if game.scores[game.current_player][category] == -1 else MUTED)
		category_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cells.add_child(category_name)
		for player in range(game.names.size()):
			var points: int = game.scores[player][category]
			var content := "—"
			var color := Color("536e65")
			if points >= 0:
				content = str(points) if points > 0 else "×"
				color = CREAM if points > 0 else Color("b77d6e")
			elif player == game.current_player and selectable:
				content = "+%d" % possible if possible > 0 else "0"
				color = GREEN if possible > 0 else Color("7c9690")
			var cell := _label(content, 15, color, BOLD)
			cell.custom_minimum_size.x = _score_column_width()
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cells.add_child(cell)
		row.add_child(row_margin)
		box.add_child(row)
	box.add_child(_separator())
	var totals := HBoxContainer.new()
	totals.add_theme_constant_override("separation", 5)
	var total_label := _label("TOTAL", 12, GOLD, BOLD)
	total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	totals.add_child(total_label)
	for player in range(game.names.size()):
		var total := _label(str(game.total(player)), 25, GOLD if player == game.current_player else CREAM, BOLD)
		total.custom_minimum_size.x = _score_column_width()
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		totals.add_child(total)
	box.add_child(totals)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var note := _label("Los valores en verde son puntos posibles.\nUn cero tacha la categoría para esta partida.", 12, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	box.add_child(_label("●  GUARDADO AUTOMÁTICO", 10, Color("648d7d"), BOLD))

func _score_column_width() -> float:
	return 64.0 if game.names.size() == 1 else 48.0 if game.names.size() == 2 else 43.0

func _roll() -> void:
	if game == null or _rolling or is_instance_valid(dialog):
		return
	if game.game_over:
		_show_results()
		return
	if not game.can_roll():
		return
	_release_focus()
	_rolling = true
	_roll_elapsed = 0.0
	_quiet_time = 0.0
	for i in range(5):
		if not game.held[i]:
			dice[i].toss(Vector3((i - 2) * 1.7, 2.6 + randf() * 0.8, randf_range(-0.6, 0.6)))
	_play("roll", -5.0)
	_refresh()

func _finish_roll() -> void:
	var values: Array[int] = []
	for i in range(5):
		var value := game.dice[i] if game.held[i] else dice[i].top_value()
		values.append(value)
		if not game.held[i]:
			var yaw := dice[i].rotation.y
			dice[i].position = Vector3(clampf(dice[i].position.x, -4.9, 4.9), 0.505, clampf(dice[i].position.z, -2.1, 2.1))
			dice[i].show_value(value, yaw)
	_rolling = false
	game.record_roll(values)
	_refresh()
	_save_game()
	if game.game_over and not _exiting:
		_show_results()

func _toggle_die(index: int) -> void:
	if game == null or _rolling or is_instance_valid(dialog):
		return
	if game.toggle_hold(index):
		_release_focus()
		_play("select", -5.0)
		_refresh()
		_save_game()

func _request_score(category: int) -> void:
	if game == null or _rolling or is_instance_valid(dialog) or not game.can_score(category):
		return
	_release_focus()
	if game.preview(category) == 0:
		_show_dialog("¿Tachar %s?" % Rules.CATEGORIES[category], "CERO PUNTOS", "Esta jugada no suma en esa categoría. Si la tachás, no vas a poder usarla de nuevo en esta partida.", [
			{"text": "SEGUIR JUGANDO", "callback": func() -> void: pass},
			{"text": "TACHAR CATEGORÍA", "callback": _commit_score.bind(category), "primary": true}])
	else:
		_commit_score(category)

func _commit_score(category: int) -> void:
	if game == null or _rolling:
		return
	if game.choose_category(category):
		_play("score", -6.0)
		if not game.game_over:
			_reset_dice_display()
		_refresh()
		_save_game()
		if game.game_over:
			_show_results()

func _show_pause() -> void:
	if game == null or _rolling:
		return
	_release_focus()
	_show_dialog("Una pausa en la mesa.", "LA PARTIDA ESTÁ GUARDADA", "Podés volver al inicio y continuar esta partida más tarde. El progreso se guarda en esta computadora.", [
		{"text": "SEGUIR JUGANDO", "callback": func() -> void: pass, "primary": true},
		{"text": "VOLVER AL INICIO", "callback": _show_home}])

func _show_help() -> void:
	_release_focus()
	_show_dialog("Las reglas de esta mesa.", "FÁCIL DE JUGAR. DIFÍCIL DE DEJAR.",
		"En cada turno tenés hasta 3 tiradas. Después de tirar, hacé clic en los dados que quieras conservar. Podés cambiar tu selección antes de la siguiente tirada.\n\nAnotá en una categoría libre para terminar el turno. Cada una se usa una vez. Si no sumás puntos, podés tacharla con un cero.\n\n1 al 6: sumá los dados de ese número.\nEscalera: 1–2–3–4–5 o 2–3–4–5–6 → 20 pts.\nFull: un trío y un par → 30 pts.\nPóker: cuatro o cinco iguales → 40 pts.\nGenerala: cinco iguales → 50 pts.\n\nEscalera, full y póker suman 5 puntos extra si salen en la primera tirada. Con la opción activada, una generala en la primera tirada gana la partida al instante.\n\nDespués de 10 rondas gana quien sume más puntos. Se comparten los empates. No se usa doble generala.",
		[{"text": "A LA MESA   →", "callback": func() -> void: pass, "primary": true}], 650)

func _show_results() -> void:
	if game == null:
		return
	var winners := game.winners()
	var winner_names: Array[String] = []
	for player in winners:
		winner_names.append(game.names[player])
	var title := "¡Bien jugado, %s!" % game.names[0] if game.names.size() == 1 else "¡Ganó %s!" % " y ".join(winner_names)
	if winners.size() > 1:
		title = "¡Empate en la mesa!"
	if game.served_winner >= 0:
		title = "¡Generala servida!"
	var body := "%s gana al instante: cinco iguales en la primera tirada.\n\n" % game.names[game.served_winner] if game.served_winner >= 0 else "La suerte pasó. Los puntos quedaron.\n\n"
	var ranking: Array[int] = []
	for player in range(game.names.size()):
		ranking.append(player)
	ranking.sort_custom(func(a: int, b: int) -> bool: return game.total(a) > game.total(b))
	for player in ranking:
		body += "%s   ·   %d puntos\n" % [game.names[player], game.total(player)]
		best_score = maxi(best_score, game.total(player))
	_save_settings()
	var rematch_names: Array[String] = game.names.duplicate()
	var rematch_served := game.served_wins
	_show_dialog(title, "FIN DE LA PARTIDA", body, [
		{"text": "REVANCHA   →", "callback": func() -> void: _start_game(rematch_names, rematch_served), "primary": true},
		{"text": "VOLVER AL INICIO", "callback": _show_home}])
	_play("score", -3.0)

func _show_dialog(title: String, kicker: String, body: String, actions: Array, width: float = 590) -> void:
	_close_dialog()
	dialog = Control.new()
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dialog)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.055, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(Color("142d2d"), Color("566b53"), 18))
	center.add_child(panel)
	var margin := _margin(32, 30, 32, 30)
	panel.add_child(margin)
	var box := _vbox(18)
	margin.add_child(box)
	box.add_child(_label(kicker, 11, GOLD, BOLD))
	var title_label := _label(title, 29, CREAM, SERIF)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)
	var body_label := _label(body, 16, Color("c0cec3"))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size.x = width - 64
	box.add_child(body_label)
	box.add_child(_separator())
	for action: Dictionary in actions:
		var button := _button(action.text, func() -> void:
			_close_dialog()
			var callback: Callable = action.callback
			callback.call(), action.get("primary", false))
		button.custom_minimum_size.y = 44
		box.add_child(button)

func _close_dialog() -> void:
	if is_instance_valid(dialog):
		dialog.get_parent().remove_child(dialog)
		dialog.queue_free()
	dialog = null

func _clear_sidebar() -> void:
	for child in sidebar.get_children():
		sidebar.remove_child(child)
		child.queue_free()

func _sidebar_box(separation: int = 15) -> VBoxContainer:
	var margin := _margin(22, 25, 22, 23)
	sidebar.add_child(margin)
	var box := _vbox(separation)
	margin.add_child(box)
	return box

func _label(text: String, size_px: int, color: Color, font: Font = FONT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(callback)
	_style_button(button, primary)
	return button

func _style_button(button: Button, primary: bool) -> void:
	var background := GOLD if primary else Color("19312f")
	var border := GOLD if primary else Color("3c5149")
	button.add_theme_stylebox_override("normal", _style(background, border, 8))
	button.add_theme_stylebox_override("hover", _style(background.lightened(0.12), GOLD, 8))
	button.add_theme_stylebox_override("pressed", _style(background.darkened(0.12), CREAM, 8))
	button.add_theme_stylebox_override("disabled", _style(Color("1a2d2a"), Color("30423a"), 8))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, CREAM, 8))
	button.add_theme_color_override("font_color", Color("1b3029") if primary else CREAM)
	button.add_theme_color_override("font_hover_color", Color("1b3029") if primary else CREAM)
	button.add_theme_color_override("font_pressed_color", Color("1b3029") if primary else CREAM)
	button.add_theme_color_override("font_disabled_color", Color("6c8176"))

func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func _margin(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin

func _vbox(separation: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	return box

func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

func _separator() -> HSeparator:
	var separator := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("30463f")
	style.content_margin_top = 1
	separator.add_theme_stylebox_override("separator", style)
	return separator

func _release_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()

func _build_audio() -> void:
	for key in ["roll", "select", "score", "hit"]:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/%s.wav" % key)
		player.max_polyphony = 5
		add_child(player)
		audio[key] = player

func _play(key: String, volume: float = 0.0) -> void:
	if muted or _test_mode or not audio.has(key):
		return
	var player: AudioStreamPlayer = audio[key]
	player.volume_db = volume
	player.pitch_scale = randf_range(0.93, 1.07)
	player.play()

func _on_die_collision(_body: Node, die: GeneralaDie) -> void:
	if _rolling and _collision_cooldown <= 0 and die.linear_velocity.length() > 0.6:
		_play("hit", -16.0 + minf(die.linear_velocity.length(), 8.0))
		_collision_cooldown = 0.065

func _toggle_sound() -> void:
	muted = not muted
	sound_button.text = "SILENCIADO" if muted else "SONIDO ON"
	if muted:
		for player: AudioStreamPlayer in audio.values():
			player.stop()
	else:
		_play("select", -8.0)
	_save_settings()
	_release_focus()

func _save_game() -> void:
	if _test_mode or game == null or _rolling:
		return
	# Write atomically so an interrupted write cannot destroy the previous match.
	var file := FileAccess.open(_save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_warning("No se pudo guardar la partida.")
		return
	file.store_string(JSON.stringify(game.to_dict()))
	file.close()
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(_save_path + ".tmp"), ProjectSettings.globalize_path(_save_path))
	if error != OK:
		push_warning("No se pudo reemplazar la partida guardada: %s" % error_string(error))

func _read_saved_game() -> GeneralaGame:
	if _test_mode or not FileAccess.file_exists(_save_path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_path))
	return Game.from_dict(data) if data is Dictionary else null

func _save_settings() -> void:
	if _test_mode:
		return
	var config := ConfigFile.new()
	config.set_value("audio", "muted", muted)
	config.set_value("records", "best_score", best_score)
	config.save(SETTINGS_PATH)

func _load_settings() -> void:
	if _test_mode:
		return
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		muted = bool(config.get_value("audio", "muted", false))
		best_score = maxi(0, int(config.get_value("records", "best_score", 0)))
