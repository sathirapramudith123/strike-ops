"""Rebuilds Factory's art (assets/maps/factory/factory.glb) from the greybox.

Run inside Blender with assets/maps/factory/src/factory.blend open, after
`python3 tools/greybox.py` and
`godot --headless --path . --script res://tools/export_blockout.gd factory`:

    exec(open(r"<repo>/tools/factory_art.py").read())

It drops the old art (every mesh outside the Detail collection) and the old
near-play-area detail (Near*), imports assets/blockouts/factory.glb, gives
each mesh the textured material of its greybox kind (Mat_brick, Mat_concrete
...; floors get Mat_ground), box-projects world-space UVs at each texture's
real size (`tex_size`, metres per tile), and exports the meshes that have
art to factory.glb. Then it dresses the walls for the Detail layer
(near_detail: gutters, downpipes, electrical boxes, pipes along low indoor
walls) and exports factory_detail.glb. Meshes whose kind has no texture (glass, lamps, signs'
paint ...) stay greybox in the game. Far scenery (Far_*) is kept.
"""
import bpy, bmesh, os, sys, io

# <repo>/assets/maps/factory/src/factory.blend
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(bpy.data.filepath)))))
ROOT = os.path.join(REPO, "assets", "maps", "factory")
BLOCKOUT = os.path.join(REPO, "assets", "blockouts", "factory.glb")
DET = bpy.data.collections["Detail"]
# Real prop models (PropSources collection, bottom-centred, not exported
# themselves): CC0 Poly Haven barrels, CC BY Sketchfab crate / container /
# forklift (docs/CREDITS.md).
PROPS_SRC = bpy.data.collections["PropSources"]
DRUMS = {"Mat_blue": "Prop_drum_blue", "Mat_steel_blue": "Prop_drum_blue", "Mat_teal": "Prop_drum_plastic"}
# Greybox parts a real prop stands in for (dropped from the art).
PROP_PARTS = ("DrumLid", "ContainerEnd", "ForkliftFrame", "ForkliftRoof", "ForkliftMast", "Fork",
              "ForkliftWheel")

# Kinds the greybox uses that the art paints from an existing texture:
# new material = copy of `src` with its tint colour set.
DERIVED = {
    "Mat_plaster": ("Mat_sandstone", (0.62, 0.56, 0.45, 1)),
    "Mat_paving": ("Mat_floor_dark", (0.36, 0.33, 0.28, 1)),
    "Mat_teal": ("Mat_blue", (0.03, 0.18, 0.17, 1)),
    "Mat_silver": ("Mat_cable", (0.42, 0.44, 0.46, 1)),
    "Mat_office_wall": ("Mat_sandstone", (0.66, 0.65, 0.6, 1)),
    "Mat_sack": ("Mat_sandstone", (0.42, 0.3, 0.17, 1)),
}
# Objects (by name prefix) that get a different material than their kind.
FLOORS = ("Floor", "Ground")


def derive():
    for name, (src, color) in DERIVED.items():
        if name in bpy.data.materials:
            continue
        m = bpy.data.materials[src].copy()
        m.name = name
        mix = next(n for n in m.node_tree.nodes if n.type == "MIX")
        mix.inputs[7].default_value = color


