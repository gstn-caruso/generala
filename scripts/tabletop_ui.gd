extends RefCounted
## Tabletop view: a paper score sheet, contextual controls, and a large 3D tray.

const DiceIcon = preload("res://scripts/dice_icon.gd")
const Rules = preload("res://scripts/rules.gd")
const PAPER := Color("faf9ed")
const INK := Color("383d3d")
const FAINT := Color("858b87")
const LINE := Color("8b8e87")
const YELLOW := Color("ffe172")
const PALE_YELLOW := Color("fff0ac")
const BLUE := Color("57768b")
const PLAYER_COLORS: Array[Color] = [Color("c97256"), Color("698da4"), Color("789b73"), Color("b292bd")]

static func build(host) -> void:
	var layer := CanvasLayer.new()
	host.add_child(layer)
	host.ui = Control.new()
	host.ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = host.FONT
	theme.default_font_size = 16
	host.ui.theme = theme
	layer.add_child(host.ui)
	host.sidebar = PanelContainer.new()
	host.sidebar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	host.sidebar.offset_left = 26
	host.sidebar.offset_right = 414
	host.sidebar.offset_top = 24
	host.sidebar.offset_bottom = -24
	var paper: StyleBoxFlat = host._style(PAPER, Color("d5d2be"), 2)
	paper.shadow_color = Color(0.13, 0.08, 0.035, 0.28)
	paper.shadow_size = 9
	paper.shadow_offset = Vector2(3, 5)
	paper.content_margin_left = 0
	paper.content_margin_right = 0
	host.sidebar.add_theme_stylebox_override("panel", paper)
	host.ui.add_child(host.sidebar)
	# A quiet player marker replaces the previous large title and navigation bar.
	var player := PanelContainer.new()
	player.position = Vector2(474, 28)
	player.size = Vector2(300, 69)
	player.add_theme_stylebox_override("panel", host._style(Color("f8f5e8"), Color("e0d8bf"), 34))
	host.ui.add_child(player)
	var player_margin: MarginContainer = host._margin(24, 10, 24, 10)
	player.add_child(player_margin)
	var player_text: VBoxContainer = host._vbox(1)
	player_margin.add_child(player_text)
	host.eyebrow = host._label("MESA LOCAL", 10, FAINT, host.BOLD)
	host.heading = host._label("Generala", 23, INK, host.BOLD)
	player_text.add_child(host.eyebrow)
	player_text.add_child(host.heading)
	var remaining := PanelContainer.new()
	remaining.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	remaining.offset_left = -285
	remaining.offset_right = -34
	remaining.offset_top = 31
	remaining.offset_bottom = 89
	remaining.add_theme_stylebox_override("panel", host._style(Color("f8f5e8"), Color("e0d8bf"), 29))
	host.ui.add_child(remaining)
	var remaining_margin: MarginContainer = host._margin(20, 5, 20, 5)
	remaining.add_child(remaining_margin)
	var remaining_row := HBoxContainer.new()
	remaining_row.add_theme_constant_override("separation", 12)
	remaining_margin.add_child(remaining_row)
	var icon := DiceIcon.new()
	icon.value = 5
	icon.custom_minimum_size = Vector2(26, 26)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remaining_row.add_child(icon)
	host.roll_counter = host._label("3 tiradas", 22, INK, host.BOLD)
	host.roll_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remaining_row.add_child(host.roll_counter)
	host.dice_row = HBoxContainer.new()
	host.dice_row.add_theme_constant_override("separation", 20)
	host.dice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.ui.add_child(host.dice_row)
	for i in range(5):
		var button: Button = host._button(str(i + 1), host._toggle_die.bind(i))
		button.custom_minimum_size = Vector2(94, 28)
		button.tooltip_text = "Conservar / devolver el dado %d · Tecla %d" % [i + 1, i + 1]
		host.dice_row.add_child(button)
		host.dice_buttons.append(button)
	host.subtitle = host._label("", 17, PAPER, host.BOLD)
	host.subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	host.subtitle.offset_left = -950
	host.subtitle.offset_right = -38
	host.subtitle.offset_top = -203
	host.subtitle.offset_bottom = -173
	host.ui.add_child(host.subtitle)
	host.dice_hint = host._label("", 14, Color("f9f5e8"))
	host.dice_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host.dice_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	host.dice_hint.offset_left = -950
	host.dice_hint.offset_right = -38
	host.dice_hint.offset_top = -100
	host.dice_hint.offset_bottom = -76
	host.dice_hint.add_theme_color_override("font_shadow_color", Color(0.2, 0.10, 0.035, 0.8))
	host.dice_hint.add_theme_constant_override("shadow_offset_y", 1)
	host.ui.add_child(host.dice_hint)
	host.controls = HBoxContainer.new()
	host.controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	host.controls.offset_left = -360
	host.controls.offset_right = -34
	host.controls.offset_top = -72
	host.controls.offset_bottom = -22
	host.ui.add_child(host.controls)
	host.roll_button = host._button("ESPACIO   Tirar dados", host._roll)
	host.roll_button.custom_minimum_size = Vector2(326, 50)
	host.roll_button.add_theme_font_size_override("font_size", 17)
	host.controls.add_child(host.roll_button)
	var options := HBoxContainer.new()
	options.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	options.offset_left = 465
	options.offset_right = 930
	options.offset_top = -66
	options.offset_bottom = -26
	options.add_theme_constant_override("separation", 9)
	host.ui.add_child(options)
	host.menu_button = host._button("ESC  Menú", host._show_pause)
	host.sound_button = host._button("M  Sonido", host._toggle_sound)
	var help: Button = host._button("F1  Reglas", host._show_help)
	for button: Button in [host.menu_button, host.sound_button, help]:
		button.custom_minimum_size = Vector2(115, 40)
		button.add_theme_font_size_override("font_size", 13)
		options.add_child(button)
	host.footer = host._label("", 10, FAINT)
	host.footer.hide()
	host.ui.add_child(host.footer)
	host.ui.resized.connect(func() -> void:
		if host.game != null:
			position_dice_controls(host))
	host.sound_button.text = "M  Sin sonido" if host.muted else "M  Sonido"

