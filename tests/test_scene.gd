extends SceneTree
## Real scene + physics integration. Uses --test-mode to leave user saves alone.

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	check(main.dice.size() == 5, "Faltan dados en la mesa")
	for die in main.dice:
		# Native KayKit D6_B orientations, checked visually against the source mesh.
		# This catches a face map that is internally consistent but reads wrong pips.
		var native_faces: Array[Vector3] = [Vector3.UP, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.DOWN]
		var native_values: Array[int] = [6, 4, 2, 5, 3, 1]
		for face in range(6):
			die.quaternion = Quaternion(native_faces[face], Vector3.UP)
			check(die.top_value() == native_values[face], "El valor no coincide con los puntos originales de KayKit")
		for value in range(1, 7):
			die.show_value(value, randf() * TAU)
			check(die.top_value() == value, "La cara visible no coincide con su valor")
	var names: Array[String] = ["Ana", "Luis"]
	main._start_game(names, false)
	main._roll()
	check(main._rolling, "La tirada no comenzó")
	await _wait_for_roll(main)
	check(main.game.rolls_used == 1, "La primera tirada no se registró")
	check(GeneralaRules.valid_dice(main.game.dice), "La física devolvió valores inválidos")
	# Exercise the actual viewport input route, including GUI mouse filtering.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = main.camera.unproject_position(main.dice[0].global_position)
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await process_frame
	check(main.game.held[0], "El clic en el dado 3D no conserva el dado")
	var held_value: int = main.game.dice[0]
	var held_position: Vector3 = main.dice[0].position
	main._roll()
	await _wait_for_roll(main)
	check(main.game.rolls_used == 2, "La segunda tirada no se registró")
	check(main.game.dice[0] == held_value, "Se alteró el valor conservado")
	check(main.dice[0].position.is_equal_approx(held_position), "Se movió el dado conservado")
	main._roll()
	await _wait_for_roll(main)
	check(main.game.rolls_used == 3 and main.roll_button.disabled, "No se respeta el límite de tiradas")
	for die in main.dice:
		check(die.freeze and die.top_alignment() > 0.99 and absf(die.position.y - 0.505) < 0.01, "Dado final inestable")
	for category in range(10):
		if main.game.preview(category) == 0:
			main._request_score(category)
			check(is_instance_valid(main.dialog) and main.game.scores[0][category] == -1, "Tachar cero no pide confirmación")
			main._close_dialog()
			break
	main._commit_score(0)
	check(main.game.current_player == 1 and main.game.rolls_used == 0, "La planilla no avanza el turno")
	# Use a separate temporary save path; never touch the user's match or settings.
	main._save_path = "user://prueba-%d.json" % Time.get_ticks_usec()
	main._test_mode = false
	main._save_game()
	check(FileAccess.file_exists(main._save_path), "No se escribió el guardado")
	var values: Array[int] = [2, 2, 3, 4, 5]
	main.game.record_roll(values)
	main.game.toggle_hold(0)
	main._save_game()
	var expected: String = JSON.stringify(main.game.to_dict())
	main._show_home()
	main._resume_game()
	check(main.game != null and JSON.stringify(main.game.to_dict()) == expected, "Continuar no recupera el archivo guardado")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main._save_path))
	main._test_mode = true
	main._show_help()
	check(is_instance_valid(main.dialog), "No se abren las reglas")
	main._close_dialog()
	main._show_pause()
	check(is_instance_valid(main.dialog), "No se abre el menú")
	main._show_home()
	check(main.game == null and not is_instance_valid(main.dialog), "No se vuelve al inicio")
	main._player_count = 4
	main._show_setup()
	await process_frame
	await process_frame
	check(main.sidebar.get_global_rect().end.y <= main.ui.size.y - 10, "El panel para cuatro jugadores desborda la ventana")
	var four_names: Array[String] = ["Nombre bastante la", "Jugador 2", "Jugador 3", "Jugador 4"]
	main._start_game(four_names, false)
	await process_frame
	await process_frame
	check(main.sidebar.get_global_rect().end.y <= main.ui.size.y - 10, "La planilla para cuatro jugadores desborda la ventana")
	print("Escena 3D: %d errores." % failures)
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _wait_for_roll(main: Node) -> void:
	var frames: int = 0
	while main._rolling and frames < 600:
		await physics_frame
		frames += 1
	check(not main._rolling, "La tirada no termina")
