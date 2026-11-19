extends RefCounted
## Procedural meshes for the pieces. Everything is generated, so there are no art assets.


## Box with the top edges chamfered by `b`. Origin at the bottom centre.
static func bevel_box(w: float, h: float, d: float, b: float) -> ArrayMesh:
	var hw := w * 0.5
	var hd := d * 0.5
	var yb := h - b
	var ring0: Array[Vector3] = [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]
	var ring1: Array[Vector3] = [Vector3(-hw, yb, -hd), Vector3(hw, yb, -hd), Vector3(hw, yb, hd), Vector3(-hw, yb, hd)]
	var ring2: Array[Vector3] = [Vector3(-hw + b, h, -hd + b), Vector3(hw - b, h, -hd + b), Vector3(hw - b, h, hd - b), Vector3(-hw + b, h, hd - b)]
	var centre := Vector3(0, h * 0.5, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, ring0[i], ring0[j], ring1[j], ring1[i], centre)
		_quad(st, ring1[i], ring1[j], ring2[j], ring2[i], centre)
	_quad(st, ring2[0], ring2[1], ring2[2], ring2[3], centre)
	_quad(st, ring0[3], ring0[2], ring0[1], ring0[0], centre)
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
