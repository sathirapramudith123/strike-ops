class_name MeshBuilder
extends RefCounted
## Builds one ArrayMesh from many primitive parts (boxes, cylinders, spheres,
## limbs). Colours go into the vertices (see assets/shaders/model.gdshader), so
## a whole model is ONE surface and one draw call; parts marked "armor" go into
## a second surface that can be tinted per player (team colour). Used for the
## weapon and player models until real art replaces them.
##
##   var b := MeshBuilder.new()
##   b.box(&"steel", Vector3(0.06, 0.09, 0.4), Vector3.ZERO)
##   b.cylinder_z(&"steel", 0.012, 0.28, Vector3(0, 0.015, -0.34))
##   var mesh := b.build()

## Colour (sRGB) and metalness of each part type. "armor" is white: tinted.
const MATERIALS := {
	&"steel": [Color(0.2, 0.21, 0.22), 0.7],
	&"polymer": [Color(0.1, 0.1, 0.11), 0.0],
	&"tan": [Color(0.55, 0.47, 0.34), 0.0],
	&"olive": [Color(0.3, 0.34, 0.24), 0.0],
	&"wood": [Color(0.45, 0.28, 0.15), 0.0],
	&"lens": [Color(0.2, 0.38, 0.55), 0.9],
	&"fabric": [Color(0.22, 0.24, 0.22), 0.0],
	&"gear": [Color(0.13, 0.13, 0.12), 0.0],
	&"skin": [Color(0.78, 0.62, 0.5), 0.0],
	&"visor": [Color(0.06, 0.07, 0.08), 0.8],
	&"armor": [Color(1, 1, 1), 0.0],
	&"glove": [Color(0.1, 0.1, 0.09), 0.0],
	&"glove_pad": [Color(0.2, 0.19, 0.16), 0.0],
	&"sleeve": [Color(0.42, 0.41, 0.32), 0.0],
}
const TINTED := &"armor"

static var _shared_material: ShaderMaterial

var _groups: Dictionary = {} # "base" / "tint" -> { v, n, c, i }


## The one material all built models share (duplicate it to tint).
static func shared_material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = preload("res://assets/shaders/model.gdshader")
	return _shared_material


func box(mat: StringName, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	_add(mat, m, _xform(pos, rot_deg))


## Cylinder along -Z (the barrel direction): `r_front` at the -Z end.
func cylinder_z(mat: StringName, radius: float, length: float, pos: Vector3,
		r_front: float = -1.0, segments: int = 8) -> void:
	_add(mat, _cylinder(radius if r_front < 0.0 else r_front, radius, length, segments), _xform(pos, Vector3(-90, 0, 0)))


func cylinder_y(mat: StringName, radius: float, height: float, pos: Vector3, segments: int = 8) -> void:
	_add(mat, _cylinder(radius, radius, height, segments), _xform(pos, Vector3.ZERO))


func cylinder_x(mat: StringName, radius: float, length: float, pos: Vector3, segments: int = 6) -> void:
	_add(mat, _cylinder(radius, radius, length, segments), _xform(pos, Vector3(0, 0, 90)))


func sphere(mat: StringName, radius: float, pos: Vector3, scale: Vector3 = Vector3.ONE,
		hemisphere: bool = false, segments: int = 8) -> void:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * (1.0 if hemisphere else 2.0)
	m.is_hemisphere = hemisphere
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 3)
	_add(mat, m, Transform3D(Basis.from_scale(scale), pos))


## A limb from point a to point b (tapered cylinder).
func limb(mat: StringName, a: Vector3, b: Vector3, r_a: float, r_b: float = -1.0, segments: int = 6) -> void:
	var d := b - a
	var m := _cylinder(r_b if r_b > 0.0 else r_a, r_a, d.length(), segments)
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD) if absf(up.dot(Vector3.FORWARD)) < 0.99 else up.cross(Vector3.RIGHT)
	var basis := Basis(side.normalized(), up, side.normalized().cross(up)).orthonormalized()
	_add(mat, m, Transform3D(basis, (a + b) * 0.5))


## Surface 0: everything else; surface 1 (if any armor parts): the tinted part.
func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in ["base", "tint"]:
		if not _groups.has(key):
			continue
		var g: Dictionary = _groups[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_COLOR] = g.c
		arrays[Mesh.ARRAY_INDEX] = g.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_material(idx, shared_material())
		mesh.surface_set_name(idx, "armor" if key == "tint" else "base")
	return mesh


## Index of the tinted (armor) surface of a built mesh, or -1.
static func surface_of(mesh: Mesh, mat: StringName) -> int:
	for i in mesh.get_surface_count():
		if (mesh as ArrayMesh).surface_get_name(i) == ("armor" if mat == TINTED else "base"):
			return i
	return -1


## A copy of the shared material with a tint (per player, for team colours).
static func tinted_material() -> ShaderMaterial:
	return shared_material().duplicate() as ShaderMaterial


func _add(mat: StringName, primitive: PrimitiveMesh, xform: Transform3D) -> void:
	var key := "tint" if mat == TINTED else "base"
	if not _groups.has(key):
		_groups[key] = { "v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array() }
	var g: Dictionary = _groups[key]
	var spec: Array = MATERIALS.get(mat, [Color.MAGENTA, 0.0])
	var color: Color = spec[0]
	color.a = spec[1]
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base: int = g.v.size()
	var nbasis := xform.basis.inverse().transposed()
	for k in verts.size():
		g.v.append(xform * verts[k])
		g.n.append((nbasis * normals[k]).normalized())
		g.c.append(color)
	for k in indices.size():
		g.i.append(base + indices[k])


static func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func _xform(pos: Vector3, rot_deg: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos)
