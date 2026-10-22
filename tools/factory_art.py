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
walls) and exports factory_detail.glb. For the ruins it bakes age into the
textures once (age_materials: rust on metal, soot on masonry, stains on
floors), smashes the windows (make_glass), makes the alpha-clipped weeds,
creepers and burn marks (make_ruin_cards) and a charred truck. Meshes whose kind has no texture (glass, lamps, signs'
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
    "Mat_gravel": ("Mat_ground", (0.3, 0.27, 0.22, 1)),
}
# Objects (by name prefix) that get a different material than their kind.
FLOORS = ("Floor", "Ground")


def derive():
    for name, (src, color) in DERIVED.items():
        if name in bpy.data.materials:
            continue
        mixes = [n for n in bpy.data.materials[src].node_tree.nodes if n.type == "MIX"]
        if not mixes:
            continue  # the source is already aged (baked); this kind stays greybox
        m = bpy.data.materials[src].copy()
        m.name = name
        mix = next(n for n in m.node_tree.nodes if n.type == "MIX")
        mix.inputs[7].default_value = color


def make_glass():
    """Mat_glass: an abandoned factory window made in code - 4 x 4 grimy
    panes per 2.2 m tile in dark steel glazing bars, lighter towards the top
    (the sky in it); about half the panes smashed (dark inside, jagged
    shards left in the frame). Glossy glass, rough frames. 512 px."""
    import numpy as np
    if "Mat_glass" in bpy.data.materials and bpy.data.materials["Mat_glass"].get("broken"):
        return
    n = 512
    rng = np.random.default_rng(5)
    y, x = np.mgrid[0:n, 0:n] / n
    bar = 0.02
    fx = np.minimum((x % 0.25), 0.25 - (x % 0.25)) < bar / 2 + 0.002
    fy = np.minimum((y % 0.25), 0.25 - (y % 0.25)) < bar / 2 + 0.002
    frame = fx | fy
    # Soft grime: blurred noise (sum of a few upsampled random grids).
    grime = np.zeros((n, n))
    for k, w in ((8, 0.5), (32, 0.3), (128, 0.2)):
        g = rng.random((k, k))
        grime += w * np.kron(g, np.ones((n // k, n // k)))
    pane_y = (y % 0.25) / 0.25  # 0 at the top of each pane (image row 0 = top)
    sky = 0.36 - 0.18 * pane_y
    col = np.stack([sky * 0.85, sky * 0.9, sky * 0.92], -1)
    col *= (0.6 + 0.35 * grime)[..., None]
    # Smashed panes: dark inside, a ragged rim of glass left in the frame.
    broken = np.zeros((n, n), bool)
    for py in range(4):
        for px in range(4):
            if rng.random() < 0.5:
                cx, cy = (px + 0.5) * 0.25, (py + 0.5) * 0.25
                d = np.maximum(abs(x - cx), abs(y - cy)) / 0.125
                rim = 0.55 + 0.4 * rng.random((n, n)) ** 3
                broken |= (abs(x - cx) < 0.125) & (abs(y - cy) < 0.125) & (d < rim)
    col[broken] = (0.03, 0.03, 0.035)
    col[frame] = (0.07, 0.06, 0.055)
    rough = np.where(frame | broken, 0.85, 0.12 + 0.35 * grime)
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
    m["tex_size"] = 2.2
    m["broken"] = 1


# --- The ruins: aged materials, broken windows, weeds, creepers, burn marks ----------
# Everything is baked into plain textures (glTF carries one image per slot).
RUST = ("Mat_corrugated", "Mat_blue", "Mat_red", "Mat_green", "Mat_steel_blue", "Mat_shutter", "Mat_teal",
        "Mat_metal", "Mat_yellow", "Mat_hazard", "Mat_silver")
SOOT = ("Mat_brick", "Mat_concrete", "Mat_plaster", "Mat_sandstone", "Mat_office_wall", "Mat_tile")
STAINS = ("Mat_ground", "Mat_paving", "Mat_floor_dark", "Mat_gravel")


def _np_noise(n, k, seed, blur=3):
    """Tileable soft noise in 0..1: an upsampled random grid, box-blurred with wrap-around."""
    import numpy as np
    g = np.random.default_rng(seed).random((k, k))
    a = np.kron(g, np.ones((n // k, n // k)))
    r = max(1, n // k // 2)
    for _ in range(blur):
        a = (a + np.roll(a, r, 0) + np.roll(a, -r, 0) + np.roll(a, r, 1) + np.roll(a, -r, 1)) / 5.0
    a -= a.min()
    return a / max(a.max(), 1e-6)


def _np_streaks(mask, seed, length=60):
    """Dirt / rust running down from `mask` (rows bottom-up), in thin streaks."""
    import numpy as np
    n = mask.shape[0]
    s = mask.copy()
    for k in range(1, length):
        s = np.maximum(s, np.roll(mask, -k * 3, 0) * (0.97 ** k))
    cols = _np_noise(n, 64, seed, 1)[0][None, :]
    return s * np.clip(cols * 2.0 - 0.6, 0, 1)


def _img_rgb(im, n):
    import numpy as np
    w, h = im.size
    px = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(px)
    a = px.reshape(h, w, 4)[..., :3]
    if (w, h) != (n, n):
        ys = (np.arange(n) * h // n)
        xs = (np.arange(n) * w // n)
        a = a[ys][:, xs]
    return a


def _new_image(name, rgba, jpeg=True):
    import numpy as np
    n = rgba.shape[0]
    im = bpy.data.images.get(name) or bpy.data.images.new(name, n, n, alpha=not jpeg)
    if tuple(im.size) != (n, n):
        im.scale(n, n)
    a = np.ones((n, n, 4), np.float32)
    a[..., :rgba.shape[2]] = rgba
    im.pixels.foreach_set(a.ravel())
    im.file_format = "JPEG" if jpeg else "PNG"
    im.pack()
    return im


def _base_source(m):
    """(image, tint colour or None, the node linked into Base Color)."""
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    link = bsdf.inputs["Base Color"].links[0]
    node = link.from_node
    if node.type == "TEX_IMAGE":
        return node.image, None, bsdf
    img = node.inputs[6].links[0].from_node.image
    return img, tuple(node.inputs[7].default_value)[:3], bsdf


def age_materials():
    """Years of neglect, baked in: rust patches and rust running down the
    metal and painted cladding, soot and dirt streaks on brick, concrete and
    plaster, oil and damp stains on the floors; everything a little darker
    and greyer. Once per material (m["aged"])."""
    import numpy as np
    n = 1024
    rust_img = next(i for i in bpy.data.images if i.name.startswith("rusty_metal_04") and "Diffuse" in i.name)
    rust = _img_rgb(rust_img, n)
    for k, name in enumerate(RUST + SOOT + STAINS):
        m = bpy.data.materials.get(name)
        if m is None or m.get("aged"):
            continue
        img, tint, bsdf = _base_source(m)
        col = _img_rgb(img, n)
        if tint:
            col = col * np.array(tint)
        patch = _np_noise(n, 8, 100 + k) * 0.6 + _np_noise(n, 32, 200 + k) * 0.4
        if name in RUST:
            spots = np.clip(patch * 2.2 - 1.15, 0, 1)
            amount = np.clip(spots + _np_streaks(spots, 300 + k) * 0.55, 0, 0.92)[..., None]
            col = col * (1 - amount) + rust * amount
            col *= 0.86
        elif name in SOOT:
            dirt = np.clip(patch * 1.8 - 0.8, 0, 1)
            amount = np.clip(dirt * 0.5 + _np_streaks(dirt, 400 + k, 80) * 0.45, 0, 0.8)[..., None]
            col = col * (1 - amount * 0.7)
            col *= 0.84
        else:
            stain = np.clip(_np_noise(n, 16, 500 + k) * 2.4 - 1.4, 0, 1)[..., None]
            col = col * (1 - stain * 0.6) * 0.88
        grey = col.mean(-1, keepdims=True)
        col = col * 0.8 + grey * 0.2
        new = _new_image(name[4:] + "_aged", np.clip(col, 0, 1))
        nt = m.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = new
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        for nd in [nd for nd in nt.nodes if nd.type == "MIX"]:
            nt.nodes.remove(nd)
        m["aged"] = 1


def _alpha_material(name, rgba, tex_size, rough=0.9):
    """A material with an alpha-clipped colour texture (MASK in glTF)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        if nd.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(nd)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], next(nd for nd in nt.nodes if nd.type == "OUTPUT_MATERIAL").inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _new_image(name[4:] + "_tex", rgba, jpeg=False)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    less = nt.nodes.new("ShaderNodeMath")
    less.operation = "LESS_THAN"
    less.inputs[1].default_value = 0.5
    nt.links.new(tex.outputs["Alpha"], less.inputs[0])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(less.outputs[0], inv.inputs[1])
    nt.links.new(inv.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = rough
    m.surface_render_method = "DITHERED"
    m["tex_size"] = tex_size
    return m


def make_ruin_cards():
    """Mat_weeds (grass and weed blades growing from the bottom of a 0.9 m
    tile), Mat_ivy (creepers thick at the foot of a 7 m tile, thinning
    upwards) and Mat_scorch (a ragged burn mark; its objects get their own
    0..1 UVs)."""
    import numpy as np
    if all(n in bpy.data.materials and bpy.data.materials[n].get("cards") == 2 for n in ("Mat_weeds", "Mat_ivy", "Mat_scorch")):
        return
    rng = np.random.default_rng(9)
    # Weeds: 256 px, rows bottom-up.
    n = 256
    w = np.zeros((n, n, 4), np.float32)
    for i in range(140):
        x0 = rng.uniform(0, n)
        hgt = rng.uniform(0.25, 0.95) * n
        lean = rng.uniform(-0.35, 0.35)
        width = rng.uniform(1.0, 3.0)
        c = np.array([rng.uniform(0.18, 0.42), rng.uniform(0.3, 0.48), rng.uniform(0.06, 0.15)])
        if rng.random() < 0.3:
            c = np.array([0.45, 0.4, 0.2]) * rng.uniform(0.7, 1.1)  # dry blade
        for y in range(int(hgt)):
            t = y / hgt
            x = x0 + lean * y * (0.5 + t)
            half = width * (1 - t) * 0.5 + 0.4
            xs = np.arange(int(x - half), int(x + half) + 1) % n
            w[y, xs, :3] = c * (0.6 + 0.5 * t)
            w[y, xs, 3] = 1
    _alpha_material("Mat_weeds", w, 0.9)
    # Ivy: 512 px over 7 m, rows bottom-up.
    n = 512
    v = np.zeros((n, n, 4), np.float32)
    yy, xx = np.mgrid[0:n, 0:n]
    for i in range(2600):
        y = abs(rng.normal(0, 0.55)) * n
        if y >= n:
            continue
        x = rng.uniform(0, n)
        r = rng.uniform(4, 10) * (1.25 - y / n)
        y0, y1 = int(max(0, y - r)), int(min(n, y + r + 1))
        x0, x1 = int(x - r), int(x + r + 1)
        sub_y, sub_x = np.mgrid[y0:y1, x0:x1]
        inside = (sub_y - y) ** 2 + (sub_x - x) ** 2 <= r * r
        c = np.array([rng.uniform(0.08, 0.2), rng.uniform(0.2, 0.36), rng.uniform(0.04, 0.1)])
        v[sub_y[inside], sub_x[inside] % n, :3] = c
        v[sub_y[inside], sub_x[inside] % n, 3] = 1
    _alpha_material("Mat_ivy", v, 7.0, 0.8)
    # Scorch: 256 px, a dark ragged disc.
    n = 256
    d = np.hypot(*(np.mgrid[0:n, 0:n] - n / 2)) / (n / 2)
    edge = 0.75 + (_np_noise(n, 16, 77) - 0.5) * 0.45
    s = np.zeros((n, n, 4), np.float32)
    s[..., :3] = (0.035 + 0.04 * d)[..., None] * np.array([1.0, 0.92, 0.85])
    s[..., 3] = (d < edge * (0.7 + 0.3 * _np_noise(n, 64, 78))).astype(np.float32)
    _alpha_material("Mat_scorch", s, 1.0, 1.0)
    for name in ("Mat_weeds", "Mat_ivy", "Mat_scorch"):
        bpy.data.materials[name]["cards"] = 2


def make_burnt_truck():
    """Prop_truck_burnt: the delivery truck charred black with rust coming through."""
    import numpy as np
    if "Prop_truck_burnt" in bpy.data.objects:
        return
    src = bpy.data.objects["Prop_truck"]
    b = src.copy()
    b.data = src.data.copy()
    PROPS_SRC.objects.link(b)
    b.name = "Prop_truck_burnt"
    m = src.data.materials[0].copy()
    m.name = "Truck_burnt"
    img, _, bsdf = _base_source(m)
    n = 1024
    col = _img_rgb(img, n)
    rust = _img_rgb(next(i for i in bpy.data.images if i.name.startswith("rusty_metal_04") and "Diffuse" in i.name), n)
    soot = _np_noise(n, 16, 61)
    amount = np.clip(soot * 1.6 - 0.3, 0, 1)[..., None]
    col = col * 0.18 * (1 - amount) + rust * 0.7 * amount
    tex = m.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = _new_image("truck_burnt", np.clip(col, 0, 1))
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Metallic"].default_value = 0.3
    b.data.materials[0] = m


def local_uv(o):
    """0..1 UVs over the object's own top face (burn marks)."""
    from mathutils import Vector
    vs = [v.co for v in o.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), 0))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), 0))
    me = o.data
    uv = me.uv_layers.active or me.uv_layers.new()
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = ((co.x - lo.x) / max(hi.x - lo.x, 1e-4), (co.y - lo.y) / max(hi.y - lo.y, 1e-4))


def clear_old():
    for o in list(bpy.data.objects):
        if DET in o.users_collection and not o.name.startswith("Near"):
            continue
        if PROPS_SRC in o.users_collection:
            continue
        if any(c.name == "Showcase" for c in o.users_collection):
            continue  # the sun and cameras for viewing / rendering the map in Blender
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
        if o.name.startswith("Scorch"):
            local_uv(o)
        else:
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
        if base not in ("Drum", "Crate", "Container", "Forklift", "Truck", "BurntTruck", "PalmTrunk", "AirCon",
                        "Goods"):
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
        elif base in ("Truck", "BurntTruck"):
            # Front towards local +Y in Blender (the greybox's -Z), like the model.
            src = bpy.data.objects["Prop_truck" if base == "Truck" else "Prop_truck_burnt"]
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
age_materials()
make_ruin_cards()
make_burnt_truck()
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
