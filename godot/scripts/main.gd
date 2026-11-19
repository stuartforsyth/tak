extends Node3D
## Game controller: builds the scene, owns the Rust game, handles input, the HUD and the AI thread.

const BoardView = preload("res://scripts/board_view.gd")
const Wood = preload("res://scripts/wood.gd")

const LEVEL_NAMES := ["Easy", "Medium", "Hard"]
const STONES := {4: 15, 5: 21, 6: 30}
const CAPS := {4: 0, 5: 1, 6: 1}
const DIRS := {"+": Vector2i(0, 1), "-": Vector2i(0, -1), "<": Vector2i(-1, 0), ">": Vector2i(1, 0)}

var game: TakGame
var view: Node3D
var camera: Camera3D
var size := 5
var level := 1
var human_white := true
var piece_kind := "F"
var stacks := {}
var legal: PackedStringArray
var sel := {}                  # movement in progress: src, n, dir, drops
var hover_sq := ""
var thinking := false
var demo_shot := ""
var cam_offset := Vector3(0, 8, 7)
var _move_re := RegEx.create_from_string("^(\\d?)([a-h][1-8])([+\\-<>])(\\d*)$")

var status: Label
var banner: Label
var kind_buttons := {}
var undo_btn: Button
var carry_label: Label
var size_opt: OptionButton
var level_opt: OptionButton
var side_opt: OptionButton


func _ready() -> void:
	_build_scene()
	_build_hud()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot="):
			demo_shot = a.substr(7)
		elif a.begins_with("--size="):
			size = int(a.substr(7))
	_new_game()
	if demo_shot != "":
		_run_demo(args)
	elif "--selftest" in args:
		_run_selftest()


# ---- scene -------------------------------------------------------------------

func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.03, 0.028)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.13, 0.11)
	sky_mat.sky_horizon_color = Color(0.42, 0.34, 0.27)
	sky_mat.ground_horizon_color = Color(0.35, 0.26, 0.18)
	sky_mat.ground_bottom_color = Color(0.05, 0.04, 0.03)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.35
	key.rotation_degrees = Vector3(-52, -32, 0)
	key.shadow_enabled = true
	key.light_angular_distance = 1.4
	key.directional_shadow_max_distance = 30.0
	add_child(key)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 0.5
	fill.omni_range = 40.0
	fill.position = Vector3(-7, 6, 8)
	add_child(fill)

	var table := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	table.mesh = pm
	var tm := Wood.make(Color(0.17, 0.11, 0.075), Color(0.075, 0.045, 0.032), 77, 0.55, 0.12, 5)
	table.material_override = tm
	table.position.y = 0.0
	add_child(table)

	view = BoardView.new()
	add_child(view)
	camera = Camera3D.new()
	camera.fov = 36
	add_child(camera)
	camera.make_current()
	get_viewport().size_changed.connect(_fit_camera)


func _frame_camera() -> void:
	cam_offset = Vector3(0, size * 0.9 + 2.4, size * 1.0 + 3.2)
	camera.attributes = CameraAttributesPractical.new()
	_fit_camera()


## Pull the camera back on narrow windows so the whole board stays in frame, and keep the
## depth-of-field focus on the board.
func _fit_camera() -> void:
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var tan_half_h := tan(deg_to_rad(camera.fov) * 0.5) * aspect
	var need := (size + 1.3) * 0.55 / tan_half_h
	var back := maxf(1.0, need / cam_offset.length())
	camera.look_at_from_position(cam_offset * back, Vector3(0, 0.15, 0.1))
	var attr := camera.attributes as CameraAttributesPractical
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = cam_offset.length() * back + size * 0.9
	attr.dof_blur_far_transition = 10.0
	attr.dof_blur_amount = 0.05


# ---- HUD ---------------------------------------------------------------------

func _panel(anchor_pos: Control.LayoutPreset) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.05, 0.04, 0.78)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	sb.border_color = Color(0.55, 0.40, 0.22, 0.8)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_and_offsets_preset(anchor_pos, Control.PRESET_MODE_MINSIZE, 16)
	if anchor_pos == Control.PRESET_TOP_RIGHT:
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif anchor_pos == Control.PRESET_CENTER_BOTTOM:
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
		p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return p


