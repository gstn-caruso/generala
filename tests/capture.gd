extends SceneTree
## Visual QA: xvfb-run godot --path . --script tests/capture.gd -- --test-mode

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1440, 900)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/generala-menu.png")
	var names: Array[String] = ["Gastón", "Martina"]
	var values: Array[int] = [4, 4, 4, 2, 2]
	main._start_game(names, false)
	main.game.record_roll(values)
	main.game.toggle_hold(0)
	main.game.toggle_hold(1)
	main.game.toggle_hold(2)
	main._reset_dice_display()
	main._refresh()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/generala-juego.png")
	main._show_help()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/generala-reglas.png")
	main._show_home()
	main._player_count = 4
	main._show_setup()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/generala-cuatro.png")
	var four_names: Array[String] = ["Gastón", "Martina", "Jugador 3", "Jugador 4"]
	main._start_game(four_names, false)
	main.game.record_roll(values)
	main._reset_dice_display()
	main._refresh()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/generala-planilla-cuatro.png")
	print("Capturas guardadas en /tmp/generala-{menu,juego,reglas,cuatro}.png")
	main.queue_free()
	await process_frame
	quit()
