class_name GeneralaGame
extends RefCounted
## A complete local match. A used category is >= 0; an empty one is -1.

const Rules = preload("res://scripts/rules.gd")
const SAVE_VERSION: int = 1

var names: Array[String] = []
var scores: Array = []
var current_player: int = 0
var rolls_used: int = 0
var dice: Array[int] = [0, 0, 0, 0, 0]
var held: Array[bool] = [false, false, false, false, false]
var game_over: bool = false
var served_wins: bool = true
var served_winner: int = -1

func start(player_names: Array[String], instant_win: bool = true) -> void:
	names.clear()
	for i in range(clampi(player_names.size(), 1, 4)):
		var player_name := player_names[i].strip_edges().left(18) if i < player_names.size() else ""
		names.append(player_name if not player_name.is_empty() else "Jugador %d" % (i + 1))
	scores.clear()
	for _name in names:
		var sheet: Array[int] = []
		sheet.resize(Rules.ROUND_COUNT)
		sheet.fill(-1)
		scores.append(sheet)
	current_player = 0
	game_over = false
	served_wins = instant_win
	served_winner = -1
	_reset_turn()

func can_roll() -> bool:
	return not names.is_empty() and not game_over and rolls_used < 3 and not held.all(func(v: bool) -> bool: return v)

func record_roll(values: Array[int]) -> bool:
	if not can_roll() or not Rules.valid_dice(values):
		return false
	for i in range(5):
		if held[i] and values[i] != dice[i]:
			return false
	dice = values.duplicate()
	rolls_used += 1
	if served_wins and rolls_used == 1 and Rules.score(dice, 9) == 50:
		scores[current_player][9] = 50
		served_winner = current_player
		game_over = true
	return true

func toggle_hold(index: int) -> bool:
	if game_over or rolls_used == 0 or rolls_used >= 3 or index < 0 or index >= 5:
		return false
	held[index] = not held[index]
	return true

func preview(category: int) -> int:
	if not can_score(category):
		return -1
	return Rules.score(dice, category, rolls_used == 1)

func can_score(category: int) -> bool:
	return not game_over and rolls_used > 0 and category >= 0 and category < Rules.ROUND_COUNT and scores[current_player][category] == -1

func choose_category(category: int) -> bool:
	if not can_score(category):
		return false
	scores[current_player][category] = preview(category)
	game_over = scores.all(func(sheet: Array) -> bool: return not sheet.has(-1))
	if not game_over:
		current_player = (current_player + 1) % names.size()
		_reset_turn()
	return true

func total(player: int) -> int:
	var result: int = 0
	for points in scores[player]:
		result += maxi(0, int(points))
	return result

func round_number() -> int:
	if names.is_empty():
		return 1
	return mini(Rules.ROUND_COUNT, Rules.ROUND_COUNT - scores[current_player].count(-1) + 1)

func winners() -> Array[int]:
	if served_winner >= 0:
		return [served_winner]
	var result: Array[int] = []
	var highest: int = -1
	for player in range(names.size()):
		var points := total(player)
		if points > highest:
			highest = points
			result = [player]
		elif points == highest:
			result.append(player)
	return result

func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "names": names, "scores": scores,
		"current_player": current_player, "rolls_used": rolls_used, "dice": dice,
		"held": held, "game_over": game_over, "served_wins": served_wins,
		"served_winner": served_winner}

static func from_dict(data: Dictionary) -> GeneralaGame:
	# Reject malformed or incompatible saves instead of trusting external JSON.
	if data.get("version") != SAVE_VERSION:
		return null
	var saved_names: Variant = data.get("names")
	var saved_scores: Variant = data.get("scores")
	if not saved_names is Array or saved_names.size() < 1 or saved_names.size() > 4:
		return null
	if not saved_scores is Array or saved_scores.size() != saved_names.size():
		return null
	var game := GeneralaGame.new()
	for value in saved_names:
		if not value is String or value.is_empty() or value.length() > 18:
			return null
		game.names.append(value)
	for sheet in saved_scores:
		if not sheet is Array or sheet.size() != Rules.ROUND_COUNT:
			return null
		var clean_sheet: Array[int] = []
		for points in sheet:
			if not (points is float or points is int) or float(points) != int(points) or points < -1 or points > 50:
				return null
			clean_sheet.append(int(points))
		game.scores.append(clean_sheet)
	for key in ["current_player", "rolls_used", "served_winner"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or float(value) != int(value):
			return null
	game.current_player = int(data.current_player)
	game.rolls_used = int(data.rolls_used)
	game.served_winner = int(data.served_winner)
	if game.current_player < 0 or game.current_player >= game.names.size() or game.rolls_used < 0 or game.rolls_used > 3:
		return null
	if game.served_winner < -1 or game.served_winner >= game.names.size():
		return null
	if not data.get("game_over") is bool or not data.get("served_wins") is bool:
		return null
	game.game_over = data.game_over
	game.served_wins = data.served_wins
	var saved_dice: Variant = data.get("dice")
	var saved_held: Variant = data.get("held")
	if not saved_dice is Array or saved_dice.size() != 5 or not saved_held is Array or saved_held.size() != 5:
		return null
	if game.rolls_used > 0 and not Rules.valid_dice(saved_dice):
		return null
	for i in range(5):
		if not saved_held[i] is bool:
			return null
		if game.rolls_used == 0 and (saved_dice[i] != 0 or saved_held[i]):
			return null
		game.dice[i] = int(saved_dice[i])
		game.held[i] = saved_held[i]
	# A normal match must have a consistent, cyclic turn history.
	if game.served_winner >= 0:
		if not game.game_over or not game.served_wins or game.rolls_used != 1 or game.served_winner != game.current_player or Rules.score(game.dice, 9) != 50 or game.scores[game.current_player][9] != 50:
			return null
	elif game.game_over:
		if not game.scores.all(func(sheet: Array) -> bool: return not sheet.has(-1)):
			return null
	else:
		var completed: int = Rules.ROUND_COUNT - game.scores[game.current_player].count(-1)
		if completed >= Rules.ROUND_COUNT:
			return null
		for p in range(game.names.size()):
			if Rules.ROUND_COUNT - game.scores[p].count(-1) != completed + (1 if p < game.current_player else 0):
				return null
	return game

func _reset_turn() -> void:
	rolls_used = 0
	dice = [0, 0, 0, 0, 0]
	held = [false, false, false, false, false]