func _build_hud() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var theme := Theme.new()
	theme.default_font_size = 18
	ui.add_child(Control.new())

	# Top-left: status.
	var sp := _panel(Control.PRESET_TOP_LEFT)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 22)
	status.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	sp.add_child(status)
	ui.add_child(sp)

	# Top-right: new game controls.
	var cp := _panel(Control.PRESET_TOP_RIGHT)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	size_opt = _option(cv, "Board", ["4x4", "5x5", "6x6"], size - 4)
	level_opt = _option(cv, "Engine", LEVEL_NAMES, level)
	side_opt = _option(cv, "You play", ["White (first)", "Black"], 0)
	var nb := Button.new()
	nb.text = "New game"
	nb.pressed.connect(_on_new_pressed)
	cv.add_child(nb)
	cp.add_child(cv)
	ui.add_child(cp)

	# Bottom-centre: piece picker.
	var bp := _panel(Control.PRESET_CENTER_BOTTOM)
	var bv := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for k in ["F", "S", "C"]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(150, 40)
		b.pressed.connect(_on_kind.bind(k))
		row.add_child(b)
		kind_buttons[k] = b
	kind_buttons["F"].button_pressed = true
	undo_btn = Button.new()
	undo_btn.text = "Undo (U)"
	undo_btn.custom_minimum_size = Vector2(110, 40)
	undo_btn.pressed.connect(_undo)
	row.add_child(undo_btn)
	bv.add_child(row)
	carry_label = Label.new()
	carry_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.55))
	carry_label.add_theme_font_size_override("font_size", 15)
	carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(carry_label)
	bp.add_child(bv)
	ui.add_child(bp)

	banner = Label.new()
	banner.add_theme_font_size_override("font_size", 64)
	banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override("outline_size", 12)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 90)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.visible = false
	ui.add_child(banner)


func _option(parent: Control, caption: String, items: Array, selected: int) -> OptionButton:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = caption
	l.custom_minimum_size = Vector2(80, 0)
	h.add_child(l)
	var o := OptionButton.new()
	for i in items:
		o.add_item(i)
	o.select(selected)
	h.add_child(o)
	parent.add_child(h)
	return o


func _on_new_pressed() -> void:
	size = 4 + size_opt.selected
	level = level_opt.selected
	human_white = side_opt.selected == 0
	_new_game()


func _on_kind(k: String) -> void:
	piece_kind = k


# ---- game flow ---------------------------------------------------------------

func _new_game() -> void:
	thinking = false
	sel = {}
	game = TakGame.create(size)
	view.setup(size)
	_frame_camera()
	banner.visible = false
	_refresh(false)
	if not human_turn() and demo_shot == "":
		_start_ai()


func human_turn() -> bool:
	return game.white_to_move() == human_white


func _refresh(animate: bool, ptn: String = "") -> void:
	stacks = BoardView.parse_tps(game.tps(), size)
	legal = game.legal_moves()
	view.show_position(stacks, animate, ptn)
	_update_marks()
	_update_hud()


func _update_hud() -> void:
	var out := game.outcome()
	banner.visible = out != 0
	undo_btn.disabled = not _can_undo()
	if out != 0:
		var who := "Draw" if out == 3 else ("White wins" if out == 1 else "Black wins")
		banner.text = who + "!"
		status.text = "Game over"
	elif thinking:
		status.text = "Engine is thinking..."
	elif _opening():
		status.text = "Place a flat stone: it goes to your opponent"
	elif sel.is_empty():
		status.text = "Your move" if human_turn() else "Engine to move"
	else:
		status.text = "Moving a stack: click where it goes"
	var mine := "1" if human_white else "2"
	var used := 0
	var caps_used := 0
	for sq in stacks:
		var s: String = stacks[sq]
		var top_cap := s.ends_with("C")
		var digits := s.substr(0, s.length() - (1 if (top_cap or s.ends_with("S")) else 0))
		used += digits.count(mine)
		if top_cap and digits.ends_with(mine):
			caps_used += 1
	var caps_total: int = CAPS[size]
	var stones_left: int = STONES[size] - (used - caps_used)
	kind_buttons["F"].text = "Flat   x%d" % stones_left
	kind_buttons["S"].text = "Wall   x%d" % stones_left
	kind_buttons["C"].text = "Cap   x%d" % (caps_total - caps_used)
	kind_buttons["C"].visible = caps_total > 0
	kind_buttons["S"].visible = not _opening()
	kind_buttons["C"].visible = caps_total > 0 and not _opening()
	if _opening():
		piece_kind = "F"
		kind_buttons["F"].button_pressed = true
	if sel.is_empty():
		carry_label.text = "F / S / C choose a piece. Click a stack of yours to move it."
	elif sel["dir"] == "":
		carry_label.text = "Carrying %d (keys 1-%d or wheel). Click a neighbouring square. Right-click cancels." % [sel["n"], _max_carry(sel["src"])]
	else:
		carry_label.text = "%d left to drop. Same square drops more, next square moves on." % _remaining()


