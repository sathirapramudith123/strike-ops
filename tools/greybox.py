#!/usr/bin/env python3
"""Greybox map generator.

Writes Godot .tscn maps made of boxes (mesh + collision), ramps and spawn
markers, using the Level script, grid shader, HUD and pause menu — the same
structure as scenes/levels/test_map.tscn.

    python3 tools/greybox.py          # regenerates every map below

Edit a map by changing its build function and re-running the script.
Coordinates: metres, +Y up, -Z = north. Box position = centre.
"""
import math
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")

MATERIALS = {
    "grid": {},
    "wall": {"base_color": (0.62, 0.6, 0.56), "line_color": (0.45, 0.43, 0.4)},
    "accent": {"base_color": (0.3, 0.42, 0.55), "line_color": (0.2, 0.3, 0.4), "cell_size": 0.5},
    "wood": {"base_color": (0.55, 0.42, 0.28), "line_color": (0.4, 0.3, 0.2), "cell_size": 0.5},
    "metal": {"base_color": (0.38, 0.4, 0.42), "line_color": (0.28, 0.3, 0.32), "cell_size": 0.5},
    "stone": {"base_color": (0.7, 0.66, 0.58), "line_color": (0.55, 0.51, 0.45), "cell_size": 2.0},
    "blue": {"base_color": (0.25, 0.4, 0.75), "line_color": (0.18, 0.3, 0.6)},
    "red": {"base_color": (0.75, 0.3, 0.25), "line_color": (0.6, 0.2, 0.18)},
    "site": {"base_color": (0.95, 0.55, 0.15), "line_color": (0.75, 0.35, 0.1), "cell_size": 0.5},
}

SITE_RADIUS = 3.5  # keep in sync with BombRules.SITE_RADIUS


