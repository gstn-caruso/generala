extends Node3D
## Scene construction and presentation. Game state lives in game.gd.

const Game = preload("res://scripts/game.gd")
const Rules = preload("res://scripts/rules.gd")
const Die = preload("res://scripts/die.gd")
const TabletopUI = preload("res://scripts/tabletop_ui.gd")
const TRAY: PackedScene = preload("res://assets/kaykit/container_B.gltf")
const FONT = preload("res://assets/fonts/Lato-Regular.ttf")
const BOLD = preload("res://assets/fonts/Lato-Bold.ttf")
const CREAM := Color("383d3d")
const MUTED := Color("858b87")
const GOLD := Color("edc94b")
const GREEN := Color("57768b")
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
var _die_rest_positions: Array[Vector3] = []
var _cup: Node3D
var _cup_tween: Tween

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
		# Dice use layer 2 and the cup uses layer 4; retaining walls use layer 1.
		var query := PhysicsRayQueryParameters3D.create(origin, end, 6)
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is GeneralaDie:
			_toggle_die(hit.collider.die_index)
		elif not hit.is_empty() and hit.collider is Area3D and hit.collider.name == "CupHitbox":
			_roll()

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
	environment.ambient_light_color = Color("e6e1d8")
	environment.ambient_light_energy = 0.4
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -35, 0)
	key.light_color = Color("fff5e4")
	key.light_energy = 1.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 40.0
	add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-4, 7, -3)
	fill.light_color = Color("e6e9ed")
	fill.light_energy = 0.8
	fill.omni_range = 15
	add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.2
	camera.v_offset = 0.2
	camera.position = Vector3(-3.8, 18, 7.4)
	add_child(camera)
	camera.look_at(Vector3(-3.8, 0, 0))
	camera.current = true
	var wood := ShaderMaterial.new()
	wood.shader = preload("res://shaders/wood.gdshader")
	_mesh_box(Vector3(44, 0.2, 32), Vector3(0, -0.21, 0), wood)
	var outer_tray := _add_asset(TRAY, "BordeKayKit", Vector3(0, -0.10, 0), Vector3(3.56, 0.72, 3.36))
	_paint_asset(outer_tray, _material(Color("a0a9ab"), 0.28, 0.72))
	var tray := _add_asset(TRAY, "BandejaKayKit", Vector3(0, -0.08, 0), Vector3(3.45, 0.8, 3.25))
	_paint_asset(tray, _material(Color("424d52"), 0.44, 0.38))
	for ridge in range(3):
		var rim := MeshInstance3D.new()
		rim.mesh = _rim_mesh(Vector2(5.32 + ridge * 0.23, 5.02 + ridge * 0.23))
		rim.material_override = _material(Color("a1a9aa") if ridge != 1 else Color("606b6f"), 0.31, 0.55)
		add_child(rim)
	var felt := ShaderMaterial.new()
	felt.shader = preload("res://shaders/felt.gdshader")
	var felt_surface := MeshInstance3D.new()
	felt_surface.name = "Pano"
	felt_surface.mesh = _felt_mesh()
	felt_surface.material_override = felt
	add_child(felt_surface)
	_static_box(Vector3(9.66, 0.4, 9.10), Vector3(0, -0.2, 0))
	for side in [-1.0, 1.0]:
		# Invisible walls protect every throw without hiding the board.
		_static_box(Vector3(0.4, 5, 9.3), Vector3(side * 4.88, 2, 0))
	_static_box(Vector3(10.0, 5, 0.35), Vector3(0, 2, -3.3))
	_static_box(Vector3(10.0, 5, 0.35), Vector3(0, 2, 4.55))
	# Five physical pockets visibly separate kept dice from the next throw.
	for i in range(5):
		var location := _held_position(i)
		_mesh_box(Vector3(1.62, 0.14, 1.4), Vector3(location.x, 0.32, location.z), _material(Color("738083"), 0.4, 0.45))
		_mesh_box(Vector3(1.43, 0.025, 1.2), Vector3(location.x, 0.401, location.z), _material(Color("303a3d"), 0.8))
	for i in range(5):
		var die := Die.new()
		die.die_index = i
		die.name = "Dado%d" % (i + 1)
		add_child(die)
		die.body_entered.connect(_on_die_collision.bind(die))
		dice.append(die)
		_die_rest_positions.append(Vector3((i - 2) * 1.5, 0.505, 0.8))
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
	_build_cup()
	_build_pencil()