def make_glass():
    """Mat_glass: an industrial window made in code - 2 x 2 grimy panes per
    1.1 m tile in dark steel glazing bars, lighter towards the top (the sky
    in it), glossy glass and rough frames. 512 px."""
    import numpy as np
    if "Mat_glass" in bpy.data.materials and "tex_size" in bpy.data.materials["Mat_glass"]:
        return
    n = 512
    rng = np.random.default_rng(5)
    y, x = np.mgrid[0:n, 0:n] / n
    bar = 0.035
    fx = np.minimum((x % 0.5), 0.5 - (x % 0.5)) < bar / 2 + 0.004
    fy = np.minimum((y % 0.5), 0.5 - (y % 0.5)) < bar / 2 + 0.004
    frame = fx | fy
    # Soft grime: blurred noise (sum of a few upsampled random grids).
    grime = np.zeros((n, n))
    for k, w in ((8, 0.5), (32, 0.3), (128, 0.2)):
        g = rng.random((k, k))
        grime += w * np.kron(g, np.ones((n // k, n // k)))
    pane_y = (y % 0.5) / 0.5  # 0 at the top of each pane (image row 0 = top)
    sky = 0.42 - 0.22 * pane_y
    col = np.stack([sky * 0.82, sky * 0.92, sky * 1.0], -1)
    col *= (0.75 + 0.35 * grime)[..., None]
    col[frame] = (0.09, 0.09, 0.1)
    rough = np.where(frame, 0.65, 0.08 + 0.3 * grime)
    def img(name, rgb):
        im = bpy.data.images.new(name, n, n, alpha=False)
        a = np.ones((n, n, 4), np.float32)
        a[..., :3] = rgb
        im.pixels.foreach_set(a[::-1].ravel())
        im.file_format = "JPEG"
        im.pack()
        return im
    base = img("glass_window_Base", col)
    r = img("glass_window_Rough", np.repeat(rough[..., None], 3, -1))
    m = bpy.data.materials.get("Mat_glass") or bpy.data.materials.new("Mat_glass")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], next(nd for nd in nt.nodes if nd.type == "OUTPUT_MATERIAL").inputs[0])
    tb = nt.nodes.new("ShaderNodeTexImage")
    tb.image = base
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = r
    r.colorspace_settings.name = "Non-Color"
    nt.links.new(tb.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    m["tex_size"] = 1.1


def clear_old():
    for o in list(bpy.data.objects):
        if DET in o.users_collection and not o.name.startswith("Near"):
            continue
        if PROPS_SRC in o.users_collection:
            continue
        bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


def world_uv(o):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new()
    mw = o.matrix_world
    nmw = mw.to_3x3().inverted().transposed()
    for f in bm.faces:
        s = float(o.material_slots[f.material_index].material.get("tex_size", 1.0))
        n = (nmw @ f.normal).normalized()
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            p = mw @ l.vert.co
            if ax == 0:
                u, v = (p.y if n.x > 0 else -p.y), p.z
            elif ax == 1:
                u, v = (-p.x if n.y > 0 else p.x), p.z
            else:
                u, v = p.x, (p.y if n.z > 0 else -p.y)
            l[uv].uv = (u / s, v / s)
    bm.to_mesh(me)
    bm.free()


def import_blockout():
    before = set(bpy.data.objects)
    # Into the scene's own collection (not whichever one was left active).
    bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        bpy.ops.import_scene.gltf(filepath=BLOCKOUT)
    finally:
        sys.stdout = old
    new = [o for o in bpy.data.objects if o not in before]
    art, plain = [], 0
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        ok = True
        for slot in o.material_slots:
            base = slot.material.name.split(".")[0] if slot.material else ""
            if base == "Mat_concrete" and o.name.startswith(FLOORS):
                base = "Mat_ground"
            m = bpy.data.materials.get(base)
            if m is None or "tex_size" not in m:
                ok = False
                break
            slot.material = m
        if not ok:
            bpy.data.objects.remove(o, do_unlink=True)
            plain += 1
            continue
        # Clear the import's parenting so world-space UVs and export match.
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        art.append(o)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY" and not o.children]:
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    for o in art:
        world_uv(o)
    return art, plain


def replace_props(art):
    """Swaps greybox props for the real models, fitted to each prop's box
    (its collision stays the greybox's): drums (red oil drum, blue steel or
    blue plastic by colour), crates, containers (in the greybox colour, as
    textured copies), forklifts, delivery trucks, coconut palms, air-con
    units and boxes of goods on the pallets. Returns the new art list."""
    from mathutils import Matrix, Vector
    out, n = [], 0
    for o in art:
        base = o.name.rstrip("0123456789").split(".")[0]
        if base in PROP_PARTS:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if base not in ("Drum", "Crate", "Container", "Forklift", "Truck", "PalmTrunk", "AirCon", "Goods"):
            out.append(o)
            continue
        vs = [v.co for v in o.data.vertices]
        lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
        hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
        size = hi - lo
        bottom = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
        mat = o.material_slots[0].material.name
        place = o.matrix_world.copy()
        if base == "Drum":
            src = bpy.data.objects[DRUMS.get(mat, "Prop_drum_red")]
            s_ = size.z / src.dimensions.z
            fit = Matrix.Translation(bottom) @ Matrix.Rotation(n * 1.3, 4, "Z") @ Matrix.Scale(s_, 4)
        elif base == "Crate":
            src = bpy.data.objects["Prop_crate"]
            d = src.dimensions
            fit = Matrix.Translation(bottom) @ Matrix.Diagonal((size.x / d.x, size.y / d.y, size.z / d.z, 1.0))
        elif base == "Container":
            src = bpy.data.objects["Prop_container"]
            d = src.dimensions
            fit = Matrix.Translation(bottom) @ Matrix.Diagonal((size.x / d.x, size.y / d.y, size.z / d.z, 1.0))
        elif base == "Truck":
            # Front towards local +Y in Blender (the greybox's -Z), like the model.
            src = bpy.data.objects["Prop_truck"]
            fit = Matrix.Translation(bottom) @ Matrix.Scale(size.y / src.dimensions.y, 4)
        elif base == "PalmTrunk":
            src = bpy.data.objects["Prop_palm"]
            fit = Matrix.Translation(bottom) @ Matrix.Rotation(n * 2.1, 4, "Z") @ Matrix.Scale(size.z / src.dimensions.z, 4)
        elif base == "AirCon":
            src = bpy.data.objects["Prop_aircon"]
            fit = Matrix.Translation(bottom) @ Matrix.Scale(size.z / src.dimensions.z, 4)
        elif base == "Goods":
            src = bpy.data.objects["Prop_boxes"]
            d = src.dimensions
            fit = Matrix.Translation(bottom) @ Matrix.Diagonal((size.x / d.x, size.y / d.y, size.z / d.z, 1.0))
        else:
            # Forklift: the greybox body is the rear 2 m; the forks reach
            # 1.1 m past its front (local +Y in Blender = the greybox's -Z).
            src = bpy.data.objects["Prop_forklift"]
            fit = Matrix.Translation(bottom + Vector((0, 0.55, 0))) @ Matrix.Rotation(3.14159265, 4, "Z")
        name = o.name
        bpy.data.objects.remove(o, do_unlink=True)
        p = src.copy()
        if base == "Container":
            p.data = src.data.copy()
            p.data.materials[0] = bpy.data.materials[mat]
            p.data.materials[1] = bpy.data.materials["Mat_metal"]
        bpy.context.scene.collection.objects.link(p)
        p.matrix_world = place @ fit
        p.name = name
        if base == "Container":
            world_uv(p)
        out.append(p)
        n += 1
    return out, n


def export(art):
    for o in bpy.data.objects:
        o.select_set(False)
    for o in art:
        o.select_set(True)
    bpy.context.view_layer.objects.active = art[0]
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "factory.glb"), export_format="GLB",
                                  use_selection=True, export_image_format="JPEG", export_jpeg_quality=85,
                                  export_cameras=False, export_lights=False, export_extras=False)
    finally:
        sys.stdout = old