static func setup(host) -> void:
	host._clear_sidebar()
	var box: VBoxContainer = host._sidebar_box(14)
	box.add_child(host._label("GENERALA", 31, INK, host.BOLD))
	box.add_child(host._label("Una partida de sobremesa", 15, FAINT))
	box.add_child(host._separator())
	box.add_child(host._label("Prepará la mesa", 22, INK, host.BOLD))
	var count := OptionButton.new()
	count.custom_minimum_size.y = 43
	count.add_theme_color_override("font_color", INK)
	count.add_theme_stylebox_override("normal", host._style(Color("efeee4"), Color("bfc0b4"), 5))
	for title in ["1 jugador · Solitario", "2 jugadores", "3 jugadores", "4 jugadores"]:
		count.add_item(title)
	count.select(host._player_count - 1)
	count.item_selected.connect(func(index: int) -> void:
		host._player_count = index + 1
		setup(host))
	box.add_child(count)
	for i in range(host._player_count):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_avatar(host, str(i + 1), PLAYER_COLORS[i], 38))
		var name := LineEdit.new()
		name.text = host._player_names[i]
		name.placeholder_text = "Jugador %d" % (i + 1)
		name.max_length = 18
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.custom_minimum_size.y = 42
		name.add_theme_color_override("font_color", INK)
		name.add_theme_color_override("caret_color", INK)
		name.add_theme_color_override("selection_color", Color("e5c968"))
		name.add_theme_stylebox_override("normal", host._style(Color("fffef6"), Color("bfc0b4"), 4))
		name.add_theme_stylebox_override("focus", host._style(Color("fff9d8"), Color("b9942c"), 4))
		name.text_changed.connect(func(value: String) -> void: host._player_names[i] = value)
		row.add_child(name)
		box.add_child(row)
	var served := CheckBox.new()
	served.text = "Generala servida gana"
	served.button_pressed = host._served_wins
	served.add_theme_color_override("font_color", INK)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		served.add_theme_color_override(state, INK)
	served.add_theme_font_size_override("font_size", 14)
	served.toggled.connect(func(value: bool) -> void: host._served_wins = value)
	box.add_child(served)
	var start: Button = host._button("Empezar partida", host._start_from_setup, true)
	start.custom_minimum_size.y = 50
	start.add_theme_font_size_override("font_size", 18)
	box.add_child(start)
	var saved = host._read_saved_game()
	if saved != null and not saved.game_over:
		var resume: Button = host._button("Continuar partida", host._resume_game)
		resume.custom_minimum_size.y = 43
		box.add_child(resume)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(air)
	box.add_child(host._separator())
	var rules: Label = host._label("5 dados · 10 rondas\nHasta 3 tiradas por turno", 15, FAINT)
	box.add_child(rules)
	if host.best_score > 0:
		box.add_child(host._label("Récord de la mesa: %d puntos" % host.best_score, 14, INK, host.BOLD))
	box.add_child(host._label("Club de dados · v" + FileAccess.get_file_as_string("res://version.txt").strip_edges(), 11, FAINT))