func _held_position(index: int) -> Vector3:
	return Vector3((index - 2) * 1.8, 0.92, -4.48)

func _rim_mesh(half_size: Vector2) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array[Vector2] = []
	for corner in range(4):
		var signs := Vector2(1.0 if corner == 0 or corner == 3 else -1.0, 1.0 if corner < 2 else -1.0)
		var center := (half_size - Vector2.ONE * 1.05) * signs
		for step in range(13):
			var angle: float = corner * PI / 2.0 + step * PI / 24.0
			ring.append(center + Vector2(cos(angle), sin(angle)) * 1.05)
	for i in range(ring.size()):
		var next: int = (i + 1) % ring.size()
		var direction := (ring[next] - ring[i]).normalized()
		var inward := Vector2(-direction.y, direction.x) * 0.04
		for point: Vector2 in [ring[i] - inward, ring[next] + inward, ring[i] + inward, ring[i] - inward, ring[next] - inward, ring[next] + inward]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x, 0.349, point.y))
	return surface.commit()

func _paint_asset(asset: Node3D, material: Material) -> void:
	for mesh: MeshInstance3D in asset.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material

func _mesh_box(dimensions: Vector3, location: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = location
	instance.material_override = material
	add_child(instance)
	return instance

func _build_cup() -> void:
	_cup = Node3D.new()
	_cup.name = "Cubilete"
	_cup.position = Vector3(6.3, 1.10, 0.9)
	_cup.rotation.z = 1.22
	add_child(_cup)
	var hitbox := Area3D.new()
	hitbox.name = "CupHitbox"
	hitbox.collision_layer = 4
	hitbox.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = 0.9
	cylinder_shape.height = 2.1
	shape.shape = cylinder_shape
	hitbox.add_child(shape)
	_cup.add_child(hitbox)
	var leather := _material(Color("252321"), 0.78)
	leather.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lining := _material(Color("361216"), 0.95)
	lining.cull_mode = BaseMaterial3D.CULL_DISABLED
	for inner in [false, true]:
		var body := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.79 if inner else 0.88
		cylinder.bottom_radius = 0.62 if inner else 0.72
		cylinder.height = 1.94 if inner else 2.10
		cylinder.cap_top = false
		cylinder.radial_segments = 64
		body.mesh = cylinder
		body.material_override = lining if inner else leather
		body.position.y = 0.05 if inner else 0.0
		_cup.add_child(body)
	var lip := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.78
	ring.outer_radius = 0.89
	ring.rings = 64
	ring.ring_segments = 12
	lip.mesh = ring
	lip.material_override = leather
	lip.position.y = 1.05
	_cup.add_child(lip)

func _animate_cup() -> void:
	if is_instance_valid(_cup_tween):
		_cup_tween.kill()
	_cup_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cup_tween.tween_property(_cup, "position", Vector3(4.9, 2.0, 0.4), 0.22)
	_cup_tween.parallel().tween_property(_cup, "rotation:z", 1.9, 0.22)
	_cup_tween.tween_interval(0.22)
	_cup_tween.tween_property(_cup, "position", Vector3(6.3, 1.1, 0.9), 0.32)
	_cup_tween.parallel().tween_property(_cup, "rotation:z", 1.22, 0.32)

func _build_pencil() -> void:
	var pencil := Node3D.new()
	pencil.name = "Lapiz"
	pencil.position = Vector3(-7.6, 0.02, 1.2)
	pencil.rotation_degrees = Vector3(90, 0, -9)
	add_child(pencil)
	for piece in range(4):
		var instance := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.radial_segments = 6 if piece == 0 else 24
		cylinder.top_radius = 0.0 if piece == 1 else 0.075
		cylinder.bottom_radius = 0.075
		cylinder.height = [2.55, 0.35, 0.22, 0.20][piece]
		instance.mesh = cylinder
		instance.position.y = [0.0, 1.45, -1.38, -1.59][piece]
		instance.material_override = _material([Color("dcb237"), Color("b69a73"), Color("9cabb1"), Color("d1c6b6")][piece], 0.7, 0.3 if piece == 2 else 0.0)
		pencil.add_child(instance)

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
	var half_size := Vector2(4.82, 4.54)
	var radius := Vector2(0.94, 0.88)
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
	TabletopUI.build(self)

func _show_home() -> void:
	_close_dialog()
	game = null
	_rolling = false
	camera.v_offset = 0.2
	for i in range(5):
		dice[i].show()
		dice[i].position = Vector3((i - 2) * 1.5, 0.505, 0.8 + sin(i * 1.8) * 0.12)
		dice[i].show_value([5, 3, 1, 6, 2][i], (i - 2) * 0.10)
		rings[i].hide()
	eyebrow.text = "JUEGO DE DADOS"
	heading.add_theme_font_size_override("font_size", 23)
	heading.text = "Generala"
	subtitle.text = ""
	dice_hint.text = ""
	roll_counter.text = "5 dados"
	dice_row.hide()
	controls.hide()
	menu_button.disabled = true
	_show_setup()

func _show_setup() -> void:
	TabletopUI.setup(self)

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
		_die_rest_positions[i] = Vector3((i - 2) * 1.5, 0.505, 0.8)
		dice[i].position = _held_position(i) if game.held[i] else _die_rest_positions[i]
		dice[i].show_value(game.dice[i] if game.dice[i] > 0 else [5, 3, 1, 6, 2][i], 0.0 if game.held[i] else randf_range(-0.15, 0.15))
		dice[i].visible = game.rolls_used > 0

func _refresh() -> void:
	if game == null:
		return
	menu_button.disabled = _rolling
	dice_row.visible = game.rolls_used > 0
	controls.show()
	eyebrow.text = "TURNO DE" if not game.game_over else "FIN DE LA PARTIDA"
	heading.text = game.names[game.current_player] if not game.game_over else "Bien jugado"
	heading.add_theme_font_size_override("font_size", 23)
	subtitle.text = _combination_text() if game.rolls_used > 0 and not _rolling else ""
	for i in range(5):
		var held: bool = game.held[i]
		dice_buttons[i].text = str(i + 1)
		dice_buttons[i].disabled = _rolling or game.rolls_used == 0 or game.rolls_used >= 3 or game.game_over
		_style_button(dice_buttons[i], held)
		for state in ["normal", "disabled"]:
			dice_buttons[i].add_theme_stylebox_override(state, _style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
		dice_buttons[i].add_theme_color_override("font_color", GOLD if held else Color("e8e8dc"))
		dice_buttons[i].add_theme_color_override("font_disabled_color", Color("acae9f"))
		rings[i].visible = held
		rings[i].position = Vector3(dice[i].position.x, 0.425 if held else 0.055, dice[i].position.z)
	TabletopUI.position_dice_controls(self)
	if _rolling:
		dice_hint.text = "Tirando los dados…"
	elif game.rolls_used == 0:
		dice_hint.text = "Hacé clic en el cubilete o pulsá Espacio para tirar."
	elif game.rolls_used == 3:
		dice_hint.text = "Elegí una casilla de la planilla para anotar."
	elif game.held.all(func(v: bool) -> bool: return v):
		dice_hint.text = "Dados guardados. Podés anotar o devolver alguno a la bandeja."
	else:
		dice_hint.text = "Clic en un dado para guardarlo o devolverlo a la bandeja."
	roll_button.disabled = _rolling or not game.can_roll()
	roll_button.text = "ESPACIO   Tirar dados" if game.rolls_used == 0 else "ESPACIO   Volver a tirar"
	if _rolling:
		roll_button.text = "Tirando…"
	elif game.game_over:
		roll_button.text = "Ver resultado"
		roll_button.disabled = false
		dice_hint.text = "La partida terminó. ¿Una más?"
	elif game.rolls_used >= 3:
		roll_button.text = "Anotá en la planilla"
	var remaining: int = 3 - game.rolls_used
	roll_counter.text = "%d %s" % [remaining, "tirada" if remaining == 1 else "tiradas"]
	_show_scorecard()

func _combination_text() -> String:
	for category in [9, 8, 7, 6]:
		var points: int = Rules.score(game.dice, category, game.rolls_used == 1)
		if points > 0:
			return "%s · %d puntos" % [Rules.CATEGORIES[category], points]
	return ""

func _show_scorecard() -> void:
	TabletopUI.scorecard(self)

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
	_animate_cup()
	for i in range(5):
		if not game.held[i]:
			dice[i].show()
			dice[i].toss(Vector3((i - 2) * 1.5, 2.6 + randf() * 0.8, randf_range(-0.6, 0.6)))
	_play("roll", -5.0)
	_refresh()

func _finish_roll() -> void:
	var values: Array[int] = []
	for i in range(5):
		var value := game.dice[i] if game.held[i] else dice[i].top_value()
		values.append(value)
		if not game.held[i]:
			var yaw := dice[i].rotation.y
			dice[i].position = Vector3(clampf(dice[i].position.x, -4.05, 4.05), 0.505, clampf(dice[i].position.z, -2.4, 3.8))
			dice[i].show_value(value, yaw)
			_die_rest_positions[i] = dice[i].position
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
		if game.held[index]:
			_die_rest_positions[index] = dice[index].position
			dice[index].move_to(_held_position(index))
		else:
			dice[index].move_to(_free_position(index))
		_play("select", -5.0)
		_refresh()
		_save_game()

func _free_position(index: int) -> Vector3:
	var candidates: Array[Vector3] = [_die_rest_positions[index]]
	for z in [-1.5, 0.0, 1.5, 3.0]:
		for x in [-3.6, -1.8, 0.0, 1.8, 3.6]:
			candidates.append(Vector3(x, 0.505, z))
	for candidate in candidates:
		var clear := true
		for other in range(5):
			if other != index and not game.held[other] and candidate.distance_to(dice[other].position) < 1.25:
				clear = false
		if clear:
			return candidate
	return candidates[0]

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
	shade.color = Color(0.12, 0.08, 0.035, 0.58)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _style(Color("faf9ed"), Color("c3c2b2"), 8))
	center.add_child(panel)
	var margin := _margin(32, 30, 32, 30)
	panel.add_child(margin)
	var box := _vbox(18)
	margin.add_child(box)
	box.add_child(_label(kicker, 11, MUTED, BOLD))
	var title_label := _label(title, 29, CREAM, BOLD)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)
	var body_label := _label(body, 16, Color("545c56"))
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
	var margin := _margin(12, 18, 12, 18)
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
	var background: Color = GOLD if primary else Color("faf8ee")
	var border: Color = Color("c5a33c") if primary else Color("c9c8ba")
	button.add_theme_stylebox_override("normal", _style(background, border, 18))
	button.add_theme_stylebox_override("hover", _style(Color("fff2b4"), Color("b89c45"), 18))
	button.add_theme_stylebox_override("pressed", _style(Color("e6cc72"), Color("8f8048"), 18))
	button.add_theme_stylebox_override("disabled", _style(Color("e0dfd2"), Color("babbb0"), 18))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("5f8aab"), 18))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, CREAM)
	button.add_theme_color_override("font_disabled_color", Color("9b9e93"))

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
	style.bg_color = Color("c6c8bb")
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
	sound_button.text = "M  Sin sonido" if muted else "M  Sonido"
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