def near_detail(art):
    """Wall dressing for the Detail layer (looks only, flat on the walls):
    on every long wall face that looks into a play area, a dark concrete
    plinth at the foot; on tall ones a metal coping on the top edge, a
    gutter and a downpipe at each end, and an electrical box; on low indoor
    walls (Tunnel, Lanka Steel, Workshop) two pipes along the top instead.
    Joined into one mesh per material: Near_<material>."""
    from mathutils import Vector
    dg = bpy.context.evaluated_depsgraph_get()
    scene = bpy.context.scene
    parts = {}  # material -> bmesh

    def bm_for(mat):
        if mat not in parts:
            parts[mat] = bmesh.new()
        return parts[mat]

    def box(mat, c, s):
        bm = bm_for(mat)
        r = bmesh.ops.create_cube(bm, size=1.0)
        for v in r["verts"]:
            v.co = Vector((c[0] + v.co.x * s[0], c[1] + v.co.y * s[1], c[2] + v.co.z * s[2]))

    def pipe(mat, a, b, radius):
        """Cylinder from a to b along one axis."""
        bm = bm_for(mat)
        d = Vector(b) - Vector(a)
        r = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=radius, radius2=radius, depth=d.length)
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        mid = (Vector(a) + Vector(b)) / 2
        for v in r["verts"]:
            v.co = mid + (rot @ v.co.to_4d()).to_3d()

    def floor_side(p):
        hit, loc, n, i, obj, mx = scene.ray_cast(dg, p, Vector((0, 0, -1)), distance=1.6)
        return hit and obj.name.startswith("Floor")

    n_faces = 0
    for w in art:
        if not w.name.startswith("RoomWall"):
            continue
        pts = [w.matrix_world @ Vector(c) for c in w.bound_box]
        lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        size = hi - lo
        along_x = size.x > size.y
        length = size.x if along_x else size.y
        if length < 5.0 or size.z < 3.0:
            continue
        c = (lo + hi) / 2
        for side in (-1, 1):
            nrm = Vector((0, side, 0)) if along_x else Vector((side, 0, 0))
            face = c + nrm * ((size.y if along_x else size.x) / 2)
            probe = face + nrm * 0.6
            probe.z = lo.z + 1.0
            if not floor_side(probe):
                continue
            n_faces += 1
            ax = Vector((1, 0, 0)) if along_x else Vector((0, 1, 0))
            top = hi.z
            # A dark concrete plinth along the foot of the wall.
            pl = face + nrm * 0.04
            pl.z = lo.z + 0.35
            box("Mat_floor_dark", pl, (length if along_x else 0.08, 0.08 if along_x else length, 0.7))
            if size.z >= 6.0:
                # A metal coping along the top edge.
                cp = face + nrm * 0.03
                cp.z = top + 0.05
                box("Mat_metal", cp, (length if along_x else 0.5, 0.5 if along_x else length, 0.1))
            if size.z >= 6.0:
                # Gutter + downpipes at both ends, an electrical box.
                g = face + nrm * 0.1
                g.z = top - 0.12
                box("Mat_cable", g, (length if along_x else 0.16, 0.16 if along_x else length, 0.14))
                for end in (-1, 1):
                    p = face + nrm * 0.12 + ax * end * (length / 2 - 0.5)
                    pipe("Mat_metal", (p.x, p.y, lo.z + 0.05), (p.x, p.y, top - 0.12), 0.06)
                if length >= 10.0:
                    e = face + nrm * 0.1 + ax * (length / 2 - 2.2)
                    e.z = lo.z + 1.5
                    box("Mat_steel_blue", e, (0.55 if along_x else 0.2, 0.2 if along_x else 0.55, 0.75))
                    box("Mat_hazard", e + nrm * 0.105 + Vector((0, 0, 0.2)), (0.2 if along_x else 0.01, 0.01 if along_x else 0.2, 0.12))
            else:
                # Low indoor wall: two pipes along the top on brackets.
                for (off, dz, r, mat) in ((0.18, 0.35, 0.09, "Mat_rust"), (0.38, 0.6, 0.12, "Mat_steel_blue")):
                    p = face + nrm * off
                    a = p - ax * (length / 2 - 0.2)
                    b = p + ax * (length / 2 - 0.2)
                    a.z = b.z = top - dz
                    pipe(mat, a, b, r)
                k = -length / 2 + 1.0
                while k < length / 2 - 0.5:
                    br = face + nrm * 0.25 + ax * k
                    br.z = top - 0.48
                    box("Mat_cable", br, (0.05 if along_x else 0.5, 0.5 if along_x else 0.05, 0.05))
                    k += 3.0
    det_objs = []
    for mat, bm in parts.items():
        name = "Near_" + mat[4:]
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(name, me)
        DET.objects.link(o)
        o.data.materials.append(bpy.data.materials[mat])
        world_uv(o)
        det_objs.append(o)
    return n_faces


def export_detail():
    objs = list(DET.objects)
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, "factory_detail.glb"), export_format="GLB",
                                  use_selection=True, export_image_format="NONE", export_cameras=False,
                                  export_lights=False, export_extras=False)
    finally:
        sys.stdout = old


derive()
make_glass()
clear_old()
art, plain = import_blockout()
art, props = replace_props(art)
export(art)
faces = near_detail(art)
export_detail()
for im in list(bpy.data.images):
    if im.users == 0:
        bpy.data.images.remove(im)
bpy.ops.wm.save_mainfile()
print("factory art: %d meshes (%d real props, %d left greybox), %d KB; wall dressing on %d faces" % (
    len(art), props, plain, os.path.getsize(os.path.join(ROOT, "factory.glb")) // 1024, faces))
