extends RefCounted
## Procedural meshes for the pieces. Everything is generated, so there are no art assets.


## Box with chamfered top edges, and bottom edges too when `both` is set, so stacked pieces
## show a clear seam between layers. Origin at the bottom centre.
static func bevel_box(w: float, h: float, d: float, b: float, both: bool = false) -> ArrayMesh:
	var hw := w * 0.5
	var hd := d * 0.5
	var rings: Array = []   # each: [y, inset]
	if both:
		rings = [[0.0, b], [b, 0.0], [h - b, 0.0], [h, b]]
	else:
		rings = [[0.0, 0.0], [h - b, 0.0], [h, b]]
	var loops: Array = []
	for r in rings:
		var y: float = r[0]
		var i: float = r[1]
		loops.append([Vector3(-hw + i, y, -hd + i), Vector3(hw - i, y, -hd + i), Vector3(hw - i, y, hd - i), Vector3(-hw + i, y, hd - i)])
	var centre := Vector3(0, h * 0.5, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in loops.size() - 1:
		var lo: Array = loops[k]
		var hi: Array = loops[k + 1]
		for i in 4:
			var j := (i + 1) % 4
			_quad(st, lo[i], lo[j], hi[j], hi[i], centre)
	var top: Array = loops[loops.size() - 1]
	var bot: Array = loops[0]
	_quad(st, top[0], top[1], top[2], top[3], centre)
	_quad(st, bot[3], bot[2], bot[1], bot[0], centre)
	return st.commit()


## Solid of revolution. `profile` is (radius, y) pairs from bottom to top; smooth normals.
static func lathe(profile: PackedVector2Array, segments: int) -> ArrayMesh:
	var n := profile.size()
	var normals: Array[Vector2] = []
	for j in n:
		var a := profile[maxi(j - 1, 0)]
		var c := profile[mini(j + 1, n - 1)]
		var t := c - a
		normals.append(Vector2(t.y, -t.x).normalized())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		for j in n - 1:
			var p: Array[Vector3] = []
			var nn: Array[Vector3] = []
			for k in [[a0, j], [a1, j], [a1, j + 1], [a0, j + 1]]:
				var ang: float = k[0]
				var idx: int = k[1]
				p.append(Vector3(profile[idx].x * cos(ang), profile[idx].y, profile[idx].x * sin(ang)))
				nn.append(Vector3(normals[idx].x * cos(ang), normals[idx].y, normals[idx].x * sin(ang)))
			_tri(st, p[0], p[1], p[2], nn[0], nn[1], nn[2])
			_tri(st, p[0], p[2], p[3], nn[0], nn[2], nn[3])
	return st.commit()


## Cylinder with a rounded dome top, for the capstone.
static func capstone(radius: float, height: float, dome: float) -> ArrayMesh:
	var prof := PackedVector2Array()
	prof.append(Vector2(radius * 0.96, 0.0))
	prof.append(Vector2(radius, 0.02))
	prof.append(Vector2(radius, height - dome))
	for i in range(1, 13):
		var a := deg_to_rad(90.0 * i / 12.0)
		prof.append(Vector2(radius * cos(a), height - dome + dome * sin(a)))
	return lathe(prof, 40)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3) -> void:
	var hint := (a + b + c + d) * 0.25 - centre
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.dot(hint) < 0.0:
		nrm = -nrm
	_tri(st, a, b, c, nrm, nrm, nrm)
	_tri(st, a, c, d, nrm, nrm, nrm)


## Emits a triangle wound for Godot's clockwise front faces, using the given outward normals.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-12:
		return
	if cr.dot(na + nb + nc) > 0.0:
		var tp := b
		b = c
		c = tp
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)