func _opening() -> bool:
	var n := 0
	for sq in stacks:
		n += 1
	return n < 2 and legal.size() > 0 and _count_pieces() < 2


func _count_pieces() -> int:
	var c := 0
	for sq in stacks:
		var s: String = stacks[sq]
		c += s.length() - (1 if (s.ends_with("S") or s.ends_with("C")) else 0)
	return c


func _start_ai() -> void:
	thinking = true
	game.start_ai(level)
	_update_hud()


func _process(_dt: float) -> void:
	if not thinking:
		return
	var r := game.poll_ai()
	if r.is_empty():
		return
	thinking = false
	var err := game.play(r["move"])
	if err != "":
		push_error("engine produced an illegal move: " + err)
	_refresh(true, r["move"])


# ---- input -------------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var sq := _pick(ev.position)
		if sq != hover_sq:
			hover_sq = sq
			view.set_hover(sq if _can_act() else "")
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			var sq := _pick(ev.position)
			if sq != "":
				_click(sq)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_carry(1)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_carry(-1)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_F: _select_kind("F")
			KEY_S: _select_kind("S")
			KEY_C: _select_kind("C")
			KEY_ESCAPE: _cancel()
			KEY_U: _undo()
			KEY_Z:
				if ev.ctrl_pressed:
					_undo()
			_:
				if ev.keycode >= KEY_1 and ev.keycode <= KEY_8 and not sel.is_empty() and sel["dir"] == "":
					_set_carry(ev.keycode - KEY_0)


func _select_kind(k: String) -> void:
	if k == "S" and _opening() or k == "C" and (_opening() or CAPS[size] == 0):
		return
	piece_kind = k
	kind_buttons[k].button_pressed = true


func _can_act() -> bool:
	return not thinking and game.outcome() == 0 and human_turn()


func _pick(pos: Vector2) -> String:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	var hit = Plane(Vector3.UP, BoardView.BOARD_TOP).intersects_ray(o, d)
	if hit == null:
		return ""
	return view.world_to_square(hit)


func _click(sq: String) -> void:
	if not _can_act():
		return
	if sel.is_empty():
		var st: String = stacks.get(sq, "")
		if st == "":
			_place(sq)
		elif not _opening() and _top_owner(st) == ("1" if human_white else "2"):
			_begin_move(sq)
		return
	_move_click(sq)


func _top_owner(st: String) -> String:
	var digits := st.substr(0, st.length() - (1 if (st.ends_with("S") or st.ends_with("C")) else 0))
	return digits.substr(digits.length() - 1)


func _place(sq: String) -> void:
	var ptn := sq if piece_kind == "F" else piece_kind + sq
	if ptn in legal:
		_play_human(ptn)


func _play_human(ptn: String) -> void:
	var err := game.play(ptn)
	if err != "":
		push_warning(err)
		return
	sel = {}
	_refresh(true, ptn)
	if game.outcome() == 0:
		_start_ai()


# ---- undo --------------------------------------------------------------------

## Undo needs at least one move of the human's to take back.
func _can_undo() -> bool:
	return game.plies() >= (1 if human_white else 2)


## Takes back the human's last move and the engine's reply, so it is the human's turn again.
## While the engine is thinking, its search is abandoned and only the human's move goes.
func _undo() -> void:
	if not sel.is_empty():
		_cancel()
		return
	if not _can_undo():
		return
	thinking = false
	game.undo()
	if not human_turn() and _can_undo():
		game.undo()
	_refresh(false)


