extends SceneTree
## Run: godot --headless --path . --script tests/test_game.gd

const Rules = preload("res://scripts/rules.gd")
const Game = preload("res://scripts/game.gd")
var checks: int = 0
var failures: int = 0

func _init() -> void:
	_test_rules_exhaustively()
	_test_turns()
	_test_full_matches()
	_test_served()
	_test_saves()
	print("Generala: %d comprobaciones, %d errores." % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _test_rules_exhaustively() -> void:
	var frequencies: Array[int] = [0, 0, 0, 0]
	for encoded in range(7776):
		var values: Array[int] = []
		var n := encoded
		for _i in range(5):
			values.append(n % 6 + 1)
			n /= 6
		for category in range(6):
			check(Rules.score(values, category) == values.count(category + 1) * (category + 1), "Suma numérica incorrecta")
		for category in range(6, 10):
			var score := Rules.score(values, category)
			var served := Rules.score(values, category, true)
			check(served == score + (5 if score > 0 and category < 9 else 0), "Bonus servido incorrecto")
			if score > 0:
				frequencies[category - 6] += 1
	check(frequencies == [240, 300, 156, 6], "Frecuencias combinatorias incorrectas: %s" % str(frequencies))
	for invalid in [[], [1, 2, 3], [0, 1, 2, 3, 4], [1, 2, 3, 4, 7], [1, 2, 3, 4, 1.5], ["1", 2, 3, 4, 5]]:
		check(not Rules.valid_dice(invalid), "Se aceptaron dados inválidos")
	check(Rules.score([1, 2, 3, 4, 5], -1) == 0, "Categoría negativa aceptada")
	check(Rules.score([1, 2, 3, 4, 5], 10) == 0, "Categoría fuera de rango aceptada")
	check(Rules.score([6, 6, 6, 6, 6], 7) == 0, "Una generala no es full")

func _test_turns() -> void:
	var game := Game.new()
	game.start(["Ana", "Luis"], false)
	check(not game.can_score(0), "Se puede anotar antes de tirar")
	check(not game.toggle_hold(0), "Se puede guardar antes de tirar")
	check(game.record_roll([1, 2, 3, 4, 5]), "Primera tirada rechazada")
	check(game.preview(6) == 25, "Escalera servida incorrecta")
	check(game.toggle_hold(0), "No se pudo guardar dado")
	check(not game.record_roll([2, 2, 3, 4, 5]), "Se modificó un dado guardado")
	check(game.rolls_used == 1, "Una tirada inválida consume intento")
	for i in range(1, 5):
		game.toggle_hold(i)
	check(not game.can_roll(), "Se puede tirar con todos guardados")
	game.toggle_hold(4)
	check(game.record_roll([1, 2, 3, 4, 6]), "Segunda tirada rechazada")
	check(game.record_roll([1, 2, 3, 4, 5]), "Tercera tirada rechazada")
	check(not game.can_roll(), "Se puede tirar una cuarta vez")
	check(not game.toggle_hold(0), "Se puede cambiar selección tras tercera tirada")
	check(game.preview(6) == 20, "Bonus aplicado en tercera tirada")
	check(game.choose_category(6), "No se pudo anotar escalera")
	check(game.current_player == 1 and game.rolls_used == 0 and game.dice == [0, 0, 0, 0, 0], "El turno no se reinició")
	check(game.total(0) == 20 and game.total(1) == 0, "Totales incorrectos")
	game.record_roll([1, 1, 1, 1, 2])
	game.choose_category(8)
	game.record_roll([1, 2, 3, 4, 5])
	check(not game.choose_category(6), "Se reutilizó una categoría")
	check(game.choose_category(7), "No se pudo tachar full")
	check(game.scores[0][7] == 0, "Tachadura incorrecta")

func _test_full_matches() -> void:
	for player_count in range(1, 5):
		var game := Game.new()
		var names: Array[String] = []
		for player in range(player_count):
			names.append("Jugador %d" % player)
		game.start(names, false)
		for round_index in range(10):
			for player in range(player_count):
				check(game.round_number() == round_index + 1, "Ronda incorrecta")
				check(game.current_player == player, "Turno incorrecto")
				check(game.record_roll([1, 2, 3, 4, 5]), "Tirada de partida completa rechazada")
				check(game.choose_category(round_index), "Casilla de partida completa rechazada")
				check(Game.from_dict(JSON.parse_string(JSON.stringify(game.to_dict()))) != null, "Guardado válido no recuperable")
		check(game.game_over, "La partida no terminó tras 10 rondas")
		check(not game.can_roll(), "Se puede tirar tras fin de partida")
		check(not game.choose_category(0), "Se puede anotar tras fin")
		check(game.winners().size() == player_count, "Empate no compartido")
		for player in range(player_count):
			check(game.total(player) == 40, "Total final incorrecto")

func _test_served() -> void:
	var game := Game.new()
	game.start(["Ana", "Luis"])
	game.record_roll([1, 2, 3, 4, 5])
	game.choose_category(6)
	game.record_roll([3, 3, 3, 3, 3])
	check(game.game_over and game.served_winner == 1, "Generala servida no termina partida")
	check(game.winners() == [1] and game.total(1) == 50, "Ganador de servida incorrecto")
	check(Game.from_dict(JSON.parse_string(JSON.stringify(game.to_dict()))) != null, "Generala servida no se puede cargar")
	game.start(["Ana"], false)
	game.record_roll([3, 3, 3, 3, 3])
	check(not game.game_over and game.preview(9) == 50, "Opción servida desactivada no se respeta")
	game.start(["Ana"], true)
	game.record_roll([1, 2, 3, 4, 5])
	game.record_roll([3, 3, 3, 3, 3])
	check(not game.game_over and game.preview(9) == 50, "Generala no servida termina partida")

func _test_saves() -> void:
	var game := Game.new()
	game.start(["  ", "Un nombre exageradamente largo"], false)
	check(game.names[0] == "Jugador 1" and game.names[1].length() == 18, "Normalización de nombres incorrecta")
	game.record_roll([1, 2, 3, 4, 5])
	game.toggle_hold(2)
	var data: Dictionary = JSON.parse_string(JSON.stringify(game.to_dict()))
	var restored := Game.from_dict(data)
	check(restored != null and restored.dice == game.dice and restored.held == game.held and restored.rolls_used == 1, "Estado guardado difiere del original")
	for key in data.keys():
		var broken := data.duplicate(true)
		broken.erase(key)
		check(Game.from_dict(broken) == null, "Campo obligatorio faltante aceptado: %s" % key)
	for pair in [["current_player", 9], ["rolls_used", 4], ["dice", [7, 2, 3, 4, 5]], ["held", [1, 2]], ["scores", []], ["names", []], ["game_over", "false"], ["served_winner", 8]]:
		var broken := data.duplicate(true)
		broken[pair[0]] = pair[1]
		check(Game.from_dict(broken) == null, "Guardado corrupto aceptado: %s" % pair[0])
