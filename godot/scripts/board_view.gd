extends Node3D
## The 3D board: frame, squares, coordinate labels, stacks of stones and the highlights.

const MeshLib = preload("res://scripts/mesh_lib.gd")
const Wood = preload("res://scripts/wood.gd")

const BOARD_TOP := 0.25
const FLAT_H := 0.2
const STONE := 0.62
const WALL_H := STONE      # a wall is a flat stone turned on its edge
const WALL_T := FLAT_H
const CAP_R := 0.24
const CAP_H := 0.7
const LIFT := 0.22
const BAR := 0.5

var size := 5
var _pieces: Node3D
var _marks: Node3D
var _road: Node3D
var _prev := {}
var _nodes := {}   # square -> Array of piece nodes, bottom to top
var _slides := {}  # square -> { from: Vector3 world, count: int, group: int } for the move being shown
var _move_re := RegEx.create_from_string("^(\\d?)([a-h][1-8])([+\\-<>])(\\d*)$")
var _flat_mesh: ArrayMesh
var _wall_mesh: ArrayMesh
var _cap_mesh: ArrayMesh
var _white: StandardMaterial3D
var _black: StandardMaterial3D
var _hover: MeshInstance3D
var _mark_mat: StandardMaterial3D
var coords_visible := true
var counts_visible := false
var _yaw := 0.0   # camera orbit angle in radians; flat labels turn with it so they stay upright
var _coord_labels: Array[Label3D] = []


func setup(board_size: int) -> void:
	size = board_size
	for c in get_children():
		c.queue_free()
	_prev = {}
	_nodes = {}
	_coord_labels = []
	_flat_mesh = MeshLib.bevel_box(STONE, FLAT_H, STONE, 0.04, true)
	_wall_mesh = MeshLib.bevel_box(STONE, WALL_H, WALL_T, 0.04, true)
	_cap_mesh = MeshLib.capstone(CAP_R, CAP_H, 0.22)
	_white = Wood.make(Color(0.90, 0.80, 0.63), Color(0.74, 0.61, 0.44), 11, 0.38, 0.9, 5)
	_black = Wood.make(Color(0.27, 0.16, 0.11), Color(0.11, 0.065, 0.045), 23, 0.36, 0.9, 5)
	_build_board()
	_pieces = Node3D.new()
	add_child(_pieces)
	_marks = Node3D.new()
	add_child(_marks)
	_road = Node3D.new()
	add_child(_road)
	_make_hover()


func _build_board() -> void:
	var frame := Wood.make(Color(0.31, 0.17, 0.10), Color(0.14, 0.075, 0.045), 5, 0.4, 0.5, 4)
	# One playing surface: every square is the same wood, cut from a slightly different part of
	# the plank, with grooves between them. No chequering.
	var tiles: Array[StandardMaterial3D] = []
	for sd in [31, 47, 59, 71]:
		tiles.append(Wood.make(Color(0.64, 0.49, 0.32), Color(0.48, 0.34, 0.21), sd, 0.45, 0.7, 5))
	var field := float(size)
	var outer := field + 2.0 * BAR
	# Underlay beneath the squares, then four border bars standing slightly proud of them.
	var under := MeshInstance3D.new()
	under.mesh = MeshLib.bevel_box(field + 0.02, 0.2, field + 0.02, 0.0)
	under.material_override = frame
	add_child(under)
	var bars := [
		[Vector3(outer, 0.27, BAR), Vector3(0, 0, -(field + BAR) * 0.5)],
		[Vector3(outer, 0.27, BAR), Vector3(0, 0, (field + BAR) * 0.5)],
		[Vector3(BAR, 0.27, field), Vector3(-(field + BAR) * 0.5, 0, 0)],
		[Vector3(BAR, 0.27, field), Vector3((field + BAR) * 0.5, 0, 0)],
	]
	for b in bars:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.bevel_box(b[0].x, b[0].y, b[0].z, 0.05)
		mi.material_override = frame
		mi.position = b[1]
		add_child(mi)
	var tile_mesh := MeshLib.bevel_box(0.95, BOARD_TOP - 0.2, 0.95, 0.012)
	for f in size:
		for r in size:
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			mi.material_override = tiles[hash(Vector2i(f, r)) % tiles.size()]
			mi.position = Vector3(_x(f), 0.2, _z(r + 1))
			add_child(mi)
	for i in size:
		var letter := char(97 + i)
		_label(letter, Vector3(_x(i), 0.275, (field + BAR) * 0.5))
		_label(letter, Vector3(_x(i), 0.275, -(field + BAR) * 0.5))
		_label(str(i + 1), Vector3(-(field + BAR) * 0.5, 0.275, _z(i + 1)))
		_label(str(i + 1), Vector3((field + BAR) * 0.5, 0.275, _z(i + 1)))