# ---- stack movement ----------------------------------------------------------

func _max_carry(src: String) -> int:
	var s: String = stacks[src]
	var h := s.length() - (1 if (s.ends_with("S") or s.ends_with("C")) else 0)
	return mini(h, size)


func _begin_move(src: String) -> void:
	sel = {"src": src, "n": _max_carry(src), "dir": "", "drops": []}
	_update_marks()
	_update_hud()


func _cancel() -> void:
	if not sel.is_empty():
		sel = {}
		_update_marks()
		_update_hud()


func _adjust_carry(delta: int) -> void:
	if not sel.is_empty() and sel["dir"] == "":
		_set_carry(sel["n"] + delta)


func _set_carry(n: int) -> void:
	sel["n"] = clampi(n, 1, _max_carry(sel["src"]))
	_update_marks()
	_update_hud()


func _remaining() -> int:
	var t := 0
	for d in sel["drops"]:
		t += d
	return sel["n"] - t


func _ptn_for(n: int, src: String, dir: String, drops: Array, complete: bool) -> String:
	var s := (str(n) if n > 1 else "") + src + dir
	if dir != "" and not (complete and drops.size() == 1):
		for d in drops:
			s += str(d)
	return s


## Is this (possibly partial) drop sequence the start of a legal move? A partial sequence may
## still grow: its last square can take more stones, or further squares can follow.
func _ok(n: int, src: String, dir: String, drops: Array) -> bool:
	var k := drops.size()
	for m in legal:
		var g := _move_re.search(m)
		if g == null or g.get_string(2) != src or g.get_string(3) != dir:
			continue
		var mn := int(g.get_string(1)) if g.get_string(1) != "" else 1
		if mn != n:
			continue
		var md: Array = []
		if g.get_string(4) == "":
			md = [mn]
		else:
			for ch in g.get_string(4):
				md.append(int(ch))
		if md.size() < k or md[k - 1] < drops[k - 1]:
			continue
		var same := true
		for i in k - 1:
			if md[i] != drops[i]:
				same = false
		if same and (md.size() == k and md[k - 1] == drops[k - 1] or _sum(drops) < n):
			return true
	return false


func _offset(src: String, dir: String, steps: int) -> String:
	var f: int = src.unicode_at(0) - 97 + int(DIRS[dir].x) * steps
	var r: int = int(src.substr(1)) + int(DIRS[dir].y) * steps
	if f < 0 or f >= size or r < 1 or r > size:
		return ""
	return char(97 + f) + str(r)


## Squares the next click may land on, given the current movement state.
func _next_targets() -> Array:
	var out := []
	if sel.is_empty():
		return out
	var src: String = sel["src"]
	var n: int = sel["n"]
	if sel["dir"] == "":
		for dir in DIRS:
			var sq := _offset(src, dir, 1)
			if sq != "" and _ok(n, src, dir, [1]):
				out.append(sq)
	elif _remaining() > 0:
		var dir: String = sel["dir"]
		var drops: Array = sel["drops"]
		var same := drops.duplicate()
		same[same.size() - 1] += 1
		if _ok(n, src, dir, same):
			out.append(_offset(src, dir, drops.size()))
		var nxt := drops.duplicate()
		nxt.append(1)
		var sq := _offset(src, dir, nxt.size())
		if sq != "" and _ok(n, src, dir, nxt):
			out.append(sq)
	return out


func _sum(a: Array) -> int:
	var t := 0
	for v in a:
		t += v
	return t


func _update_marks() -> void:
	view.set_marks(_next_targets(), sel["src"] if not sel.is_empty() else "")
	if sel.is_empty():
		view.set_lift("", 0)
	else:
		view.set_lift(sel["src"], _remaining() if sel["dir"] != "" else sel["n"])


func _move_click(sq: String) -> void:
	var src: String = sel["src"]
	if sq == src:
		_cancel()
		return
	if not sq in _next_targets():
		return
	var n: int = sel["n"]
	if sel["dir"] == "":
		for dir in DIRS:
			if _offset(src, dir, 1) == sq:
				sel["dir"] = dir
				sel["drops"] = [1]
	else:
		var drops: Array = sel["drops"]
		if _offset(src, sel["dir"], drops.size()) == sq:
			drops[drops.size() - 1] += 1
		else:
			drops.append(1)
	if _remaining() == 0:
		_play_human(_ptn_for(n, src, sel["dir"], sel["drops"], true))
	else:
		_update_marks()
		_update_hud()


