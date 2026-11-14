class_name GeneralaRules
extends RefCounted
## Scoring is independent of the scene, UI, and physics.

const CATEGORIES: Array[String] = [
	"Unos", "Doses", "Treses", "Cuatros", "Cincos", "Seises",
	"Escalera", "Full", "Póker", "Generala",
]
const DESCRIPTIONS: Array[String] = [
	"Sumá todos los dados con un punto.", "Sumá todos los dados con dos puntos.",
	"Sumá todos los dados con tres puntos.", "Sumá todos los dados con cuatro puntos.",
	"Sumá todos los dados con cinco puntos.", "Sumá todos los dados con seis puntos.",
	"1–2–3–4–5 o 2–3–4–5–6. Vale 20; servida, 25.",
	"Tres iguales y un par. Vale 30; servido, 35.",
	"Cuatro o cinco iguales. Vale 40; servido, 45.",
	"Cinco iguales. Vale 50. La servida puede ganar la partida.",
]
const ROUND_COUNT: int = 10

static func valid_dice(dice: Array) -> bool:
	if dice.size() != 5:
		return false
	for value in dice:
		if not (value is int or value is float) or float(value) != int(value) or value < 1 or value > 6:
			return false
	return true

static func score(dice: Array, category: int, served: bool = false) -> int:
	if not valid_dice(dice) or category < 0 or category >= CATEGORIES.size():
		return 0
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	for value in dice:
		counts[int(value) - 1] += 1
	if category < 6:
		return counts[category] * (category + 1)
	var bonus: int = 5 if served else 0
	match category:
		6:
			if counts == [1, 1, 1, 1, 1, 0] or counts == [0, 1, 1, 1, 1, 1]:
				return 20 + bonus
		7:
			if counts.has(3) and counts.has(2):
				return 30 + bonus
		8:
			if counts.max() >= 4:
				return 40 + bonus
		9:
			if counts.max() == 5:
				return 50
	return 0