class Map:
    def __init__(self, name):
        self.name = name
        self.boxes = []  # (name, pos, size, basis_rows, material, collide)
        self.spawns = {"ffa": [], "blue": [], "red": []}
        self.lights = []
        self.sites = []  # (name, pos)
        self._n = {}

    def _id(self, prefix):
        self._n[prefix] = self._n.get(prefix, 0) + 1
        return f"{prefix}{self._n[prefix]}"

    def box(self, pos, size, mat="grid", name="Box", yaw=0.0, collide=True):
        c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        basis = (c, 0, s, 0, 1, 0, -s, 0, c)
        self.boxes.append((self._id(name), pos, size, basis, mat, collide))

    def ramp(self, start, end, width, mat="accent", thickness=0.3, name="Ramp"):
        """Walkable slab from start (x,y,z) to end (x,y,z) along X or Z. The
        top surface passes through both points."""
        sx, sy, sz = start
        ex, ey, ez = end
        dx, dy, dz = ex - sx, ey - sy, ez - sz
        horiz = math.hypot(dx, dz)
        length = math.hypot(horiz, dy)
        ang = math.atan2(dy, horiz)
        c, s = math.cos(ang), math.sin(ang)
        # Centre sits half a thickness below the top surface.
        cx, cy, cz = sx + dx / 2, sy + dy / 2 - thickness / 2 * c, sz + dz / 2
        if abs(dz) >= abs(dx):
            # Running along Z: rotate about X. Rising towards -Z needs +angle.
            a = ang if dz < 0 else -ang
            ca, sa = math.cos(a), math.sin(a)
            basis = (1, 0, 0, 0, ca, -sa, 0, sa, ca)
            size = (width, thickness, length)
        else:
            a = ang if dx > 0 else -ang
            ca, sa = math.cos(a), math.sin(a)
            basis = (ca, -sa, 0, sa, ca, 0, 0, 0, 1)
            size = (length, thickness, width)
        self.boxes.append((self._id(name), (cx, cy, cz), size, basis, mat, True))

    def wall_with_gaps(self, a, b, height, thickness, gaps, mat="wall", y0=0.0, name="Wall"):
        """Straight wall from a=(x,z) to b=(x,z) (axis-aligned) with door gaps:
        gaps = [(offset_from_a, gap_width, gap_height)]; gap_height >= height = full."""
        ax, az = a
        bx, bz = b
        along_x = abs(bx - ax) > abs(bz - az)
        total = abs(bx - ax) if along_x else abs(bz - az)
        sign = 1 if (bx - ax if along_x else bz - az) > 0 else -1
        cuts = sorted(gaps)
        pos = 0.0
        segments = []
        for off, w, gh in cuts:
            if off > pos:
                segments.append((pos, off, 0.0, height))
            if gh < height:  # lintel above the door
                segments.append((off, off + w, gh, height))
            pos = off + w
        if pos < total:
            segments.append((pos, total, 0.0, height))
        for s0, s1, h0, h1 in segments:
            mid = (s0 + s1) / 2 * sign
            length = s1 - s0
            cy = y0 + (h0 + h1) / 2
            if along_x:
                self.box((ax + mid, cy, az), (length, h1 - h0, thickness), mat, name)
            else:
                self.box((ax, cy, az + mid), (thickness, h1 - h0, length), mat, name)

    def spawn(self, team, pos, yaw_deg):
        self.spawns[team].append((pos, yaw_deg))
        if team != "ffa":
            self.spawns["ffa"].append((pos, yaw_deg))

    def site(self, name, pos):
        """Bomb site: marker at the centre + an orange floor plate (visual)."""
        self.sites.append((name, pos))
        d = SITE_RADIUS * 2
        self.box((pos[0], pos[1] + 0.01, pos[2]), (d, 0.02, d), "site", f"Site{name}Plate", collide=False)

    def omni(self, pos, energy=1.5, rng=12.0, color=(1.0, 0.9, 0.75)):
        self.lights.append((pos, energy, rng, color))

    # ------------------------------------------------------------------
    def write(self, path, sun_rot=(-50.0, 30.0), sky=(0.32, 0.5, 0.75), fog=0.0):
        subs, nodes = [], []
        for i, (name, pos, size, basis, mat, collide) in enumerate(self.boxes):
            sid = i + 1
            subs.append(f'[sub_resource type="BoxMesh" id="Mesh_{sid}"]\nmaterial = SubResource("Mat_{mat}")\nsize = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n')
            b = ", ".join(f"{v:.6f}" for v in basis)
            nodes.append(f'[node name="{name}" type="StaticBody3D" parent="Geometry"]\ntransform = Transform3D({b}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n'
                         f'\n[node name="Mesh" type="MeshInstance3D" parent="Geometry/{name}"]\nmesh = SubResource("Mesh_{sid}")\n')
            if collide:
                subs.append(f'[sub_resource type="BoxShape3D" id="Shape_{sid}"]\nsize = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n')
                nodes.append(f'[node name="Collision" type="CollisionShape3D" parent="Geometry/{name}"]\nshape = SubResource("Shape_{sid}")\n')
        mats = []
        for key, params in MATERIALS.items():
            lines = [f'[sub_resource type="ShaderMaterial" id="Mat_{key}"]', "render_priority = 0", 'shader = ExtResource("4_grid")']
            for k, v in params.items():
                if isinstance(v, tuple):
                    lines.append(f"shader_parameter/{k} = Color({v[0]}, {v[1]}, {v[2]}, 1)")
                else:
                    lines.append(f"shader_parameter/{k} = {v}")
            mats.append("\n".join(lines) + "\n")

        spawn_nodes, groups = [], {"ffa": [], "blue": [], "red": []}
        for team in ("blue", "red", "ffa"):
            for i, (pos, yaw) in enumerate(self.spawns[team] if team != "ffa" else [s for s in self.spawns["ffa"] if s not in self.spawns["blue"] + self.spawns["red"]]):
                n = f"{team.title()}{i + 1}"
                c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
                spawn_nodes.append(f'[node name="{n}" type="Marker3D" parent="SpawnPoints"]\ntransform = Transform3D({c:.6f}, 0, {s:.6f}, 0, 1, 0, {-s:.6f}, 0, {c:.6f}, {pos[0]}, {pos[1]}, {pos[2]})\n')
                groups[team].append(f'NodePath("SpawnPoints/{n}")')
        all_ffa = groups["ffa"] + groups["blue"] + groups["red"]

        light_nodes = []
        for i, (pos, energy, rng, col) in enumerate(self.lights):
            light_nodes.append(f'[node name="Lamp{i + 1}" type="OmniLight3D" parent="Lights"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})\nlight_color = Color({col[0]}, {col[1]}, {col[2]}, 1)\nlight_energy = {energy}\nomni_range = {rng}\n')

        pitch, yaw = map(math.radians, sun_rot)
        # Sun basis from yaw (Y) then pitch (X).
        cy_, sy_ = math.cos(yaw), math.sin(yaw)
        cp, sp = math.cos(pitch), math.sin(pitch)
        sun_basis = (cy_, sy_ * sp, sy_ * cp, 0, cp, -sp, -sy_, cy_ * sp, cy_ * cp)
        sb = ", ".join(f"{v:.6f}" for v in sun_basis)

        head = f'''[gd_scene load_steps={len(subs) + len(mats) + 9} format=3]

[ext_resource type="Script" path="res://scripts/levels/level.gd" id="1_level"]
[ext_resource type="PackedScene" path="res://scenes/ui/hud.tscn" id="2_hud"]
[ext_resource type="PackedScene" path="res://scenes/ui/pause_menu.tscn" id="3_pause"]
[ext_resource type="Shader" path="res://assets/shaders/prototype_grid.gdshader" id="4_grid"]
[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="6_player"]

[sub_resource type="ProceduralSkyMaterial" id="SkyMat"]
sky_top_color = Color({sky[0]}, {sky[1]}, {sky[2]}, 1)
sky_horizon_color = Color(0.7, 0.75, 0.8, 1)
ground_bottom_color = Color(0.2, 0.2, 0.22, 1)
ground_horizon_color = Color(0.7, 0.75, 0.8, 1)

[sub_resource type="Sky" id="Sky"]
sky_material = SubResource("SkyMat")

[sub_resource type="Environment" id="Env"]
background_mode = 2
sky = SubResource("Sky")
ambient_light_source = 3
reflected_light_source = 2
tonemap_mode = 2
glow_enabled = true
fog_enabled = {"true" if fog > 0 else "false"}
fog_density = {fog}
volumetric_fog_density = 0.01

'''
        site_nodes, site_paths = [], []
        for name, pos in self.sites:
            site_nodes.append(f'[node name="{name}" type="Marker3D" parent="BombSites"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})\n')
            site_nodes.append(f'[node name="Letter" type="Label3D" parent="BombSites/{name}"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.2, 0)\nbillboard = 1\nmodulate = Color(1, 0.6, 0.2, 0.9)\noutline_modulate = Color(0, 0, 0, 0.8)\ntext = "{name}"\nfont_size = 160\noutline_size = 24\n')
            site_paths.append(f'NodePath("BombSites/{name}")')

        root = f'''[node name="{self.name}" type="Node3D" node_paths=PackedStringArray("world_environment", "sun", "spawn_points", "blue_spawn_points", "red_spawn_points", "bomb_sites")]
script = ExtResource("1_level")
player_scene = ExtResource("6_player")
world_environment = NodePath("WorldEnvironment")
sun = NodePath("Sun")
spawn_points = [{", ".join(all_ffa)}]
blue_spawn_points = [{", ".join(groups["blue"])}]
red_spawn_points = [{", ".join(groups["red"])}]
bomb_sites = [{", ".join(site_paths)}]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D({sb}, 0, 20, 0)
light_energy = 1.1
shadow_enabled = true
directional_shadow_max_distance = 100.0

[node name="Geometry" type="Node3D" parent="."]

'''
        tail = '''[node name="HUD" parent="." instance=ExtResource("2_hud")]

[node name="PauseMenu" parent="." instance=ExtResource("3_pause")]
'''
        out = (head + "\n".join(mats) + "\n" + "\n".join(subs) + "\n" + root + "\n".join(nodes)
               + '\n[node name="SpawnPoints" type="Node3D" parent="."]\n\n' + "\n".join(spawn_nodes)
               + '\n[node name="Lights" type="Node3D" parent="."]\n\n' + "\n".join(light_nodes)
               + '\n[node name="BombSites" type="Node3D" parent="."]\n\n' + "\n".join(site_nodes) + "\n" + tail)
        with open(os.path.join(ROOT, path), "w") as f:
            f.write(out)
        print(f"wrote {path}: {len(self.boxes)} boxes, spawns blue={len(self.spawns['blue'])} red={len(self.spawns['red'])} ffa={len(self.spawns['ffa'])}")