# ---- screenshot demo ---------------------------------------------------------

func _run_demo(args: PackedStringArray) -> void:
	var plies := 14
	for a in args:
		if a.begins_with("--plies="):
			plies = int(a.substr(8))
	if "--stackdemo" in args:
		for m in ["d4", "a4", "a1", "d3", "b1", "c4", "a1>", "c3", "a1", "c2", "a1>", "d2"]:
			game.play(m)
		_refresh(false)
		if "--slide" in args:
			game.play("3b1>12")
			_refresh(true, "3b1>12")
		elif not "--nosel" in args:
			_click("b1")
			_set_carry(2)
	else:
		for i in plies:
			if game.outcome() != 0:
				break
			var r := game.ai_move(0)
			game.play(r["move"])
		_refresh(false)
	var wait := 1.2
	for a in args:
		if a.begins_with("--wait="):
			wait = float(a.substr(7))
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(demo_shot)
	get_tree().quit()


# ---- self-test (godot --path godot -- --selftest) ----------------------------

func _wait_ai() -> void:
	while thinking:
		await get_tree().process_frame
	await get_tree().process_frame


func _run_selftest() -> void:
	var fails := 0
	for sq in view.get_all_squares():
		var got := _pick(camera.unproject_position(view.square_pos(sq)))
		if got != sq:
			print("FAIL pick ", sq, " -> ", got)
			fails += 1
	print("pick round-trip: ", "ok" if fails == 0 else "FAILED")
	_click("a1")                       # opening: places a black stone
	await _wait_ai()
	var count_a := _count_pieces()
	print("after opening: ", count_a, " pieces (expect 2)")
	_click("c3")                       # own flat
	await _wait_ai()
	print("own flat placed: ", stacks.get("c3", "") == "1", " pieces=", _count_pieces())
	_undo()
	print("undo: pieces=", _count_pieces(), " (expect 2), human to move: ", human_turn(), ", c3 empty: ", not stacks.has("c3"))
	_click("c3")
	await _wait_ai()
	# Undo while the engine is thinking: only the human's move is taken back.
	var empty := ""
	for sq in view.get_all_squares():
		if not stacks.has(sq):
			empty = sq
			break
	_click(empty)
	print("placed on ", empty, "; thinking: ", thinking, " (expect true)")
	_undo()
	print("undo mid-search: thinking=", thinking, " pieces=", _count_pieces(), " (expect 4), human to move: ", human_turn())
	await get_tree().create_timer(0.8).timeout
	print("no stale engine move applied: pieces=", _count_pieces(), " (expect 4)")
	_click("c3")
	var targets := _next_targets()
	print("move targets from c3: ", targets)
	if not targets.is_empty():
		var dest: String = targets[0]
		_click(dest)
		print("moved c3 -> ", dest, ": c3=", stacks.get("c3", "-"), " ", dest, "=", stacks.get(dest, "-"))
	await _wait_ai()
	print("legal moves still generated: ", legal.size() > 0)

	# Multi-drop stack move on 4x4: build a white stack of three on b1, then carry it east.
	size = 4
	human_white = true
	_new_game()
	for m in ["d4", "a4", "a1", "d3", "b1", "c4", "a1>", "c3", "a1", "c2", "a1>", "d2"]:
		var err := game.play(m)
		if err != "":
			print("FAIL setup ", m, ": ", err)
	_refresh(false)
	print("stack on b1: ", stacks.get("b1", ""), " (expect 111)")
	_click("b1")
	print("carry: ", sel.get("n"), " targets: ", _next_targets())
	_click("c1")
	print("after c1: ", sel, " targets ", _next_targets())
	_click("d1")
	print("after d1: ", sel, " targets ", _next_targets())
	_click("d1")
	print("result: b1=", stacks.get("b1", "-"), " c1=", stacks.get("c1", "-"), " d1=", stacks.get("d1", "-"), " (expect - 1 11)")
	await _wait_ai()
	get_tree().quit()