func _label(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = 0.0055
	l.modulate = Color(0.86, 0.68, 0.36)
	l.outline_size = 0
	l.rotation_degrees = _flat_rot()
	l.add_to_group("flat_label")
	l.position = pos
	l.visible = coords_visible
	_coord_labels.append(l)
	add_child(l)


func _flat_rot() -> Vector3:
	return Vector3(-90, rad_to_deg(_yaw), 0)


## Turn every flat label with the camera so the text keeps reading the right way up.
func set_yaw(yaw: float) -> void:
	_yaw = yaw
	for l in get_tree().get_nodes_in_group("flat_label"):
		(l as Label3D).rotation_degrees = _flat_rot()
	for b in get_tree().get_nodes_in_group("count_label"):
		(b as Node3D).position = _badge_pos(b.get_meta("top_y"))


func set_counts(on: bool) -> void:
	counts_visible = on
	for b in get_tree().get_nodes_in_group("count_label"):
		(b as Node3D).visible = on


func set_coords(on: bool) -> void:
	coords_visible = on
	for l in _coord_labels:
		l.visible = on


func _make_hover() -> void:
	_hover = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(0.92, 0.92)
	_hover.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.92, 0.7, 0.22)
	_hover.material_override = m
	_hover.visible = false
	_hover.position.y = BOARD_TOP + 0.003
	add_child(_hover)
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_mat.albedo_color = Color(0.45, 1.0, 0.75)
	_mark_mat.emission_enabled = true
	_mark_mat.emission = Color(0.3, 1.0, 0.7)
	_mark_mat.emission_energy_multiplier = 1.6


# ---- coordinates -------------------------------------------------------------

func _x(file: int) -> float:
	return file - (size - 1) * 0.5


## Rank 1 is nearest the camera (+z).
func _z(rank: int) -> float:
	return (size + 1) * 0.5 - rank


func square_name(file: int, rank: int) -> String:
	return char(97 + file) + str(rank)


func get_all_squares() -> Array:
	var out := []
	for f in size:
		for r in range(1, size + 1):
			out.append(square_name(f, r))
	return out


func square_pos(sq: String) -> Vector3:
	return Vector3(_x(sq.unicode_at(0) - 97), BOARD_TOP, _z(int(sq.substr(1))))


## Square under a world point on the board plane, or "" when off the board.
func world_to_square(p: Vector3) -> String:
	var f := int(floor(p.x + size * 0.5))
	var r := int(round((size + 1) * 0.5 - p.z))
	if f < 0 or f >= size or r < 1 or r > size:
		return ""
	return square_name(f, r)


# ---- position ----------------------------------------------------------------

## "1,x,1S,2/x3,.. 1 4" -> { "a1": "12", "c4": "1S" } bottom-to-top, trailing S/C marks the top piece.
static func parse_tps(tps: String, n: int) -> Dictionary:
	var out := {}
	var rows := tps.split(" ")[0].split("/")
	for ri in rows.size():
		var rank := n - ri
		var file := 0
		for cell in rows[ri].split(","):
			if cell.begins_with("x"):
				file += 1 if cell.length() == 1 else int(cell.substr(1))
			else:
				out[char(97 + file) + str(rank)] = cell
				file += 1
	return out


## `ptn` is the move just played; a stack move makes its stones fly from the source square.
func show_position(stacks: Dictionary, animate: bool, ptn: String = "") -> void:
	for c in _pieces.get_children():
		c.queue_free()
	_nodes = {}
	_slides = _slides_for(ptn) if animate else {}
	for sq in stacks:
		var changed: bool = animate and _prev.get(sq, "") != stacks[sq]
		_pieces.add_child(_build_stack(sq, stacks[sq], changed))
	_prev = stacks.duplicate()