static func scorecard(host) -> void:
	host._clear_sidebar()
	var game = host.game
	var box: VBoxContainer = host._sidebar_box(10)
	var top := HBoxContainer.new()
	var titles: VBoxContainer = host._vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(host._label("GENERALA", 24, INK, host.BOLD))
	titles.add_child(host._label("Planilla de puntajes", 12, FAINT))
	top.add_child(titles)
	var round_label: Label = host._label("Ronda\n%d / 10" % game.round_number(), 20, INK)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(round_label)
	box.add_child(top)
	var grid := GridContainer.new()
	grid.columns = game.names.size() + 1
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	box.add_child(grid)
	var width: float = 88.0 if game.names.size() == 1 else 70.0 if game.names.size() == 2 else 49.0 if game.names.size() == 3 else 43.0
	var heading: PanelContainer = _cell(host, Color("454a47"), 73)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading_label: Label = host._label("Categorías", 17, PAPER, host.BOLD)
	heading_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	heading.add_child(heading_label)
	grid.add_child(heading)
	for player in range(game.names.size()):
		var active: bool = player == game.current_player
		var cell := _cell(host, PALE_YELLOW if active else PAPER, 73)
		cell.custom_minimum_size.x = width
		var player_box: VBoxContainer = host._vbox(3)
		var avatar := _avatar(host, game.names[player].left(1).to_upper(), PLAYER_COLORS[player], 28 if game.names.size() > 2 else 35)
		avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		player_box.add_child(avatar)
		var player_caption: String = "J%d" % (player + 1) if game.names.size() > 2 else game.names[player].left(8)
		var label: Label = host._label(player_caption, 11, INK, host.BOLD)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.tooltip_text = game.names[player]
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		player_box.add_child(label)
		cell.add_child(player_box)
		grid.add_child(cell)
	for category in range(10):
		if category == 6:
			for column in range(game.names.size() + 1):
				var divider := _cell(host, Color("e5e5d8"), 19)
				if column == 0:
					divider.add_child(host._label("Combinaciones", 11, FAINT))
				grid.add_child(divider)
		var possible: int = game.preview(category)
		var selectable: bool = possible >= 0 and not host._rolling
		var category_cell := _cell(host, PAPER, 47)
		var category_content := HBoxContainer.new()
		category_content.add_theme_constant_override("separation", 7)
		category_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if category < 6:
			var dice_icon := DiceIcon.new()
			dice_icon.value = category + 1
			dice_icon.custom_minimum_size = Vector2(17, 17)
			dice_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dice_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			category_content.add_child(dice_icon)
		else:
			var symbol: Label = host._label(["↗", "3+2", "4×", "5×"][category - 6], 11, INK, host.BOLD)
			symbol.custom_minimum_size.x = 22
			category_content.add_child(symbol)
		var category_name: Label = host._label(Rules.CATEGORIES[category], 16, INK)
		category_content.add_child(category_name)
		category_cell.add_child(category_content)
		category_cell.tooltip_text = Rules.DESCRIPTIONS[category]
		category_cell.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				host._request_score(category))
		category_cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if selectable else Control.CURSOR_ARROW
		grid.add_child(category_cell)
		for player in range(game.names.size()):
			var active: bool = player == game.current_player
			var points: int = game.scores[player][category]
			var content := ""
			var color := INK
			if points >= 0:
				content = str(points) if points > 0 else "×"
			elif active and selectable:
				content = str(possible)
				color = BLUE if possible > 0 else Color("b2a772")
			var button := Button.new()
			button.text = content
			button.custom_minimum_size = Vector2(width, 47)
			button.disabled = not active or not selectable
			button.add_theme_font_override("font", host.BOLD if points >= 0 else host.FONT)
			button.add_theme_font_size_override("font_size", 23)
			button.add_theme_color_override("font_color", color)
			button.add_theme_color_override("font_hover_color", INK)
			button.add_theme_color_override("font_pressed_color", INK)
			button.add_theme_color_override("font_disabled_color", INK)
			var background: Color = PALE_YELLOW if active else PAPER
			for state in ["normal", "disabled"]:
				var normal_style: StyleBoxFlat = host._style(background, LINE, 0)
				normal_style.content_margin_left = 0
				normal_style.content_margin_right = 0
				button.add_theme_stylebox_override(state, normal_style)
			button.add_theme_stylebox_override("hover", host._style(YELLOW, INK, 0))
			button.add_theme_stylebox_override("pressed", host._style(Color("ebc954"), INK, 0))
			button.add_theme_stylebox_override("focus", host._style(Color.TRANSPARENT, BLUE, 0))
			button.tooltip_text = Rules.DESCRIPTIONS[category]
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.pressed.connect(host._request_score.bind(category))
			grid.add_child(button)
	var total_row := HBoxContainer.new()
	total_row.add_theme_constant_override("separation", 0)
	var total_title := _cell(host, Color("454a47"), 48)
	total_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_title.add_child(host._label("Total", 18, PAPER, host.BOLD))
	total_row.add_child(total_title)
	for player in range(game.names.size()):
		var cell := _cell(host, YELLOW if player == game.current_player else PAPER, 48)
		cell.custom_minimum_size.x = width
		var number_style := cell.get_theme_stylebox("panel") as StyleBoxFlat
		number_style.content_margin_left = 2
		number_style.content_margin_right = 2
		var total: Label = host._label(str(game.total(player)), 27 if game.names.size() < 4 else 19, INK, host.BOLD)
		total.clip_text = true
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(total)
		total_row.add_child(cell)
	box.add_child(total_row)
	var air := Control.new()
	air.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(air)
	var note: Label = host._label("Elegí una casilla para anotar.\nUna casilla se usa una sola vez.", 13, FAINT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	box.add_child(host._label("Guardado automático", 10, FAINT))

static func position_dice_controls(host) -> void:
	if host.dice_row == null or host.camera == null:
		return
	var first: Vector2 = host.camera.unproject_position(host._held_position(0))
	var last: Vector2 = host.camera.unproject_position(host._held_position(4))
	var spacing: float = (last.x - first.x) / 4.0
	host.dice_row.position = first + Vector2(-47, 43)
	host.dice_row.size = Vector2(last.x - first.x + 94, 28)
	host.dice_row.add_theme_constant_override("separation", roundi(spacing - 94))

static func _cell(host, background: Color, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = height
	var style: StyleBoxFlat = host._style(background, LINE, 0)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	return panel

static func _avatar(host, initial: String, color: Color, side: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2.ONE * side
	panel.add_theme_stylebox_override("panel", host._style(color, color.lightened(0.25), 40))
	var label: Label = host._label(initial, roundi(side * 0.49), PAPER, host.BOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel
