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
    # kind: 0 panels, 1 concrete, 2 metal, 3 wood, 4 painted, 5 stone paving, 6 foliage
    # (see assets/shaders/prototype_grid.gdshader)
    "grid": {"kind": 1, "base_color": (0.42, 0.42, 0.41), "line_color": (0.3, 0.3, 0.3), "cell_size": 3.0, "grime": 0.0},
    "wall": {"kind": 4, "base_color": (0.56, 0.54, 0.5), "line_color": (0.42, 0.4, 0.37), "grime": 0.35},
    "accent": {"kind": 2, "base_color": (0.3, 0.38, 0.46), "line_color": (0.2, 0.26, 0.32), "cell_size": 0.5,
               "roughness_value": 0.5, "metallic_value": 0.4, "grime": 0.15},
    "wood": {"kind": 3, "base_color": (0.5, 0.36, 0.22), "line_color": (0.24, 0.16, 0.09), "cell_size": 0.3,
             "roughness_value": 0.75, "grime": 0.1},
    "metal": {"kind": 2, "base_color": (0.36, 0.38, 0.4), "line_color": (0.22, 0.24, 0.26), "cell_size": 1.0,
              "roughness_value": 0.45, "metallic_value": 0.6, "grime": 0.2},
    "stone": {"kind": 5, "base_color": (0.6, 0.57, 0.5), "line_color": (0.36, 0.34, 0.3), "cell_size": 1.5, "grime": 0.25},
    "blue": {"kind": 4, "base_color": (0.24, 0.38, 0.66), "line_color": (0.17, 0.27, 0.5), "grime": 0.3},
    "red": {"kind": 4, "base_color": (0.66, 0.28, 0.23), "line_color": (0.5, 0.19, 0.16), "grime": 0.3},
    "site": {"kind": 0, "base_color": (0.95, 0.55, 0.15), "line_color": (0.75, 0.35, 0.1), "cell_size": 0.5, "grime": 0.0},
    "leaf": {"kind": 6, "base_color": (0.25, 0.42, 0.18), "line_color": (0.2, 0.3, 0.15), "grime": 0.0},
    # Desert town (kinds 7-10).
    "sandstone": {"kind": 7, "base_color": (0.78, 0.63, 0.44), "line_color": (0.6, 0.47, 0.33), "cell_size": 1.4,
                  "line_width": 0.035, "roughness_value": 0.95, "grime": 0.3},
    "plaster": {"kind": 8, "base_color": (0.84, 0.78, 0.67), "line_color": (0.72, 0.56, 0.38), "cell_size": 1.0,
                "line_width": 0.03, "roughness_value": 0.9, "grime": 0.35},
    "plaster_warm": {"kind": 8, "base_color": (0.84, 0.68, 0.48), "line_color": (0.66, 0.5, 0.34), "cell_size": 1.0,
                     "line_width": 0.03, "roughness_value": 0.9, "grime": 0.35},
    "paving": {"kind": 9, "base_color": (0.62, 0.52, 0.4), "line_color": (0.42, 0.37, 0.3), "cell_size": 0.9,
               "line_width": 0.04, "roughness_value": 0.9, "grime": 0.0},
    "sand": {"kind": 1, "base_color": (0.68, 0.57, 0.42), "line_color": (0.7, 0.6, 0.45), "cell_size": 4.0,
             "line_width": 0.0, "roughness_value": 1.0, "grime": 0.0},
    "teal": {"kind": 4, "base_color": (0.24, 0.47, 0.48), "line_color": (0.18, 0.36, 0.38), "grime": 0.25},
    "shutter": {"kind": 3, "base_color": (0.26, 0.42, 0.55), "line_color": (0.16, 0.27, 0.36), "cell_size": 0.12,
                "roughness_value": 0.7, "grime": 0.0},
    "dark": {"kind": 4, "base_color": (0.06, 0.06, 0.07), "line_color": (0.05, 0.05, 0.05), "grime": 0.0,
             "roughness_value": 0.6},
    "clay": {"kind": 1, "base_color": (0.78, 0.6, 0.4), "line_color": (0.6, 0.45, 0.3), "cell_size": 2.0,
             "line_width": 0.0, "roughness_value": 0.85, "grime": 0.0},
    "cloth_red": {"kind": 10, "base_color": (0.7, 0.24, 0.18), "line_color": (0.85, 0.75, 0.6), "cell_size": 0.35,
                  "roughness_value": 1.0, "grime": 0.0},
    "cloth_blue": {"kind": 10, "base_color": (0.22, 0.36, 0.55), "line_color": (0.82, 0.8, 0.72), "cell_size": 0.35,
                   "roughness_value": 1.0, "grime": 0.0},
    "cable": {"kind": 4, "base_color": (0.05, 0.05, 0.05), "line_color": (0.05, 0.05, 0.05), "grime": 0.0},
    "palm": {"kind": 6, "base_color": (0.3, 0.45, 0.16), "line_color": (0.2, 0.3, 0.1), "grime": 0.0},
    "sack": {"kind": 10, "base_color": (0.66, 0.6, 0.46), "line_color": (0.62, 0.56, 0.43), "cell_size": 0.5,
             "roughness_value": 1.0, "grime": 0.0},
}
SITE_RADIUS = 3.5  # keep in sync with BombRules.SITE_RADIUS


class Map:
    def __init__(self, name):
        self.name = name
        self.boxes = []  # (name, pos, shape, basis_columns, material, collide); shape = ("box", size) | ("cyl", ...)
        self.spawns = {"ffa": [], "blue": [], "red": []}
        self.lights = []
        self.sites = []  # (name, pos)
        self.callouts = []  # (label, pos, size)
        self.zones = []  # (pos, size, bus, amount, priority)
        self._n = {}

    def _id(self, prefix):
        self._n[prefix] = self._n.get(prefix, 0) + 1
        return f"{prefix}{self._n[prefix]}"

    @staticmethod
    def _basis(yaw=0.0, pitch=0.0, roll=0.0):
        """Columns of Ry(yaw) · Rx(pitch) · Rz(roll) (degrees)."""
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
        cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
        ry = ((cy, 0, -sy), (0, 1, 0), (sy, 0, cy))
        rx = ((1, 0, 0), (0, cp, -sp), (0, sp, cp))
        rz = ((cr, -sr, 0), (sr, cr, 0), (0, 0, 1))

        def mul(a, b):
            return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))
        m = mul(mul(ry, rx), rz)
        return tuple(m[r][c] for c in range(3) for r in range(3))

    def box(self, pos, size, mat="grid", name="Box", yaw=0.0, collide=True, pitch=0.0, roll=0.0):
        self.boxes.append((self._id(name), pos, ("box", size), self._basis(yaw, pitch, roll), mat, collide))

    def cyl(self, pos, radius, height, mat="grid", name="Cyl", top=None, segments=10, collide=True,
            yaw=0.0, pitch=0.0, roll=0.0):
        """Upright cylinder (or cone/frustum with `top` radius), centred on pos."""
        top = radius if top is None else top
        self.boxes.append((self._id(name), pos, ("cyl", top, radius, height, segments),
                           self._basis(yaw, pitch, roll), mat, collide))

    def blocker(self, pos, size, name="Blocker"):
        """Invisible collision box (e.g. one collider for a pile of sandbags)."""
        self.boxes.append((self._id(name), pos, ("box", size), self._basis(), None, True))

    def beam(self, a, b, thickness, mat="cable", name="Beam", collide=False, width=None):
        """Thin box from point a to point b (cables, poles, palm fronds)."""
        dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        h = math.hypot(dx, dz)
        length = math.hypot(h, dy)
        yaw = math.degrees(math.atan2(-dx, dz))
        pitch = -math.degrees(math.atan2(dy, h))
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
        self.box(mid, (width or thickness, thickness, length), mat, name, yaw=yaw, pitch=pitch, collide=collide)

    def callout(self, label, pos, size):
        """Location name shown under the minimap while inside this box."""
        self.callouts.append((label, pos, size))

    def ramp(self, start, end, width, mat="accent", thickness=0.3, name="Ramp", collide=True):
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
        self.boxes.append((self._id(name), (cx, cy, cz), ("box", size), basis, mat, collide))

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

    def reverb(self, pos, size, kind="room", amount=0.4, priority=0):
        """Indoor echo: sounds made inside this box are sent to the
        ReverbRoom / ReverbHall bus (Area3D on physics layer 7). Overlapping
        zones: the higher priority wins."""
        bus = {"room": "ReverbRoom", "hall": "ReverbHall"}[kind]
        self.zones.append((pos, size, bus, amount, priority))

    # ------------------------------------------------------------------
    def write(self, path, sun_rot=(-50.0, 30.0), sky=(0.32, 0.5, 0.75), fog=0.0, horizon=(0.66, 0.7, 0.76),
              sun_color=(1, 0.95, 0.86), sun_energy=1.2, ambient=1.0, fog_color=None, ambient_color=None):
        subs, nodes = [], []
        for i, (name, pos, shape, basis, mat, collide) in enumerate(self.boxes):
            sid = i + 1
            if shape[0] == "box":
                size = shape[1]
                if mat is not None:
                    subs.append(f'[sub_resource type="BoxMesh" id="Mesh_{sid}"]\nmaterial = SubResource("Mat_{mat}")\nsize = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n')
            else:
                _, top, bottom, height, segs = shape
                if mat is not None:
                    subs.append(f'[sub_resource type="CylinderMesh" id="Mesh_{sid}"]\nmaterial = SubResource("Mat_{mat}")\n'
                            f'top_radius = {top:.3f}\nbottom_radius = {bottom:.3f}\nheight = {height:.3f}\nradial_segments = {segs}\nrings = 1\n')
            b = ", ".join(f"{v:.6f}" for v in basis)
            nodes.append(f'[node name="{name}" type="StaticBody3D" parent="Geometry"]\ntransform = Transform3D({b}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n')
            if mat is not None:
                nodes.append(f'[node name="Mesh" type="MeshInstance3D" parent="Geometry/{name}"]\nmesh = SubResource("Mesh_{sid}")\n')
            if collide:
                if shape[0] == "box":
                    subs.append(f'[sub_resource type="BoxShape3D" id="Shape_{sid}"]\nsize = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n')
                else:
                    subs.append(f'[sub_resource type="CylinderShape3D" id="Shape_{sid}"]\nradius = {max(top, bottom):.3f}\nheight = {height:.3f}\n')
                nodes.append(f'[node name="Collision" type="CollisionShape3D" parent="Geometry/{name}"]\nshape = SubResource("Shape_{sid}")\n')
        mats = []
        used = {b[4] for b in self.boxes} | {"site"}
        for key, params in MATERIALS.items():
            if key not in used:
                continue
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

        zone_nodes = []
        for i, (pos, size, bus, amount, prio) in enumerate(self.zones):
            zid = i + 1
            subs.append(f'[sub_resource type="BoxShape3D" id="Zone_{zid}"]\nsize = Vector3({size[0]:.3f}, {size[1]:.3f}, {size[2]:.3f})\n')
            zone_nodes.append(f'[node name="Reverb{zid}" type="Area3D" parent="AudioZones"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})\n'
                              f'collision_layer = 64\ncollision_mask = 0\nmonitoring = false\npriority = {prio}\n'
                              f'reverb_bus_enabled = true\nreverb_bus_name = &"{bus}"\nreverb_bus_amount = {amount}\nreverb_bus_uniformity = 0.2\n'
                              f'\n[node name="Shape" type="CollisionShape3D" parent="AudioZones/Reverb{zid}"]\nshape = SubResource("Zone_{zid}")\n')

        fog_line = f"fog_light_color = Color({fog_color[0]}, {fog_color[1]}, {fog_color[2]}, 1)\nfog_sky_affect = 0.15\n" if fog_color else ""
        ambient_line = f"ambient_light_color = Color({ambient_color[0]}, {ambient_color[1]}, {ambient_color[2]}, 1)\n" if ambient_color else ""
        callout_nodes = []
        for i, (label, pos, size) in enumerate(self.callouts):
            callout_nodes.append(f'[node name="Callout{i + 1}" type="Marker3D" parent="Callouts"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]})\n'
                                 f'metadata/label = "{label}"\nmetadata/size = Vector3({size[0]}, {size[1]}, {size[2]})\n')
        head = f'''[gd_scene load_steps={len(subs) + len(mats) + 9} format=3]

[ext_resource type="Script" path="res://scripts/levels/level.gd" id="1_level"]
[ext_resource type="PackedScene" path="res://scenes/ui/hud.tscn" id="2_hud"]
[ext_resource type="PackedScene" path="res://scenes/ui/pause_menu.tscn" id="3_pause"]
[ext_resource type="Shader" path="res://assets/shaders/prototype_grid.gdshader" id="4_grid"]
[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="6_player"]

[sub_resource type="ProceduralSkyMaterial" id="SkyMat"]
sky_top_color = Color({sky[0]}, {sky[1]}, {sky[2]}, 1)
sky_horizon_color = Color({horizon[0]}, {horizon[1]}, {horizon[2]}, 1)
sky_curve = 0.12
ground_bottom_color = Color(0.3, 0.28, 0.26, 1)
ground_horizon_color = Color(0.62, 0.62, 0.62, 1)
sun_angle_max = 20.0

[sub_resource type="Sky" id="Sky"]
sky_material = SubResource("SkyMat")

[sub_resource type="Environment" id="Env"]
background_mode = 2
sky = SubResource("Sky")
ambient_light_source = 3
ambient_light_sky_contribution = {0.85 if ambient_color is None else 0.35}
{ambient_line}ambient_light_energy = {ambient}
reflected_light_source = 2
tonemap_mode = 2
tonemap_exposure = 1.0
tonemap_white = 6.0
glow_enabled = true
glow_intensity = 0.6
glow_bloom = 0.05
fog_enabled = {"true" if fog > 0 else "false"}
fog_density = {fog}
{fog_line}volumetric_fog_density = 0.01

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
light_color = Color({sun_color[0]}, {sun_color[1]}, {sun_color[2]}, 1)
light_energy = {sun_energy}
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
               + '\n[node name="BombSites" type="Node3D" parent="."]\n\n' + "\n".join(site_nodes)
               + ('\n[node name="AudioZones" type="Node3D" parent="."]\n\n' + "\n".join(zone_nodes) if zone_nodes else "")
               + ('\n[node name="Callouts" type="Node3D" parent="."]\n\n' + "\n".join(callout_nodes) if callout_nodes else "")
               + "\n" + tail)
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
    # Echo: the big hall, drier small offices.
    m.reverb((0, H / 2, 0), (W, H, D), "hall", 0.45)
    for sx in (-1, 1):
        m.reverb((sx * (W / 2 - 3.5), 1.5, D / 2 - 3.5), (7, 3, 7), "room", 0.4, priority=1)
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
        m.box((x, 3.8, z), (3.0, 2.2, 3.0), "leaf", "Canopy", collide=False)

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
    for sx in (-1, 1):
        m.reverb((sx * 21.0, 2.8, 0), (10, 5.6, 16), "room", 0.35)
    m.write("scenes/levels/courtyard.tscn", sun_rot=(-45.0, -35.0), sky=(0.35, 0.55, 0.85))


def rooftops():
    """Four flat-roofed buildings around a crossroads. Bridges link the
    roofs, ramps climb from the street; falling off just drops you back to
    the street — vertical fights with long sight lines."""
    m = Map("Rooftops")
    S, H = 54.0, 4.0
    m.box((0, -0.5, 0), (S + 2, 1, S + 2), "grid", "Street")
    for (pos, size) in (((0, 3, -S / 2 - 0.5), (S + 2, 6, 1)), ((0, 3, S / 2 + 0.5), (S + 2, 6, 1)),
                        ((S / 2 + 0.5, 3, 0), (1, 6, S)), ((-S / 2 - 0.5, 3, 0), (1, 6, S))):
        m.box(pos, size, "wall", "Boundary")
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = sx * 14.0, sz * 14.0
            m.box((cx, H / 2, cz), (14, H, 14), "wall" if sz < 0 else "stone", "Building")
            # Parapets on the outer edges only (inner edges hold bridges/ramps).
            m.box((sx * 20.85, H + 0.4, cz), (0.3, 0.8, 14), "wall", "Parapet")
            m.box((cx, H + 0.4, sz * 20.85), (14, 0.8, 0.3), "wall", "Parapet")
            # Rooftop cover: AC units and a water tank.
            m.box((cx - sx * 3, H + 0.6, cz + sz * 2), (1.6, 1.2, 1.6), "metal", "ACUnit")
            m.box((cx + sx * 2, H + 0.6, cz - sz * 3), (1.6, 1.2, 1.6), "metal", "ACUnit")
            m.box((cx + sx * 4, H + 1.25, cz + sz * 4), (2, 2.5, 2), "accent", "WaterTank")
    # Bridges between the roofs (top surface at roof height).
    m.box((0, H - 0.15, -14), (14, 0.3, 2.5), "wood", "Bridge")
    m.box((0, H - 0.15, 14), (14, 0.3, 2.5), "wood", "Bridge")
    # Ramps from the crossroads up to each roof edge.
    m.ramp((-16, 0.0, 1.0), (-16.001, H, -7.0), 2.4, "accent")
    m.ramp((-12, 0.0, -1.0), (-12.001, H, 7.0), 2.4, "accent")
    m.ramp((16, 0.0, 1.0), (16.001, H, -7.0), 2.4, "accent")
    m.ramp((12, 0.0, -1.0), (12.001, H, 7.0), 2.4, "accent")
    # Parked cars as street cover.
    for (x, z, yaw) in ((-3, -3, 90), (4, 3, 90), (0, -18, 0), (2, 20, 0), (-24, -12, 0), (24, 12, 0)):
        m.box((x, 0.7, z), (2.0, 1.4, 4.2), "red" if x < 0 else "blue", "Car", yaw=yaw)
    for (x, z) in ((0, 0), (-14, 0), (14, 0), (0, -14), (0, 14)):
        m.omni((x, 6.0, z), 1.2, 14.0)

    m.site("A", (-24.0, 0.0, 6.0))
    m.site("B", (24.0, 0.0, -6.0))
    for (x, z) in ((-14, 17), (-10, 14), (14, 17), (10, 14)):
        m.spawn("blue", (x, H + 0.1, z), 0)
    for (x, z) in ((-14, -17), (-10, -14), (14, -17), (10, -14)):
        m.spawn("red", (x, H + 0.1, z), 180)
    m.spawn("ffa", (-24, 0.1, 0), 90)
    m.spawn("ffa", (24, 0.1, 0), -90)
    m.write("scenes/levels/rooftops.tscn", sun_rot=(-40.0, 60.0), sky=(0.45, 0.55, 0.8))


def docks():
    """Container yard next to a moored ship: lanes between (stacked)
    containers, and a raised ship deck reached by two gangways."""
    m = Map("Docks")
    SX, SZ, DECK = 64.0, 48.0, 3.0
    m.box((0, -0.5, 0), (SX + 2, 1, SZ + 2), "stone", "Quay")
    for (pos, size) in (((0, 3, -SZ / 2 - 0.5), (SX + 2, 6, 1)), ((0, 3, SZ / 2 + 0.5), (SX + 2, 6, 1)),
                        ((SX / 2 + 0.5, 3, 0), (1, 6, SZ)), ((-SX / 2 - 0.5, 3, 0), (1, 6, SZ))):
        m.box(pos, size, "wall", "Boundary")
    # Ship: solid hull with a walkable deck, rail on the sea side.
    m.box((0, DECK / 2, -19), (44, DECK, 8), "metal", "Hull")
    m.box((0, DECK + 0.5, -22.85), (44, 1.0, 0.3), "metal", "Rail")
    m.ramp((-18, 0.0, -5.0), (-18.001, DECK, -15.0), 2.5, "wood")
    m.ramp((18, 0.0, -5.0), (18.001, DECK, -15.0), 2.5, "wood")
    for x in (-15, 15):
        m.box((x, DECK + 1.3, -19), (6, 2.6, 2.4), "red" if x < 0 else "blue", "DeckContainer")
    m.box((0, DECK + 0.6, -18), (1.2, 1.2, 1.2), "wood", "DeckCrate")
    # Containers: (x, z, yaw, stack level, material).
    for (x, z, yaw, lvl, mat) in (
            (-26, -8, 0, 0, "blue"), (-26, -8, 0, 1, "red"), (-10, -7, 0, 0, "red"), (-3, -7, 0, 0, "wood"),
            (8, -8, 90, 0, "blue"), (24, -8, 0, 0, "metal"), (24, -8, 0, 1, "blue"),
            (-20, 4, 90, 0, "wood"), (-12, 6, 0, 0, "blue"), (-12, 6, 0, 1, "metal"), (0, 3, 0, 0, "red"),
            (12, 6, 0, 0, "metal"), (20, 4, 90, 0, "red"), (-6, 14, 0, 0, "metal"), (6, 14, 0, 0, "wood"),
            (-24, 16, 0, 0, "red"), (24, 16, 0, 0, "blue")):
        m.box((x, 1.3 + lvl * 2.6, z), (6, 2.6, 2.4), mat, "Container", yaw=yaw)
    # Gantry crane (legs collide, beam is visual).
    for z in (-10, 10):
        m.box((-30, 6, z), (1, 12, 1), "accent", "CraneLeg")
    m.box((-30, 12.5, 0), (1.2, 1, 21), "accent", "CraneBeam", collide=False)
    for (x, z) in ((-16, 0), (0, 10), (16, 0), (0, -12)):
        m.omni((x, 6.0, z), 1.3, 15.0)

    m.site("A", (-18.0, 0.0, 10.0))
    m.site("B", (16.0, 0.0, 10.0))
    for (x, z) in ((-10, 21), (0, 21), (10, 21), (-20, 20)):
        m.spawn("blue", (x, 0.1, z), 0)
    for x in (-8, -3, 3, 8):
        m.spawn("red", (x, DECK + 0.1, -19), 180)
    m.spawn("ffa", (-30, 0.1, 0), 90)
    m.spawn("ffa", (30, 0.1, 0), -90)
    m.write("scenes/levels/docks.tscn", sun_rot=(-55.0, 20.0), sky=(0.4, 0.55, 0.75))


def bunker():
    """Small symmetric close-quarters map: a pillared atrium in the middle,
    four corner rooms, and the corridors between them. Good for 2v2."""
    m = Map("Bunker")
    S, H = 40.0, 3.5
    m.box((0, -0.5, 0), (S + 2, 1, S + 2), "metal", "Floor")
    for (pos, size) in (((0, 2, -S / 2 - 0.5), (S + 2, 4, 1)), ((0, 2, S / 2 + 0.5), (S + 2, 4, 1)),
                        ((S / 2 + 0.5, 2, 0), (1, 4, S)), ((-S / 2 - 0.5, 2, 0), (1, 4, S))):
        m.box(pos, size, "wall", "Boundary")
    # Atrium (12 × 12) with a door in the middle of each wall.
    for (a, b) in (((-6, -6), (6, -6)), ((-6, 6), (6, 6)), ((-6, -6), (-6, 6)), ((6, -6), (6, 6))):
        m.wall_with_gaps(a, b, H, 0.4, [(4.5, 3.0, 99.0)], "wall", name="AtriumWall")
    for (x, z) in ((-2.5, -2.5), (2.5, 2.5), (-2.5, 2.5), (2.5, -2.5)):
        m.box((x, H / 2, z), (0.8, H, 0.8), "stone", "Pillar")
    # Corner rooms (10 × 10), doors facing the corridors.
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.wall_with_gaps((sx * 10, sz * 20), (sx * 10, sz * 10), H, 0.4, [(3.5, 3.0, 99.0)], "wall", name="RoomWall")
            m.wall_with_gaps((sx * 20, sz * 10), (sx * 10, sz * 10), H, 0.4, [(3.5, 3.0, 99.0)], "wall", name="RoomWall")
            m.box((sx * 16, 0.6, sz * 16), (1.2, 1.2, 2.4), "wood", "RoomCrate")
            m.omni((sx * 15, H - 0.4, sz * 15), 1.0, 9.0)
    # Corridor cover and overhead beams.
    for (x, z) in ((-14, -3), (14, 3), (-3, 14), (3, -14)):
        m.box((x, 0.6, z), (1.2, 1.2, 1.2), "wood", "Crate")
    for z in (-15, -5, 5, 15):
        m.box((0, H + 0.2, z), (S, 0.4, 0.4), "metal", "Beam", collide=False)
    m.omni((0, H - 0.4, 0), 1.2, 10.0)

    m.site("A", (-15.0, 0.0, 0.0))
    m.site("B", (15.0, 0.0, 0.0))
    for (x, z) in ((-16, 13), (-13, 16), (16, 13), (13, 16)):
        m.spawn("blue", (x, 0.1, z), 0)
    for (x, z) in ((-16, -13), (-13, -16), (16, -13), (13, -16)):
        m.spawn("red", (x, 0.1, z), 180)
    m.spawn("ffa", (0, 0.1, 8), 0)
    m.spawn("ffa", (0, 0.1, -8), 180)
    m.reverb((0, H / 2, 0), (S, H, S), "room", 0.4)
    m.reverb((0, H / 2, 0), (12, H, 12), "hall", 0.4, priority=1)
    m.write("scenes/levels/bunker.tscn", sun_rot=(-70.0, 10.0), sky=(0.35, 0.4, 0.5))


# ----------------------------------------------------------------------
# Desert town dressing helpers (used by kasbah()).

def _facade(m, rng, x0, x1, z0, z1, h, faces, floor_h=3.2, spacing=4.5):
    """Windows (dark inset + frame + optional open shutters), doors and
    balconies on the given faces ("n", "s", "e", "w") of a solid block."""
    for face in faces:
        if face in "ns":
            z = z0 if face == "n" else z1
            out = -1 if face == "n" else 1
            length, along = x1 - x0, "x"
        else:
            x = x1 if face == "e" else x0
            out = 1 if face == "e" else -1
            length, along = z1 - z0, "z"
        count = max(1, int(length // spacing))
        step = length / count
        floors = max(1, int((h - 0.8) // floor_h))
        for i in range(count):
            t = (i + 0.5) * step
            for f in range(floors):
                y = 1.6 + f * floor_h + (0.3 if f > 0 else 0.0)
                if f == 0 and rng.random() < 0.3:
                    # A door instead of a ground floor window.
                    w, wh, y = 1.3, 2.3, 1.15
                elif rng.random() < 0.25:
                    continue
                else:
                    w, wh = 1.0, 1.35
                    if f == 0:
                        y = 1.9
                if along == "x":
                    px = x0 + t
                    m.box((px, y, z + out * 0.04), (w + 0.3, wh + 0.3, 0.08), "sandstone", "Frame", collide=False)
                    m.box((px, y, z + out * 0.07), (w, wh, 0.08), "dark", "Window", collide=False)
                    if wh < 2 and rng.random() < 0.5:
                        for side in (-1, 1):
                            m.box((px + side * (w / 2 + 0.28), y, z + out * 0.3), (0.5, wh, 0.05), "shutter", "Shutter",
                                  yaw=side * out * 60, collide=False)
                    if f > 0 and rng.random() < 0.2:
                        m.box((px, y - wh / 2 - 0.1, z + out * 0.5), (w + 1.0, 0.15, 1.0), "sandstone", "Balcony", collide=False)
                        m.box((px, y - wh / 2 + 0.35, z + out * 0.97), (w + 1.0, 0.8, 0.06), "cable", "Railing", collide=False)
                else:
                    pz = z0 + t
                    m.box((x + out * 0.04, y, pz), (0.08, wh + 0.3, w + 0.3), "sandstone", "Frame", collide=False)
                    m.box((x + out * 0.07, y, pz), (0.08, wh, w), "dark", "Window", collide=False)
                    if wh < 2 and rng.random() < 0.5:
                        for side in (-1, 1):
                            m.box((x + out * 0.3, y, pz + side * (w / 2 + 0.28)), (0.05, wh, 0.5), "shutter", "Shutter",
                                  yaw=-side * out * 60, collide=False)
                    if f > 0 and rng.random() < 0.2:
                        m.box((x + out * 0.5, y - wh / 2 - 0.1, pz), (1.0, 0.15, w + 1.0), "sandstone", "Balcony", collide=False)
                        m.box((x + out * 0.97, y - wh / 2 + 0.35, pz), (0.06, 0.8, w + 1.0), "cable", "Railing", collide=False)


def _building(m, rng, x0, x1, z0, z1, h, mat, faces="nsew", roof=True):
    """Solid block with a parapet, windows on `faces` and some roof clutter."""
    cx, cz, w, d = (x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0
    m.box((cx, h / 2, cz), (w, h, d), mat, "Building")
    # Parapet rim (visual — the roofs are out of reach) and a plinth.
    m.box((cx, h + 0.3, z0 + 0.15), (w, 0.6, 0.3), mat, "Parapet", collide=False)
    m.box((cx, h + 0.3, z1 - 0.15), (w, 0.6, 0.3), mat, "Parapet", collide=False)
    m.box((x0 + 0.15, h + 0.3, cz), (0.3, 0.6, d - 0.6), mat, "Parapet", collide=False)
    m.box((x1 - 0.15, h + 0.3, cz), (0.3, 0.6, d - 0.6), mat, "Parapet", collide=False)
    _facade(m, rng, x0, x1, z0, z1, h, faces)
    if roof:
        if rng.random() < 0.6:
            tx, tz = cx + rng.uniform(-w / 4, w / 4), cz + rng.uniform(-d / 4, d / 4)
            m.cyl((tx, h + 0.9, tz), 0.7, 1.4, "plaster", "Tank", collide=False)
        if rng.random() < 0.7:
            ax, az = x0 + rng.uniform(1, w - 1), z0 + rng.uniform(1, d - 1)
            m.box((ax, h + 1.6, az), (0.06, 3.2, 0.06), "cable", "Antenna", collide=False)
            m.box((ax, h + 2.8, az), (1.4, 0.05, 0.05), "cable", "Antenna", collide=False)
            m.box((ax, h + 2.3, az), (0.9, 0.05, 0.05), "cable", "Antenna", collide=False)
        if rng.random() < 0.5:
            m.box((cx + rng.uniform(-w / 3, w / 3), h + 0.8, cz + rng.uniform(-d / 3, d / 3)),
                  (w * 0.3, 1.6, d * 0.3), mat, "RoofHut", collide=False)


def _pot(m, x, z, y=0.0, scale=1.0):
    k = scale
    m.cyl((x, y + 0.24 * k, z), 0.2 * k, 0.48 * k, "clay", "Pot", top=0.34 * k)
    m.cyl((x, y + 0.63 * k, z), 0.34 * k, 0.3 * k, "clay", "PotTop", top=0.2 * k, collide=False)
    m.cyl((x, y + 0.81 * k, z), 0.22 * k, 0.06 * k, "clay", "PotRim", collide=False)


def _barrel(m, x, z, mat="teal", y=0.0):
    m.cyl((x, y + 0.45, z), 0.3, 0.9, mat, "Barrel")
    for ry in (0.18, 0.72):
        m.cyl((x, y + ry, z), 0.315, 0.04, "cable", "Hoop", collide=False)


def _sacks(m, x, z, rows=2, cols=2, y=0.0):
    """Big white sacks (cylinders on end) — solid cover."""
    for r in range(rows):
        for c in range(cols):
            m.cyl((x + c * 0.95, y + 0.55, z + r * 0.95), 0.48, 1.1, "sack", "Sack", top=0.42, segments=9)


def _sandbags(m, a, b, rows=3):
    """Sandbag wall from a=(x,z) to b=(x,z): visual bags + one collider."""
    ax, az = a
    bx, bz = b
    length = math.hypot(bx - ax, bz - az)
    yaw = math.degrees(math.atan2(-(bx - ax), bz - az))
    n = max(1, int(length / 0.55))
    for r in range(rows):
        off = 0.275 if r % 2 else 0.0
        for i in range(n - (1 if r % 2 else 0)):
            t = (i * 0.55 + 0.275 + off) / length
            m.box((ax + (bx - ax) * t, 0.12 + r * 0.22, az + (bz - az) * t), (0.34, 0.22, 0.52), "sack", "Bag",
                  yaw=yaw + (7 if (i + r) % 2 else -5), collide=False)
    m.box(((ax + bx) / 2, rows * 0.11, (az + bz) / 2), (0.36, rows * 0.22, length), None, "BagCollider", yaw=yaw)


def _palm(m, x, z, height=6.0, lean=(0.6, 0.3)):
    top = (x + lean[0], height, z + lean[1])
    m.beam((x, 0.0, z), (x + lean[0] * 0.4, height * 0.5, z + lean[1] * 0.4), 0.32, "wood", "Trunk", collide=True)
    m.beam((x + lean[0] * 0.4, height * 0.5, z + lean[1] * 0.4), top, 0.26, "wood", "Trunk", collide=False)
    for k in range(7):
        a = math.radians(k * 360 / 7 + 10)
        tip = (top[0] + math.cos(a) * 2.6, height - 1.1, top[2] + math.sin(a) * 2.6)
        m.beam(top, tip, 0.05, "palm", "Frond", width=0.7)


def _stall(m, x, z, yaw_face="s", cloth="cloth_red"):
    """Market stall: table, goods, two poles and a sloped awning."""
    out = {"s": 1, "n": -1}[yaw_face]
    m.box((x, 0.45, z), (2.4, 0.9, 1.0), "wood", "Stall")
    for gx in (-0.7, 0.0, 0.7):
        m.box((x + gx, 1.0, z), (0.5, 0.2, 0.5), "clay", "Goods", collide=False)
    for px in (-1.15, 1.15):
        m.box((x + px, 1.2, z + out * 0.9), (0.08, 2.4, 0.08), "wood", "Pole", collide=False)
    m.box((x, 2.35, z + out * 0.35), (2.7, 0.05, 1.9), cloth, "Awning", pitch=out * 14, collide=False)


def _cable(m, a, b):
    """Overhead cable with a little sag (two segments)."""
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 0.5, (a[2] + b[2]) / 2)
    m.beam(a, mid, 0.035, "cable", "Cable")
    m.beam(mid, b, 0.035, "cable", "Cable")


def kasbah():
    """Desert town, bomb-defusal layout: attackers (red) in the south,
    defenders (blue) in the north. Three lanes — A Long on the east, Mid,
    and the covered B Apartments on the west — with a Connector from Mid to
    A and a Short from Mid to B. A is a raised terrace with pots and sacks,
    B a walled courtyard around a well."""
    import random
    rng = random.Random(7)
    m = Map("Kasbah")
    X, Z = 40.0, 46.0
    m.box((0, -0.5, 0), (2 * X + 4, 1, 2 * Z + 4), "paving", "Ground")
    # Worn sandy patches (visual).
    for (x, z, w, d) in ((0, 10, 6, 30), (34, 10, 6, 20), (-34, -20, 5, 8), (0, -40, 20, 6), (28, -12, 6, 4)):
        m.box((x, 0.005, z), (w, 0.01, d), "sand", "Sand", collide=False)

    # Outer ring of tall buildings (the map boundary).
    ring = ("sandstone", "plaster_warm", "plaster", "sandstone")
    for i, x0 in enumerate(range(-40, 40, 16)):
        _building(m, rng, x0, x0 + 16, -Z - 4, -Z, rng.choice((9, 10, 11)), ring[i % 4], "s", roof=False)
        _building(m, rng, x0, x0 + 16, Z, Z + 4, rng.choice((9, 10, 11)), ring[(i + 1) % 4], "n", roof=False)
    for i, z0 in enumerate(range(-46, 46, 23)):
        _building(m, rng, X, X + 4, z0, z0 + 23, rng.choice((9, 11)), ring[(i + 2) % 4], "w", roof=False)
        _building(m, rng, -X - 4, -X, z0, z0 + 23, rng.choice((9, 11)), ring[(i + 3) % 4], "e", roof=False)

    # Inner blocks: (x0, x1, z0, z1, height, material, faces with windows).
    blocks = [
        (4, 18, -32, -20, 7, "plaster", "nswe"),        # CT-side of Connector
        (-18, -4, -32, -14, 8, "sandstone", "nswe"),    # CT-side of Short
        (4, 18, -15, 20, 6, "plaster_warm", "nswe"),    # between Mid and A Long (north)
        (18, 30, -10, 20, 7, "sandstone", "nse"),
        (4, 30, 24, 34, 6, "sandstone", "nsw"),         # Palace
        (-30, -4, -9, 20, 7, "plaster", "nswe"),        # between Mid and B Apartments
        (-30, -4, 24, 34, 6, "plaster_warm", "nse"),
        (14, 28, 38, 46, 7, "plaster", "nw"),           # T spawn sides
        (-28, -14, 38, 46, 7, "sandstone", "ne"),
        (20, 38, -46, -38, 7, "plaster_warm", "sw"),    # CT spawn sides
        (-38, -20, -46, -38, 7, "plaster", "se"),
    ]
    for (x0, x1, z0, z1, h, mat, faces) in blocks:
        _building(m, rng, x0, x1, z0, z1, h, mat, faces)

    # --- B Apartments: a covered corridor (west lane, z 0..18) ----------
    m.box((-34, 3.5, 9), (8, 0.4, 18), "plaster", "ApartmentsCeiling")
    m.box((-34, 7.3, 9), (8, 7.2, 18), "plaster", "ApartmentsUpper")
    _facade(m, rng, -38, -30, 0, 18, 10.9, "", spacing=4)
    m.wall_with_gaps((-34, 3), (-34, 15), 3.3, 0.4, [(3.0, 2.2, 99.0), (8.0, 1.6, 2.4)], "plaster_warm", name="AptWall")
    for z in (0, 18):
        m.wall_with_gaps((-38, z), (-30, z), 3.3, 0.4, [(1.5, 5.0, 2.6)], "sandstone", name="AptArch")
    m.omni((-36, 2.9, 4), 1.2, 8.0, (1.0, 0.8, 0.55))
    m.omni((-32, 2.9, 13), 1.2, 8.0, (1.0, 0.8, 0.55))
    _barrel(m, -37.2, 7.0, "metal")
    m.box((-31, 0.5, 5.5), (1.0, 1.0, 1.0), "wood", "Crate")
    m.reverb((-34, 1.65, 9), (8, 3.3, 18), "room", 0.4)

    # --- Mid: doors half-way, crates, an arch at the crossroads ---------
    m.wall_with_gaps((-4, -2), (4, -2), 4.5, 0.6, [(2.5, 3.0, 3.2)], "sandstone", name="MidDoors")
    m.box((-2.8, 0.6, 8), (1.2, 1.2, 1.2), "wood", "MidCrate")
    m.box((-2.8, 1.8, 8), (1.2, 1.2, 1.2), "wood", "MidCrate", yaw=15)
    m.box((2.6, 0.6, -12), (1.2, 1.2, 1.2), "wood", "MidCrate")
    m.wall_with_gaps((-4, 20), (4, 20), 5.0, 0.8, [(1.0, 6.0, 3.8)], "sandstone", name="MidArch")
    _stall(m, 2.4, 29, "n", "cloth_blue")
    _pot(m, -3.3, 30)
    _pot(m, -3.2, 31)
    _barrel(m, 3.3, -26, "teal")

    # --- Connector (Mid -> A) and Short (Mid -> B) ----------------------
    m.box((11, 4.5, -17.5), (14, 1.2, 5), "sandstone", "ConnectorBridge", collide=False)
    _sacks(m, 13, -19.4, 1, 1)
    m.box((-11, 0.45, -11.5), (1.8, 0.9, 1.0), "wood", "ShortCart")
    _barrel(m, -15, -13.2, "metal")
    _pot(m, -6, -9.6, 0, 0.9)

    # --- A site: raised terrace ------------------------------------------
    TY = 1.0
    m.box((28, TY / 2, -23), (12, TY, 10), "sandstone", "Terrace")
    m.ramp((28, 0.0, -13.0), (28.001, TY, -18.0), 4.0, "paving", thickness=0.4)
    # Low wall along the terrace front (either side of the ramp), pots on top.
    m.box((24.0, TY + 0.45, -18.3), (4.0, 0.9, 0.5), "plaster", "TerraceWall")
    m.box((32.0, TY + 0.45, -18.3), (4.0, 0.9, 0.5), "plaster", "TerraceWall")
    for x in (22.8, 24.0, 25.2):
        _pot(m, x, -18.3, TY + 0.9, 0.75)
    _sacks(m, 32.5, -26.5, 1, 2, TY)
    _barrel(m, 23.2, -27.2, "teal", TY)
    _barrel(m, 23.9, -27.6, "teal", TY)
    m.box((33.5, TY + 0.6, -21), (1.2, 1.2, 1.2), "wood", "SiteCrate", yaw=12)
    # The teal-covered cart near A Ramp and sacks in front of the terrace.
    m.box((21, 0.75, -14.5), (3.2, 1.5, 1.8), "teal", "Cart")
    m.box((21, 0.25, -14.5), (3.4, 0.5, 2.0), "wood", "CartBase")
    _sacks(m, 34, -13.5, 1, 2)
    _pot(m, 36.5, -30)
    _pot(m, 37.2, -29.3, 0, 1.2)
    # Half-open north side of A towards CT: wall with two gaps.
    m.wall_with_gaps((18, -32), (38, -32), 3.0, 0.5, [(2.0, 5.0, 99.0), (13.0, 4.0, 99.0)], "sandstone", name="ASiteWall")
    _palm(m, 36.5, -35, 7.0, (-0.8, 0.4))
    m.site("A", (28.0, TY, -23.0))

    # --- A Long: sandbags, a doorway into the site ------------------------
    _sandbags(m, (31.0, 6.0), (34.0, 6.0))
    m.box((36.5, 0.6, 14), (1.2, 1.2, 1.2), "wood", "LongCrate")
    m.box((36.5, 0.6, 15.3), (1.2, 1.2, 1.2), "wood", "LongCrate", yaw=8)
    m.wall_with_gaps((30, -8), (38, -8), 4.5, 0.6, [(2.5, 3.2, 3.2)], "plaster", name="LongDoors")
    _barrel(m, 37.3, 28, "metal")
    _barrel(m, 36.6, 28.4, "teal")

    # --- B site: courtyard with a well, pillars and a stall --------------
    m.cyl((-28, 0.45, -22), 1.4, 0.9, "sandstone", "Well", segments=14)
    m.box((-29.3, 1.6, -22), (0.15, 2.2, 0.15), "wood", "WellPost", collide=False)
    m.box((-26.7, 1.6, -22), (0.15, 2.2, 0.15), "wood", "WellPost", collide=False)
    m.box((-28, 2.7, -22), (2.9, 0.15, 0.15), "wood", "WellBeam", collide=False)
    for (x, z) in ((-33, -27), (-23, -27), (-33, -16), (-23, -16)):
        m.box((x, 2.0, z), (0.9, 4.0, 0.9), "sandstone", "Pillar")
    _stall(m, -34, -30.5, "s", "cloth_red")
    _sacks(m, -21.5, -29.5, 2, 1)
    _sandbags(m, (-25.0, -12.5), (-21.0, -12.5), 3)
    _barrel(m, -37, -12.5, "teal")
    m.box((-19.5, 0.6, -24), (1.2, 1.2, 1.2), "wood", "BCrate")
    m.wall_with_gaps((-38, -32), (-18, -32), 3.0, 0.5, [(6.0, 4.5, 99.0)], "plaster_warm", name="BSiteWall")
    _palm(m, -20.5, -35.5, 6.5, (0.5, 0.6))
    m.site("B", (-28.0, 0.0, -20.0))

    # --- T spawn and CT spawn dressing -----------------------------------
    for x in (-8, 8):
        _palm(m, x, 43.5, 6.5, (0.3 * (1 if x > 0 else -1), -0.5))
    _stall(m, -10, 36.2, "s", "cloth_blue")
    _pot(m, 12, 44.5)
    _pot(m, 12.8, 44.8, 0, 0.8)
    m.cyl((0, 0.5, -41), 2.2, 1.0, "sandstone", "Fountain", segments=16)
    m.cyl((0, 1.4, -41), 0.35, 1.8, "sandstone", "FountainPillar", collide=False)
    m.cyl((0, 2.35, -41), 0.9, 0.2, "sandstone", "FountainBowl", collide=False, top=1.1)
    _barrel(m, -15.5, -36.5, "metal")
    _sacks(m, 14, -37, 1, 2)

    # Overhead cables between facades (visual).
    for (a, b) in (((4, 5.5, -10), (-4, 5.8, -6)), ((4, 5.2, 2), (-4, 5.5, 8)), ((18, 6.2, -12), (30, 6.8, -9)),
                   ((30, 6.0, 4), (38, 7.5, 2)), ((-30, 6.0, 22), (-4, 5.6, 22.5)), ((4, 5.8, 22), (30, 5.6, 22.5)),
                   ((18, 6.5, -32), (30, 7.0, -38)), ((-18, 7.0, -32), (-4, 6.5, -32)), ((-30, 6.2, -9), (-38, 8.0, -12))):
        _cable(m, a, b)
    # Utility poles on A Long.
    for z in (-2, 26):
        m.cyl((30.4, 3.5, z), 0.1, 7.0, "wood", "Pole", segments=6)
        m.box((30.4, 6.7, z), (1.2, 0.08, 0.08), "wood", "PoleBar", collide=False)
    _cable(m, (30.4, 6.7, -2), (30.4, 6.7, 26))

    # Spawns.
    for x in (-6, -3, 0, 3, 6):
        m.spawn("red", (x, 0.1, 40), 0)
    for x in (-6, -3, 3, 6):
        m.spawn("blue", (x, 0.1, -36), 180)
    for (x, z, yaw) in ((34, 30, 0), (-34, 25, 0), (0, 0, 90), (28, -23, 180), (-28, -18, 90), (11, -17.5, 90)):
        m.spawn("ffa", (x, 0.1 if (x, z) != (28, -23) else TY + 0.1, z), yaw)

    # Callouts (minimap location names).
    for (label, pos, size) in (
            ("T Spawn", (5, 2, 40), (66, 6, 12)),
            ("CT Spawn", (0, 2, -40), (40, 6, 14)),
            ("Mid", (0, 2, 8), (8, 6, 52)),
            ("Top Mid", (0, 2, -20), (8, 6, 24)),
            ("Connector", (11, 2, -17.5), (14, 6, 5)),
            ("Short", (-11, 2, -11.5), (14, 6, 5)),
            ("A Long", (34, 2, 12), (8, 6, 44)),
            ("A Ramp", (28, 2, -13), (20, 6, 6)),
            ("Bombsite A", (28, 2, -24), (20, 6, 16)),
            ("B Apartments", (-34, 2, 17), (8, 6, 34)),
            ("Bombsite B", (-28, 2, -21), (20, 6, 22)),
            ("Palace", (17, 2, 22), (26, 6, 4)),
            ("Market", (-17, 2, 22), (26, 6, 4)),
            ("CT Street", (0, 2, -35), (76, 6, 6))):
        m.callout(label, pos, size)

    m.reverb((11, 2.0, -17.5), (14, 4.0, 5), "room", 0.2)
    m.write("scenes/levels/kasbah.tscn", sun_rot=(-52.0, 150.0), sky=(0.22, 0.47, 0.85), horizon=(0.62, 0.74, 0.88),
            sun_color=(1.0, 0.9, 0.74), sun_energy=1.3, ambient=0.75, fog=0.002, fog_color=(0.85, 0.8, 0.72),
            ambient_color=(0.8, 0.68, 0.55))


if __name__ == "__main__":
    warehouse()
    courtyard()
    rooftops()
    docks()
    bunker()
    kasbah()