# ======================================================================
def warehouse():
    """Close-quarters warehouse: shelving aisles, crate stacks, a raised
    catwalk along the north wall and two small offices."""
    m = Map("Warehouse")
    W, D, H = 44.0, 32.0, 8.0
    m.box((0, -0.5, 0), (W + 2, 1, D + 2), "grid", "Floor")
    m.box((0, H / 2, -D / 2 - 0.5), (W + 2, H, 1), "wall", "WallN")
    m.box((0, H / 2, D / 2 + 0.5), (W + 2, H, 1), "wall", "WallS")
    m.box((W / 2 + 0.5, H / 2, 0), (1, H, D), "wall", "WallE")
    m.box((-W / 2 - 0.5, H / 2, 0), (1, H, D), "wall", "WallW")
    # Roof beams (visual only, cheap).
    for x in (-15, -5, 5, 15):
        m.box((x, H - 0.3, 0), (0.4, 0.6, D), "metal", "Beam", collide=False)

    # Shelving aisles (3 m tall, with gaps to cut through).
    for x in (-7.0, 7.0):
        for z0, z1 in ((-9.0, -2.0), (1.5, 9.0)):
            m.box((x, 1.5, (z0 + z1) / 2), (1.4, 3.0, z1 - z0), "metal", "Shelf")
            # Boxes on shelves for silhouette variety (no collision needed).
            m.box((x, 3.25, (z0 + z1) / 2 - 1.5), (1.2, 0.5, 1.5), "wood", "ShelfCrate", collide=False)
    # Crate stacks: (x, z, stack level, yaw). Level 1 sits on a level-0 crate.
    for (x, z, level, yaw) in ((0, 0, 0, 0), (0, 0, 1, 20), (-2.5, -5, 0, 10), (2.5, 5, 0, -15),
                               (-14, 4, 0, 0), (-14, 5.3, 0, 0), (-14, 4.6, 1, 10), (14, -3, 0, 30),
                               (15, 7, 0, 0), (-3, 11, 0, 0), (3, -10.5, 0, 0)):
        m.box((x, 0.6 + level * 1.2, z), (1.2, 1.2, 1.2), "wood", "Crate", yaw=yaw)
    # Forklift pallets / low cover.
    for (x, z) in ((-10, 12), (10, 12), (-18, -2), (18, 2)):
        m.box((x, 0.5, z), (2.4, 1.0, 1.2), "wood", "Pallet")

    # North catwalk (3 m high) with ramps at both ends.
    CW_Y, CW_Z, CW_D = 3.0, -D / 2 + 1.5, 3.0
    m.box((0, CW_Y - 0.15, CW_Z), (30, 0.3, CW_D), "metal", "Catwalk")
    # Railing stops short of the ramp lanes at both ends.
    m.box((0, CW_Y + 0.5, CW_Z + CW_D / 2 - 0.05), (27.2, 1.0, 0.1), "metal", "Railing")
    for x in (-8, 0, 8):
        m.box((x, (CW_Y - 0.3) / 2, CW_Z + 1.2), (0.3, CW_Y - 0.3, 0.3), "metal", "Pillar")
    # Ramps start at the catwalk's south edge so there is headroom under it.
    edge = CW_Z + CW_D / 2
    m.ramp((-15.0, CW_Y, edge), (-15.0 - 0.001, 0.0, edge + 9.0), 2.5, "metal")
    m.ramp((15.0, CW_Y, edge), (15.0 + 0.001, 0.0, edge + 9.0), 2.5, "metal")

    # Offices (SW and SE corners) with doors.
    for sx in (-1, 1):
        x0 = sx * (W / 2 - 7)   # inner wall x
        m.wall_with_gaps((x0, D / 2), (x0, D / 2 - 7), 3.0, 0.3, [(2.0, 1.6, 2.2)], "wall", name="OfficeWall")
        m.wall_with_gaps((x0, D / 2 - 7), (sx * W / 2, D / 2 - 7), 3.0, 0.3, [(3.0, 1.6, 2.2)], "wall", name="OfficeWall")
        m.box(((x0 + sx * W / 2) / 2, 3.1, D / 2 - 3.5), (7, 0.2, 7), "wall", "OfficeRoof")
        m.box((x0 + sx * 3.5, 0.45, D / 2 - 2.0), (2.0, 0.9, 1.0), "wood", "Desk")

    # Lights (hanging lamps).
    for x in (-14, 0, 14):
        for z in (-6, 6):
            m.omni((x, H - 1.2, z), 1.2, 14.0)

    # Bomb sites (defenders = blue spawns in the south; attackers come from the north).
    m.site("A", (-16.0, 0.0, 6.0))
    m.site("B", (15.5, 0.0, 3.0))

    for x in (-4, 0, 4):
        m.spawn("blue", (x, 0.1, D / 2 - 2.0), 0)
    m.spawn("blue", (-12, 0.1, 10), 20)
    for x in (-4, 0, 4):
        m.spawn("red", (x, 0.1, -D / 2 + 4.5), 180)
    m.spawn("red", (12, 3.1, CW_Z), 200)
    m.spawn("ffa", (-19, 0.1, -8), 90)
    m.spawn("ffa", (19, 0.1, 8), -90)
    m.write("scenes/levels/warehouse.tscn", sun_rot=(-65.0, 40.0), sky=(0.4, 0.45, 0.55))


def courtyard():
    """Outdoor plaza: central fountain, low walls and pillars, and two
    two-storey buildings (east/west) with interior ramps to the roof."""
    m = Map("Courtyard")
    S = 60.0
    m.box((0, -0.5, 0), (S + 2, 1, S + 2), "stone", "Floor")
    for (pos, size) in (((0, 3, -S / 2 - 0.5), (S + 2, 6, 1)), ((0, 3, S / 2 + 0.5), (S + 2, 6, 1)),
                        ((S / 2 + 0.5, 3, 0), (1, 6, S)), ((-S / 2 - 0.5, 3, 0), (1, 6, S))):
        m.box(pos, size, "wall", "Boundary")

    # Fountain.
    m.box((0, 0.4, 0), (7, 0.8, 7), "stone", "FountainBase")
    m.box((0, 1.6, 0), (1.4, 3.2, 1.4), "stone", "FountainPillar")
    m.box((0, 3.4, 0), (3, 0.4, 3), "stone", "FountainTop")

    # Pillars ring + low walls.
    for ang in range(0, 360, 45):
        r = 10.0
        x, z = r * math.cos(math.radians(ang)), r * math.sin(math.radians(ang))
        m.box((x, 2.0, z), (1.0, 4.0, 1.0), "stone", "Pillar")
    for (x, z, w, d) in ((-6, 15, 6, 0.8), (6, -15, 6, 0.8), (15, 6, 0.8, 5), (-15, -6, 0.8, 5),
                         (0, 22, 8, 0.8), (0, -22, 8, 0.8)):
        m.box((x, 0.6, z), (w, 1.2, d), "stone", "LowWall")
    # Trees (trunk + canopy, canopy without collision).
    for (x, z) in ((-8, -24), (8, 24), (-24, 20), (24, -20), (18, 18), (-18, -18)):
        m.box((x, 1.5, z), (0.6, 3.0, 0.6), "wood", "Trunk")
        m.box((x, 3.8, z), (3.0, 2.2, 3.0), "accent", "Canopy", collide=False)

    # Two-storey buildings.
    for sx in (-1, 1):
        cx = sx * 21.0
        bw, bd, fh = 10.0, 16.0, 3.4
        x_in, x_out = cx - sx * bw / 2, cx + sx * bw / 2
        mat = "blue" if sx < 0 else "red"
        # Ground floor walls (doors on the plaza side and the ends).
        m.wall_with_gaps((x_in, -bd / 2), (x_in, bd / 2), fh, 0.4, [(3.0, 2.0, 2.4), (11.0, 2.0, 2.4)], "wall", name="BldWall")
        m.wall_with_gaps((x_out, -bd / 2), (x_out, bd / 2), fh, 0.4, [(7.0, 2.0, 2.4)], "wall", name="BldWall")
        m.wall_with_gaps((x_in, -bd / 2), (x_out, -bd / 2), fh, 0.4, [(4.0, 2.0, 2.4)], "wall", name="BldWall")
        m.wall_with_gaps((x_in, bd / 2), (x_out, bd / 2), fh, 0.4, [(4.0, 2.0, 2.4)], "wall", name="BldWall")
        # Upper floor covers the north half; the south half is open to the
        # ground floor and holds the ramp (7.6 m run for 3.6 m rise ≈ 25°).
        m.box((cx, fh + 0.1, -4.0), (bw, 0.2, 8.0), mat, "UpperFloor")
        m.ramp((cx + sx * 2.5, 0.0, bd / 2 - 0.4), (cx + sx * 2.5 + 0.001, fh + 0.2, 0.0), 2.4, "accent")
        # Upper floor parapets (plaza side has window gaps, north end solid).
        m.wall_with_gaps((x_in, -bd / 2), (x_in, 0.0), 1.1, 0.3, [(2.0, 2.5, 99.0)], "wall", y0=fh + 0.2, name="Parapet")
        m.wall_with_gaps((x_in, -bd / 2), (x_out, -bd / 2), 1.1, 0.3, [], "wall", y0=fh + 0.2, name="Parapet")
        # Cover crates on the roof.
        m.box((cx - sx * 1.5, fh + 0.7, -5.0), (1.2, 1.0, 1.2), "wood", "RoofCrate")

    # Bomb sites on the ground floor of each building.
    m.site("A", (-21.0, 0.0, -4.0))
    m.site("B", (21.0, 0.0, -4.0))

    for x in (-6, 0, 6):
        m.spawn("blue", (x, 0.1, S / 2 - 3.0), 0)
    m.spawn("blue", (-20, 0.1, S / 2 - 5.0), -15)
    for x in (-6, 0, 6):
        m.spawn("red", (x, 0.1, -S / 2 + 3.0), 180)
    m.spawn("red", (20, 0.1, -S / 2 + 5.0), 165)
    m.spawn("ffa", (-26, 0.1, 0), 90)
    m.spawn("ffa", (26, 0.1, 0), -90)
    m.write("scenes/levels/courtyard.tscn", sun_rot=(-45.0, -35.0), sky=(0.35, 0.55, 0.85))


if __name__ == "__main__":
    warehouse()
    courtyard()
