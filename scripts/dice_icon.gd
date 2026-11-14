extends Control
## Small, vector-drawn dice for the paper score sheet.

var value: int = 1
const PATTERNS: Array = [
	[Vector2(0, 0)],
	[Vector2(-1, -1), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	[Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
]

func _draw() -> void:
	var side := minf(size.x, size.y)
	var origin := (size - Vector2.ONE * side) * 0.5
	var box := StyleBoxFlat.new()
	box.bg_color = Color("414644")
	box.set_corner_radius_all(2)
	draw_style_box(box, Rect2(origin, Vector2.ONE * side))
	for pip: Vector2 in PATTERNS[clampi(value, 1, 6) - 1]:
		draw_circle(origin + Vector2.ONE * side * 0.5 + pip * side * 0.27, side * 0.082, Color("faf9ec"), true, -1, true)