## For a stack move, where each landing square's new stones came from.
func _slides_for(ptn: String) -> Dictionary:
	var out := {}
	var g := _move_re.search(ptn)
	if g == null:
		return out
	var n := int(g.get_string(1)) if g.get_string(1) != "" else 1
	var src := g.get_string(2)
	var dir := g.get_string(3)
	var drops: Array = []
	if g.get_string(4) == "":
		drops = [n]
	else:
		for ch in g.get_string(4):
			drops.append(int(ch))
	var step := {"+": Vector2i(0, 1), "-": Vector2i(0, -1), "<": Vector2i(-1, 0), ">": Vector2i(1, 0)}[dir] as Vector2i
	var f := src.unicode_at(0) - 97
	var r := int(src.substr(1))
	for k in drops.size():
		f += step.x
		r += step.y
		out[square_name(f, r)] = {"from": square_pos(src), "count": drops[k], "group": k}
	return out


func _build_stack(sq: String, s: String, animate: bool) -> Node3D:
	var root := Node3D.new()
	root.position = square_pos(sq)
	var mod := ""
	if s.ends_with("S") or s.ends_with("C"):
		mod = s.substr(s.length() - 1)
		s = s.substr(0, s.length() - 1)
	var y := 0.0
	var seed_base := hash(sq)
	var top_y := 0.0
	var nodes: Array = []
	for i in s.length():
		var white := s[i] == "1"
		var top := i == s.length() - 1
		var piece := MeshInstance3D.new()
		piece.material_override = _white if white else _black
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_base + i * 7919
		var jitter := Vector3(rng.randf_range(-0.012, 0.012), 0, rng.randf_range(-0.012, 0.012))
		var yaw := rng.randf_range(-1.6, 1.6)
		var h := FLAT_H
		if top and mod == "S":
			piece.mesh = _wall_mesh
			piece.rotation_degrees = Vector3(0, yaw * 0.5, 0)
			h = WALL_H
		elif top and mod == "C":
			piece.mesh = _cap_mesh
			h = CAP_H
		else:
			piece.mesh = _flat_mesh
			piece.rotation_degrees = Vector3(0, yaw, 0)
		piece.position = jitter + Vector3(0, y, 0)
		root.add_child(piece)
		piece.set_meta("base_y", y)
		nodes.append(piece)
		top_y = y + h
		var slide: Variant = _slides.get(sq)
		if slide != null:
			if i >= s.length() - int(slide["count"]):
				_slide_in(piece, root.position, slide, i - (s.length() - int(slide["count"])))
		elif animate:
			var final_y := y
			piece.position.y = final_y + 0.9
			var tw := piece.create_tween()
			tw.tween_property(piece, "position:y", final_y, 0.3).set_delay(0.05 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		y += h if not (top and mod != "") else 0.0
	_nodes[sq] = nodes
	if nodes.size() >= 2:
		_add_count(root, nodes.size(), top_y)
	return root


## Fly a stone from the source square to its place, in a low arc. Later landing squares wait
## for the earlier ones, so the stack visibly deals out along the line.
func _slide_in(piece: Node3D, dest_world: Vector3, slide: Dictionary, index_in_group: int) -> void:
	var to := piece.position
	var from := (slide["from"] as Vector3) - dest_world + Vector3(0, to.y + 0.25, 0)
	var delay := 0.16 * int(slide["group"]) + 0.05 * index_in_group
	piece.visible = false
	var tw := piece.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(piece.show)
	tw.tween_method(func(t: float) -> void:
		piece.position = from.lerp(to, t) + Vector3(0, 0.3 * sin(PI * t), 0), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Stack height as a small badge floating above the stack: a dark opaque disc with the number
## on it. It always faces the camera and stays the same size on screen, whatever the distance.
func _add_count(root: Node3D, count: int, top_y: float) -> void:
	var badge := Node3D.new()
	badge.set_meta("top_y", top_y)
	badge.position = _badge_pos(top_y)
	badge.visible = counts_visible
	badge.add_to_group("count_label")
	var disc := Sprite3D.new()
	disc.texture = _badge_texture()
	disc.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	disc.fixed_size = true
	disc.no_depth_test = true
	disc.shaded = false
	disc.pixel_size = 0.0006
	disc.render_priority = 0
	badge.add_child(disc)
	var l := Label3D.new()
	l.text = str(count)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.shaded = false
	l.font_size = 30
	l.outline_size = 0
	l.pixel_size = 0.0006
	l.render_priority = 1
	l.modulate = Color(1.0, 0.92, 0.72)
	badge.add_child(l)
	root.add_child(badge)


## Just in front of the stack's top, toward the camera, so on screen it sits against its own
## stack rather than above it, where it would read as belonging to the square behind.
func _badge_pos(top_y: float) -> Vector3:
	return Vector3(sin(_yaw) * 0.36, top_y - 0.04, cos(_yaw) * 0.36)


## Opaque dark disc with a thin gold rim, drawn once.
static var _badge_tex: ImageTexture

func _badge_texture() -> ImageTexture:
	if _badge_tex != null:
		return _badge_tex
	var d := 40
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	for y in d:
		for x in d:
			var r := Vector2(x - c, y - c).length()
			var col := Color(0.10, 0.06, 0.035, 1.0)
			if r > c - 2.5:
				col = Color(0.85, 0.65, 0.3, 1.0)
			col.a = clampf(c + 0.5 - r, 0.0, 1.0)
			img.set_pixel(x, y, col)
	_badge_tex = ImageTexture.create_from_image(img)
	return _badge_tex


## Lift the top `n` stones of a stack so the player sees how many are in hand.
func set_lift(sq: String, n: int) -> void:
	for key in _nodes:
		var nodes: Array = _nodes[key]
		for i in nodes.size():
			var lifted: bool = key == sq and i >= nodes.size() - n
			var node: Node3D = nodes[i]
			var want := (node.get_meta("base_y") as float) + (LIFT if lifted else 0.0)
			if absf(node.position.y - want) > 0.001:
				node.create_tween().tween_property(node, "position:y", want, 0.12).set_ease(Tween.EASE_OUT)


# ---- highlights --------------------------------------------------------------

func set_hover(sq: String) -> void:
	_hover.visible = sq != ""
	if sq != "":
		var p := square_pos(sq)
		_hover.position = Vector3(p.x, BOARD_TOP + 0.003, p.z)


## Rings on the squares the player may click next; `selected` gets a gold ring.
func set_marks(targets: Array, selected: String) -> void:
	for c in _marks.get_children():
		c.queue_free()
	for sq in targets:
		_ring(sq, _mark_mat, 0.34)
	if selected != "":
		var gold := _mark_mat.duplicate() as StandardMaterial3D
		gold.albedo_color = Color(1.0, 0.8, 0.3)
		gold.emission = Color(1.0, 0.75, 0.25)
		_ring(selected, gold, 0.42)


## Glow under the squares of a winning road; an empty list clears it. After a move it waits
## for the stones to land, then pulses gently.
func show_road(squares: Array, animate: bool) -> void:
	for c in _road.get_children():
		c.queue_free()
	if squares.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.8, 0.3, 0.0 if animate else 0.55)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.25)
	m.emission_energy_multiplier = 1.4
	var q := PlaneMesh.new()
	q.size = Vector2(0.95, 0.95)
	for sq in squares:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var p := square_pos(sq)
		mi.position = Vector3(p.x, BOARD_TOP + 0.006, p.z)
		_road.add_child(mi)
	var tw := _road.get_child(0).create_tween()
	if animate:
		tw.tween_interval(0.9)
	tw.tween_property(m, "albedo_color:a", 0.55, 0.4)
	var pulse := _road.get_child(0).create_tween().set_loops()
	pulse.tween_interval(1.4 if animate else 0.4)
	pulse.tween_property(m, "emission_energy_multiplier", 2.4, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(m, "emission_energy_multiplier", 1.0, 0.9).set_trans(Tween.TRANS_SINE)


func _ring(sq: String, mat: Material, radius: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = radius - 0.035
	t.outer_radius = radius
	t.rings = 48
	t.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat
	mi.scale = Vector3(1, 0.25, 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var p := square_pos(sq)
	mi.position = Vector3(p.x, BOARD_TOP + 0.01, p.z)
	_marks.add_child(mi)
