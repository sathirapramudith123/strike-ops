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
    # Industrial / urban (factory, office, subway, train yard).
    "concrete": {"kind": 1, "base_color": (0.5, 0.5, 0.48), "line_color": (0.38, 0.38, 0.37), "cell_size": 3.0, "grime": 0.3},
    "floor_dark": {"kind": 1, "base_color": (0.36, 0.36, 0.35), "line_color": (0.28, 0.28, 0.27), "cell_size": 4.0, "grime": 0.0},
    "brick": {"kind": 7, "base_color": (0.52, 0.27, 0.2), "line_color": (0.62, 0.58, 0.52), "cell_size": 0.55,
              "line_width": 0.02, "roughness_value": 0.9, "grime": 0.35},
    "yellow": {"kind": 4, "base_color": (0.85, 0.66, 0.12), "line_color": (0.6, 0.45, 0.08), "grime": 0.2},
    "rust": {"kind": 2, "base_color": (0.45, 0.26, 0.16), "line_color": (0.3, 0.17, 0.1), "cell_size": 1.0,
             "roughness_value": 0.8, "metallic_value": 0.3, "grime": 0.2},
    "green": {"kind": 2, "base_color": (0.2, 0.36, 0.26), "line_color": (0.14, 0.26, 0.18), "cell_size": 1.2,
              "roughness_value": 0.6, "metallic_value": 0.4, "grime": 0.2},
    "tile": {"kind": 0, "base_color": (0.82, 0.83, 0.8), "line_color": (0.55, 0.57, 0.56), "cell_size": 0.3,
             "line_width": 0.012, "roughness_value": 0.35, "grime": 0.25},
    "tile_band": {"kind": 0, "base_color": (0.16, 0.42, 0.62), "line_color": (0.1, 0.3, 0.45), "cell_size": 0.3,
                  "line_width": 0.012, "roughness_value": 0.35, "grime": 0.0},
    "ceiling": {"kind": 0, "base_color": (0.7, 0.7, 0.68), "line_color": (0.55, 0.55, 0.53), "cell_size": 1.2, "grime": 0.0},
    "carpet": {"kind": 1, "base_color": (0.3, 0.33, 0.38), "line_color": (0.26, 0.28, 0.32), "cell_size": 0.6,
               "line_width": 0.01, "roughness_value": 1.0, "grime": 0.0},
    "office_wall": {"kind": 4, "base_color": (0.78, 0.77, 0.73), "line_color": (0.62, 0.61, 0.58), "grime": 0.15},
    "glass": {"kind": 2, "base_color": (0.16, 0.24, 0.3), "line_color": (0.3, 0.32, 0.34), "cell_size": 1.5,
              "roughness_value": 0.1, "metallic_value": 0.8, "grime": 0.0},
    "gravel": {"kind": 1, "base_color": (0.42, 0.39, 0.35), "line_color": (0.4, 0.37, 0.33), "cell_size": 5.0,
               "line_width": 0.0, "roughness_value": 1.0, "grime": 0.0},
    "sleepers": {"kind": 3, "base_color": (0.3, 0.22, 0.15), "line_color": (0.36, 0.33, 0.3), "cell_size": 0.6,
                 "line_width": 0.28, "roughness_value": 0.9, "grime": 0.0},
    "silver": {"kind": 2, "base_color": (0.62, 0.64, 0.66), "line_color": (0.45, 0.47, 0.49), "cell_size": 2.0,
               "roughness_value": 0.35, "metallic_value": 0.7, "grime": 0.15},
    "lamp": {"kind": 11, "base_color": (1.0, 0.95, 0.85), "line_color": (1.0, 0.95, 0.85), "grime": 0.0},
    "lamp_red": {"kind": 11, "base_color": (1.0, 0.15, 0.1), "line_color": (1.0, 0.15, 0.1), "grime": 0.0},
    # Paint, rugs, fruit (market dressing).
    "paint_red": {"kind": 4, "base_color": (0.62, 0.1, 0.07), "line_color": (0.62, 0.1, 0.07), "grime": 0.0,
                  "roughness_value": 0.9},
    "rug_red": {"kind": 10, "base_color": (0.55, 0.12, 0.1), "line_color": (0.85, 0.6, 0.25), "cell_size": 0.12,
                "roughness_value": 1.0, "grime": 0.0},
    "rug_blue": {"kind": 10, "base_color": (0.15, 0.22, 0.45), "line_color": (0.82, 0.7, 0.5), "cell_size": 0.1,
                 "roughness_value": 1.0, "grime": 0.0},
    "fruit_orange": {"kind": 9, "base_color": (0.95, 0.5, 0.08), "line_color": (0.3, 0.17, 0.05), "cell_size": 0.07,
                     "roughness_value": 0.6, "grime": 0.0},
    "fruit_red": {"kind": 9, "base_color": (0.75, 0.1, 0.07), "line_color": (0.25, 0.06, 0.04), "cell_size": 0.07,
                  "roughness_value": 0.5, "grime": 0.0},
    # Corrugated sheet: fine vertical ribs (the stripe pattern of kind 10).
    "corrugated": {"kind": 10, "base_color": (0.5, 0.54, 0.56), "line_color": (0.4, 0.43, 0.45), "cell_size": 0.09,
                   "roughness_value": 0.55, "metallic_value": 0.45, "grime": 0.4},
    "steel_blue": {"kind": 4, "base_color": (0.2, 0.34, 0.55), "line_color": (0.14, 0.24, 0.4), "grime": 0.3},
    "hazard": {"kind": 10, "base_color": (0.9, 0.72, 0.1), "line_color": (0.08, 0.08, 0.08), "cell_size": 0.25,
               "roughness_value": 0.8, "grime": 0.0},
    "flag_maroon": {"kind": 4, "base_color": (0.5, 0.07, 0.1), "line_color": (0.5, 0.07, 0.1), "grime": 0.0},
    "flag_green": {"kind": 4, "base_color": (0.0, 0.45, 0.3), "line_color": (0.0, 0.45, 0.3), "grime": 0.0},
    "flag_orange": {"kind": 4, "base_color": (0.95, 0.5, 0.05), "line_color": (0.95, 0.5, 0.05), "grime": 0.0},
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
        self.signs = []  # (text, pos, yaw)
        self.zones = []  # (pos, size, bus, amount, priority)
        self._n = {}

    def _id(self, prefix):
        self._n[prefix] = self._n.get(prefix, 0) + 1
        return f"{prefix}{self._n[prefix]}"

    @staticmethod
    def _basis(yaw=0.0, pitch=0.0, roll=0.0):
        """Ry(yaw) · Rx(pitch) · Rz(roll) (degrees), as the 9 numbers of a .tscn Transform3D."""
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
        cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
        ry = ((cy, 0, -sy), (0, 1, 0), (sy, 0, cy))
        rx = ((1, 0, 0), (0, cp, -sp), (0, sp, cp))
        rz = ((cr, -sr, 0), (sr, cr, 0), (0, 0, 1))

        def mul(a, b):
            return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))
        m = mul(mul(ry, rx), rz)
        # Godot's text format lists the basis row by row.
        return tuple(m[r][c] for r in range(3) for c in range(3))

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

    def sign(self, pos, face, text, toward=None, color=(0.68, 0.1, 0.07), pixel=0.0045):
        """Letter painted on a wall ("A", "B"), with an arrow towards the
        world point `toward` (x, z). `face` = the wall face it is on
        ("n", "s", "e", "w"); pos is on that face."""
        normal = {"s": (0, 1), "n": (0, -1), "e": (1, 0), "w": (-1, 0)}[face]
        # Label3D text reads from its local +Z: turn that to the wall's normal.
        yaw = {"s": 0.0, "n": 180.0, "e": -90.0, "w": 90.0}[face]
        x, y, z = pos
        # In front of window frames and shutters (they stick out ~0.11 m).
        px, pz = x + normal[0] * 0.13, z + normal[1] * 0.13
        self.signs.append((text, (px, y, pz), yaw, color, pixel))
        if toward is None:
            return
        # Right, as seen by someone facing the wall.
        rx, rz = normal[1], -normal[0]
        side = 1 if (toward[0] - x) * rx + (toward[1] - z) * rz > 0 else -1
        dx, dz = rx * side, rz * side
        ax, az = px + dx * 0.75, pz + dz * 0.75
        bx, bz = ax + dx * 1.0, az + dz * 1.0
        yy = y - 0.05
        self.beam((ax, yy, az), (bx, yy, bz), 0.12, "paint_red", "Arrow", width=0.02)
        for up in (1, -1):
            self.beam((bx, yy, bz), (bx - dx * 0.35, yy + up * 0.3, bz - dz * 0.35), 0.12, "paint_red", "Arrow", width=0.02)

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
              sun_color=(1, 0.95, 0.86), sun_energy=1.2, ambient=1.0, fog_color=None, ambient_color=None,
              sun_shadow=True):
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
        sign_nodes = []
        for i, (text, pos, yaw, col, pixel) in enumerate(self.signs):
            c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            sign_nodes.append(f'[node name="Sign{i + 1}" type="Label3D" parent="Signs"]\n'
                              f'transform = Transform3D({c:.6f}, 0, {-sn:.6f}, 0, 1, 0, {sn:.6f}, 0, {c:.6f}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n'
                              f'pixel_size = {pixel}\ndouble_sided = false\nalpha_cut = 1\nmodulate = Color({col[0]}, {col[1]}, {col[2]}, 0.95)\n'
                              f'text = "{text}"\nfont_size = 256\noutline_size = 0\n')
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
shadow_enabled = {"true" if sun_shadow else "false"}
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
               + ('\n[node name="Signs" type="Node3D" parent="."]\n\n' + "\n".join(sign_nodes) if sign_nodes else "")
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
    for ring in (0.0, 0.35, 0.7):
        m.cyl((x + lean[0] * ring, height * ring + 0.3, z + lean[1] * ring), 0.2, 0.12, "wood", "TrunkRing",
              collide=False, segments=8)
    # Fronds: up and out, then drooping (two segments each), plus a few dates.
    for k in range(9):
        a = math.radians(k * 40 + 10)
        mid = (top[0] + math.cos(a) * 1.5, height + 0.35, top[2] + math.sin(a) * 1.5)
        tip = (top[0] + math.cos(a) * 3.0, height - 0.9, top[2] + math.sin(a) * 3.0)
        m.beam(top, mid, 0.05, "palm", "Frond", width=0.75)
        m.beam(mid, tip, 0.05, "palm", "Frond", width=0.6)
    m.box((top[0], height - 0.35, top[2]), (0.5, 0.4, 0.5), "clay", "Dates", collide=False)


def _stall(m, x, z, yaw_face="s", cloth="cloth_red"):
    """Market stall: table, goods, two poles and a sloped awning."""
    out = {"s": 1, "n": -1}[yaw_face]
    m.box((x, 0.45, z), (2.4, 0.9, 1.0), "wood", "Stall")
    # Crates of oranges and tomatoes on the table.
    for i, gx in enumerate((-0.7, 0.0, 0.7)):
        m.box((x + gx, 1.01, z), (0.62, 0.22, 0.46), "wood", "FruitCrate", collide=False)
        m.box((x + gx, 1.13, z), (0.56, 0.06, 0.4), ("fruit_orange", "fruit_red", "fruit_orange")[i], "Fruit",
              collide=False)
    for px in (-1.15, 1.15):
        m.box((x + px, 1.2, z + out * 0.9), (0.08, 2.4, 0.08), "wood", "Pole", collide=False)
    m.box((x, 2.35, z + out * 0.35), (2.7, 0.05, 1.9), cloth, "Awning", pitch=out * 14, collide=False)


def _rug(m, x, y, z, face, mat="rug_red", w=1.3, h=1.9):
    """A rug hung on a wall face (thin, visual)."""
    n = {"s": (0, 1), "n": (0, -1), "e": (1, 0), "w": (-1, 0)}[face]
    size = (w, h, 0.03) if face in "ns" else (0.03, h, w)
    m.box((x + n[0] * 0.03, y, z + n[1] * 0.03), size, mat, "Rug", collide=False)


def _tower(m, x, z, base, h, mat="sandstone", w=5.0):
    """Castle-style tower standing on a roof (visual only): slit windows,
    crenellations."""
    m.box((x, base + h / 2, z), (w, h, w), mat, "Tower", collide=False)
    m.box((x, base + h + 0.15, z), (w + 0.4, 0.3, w + 0.4), mat, "TowerLedge", collide=False)
    for i in range(4):
        t = -w / 2 + 0.45 + i * (w - 0.9) / 3
        for (dx, dz) in ((t, -w / 2), (t, w / 2), (-w / 2, t), (w / 2, t)):
            m.box((x + dx, base + h + 0.75, z + dz), (0.8, 0.9, 0.8), mat, "Merlon", collide=False)
    for fy in (base + 3.0, base + h - 2.5):
        for (dx, dz, sx, sz) in ((0, -w / 2 - 0.02, 0.4, 0.05), (0, w / 2 + 0.02, 0.4, 0.05),
                                 (-w / 2 - 0.02, 0, 0.05, 0.4), (w / 2 + 0.02, 0, 0.05, 0.4)):
            m.box((x + dx, fy, z + dz), (sx, 1.3, sz), "dark", "Slit", collide=False)


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
    # Painted directions (as in CS), market rugs, wooden barrels, sandbags, a tower.
    m.sign((4.0, 2.5, 2.5), "w", "A", toward=(11, -17))
    m.sign((-4.0, 2.5, 2.5), "e", "B", toward=(-11, -11))
    m.sign((20.0, 2.5, 34.0), "s", "A", toward=(34, 30))
    m.sign((-20.0, 2.5, 34.0), "s", "B", toward=(-34, 20))
    m.sign((30.0, 2.5, 4.0), "e", "A", toward=(34, -10))
    m.sign((-30.0, 2.5, -5.0), "w", "B", toward=(-34, -14))
    m.sign((10.0, 2.5, -32.0), "n", "A", toward=(24, -32))
    m.sign((-10.0, 2.5, -32.0), "n", "B", toward=(-24, -32))
    for (x, mat) in ((-13.0, "rug_red"), (-7.5, "rug_blue")):
        _rug(m, x, 1.7, 34.0, "s", mat)
    _rug(m, 4.0, 1.8, 26.5, "w", "rug_red")
    _rug(m, 4.0, 1.8, 32.0, "w", "rug_blue")
    _rug(m, -36.5, 1.6, -31.75, "s", "rug_blue")
    for (x, z) in ((-3.2, 25.5), (35.4, -15.6), (36.2, -16.3), (-21.0, -15.0), (-21.7, -15.6), (13.5, 44.3)):
        _barrel(m, x, z, "wood")
    _sandbags(m, (30.6, -5.0), (32.3, -5.0))
    _sandbags(m, (20.0, -29.5), (23.0, -29.5))
    _tower(m, 11.0, -26.0, 7.0, 9.0)
    _tower(m, -12.0, -24.0, 8.0, 6.0, "plaster_warm", 4.0)

    m.write("scenes/levels/kasbah.tscn", sun_rot=(-52.0, 150.0), sky=(0.22, 0.47, 0.85), horizon=(0.62, 0.74, 0.88),
            sun_color=(1.0, 0.9, 0.74), sun_energy=1.3, ambient=0.75, fog=0.002, fog_color=(0.85, 0.8, 0.72),
            ambient_color=(0.8, 0.68, 0.55))


# ----------------------------------------------------------------------
# Industrial / urban helpers (factory, office, subway, train yard).

def _off(yaw, dx, dz):
    """Local (dx, dz) offset rotated by `yaw` (same convention as Map.box)."""
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return dx * c - dz * s, dx * s + dz * c


def _ring(m, rng, x0, x1, z0, z1, mats, h=(9, 11), step=16):
    """Boundary: a ring of tall buildings with windows facing inward."""
    xs = list(range(int(x0), int(x1), step))
    for i, a in enumerate(xs):
        b = min(a + step, x1)
        _building(m, rng, a, b, z0 - 4, z0, rng.choice(h), mats[i % len(mats)], "s", roof=False)
        _building(m, rng, a, b, z1, z1 + 4, rng.choice(h), mats[(i + 1) % len(mats)], "n", roof=False)
    zs = list(range(int(z0), int(z1), step))
    for i, a in enumerate(zs):
        b = min(a + step, z1)
        _building(m, rng, x1, x1 + 4, a, b, rng.choice(h), mats[(i + 2) % len(mats)], "w", roof=False)
        _building(m, rng, x0 - 4, x0, a, b, rng.choice(h), mats[(i + 3) % len(mats)], "e", roof=False)


def _drum(m, x, z, mat="rust", y=0.0):
    m.cyl((x, y + 0.45, z), 0.3, 0.9, mat, "Drum")
    m.cyl((x, y + 0.9, z), 0.31, 0.03, "metal", "DrumLid", collide=False)


def _crates(m, x, z, n=2, yaw=0.0, size=1.2):
    for i in range(n):
        m.box((x, size / 2 + i * size, z), (size, size, size), "wood", "Crate", yaw=yaw + (i % 2) * 17)


def _pallets(m, x, z, yaw=0.0):
    m.box((x, 0.08, z), (1.2, 0.16, 1.0), "wood", "Pallet", yaw=yaw)
    m.box((x, 0.61, z), (1.1, 0.9, 0.9), "sack", "Goods", yaw=yaw)


def _truck(m, x, z, yaw=0.0, mat="blue"):
    """Semi truck: trailer + cab, wheels (visual)."""
    tx, tz = _off(yaw, 0, 1.5)
    m.box((x + tx, 2.1, z + tz), (2.5, 2.8, 8.5), mat, "Trailer", yaw=yaw)
    m.box((x + tx, 0.55, z + tz), (2.0, 0.5, 8.0), "floor_dark", "Chassis", yaw=yaw, collide=False)
    cx, cz = _off(yaw, 0, -4.2)
    m.box((x + cx, 1.5, z + cz), (2.4, 2.2, 2.4), "red", "Cab", yaw=yaw)
    wx, wz = _off(yaw, 0, -5.45)
    m.box((x + wx, 1.9, z + wz), (2.0, 0.8, 0.05), "glass", "Windscreen", yaw=yaw, collide=False)
    for dz in (-4.3, 3.0, 4.6):
        for side in (-1, 1):
            ox, oz = _off(yaw, side * 1.1, dz)
            m.cyl((x + ox, 0.5, z + oz), 0.5, 0.35, "floor_dark", "Wheel", segments=10, collide=False,
                  yaw=yaw, roll=90)


def _container(m, x, z, yaw=0.0, mat="blue", level=0, length=6.0):
    m.box((x, 1.3 + level * 2.6, z), (2.4, 2.6, length), mat, "Container", yaw=yaw)
    for dz in (-length / 2 + 0.05, length / 2 - 0.05):
        ox, oz = _off(yaw, 0, dz)
        m.box((x + ox, 1.3 + level * 2.6, z + oz), (2.44, 2.64, 0.08), "metal", "ContainerEnd", yaw=yaw, collide=False)


def _strip_light(m, x, y, z, length=2.4, yaw=0.0):
    m.box((x, y, z), (0.25, 0.08, length), "lamp", "StripLight", yaw=yaw, collide=False)


def _desk(m, x, z, yaw=0.0, partition=True, y=0.0):
    m.box((x, y + 0.375, z), (1.6, 0.75, 0.8), "wood", "Desk", yaw=yaw)
    mx, mz = _off(yaw, 0, -0.2)
    m.box((x + mx, y + 0.98, z + mz), (0.6, 0.4, 0.05), "dark", "Monitor", yaw=yaw, collide=False)
    m.box((x + mx, y + 0.8, z + mz), (0.08, 0.1, 0.08), "dark", "MonitorStand", yaw=yaw, collide=False)
    cx, cz = _off(yaw, 0, 0.75)
    m.cyl((x + cx, y + 0.3, z + cz), 0.25, 0.6, "floor_dark", "Chair", segments=8, collide=False)
    if partition:
        px, pz = _off(yaw, 0, -0.45)
        m.box((x + px, y + 0.65, z + pz), (1.7, 1.3, 0.08), "carpet", "Partition", yaw=yaw)


def _plant(m, x, z):
    m.cyl((x, 0.25, z), 0.25, 0.5, "floor_dark", "Planter", top=0.3)
    m.box((x, 0.95, z), (0.7, 0.9, 0.7), "leaf", "Leaves", yaw=35, collide=False)


def _rails(m, x, z0, z1, y=0.0, width=2.6):
    L = z1 - z0
    m.box((x, y + 0.03, (z0 + z1) / 2), (width, 0.06, L), "sleepers", "Sleepers", collide=False)
    for side in (-0.72, 0.72):
        m.box((x + side, y + 0.13, (z0 + z1) / 2), (0.08, 0.14, L), "metal", "Rail", collide=False)


def _freight(m, x, z, kind="box", mat="rust", length=12.0):
    """Freight car on a track along Z: box car, tank car or open hopper."""
    m.box((x, 0.75, z), (2.2, 0.7, length - 0.6), "floor_dark", "Underframe")
    for dz in (-length / 2 + 2.0, length / 2 - 2.0):
        m.box((x, 0.45, z + dz), (2.4, 0.6, 2.4), "floor_dark", "Bogie", collide=False)
    if kind == "tank":
        m.cyl((x, 2.5, z), 1.45, length - 1.0, mat, "Tank", segments=14, pitch=90)
        m.box((x, 1.3, z), (2.6, 0.3, length - 0.4), mat, "TankDeck")
        m.cyl((x, 4.05, z), 0.35, 0.3, mat, "Dome", collide=False)
    elif kind == "hopper":
        m.box((x, 2.3, z), (2.8, 2.4, length), mat, "Hopper")
        for dz in (-3.0, 0.0, 3.0):
            m.box((x, 1.2, z + dz), (2.2, 0.4, 1.8), mat, "Chute", collide=False)
    else:
        m.box((x, 2.7, z), (2.8, 3.2, length), mat, "BoxCar")
        m.box((x + 1.42, 2.5, z), (0.06, 2.6, 2.6), "metal", "Door", collide=False)
        m.box((x - 1.42, 2.5, z), (0.06, 2.6, 2.6), "metal", "Door", collide=False)
        m.box((x, 4.35, z), (2.6, 0.1, length - 0.2), "metal", "Roof", collide=False)


# ----------------------------------------------------------------------
def _forklift(m, x, z, yaw=0.0):
    """Yellow forklift: body, cab frame, mast and forks."""
    m.box((x, 0.75, z), (1.2, 1.1, 2.0), "yellow", "Forklift", yaw=yaw)
    for (dx, dz) in ((-0.55, 0.3), (0.55, 0.3), (-0.55, 0.95), (0.55, 0.95)):
        ox, oz = _off(yaw, dx, dz)
        m.box((x + ox, 1.9, z + oz), (0.06, 1.3, 0.06), "cable", "ForkliftFrame", collide=False)
    ox, oz = _off(yaw, 0, 0.6)
    m.box((x + ox, 2.55, z + oz), (1.2, 0.06, 0.8), "cable", "ForkliftRoof", collide=False)
    ox, oz = _off(yaw, 0, -1.1)
    m.box((x + ox, 1.5, z + oz), (1.0, 2.6, 0.12), "cable", "ForkliftMast", collide=False)
    for dx in (-0.3, 0.3):
        ox, oz = _off(yaw, dx, -1.6)
        m.box((x + ox, 0.25, z + oz), (0.12, 0.06, 1.0), "metal", "Fork", collide=False)
    for (dx, dz) in ((-0.62, -0.6), (0.62, -0.6), (-0.62, 0.7), (0.62, 0.7)):
        ox, oz = _off(yaw, dx, dz)
        m.cyl((x + ox, 0.3, z + oz), 0.3, 0.2, "floor_dark", "ForkliftWheel", collide=False, yaw=yaw, roll=90)


def _silo(m, x, z, r=3.5, h=14.0):
    m.cyl((x, h / 2, z), r, h, "corrugated", "Silo", segments=16)
    m.cyl((x, h + 1.0, z), 0.6, 2.0, "corrugated", "SiloRoof", top=0.6, segments=16, collide=False)
    m.cyl((x, h + 0.9, z), r, 1.8, "corrugated", "SiloCone", top=0.7, segments=16, collide=False)
    for k in range(4):
        m.cyl((x, 2.0 + k * 3.2, z), r + 0.05, 0.12, "rust", "SiloBand", segments=16, collide=False)
    m.box((x + r + 0.15, h / 2, z), (0.08, h, 0.5), "metal", "SiloLadder", collide=False)


def _chimney(m, x, z, base, h=18.0, r=0.9):
    """Red and white striped chimney (visual)."""
    bands = 6
    for k in range(bands):
        m.cyl((x, base + (k + 0.5) * h / bands, z), r * (1.0 - k * 0.05), h / bands, "red" if k % 2 == 0 else "tile",
              "Chimney", top=r * (1.0 - (k + 1) * 0.05), segments=12, collide=False)


def _flag(m, x, z, h=7.0):
    """Sri Lankan flag on a pole (simplified: maroon field, yellow border,
    green and orange stripes)."""
    m.cyl((x, h / 2, z), 0.06, h, "metal", "FlagPole", segments=6, collide=False)
    fx, fy = x + 1.05, h - 0.75
    m.box((fx, fy, z), (2.0, 1.2, 0.03), "yellow", "Flag", collide=False)
    m.box((fx + 0.22, fy, z), (1.4, 1.05, 0.04), "flag_maroon", "Flag", collide=False)
    m.box((fx - 0.72, fy, z), (0.22, 1.05, 0.04), "flag_orange", "Flag", collide=False)
    m.box((fx - 0.5, fy, z), (0.22, 1.05, 0.04), "flag_green", "Flag", collide=False)


def _gantry(m, x0, x1, z, h=9.0, mat="yellow"):
    """Overhead gantry crane across X (legs collide, beam is visual)."""
    for x in (x0, x1):
        m.box((x, h / 2, z), (0.6, h, 0.6), mat, "GantryLeg")
        m.box((x, h / 2, z + 1.6), (0.6, h, 0.6), mat, "GantryLeg")
    m.box(((x0 + x1) / 2, h + 0.3, z + 0.8), (x1 - x0 + 0.6, 0.6, 2.2), mat, "GantryBeam", collide=False)
    hx = x0 + (x1 - x0) * 0.4
    m.box((hx, h - 0.2, z + 0.8), (1.2, 0.8, 1.6), "metal", "Trolley", collide=False)
    m.box((hx, h - 2.2, z + 0.8), (0.05, 3.2, 0.05), "cable", "HookCable", collide=False)
    m.box((hx, h - 3.9, z + 0.8), (0.4, 0.3, 0.2), "rust", "Hook", collide=False)


def factory():
    """Factory (3 lanes). A in the north under a gantry crane next to two
    silos, with a flat roof over it on the east; B in a walled yard in the
    south. West lane past the warehouse, Mid with a catwalk under the Lanka
    Steel building, underground-feeling Tunnels from the west lane to Lower
    Mid, and the Rail Yard along the east. T spawn south-west, CT south-east."""
    import random
    rng = random.Random(11)
    m = Map("Factory")
    X, Z = 40.0, 48.0
    m.box((0, -0.5, 0), (2 * X + 4, 1, 2 * Z + 4), "concrete", "Ground")
    _ring(m, rng, -X, X, -Z, Z, ("brick", "corrugated", "concrete", "steel_blue"), h=(9, 11))

    # --- Warehouse (x -32..-8, z -30..-8) -------------------------------
    H = 8.0
    m.wall_with_gaps((-32, -30), (-32, -8), H, 0.5, [(8.0, 4.0, 4.0)], "corrugated", name="WarehouseWall")
    m.wall_with_gaps((-8, -30), (-8, -8), H, 0.5, [(12.0, 4.0, 4.0)], "corrugated", name="WarehouseWall")
    m.wall_with_gaps((-32, -30), (-8, -30), H, 0.5, [(16.0, 4.0, 4.0)], "corrugated", name="WarehouseWall")
    m.wall_with_gaps((-32, -8), (-8, -8), H, 0.5, [], "corrugated", name="WarehouseWall")
    m.box((-20, H + 0.2, -19), (24.5, 0.4, 22.5), "corrugated", "WarehouseRoof", collide=False)
    for z in (-26, -19, -12):
        m.box((-20, H + 0.02, z), (22, 0.1, 2.0), "glass", "Skylight", collide=False)
        m.box((-20, H - 0.5, z + 1.8), (23, 0.5, 0.3), "metal", "Truss", collide=False)
    for x in (-28.5, -24.5):
        m.box((x, 2.0, -24), (1.2, 4.0, 7.0), "steel_blue", "Shelf")
        for (dz, dy) in ((-2.0, 0.9), (1.2, 0.9), (-1.0, 2.7), (2.0, 2.7)):
            m.box((x, dy, -24 + dz), (1.0, 0.8, 1.2), "wood", "ShelfCrate", collide=False)
    for (x, z) in ((-14, -24), (-14, -22.7), (-19, -12), (-12, -12)):
        _pallets(m, x, z)
    _forklift(m, -18, -18, 30)
    for (x0, x1, z) in ((-31, -9, -16), (-31, -9, -21)):
        m.box(((x0 + x1) / 2, 0.01, z), (x1 - x0, 0.02, 0.15), "yellow", "FloorLine", collide=False)
    for (x, z) in ((-26, -24), (-14, -24), (-20, -13)):
        m.omni((x, 6.5, z), 1.2, 13.0, (1.0, 0.94, 0.85))
        _strip_light(m, x, H - 0.2, z, 3.0)
    m.reverb((-20, H / 2, -19), (24, H, 22), "hall", 0.45)

    # --- Silo yard (north-west) and A site (north) ------------------------
    _silo(m, -24, -40)
    _silo(m, -15, -41, 3.2, 12.0)
    m.beam((-20.5, 10.0, -40.5), (-7, 7.0, -40), 0.4, "rust", "Pipe", width=0.4)
    m.box((-5, 3.6, -40), (0.4, 7.2, 0.4), "metal", "PipePost", collide=False)
    m.sign((-11.8, 4.0, -41.0), "e", "A", color=(0.75, 0.08, 0.06), pixel=0.009)
    _gantry(m, -2.0, 15.0, -40.0)
    for (x, z, w, d) in ((6, -31.5, 20, 0.3), (-3.8, -38, 0.3, 18), (15.8, -38, 0.3, 18)):
        m.box((x, 0.01, z), (w, 0.02, d), "hazard", "HazardLine", collide=False)
    _forklift(m, 11.5, -33.5, -70)
    for (x, z) in ((1, -44), (2.3, -44.2), (1.6, -45.4)):
        _drum(m, x, z, "blue")
    _pallets(m, 12, -45)
    _pallets(m, 13.3, -45.1, 10)
    _crates(m, 4, -36, 2)
    _crates(m, 9.5, -40, 1)
    m.box((-1, 0.6, -33), (0.5, 1.2, 3.0), "hazard", "Barrier")
    m.site("A", (6.0, 0.0, -38.0))

    # --- Roof (north-east): flat roof over A, reached by a ramp ------------
    RH = 4.0
    m.box((29, RH / 2, -41), (22, RH, 14), "concrete", "RoofBuilding")
    _facade(m, rng, 18, 40, -48, -34, RH, "sw")
    m.ramp((24, 0.0, -22.0), (24.001, RH, -34.0), 3.0, "metal")
    # Railings (a gap where the ramp arrives).
    for (pos, size) in (((18.2, RH + 0.5, -41), (0.15, 1.0, 14)), ((20.25, RH + 0.5, -34.2), (4.5, 1.0, 0.15)),
                        ((32.75, RH + 0.5, -34.2), (14.5, 1.0, 0.15))):
        m.blocker(pos, size)
        long_x = size[0] > size[2]
        length = size[0] if long_x else size[2]
        for yy in (RH + 0.5, RH + 1.0):
            m.box((pos[0], yy, pos[2]), (length if long_x else 0.06, 0.06, 0.06 if long_x else length), "yellow",
                  "RoofRail", collide=False)
        for k in range(int(length // 1.5) + 1):
            t = -length / 2 + k * length / max(int(length // 1.5), 1)
            m.box((pos[0] + (t if long_x else 0), RH + 0.5, pos[2] + (0 if long_x else t)), (0.06, 1.0, 0.06), "yellow",
                  "RoofRailPost", collide=False)
    for (x, z) in ((26, -44), (30, -44), (34, -40)):
        m.box((x, RH + 0.7, z), (2.0, 1.4, 1.6), "metal", "ACUnit")
    _chimney(m, 37, -45, RH, 20.0)

    # --- Mid: Lanka Steel building, catwalk, containers ---------------------
    m.box((0, 4.5, -25), (12, 9, 6), "steel_blue", "LankaSteel")
    m.box((0, 9.2, -25), (12.4, 0.4, 6.4), "corrugated", "LankaSteelRoof", collide=False)
    m.sign((0.0, 6.6, -22.0), "s", "LANKA STEEL", color=(0.92, 0.94, 0.96), pixel=0.004)
    _facade(m, rng, -6, 6, -28, -22, 9, "s", spacing=4)
    m.box((15, 3.5, -25), (6, 7, 6), "brick", "Store")
    _facade(m, rng, 12, 18, -28, -22, 7, "s", spacing=3)
    CW = 4.0
    m.box((6, CW - 0.15, -11), (24, 0.3, 2.2), "metal", "Catwalk")
    # Railings: thin bars (visual) + an invisible wall each side.
    for (cx, length, z) in ((4.75, 21.5, -9.95), (6.0, 24.0, -12.05)):
        for yy in (CW + 0.5, CW + 1.0):
            m.box((cx, yy, z), (length, 0.06, 0.06), "yellow", "CatwalkRail", collide=False)
        for k in range(int(length // 2) + 1):
            m.box((cx - length / 2 + k * length / int(length // 2), CW + 0.5, z), (0.06, 1.0, 0.06), "yellow",
                  "CatwalkRailPost", collide=False)
        m.blocker((cx, CW + 0.5, z), (length, 1.0, 0.1))
    for x in (-5, 1, 7, 13):
        m.box((x, (CW - 0.3) / 2, -11), (0.3, CW - 0.3, 0.3), "metal", "CatwalkPost")
    m.ramp((16.8, CW, -9.9), (16.801, 0.0, 2.0), 2.0, "metal")
    _container(m, -2, -4, 0, "rust")
    _container(m, 9, 0, 90, "blue")
    _container(m, 9, 0, 90, "green", 1)
    _crates(m, 3, -16, 2)
    _crates(m, -4.5, -17, 1)
    _pallets(m, 13, -16)

    # --- Forklift yard, workshop (east of Mid) ------------------------------
    m.box((25, 3.5, -10), (10, 7, 12), "corrugated", "Workshop")
    _facade(m, rng, 20, 30, -16, -4, 7, "wn", spacing=4)
    _forklift(m, 20.3, -27, 180)
    _pallets(m, 27, -24)
    _pallets(m, 28.3, -24.3, 12)
    _drum(m, 19.5, 1.5, "yellow")
    _drum(m, 20.2, 2.3, "rust")

    # --- Rail yard (east strip) ----------------------------------------------
    for x in (33.0, 37.0):
        _rails(m, x, -33, 46, 0.0, 2.4)
    _freight(m, 37, -4, "tank", "rust", 12.0)
    _freight(m, 33, 16, "box", "red", 10.0)
    _freight(m, 37, 30, "box", "steel_blue", 10.0)
    _gantry(m, 31.0, 39.5, -22.0, 10.0)
    m.box((34.5, 0.6, -28), (1.2, 1.2, 1.2), "wood", "Crate")

    # --- Tunnels (west lane -> Lower Mid, under the offices) -------------------
    m.box((-19, 3.0, 0), (26, 6, 16), "concrete", "Offices")
    _facade(m, rng, -32, -6, -8, 8, 6, "we", spacing=4)
    m.box((-19, 3.5, 23), (26, 7, 22), "brick", "SouthBlock")
    _facade(m, rng, -32, -6, 12, 34, 7, "we", spacing=5)
    m.box((-19, 3.3, 10), (26, 0.6, 4), "floor_dark", "TunnelCeiling")
    m.box((-19, 5.0, 10), (26, 3.0, 4), "concrete", "TunnelTop", collide=False)
    for x in (-28, -20, -12):
        _strip_light(m, x, 2.95, 10, 2.0, yaw=90)
        m.box((x + 3, 0.005, 10.4), (1.6, 0.01, 0.9), "glass", "Puddle", collide=False)
    m.omni((-24, 2.6, 10), 0.9, 7.0, (1.0, 0.85, 0.6))
    m.omni((-12, 2.6, 10), 0.9, 7.0, (1.0, 0.85, 0.6))
    m.box((-16, 0.5, 11.3), (1.0, 1.0, 1.0), "wood", "TunnelCrate")
    m.reverb((-19, 1.5, 10), (26, 3, 4), "room", 0.5, priority=1)

    # --- B yard (south-centre) ---------------------------------------------------
    m.wall_with_gaps((-6, 16), (16, 16), 4.0, 0.5, [(8.0, 6.0, 99.0)], "concrete", name="BWall")
    m.wall_with_gaps((16, 16), (16, 34), 4.0, 0.5, [(8.0, 5.0, 99.0)], "concrete", name="BWall")
    m.box((0, 1.3, 30), (4, 2.6, 3), "green", "Transformer")
    m.box((0, 2.9, 30), (3.4, 0.6, 2.4), "metal", "TransformerTop", collide=False)
    _crates(m, 11, 22, 2)
    _crates(m, 12.3, 22.2, 1)
    _pallets(m, 3, 21)
    _drum(m, 14.5, 32.5, "blue")
    _drum(m, 13.8, 33.1, "rust")
    m.site("B", (6.0, 0.0, 27.0))

    # --- Stores block, spawns ----------------------------------------------------
    m.box((24, 3.5, 12), (12, 7, 12), "brick", "Stores")
    _facade(m, rng, 18, 30, 6, 18, 7, "nsw", spacing=4)
    m.box((-15, 3.5, 41), (18, 7, 14), "corrugated", "TBlock")
    m.box((6, 3.5, 41), (24, 7, 14), "corrugated", "BBlock")
    _facade(m, rng, -6, 18, 34, 48, 7, "ne", spacing=4)
    m.sign((-24.0, 3.2, 41.0), "w", "T", color=(0.75, 0.08, 0.06), pixel=0.012)
    m.sign((18.0, 3.2, 41.0), "e", "CT", color=(0.12, 0.35, 0.8), pixel=0.012)
    m.box((-31, 1.3, 38), (3, 2.6, 3), "steel_blue", "GuardHut")
    m.box((-31, 2.75, 38), (3.6, 0.3, 3.6), "corrugated", "GuardHutRoof", collide=False)
    _crates(m, -27, 45, 2)
    _truck(m, 26, 42, 90, "steel_blue")
    for x in (21.0, 29.0):
        m.box((x, 1.5, 34.5), (0.4, 3.0, 0.4), "metal", "GatePost")
    m.box((25, 2.9, 34.5), (8.4, 0.2, 0.2), "metal", "GateBar", collide=False)

    # Sri Lankan touch: coconut palms, the flag, chimneys, Lanka Steel.
    for (x, z, h, lean) in ((-38, 44, 7.5, (0.6, -0.4)), (-35, 30, 7.0, (0.4, 0.5)), (-38, -2, 8.0, (0.7, 0.2)),
                            (38.5, 44, 7.0, (-0.6, -0.3))):
        _palm(m, x, z, h, lean)
    _flag(m, 22, 40.5)
    _chimney(m, -30, -50, 10.0, 22.0)
    _chimney(m, 30, 50, 10.0, 18.0, 0.8)

    for x in (-38, -35, -32, -29, -26):
        m.spawn("red", (x, 0.1, 43), 0)
    for (x, z) in ((22, 38), (25, 38), (22, 44), (25, 45)):
        m.spawn("blue", (x, 0.1, z), 90)
    for (x, z, yaw) in ((-36, -20, 0), (6, -8, 0), (28, -28, 0), (35, 8, 0), (6, 10, 180), (-24, -14, 90)):
        m.spawn("ffa", (x, 0.1, z), yaw)
    for (label, pos, size) in (
            ("T Spawn", (-32, 2, 41), (16, 6, 14)),
            ("CT Spawn", (24, 2, 33), (12, 6, 30)),
            ("West Lane", (-36, 2, -5), (8, 6, 78)),
            ("Warehouse", (-20, 4, -19), (24, 8, 22)),
            ("Silo", (-18, 3, -40), (28, 8, 16)),
            ("Bombsite A", (6, 2, -38), (20, 6, 20)),
            ("Roof", (29, 6, -41), (22, 4, 14)),
            ("Mid", (6, 2, -9), (24, 6, 26)),
            ("Catwalk", (6, 5, -11), (24, 3, 2.4)),
            ("Forklift", (24, 2, -25), (12, 6, 18)),
            ("Rail Yard", (35, 2, 6), (10, 8, 80)),
            ("Tunnels", (-19, 1.5, 10), (26, 3, 4)),
            ("Lower Mid", (6, 2, 10), (24, 6, 12)),
            ("Bombsite B", (5, 2, 25), (22, 6, 18))):
        m.callout(label, pos, size)
    m.write("scenes/levels/factory.tscn", sun_rot=(-42.0, 130.0), sky=(0.28, 0.5, 0.82), horizon=(0.72, 0.76, 0.82),
            sun_color=(1.0, 0.94, 0.84), sun_energy=1.25, ambient=0.8, ambient_color=(0.66, 0.68, 0.7),
            fog=0.002, fog_color=(0.78, 0.8, 0.84))


def office():
    """Office block: lobby with a reception desk (double height), open-plan
    office (A) on the east, conference + server rooms (B) on the west,
    CT break rooms under the north mezzanine, upper offices reached by two
    stairs. T comes in from the street through the front doors and the
    side alleys."""
    import random
    rng = random.Random(5)
    m = Map("Office")
    m.box((0, -0.5, 7), (64, 1, 84), "concrete", "Street")
    _ring(m, rng, -30, 30, -34, 48, ("concrete", "brick", "wall", "concrete"), h=(12, 14))
    W0, W1, Z0, Z1, HT, F = -24.0, 24.0, -30.0, 30.0, 7.4, 3.6
    m.box((0, 0.01, 0), (48, 0.02, 60), "carpet", "Carpet", collide=False)
    # Shell: front doors, side doors.
    m.wall_with_gaps((W0, Z1), (W1, Z1), HT, 0.4, [(20.0, 8.0, 3.0)], "concrete", name="Facade")
    m.wall_with_gaps((W1, Z0), (W1, Z1), HT, 0.4, [(10.0, 2.0, 2.4), (36.0, 2.0, 2.4)], "concrete", name="Facade")
    m.wall_with_gaps((W0, Z0), (W0, Z1), HT, 0.4, [(10.0, 2.0, 2.4), (36.0, 2.0, 2.4)], "concrete", name="Facade")
    m.wall_with_gaps((W0, Z0), (W1, Z0), HT, 0.4, [], "concrete", name="Facade")
    m.box((0, HT + 0.15, 0), (48.4, 0.3, 60.4), "ceiling", "Roof", collide=False)
    # Facade windows (both floors) and the glass entrance canopy.
    for x in range(-20, 21, 5):
        if abs(x) > 5:
            m.box((x, 1.7, Z1 + 0.22), (3.2, 1.6, 0.06), "glass", "Window", collide=False)
        m.box((x, 5.3, Z1 + 0.22), (3.2, 1.6, 0.06), "glass", "Window", collide=False)
    for z in range(-26, 27, 6):
        for x in (W0 - 0.22, W1 + 0.22):
            m.box((x, 5.3, z), (0.06, 1.6, 3.2), "glass", "Window", collide=False)
    m.box((0, 3.4, 32), (10, 0.2, 4), "glass", "Canopy", collide=False)
    # Mezzanine (upper floor, north third) and the two stairs.
    m.box((0, F - 0.15, -21), (48, 0.3, 18), "concrete", "Mezzanine")
    m.box((0, F - 0.32, -21), (48, 0.04, 18), "ceiling", "MezzCeiling", collide=False)
    m.ramp((20, 0.0, 2.0), (20.001, F, -12.0), 2.4, "floor_dark")
    m.ramp((-20, 0.0, 2.0), (-20.001, F, -12.0), 2.4, "floor_dark")
    m.box((0, F + 0.5, -12.05), (37.4, 1.0, 0.1), "glass", "Balustrade")
    for x in (-23.1, 23.1):
        m.box((x, F + 0.5, -12.05), (1.4, 1.0, 0.1), "glass", "Balustrade")
    # Upper offices: glass wall with doors, desks.
    m.wall_with_gaps((W0, -21), (W1, -21), 3.4, 0.12, [(8.0, 1.6, 2.3), (23.2, 1.6, 2.3), (38.0, 1.6, 2.3)],
                     "glass", y0=F, name="GlassWall")
    for x in (-16, -6, 6, 16):
        _desk(m, x, -26, 180, partition=False, y=F)
    # Lobby: reception, pillars, sofas, plants.
    m.box((0, 0.55, 16), (6, 1.1, 1.4), "wood", "Reception")
    m.box((0, 1.15, 16.5), (6.2, 0.1, 0.6), "office_wall", "Counter", collide=False)
    m.box((0, 2.4, 29.75), (3, 0.6, 0.06), "tile_band", "Logo", collide=False)
    for (x, z) in ((-6, 6), (6, 6), (-6, 24), (6, 24)):
        m.box((x, HT / 2, z), (0.8, HT, 0.8), "office_wall", "Pillar")
    m.box((-4, 0.4, 10), (3.0, 0.8, 1.0), "tile_band", "Sofa")
    m.box((4, 0.4, 10), (3.0, 0.8, 1.0), "tile_band", "Sofa")
    for (x, z) in ((-8.5, 28.5), (8.5, 28.5), (-8.5, -10), (8.5, -10)):
        _plant(m, x, z)
    # East: open-plan office (A).
    m.wall_with_gaps((10, -12), (10, 30), 3.2, 0.2, [(3.0, 3.0, 99.0), (24.0, 3.5, 99.0)], "office_wall", name="EastWall")
    for x in (13.5, 17.0):
        for z in (6.0, 11.0, 20.0, 25.0):
            _desk(m, x, z, 0 if z < 15 else 180)
    m.box((22.5, 0.6, 13), (1.0, 1.2, 1.6), "floor_dark", "Printer")
    m.box((22.8, 1.0, 22), (0.6, 2.0, 1.2), "office_wall", "Cabinet")
    m.site("A", (15.5, 0.0, 15.5))
    # West: conference room, server room (B).
    m.wall_with_gaps((-10, -12), (-10, 30), 3.2, 0.2, [(6.0, 3.0, 99.0), (30.0, 2.0, 2.4)], "office_wall", name="WestWall")
    m.wall_with_gaps((-24, 14), (-10, 14), 3.2, 0.2, [(9.0, 1.8, 2.4)], "glass", name="ConfWall")
    m.box((-17, 0.4, 22), (6, 0.8, 2.2), "wood", "ConfTable")
    for x in (-19.5, -17, -14.5):
        for z in (20.5, 23.5):
            m.cyl((x, 0.3, z), 0.25, 0.6, "floor_dark", "Chair", collide=False)
    m.box((-17, 1.8, 29.7), (4, 1.6, 0.05), "dark", "Screen", collide=False)
    for z in (-9, -6, -3):
        m.box((-22.8, 1.0, z), (0.9, 2.0, 1.2), "dark", "ServerRack")
        m.box((-22.3, 1.6, z), (0.02, 0.05, 0.8), "lamp", "RackLed", collide=False)
    m.box((-15, 1.0, -4), (0.9, 2.0, 1.2), "dark", "ServerRack")
    m.box((-15, 0.6, 6), (1.2, 1.2, 1.2), "floor_dark", "UPS")
    m.site("B", (-17.0, 0.0, 2.0))
    # Under the mezzanine: break room (west), storage (east), CT spawn.
    m.wall_with_gaps((-24, -12), (-10, -12), 3.2, 0.2, [(9.0, 1.8, 2.4)], "office_wall", name="BreakWall")
    m.wall_with_gaps((10, -12), (24, -12), 3.2, 0.2, [(3.0, 1.8, 2.4)], "office_wall", name="StoreWall")
    m.box((-22.5, 0.45, -24), (1.2, 0.9, 6), "tile", "Kitchen")
    m.box((-17, 0.38, -20), (3, 0.75, 1.4), "wood", "Table")
    m.box((-12, 0.9, -28.8), (0.8, 1.8, 0.6), "tile_band", "Fridge")
    for (x, z) in ((14, -26), (14, -22), (19, -27)):
        _crates(m, x, z, 2 if x == 14 else 1, size=1.0)
    m.box((22.5, 1.5, -18), (1.0, 3.0, 5.0), "metal", "Shelving")
    for (x, z) in ((-17, 20), (-17, 0), (17, 20), (17, 0), (0, 16), (0, -22), (-17, -22), (17, -22)):
        _strip_light(m, x, 3.35 if z > -12 and abs(x) > 12 else (F - 0.36 if z < -12 else 7.2), z, 2.4)
    for (x, y, z) in ((0, 6.2, 14), (16, 2.9, 14), (-17, 2.9, 20), (-17, 2.9, 0), (0, 2.9, -22), (0, 6.3, -26), (17, 2.9, -22)):
        m.omni((x, y, z), 1.0, 12.0, (1.0, 0.96, 0.9))
    # Ceilings of the ground-floor wings (3.3 m).
    for x in (17, -17):
        m.box((x, 3.35, 9), (14, 0.1, 42), "ceiling", "Ceiling", collide=False)
    # Street: parked cars, lamps, trees.
    for (x, z) in ((-14, 38), (12, 40), (26, 36)):
        m.box((x, 0.7, z), (4.2, 1.4, 2.0), "blue" if x < 0 else "red", "Car")
        m.box((x - 0.2, 1.6, z), (2.2, 0.5, 1.8), "glass", "CarTop", collide=False)
    for x in (-20, -6, 6, 20):
        m.cyl((x, 2.5, 34.5), 0.08, 5.0, "metal", "LampPost", collide=False)
        m.box((x, 5.0, 34.9), (0.3, 0.1, 0.9), "lamp", "StreetLamp", collide=False)
    for x in (-26.5, 26.5):
        m.box((x, 0.45, 20), (0.6, 0.9, 5), "concrete", "Planter")

    for x in (-6, -3, 0, 3, 6):
        m.spawn("red", (x, 0.1, 40), 0)
    for x in (-6, -2, 2, 6):
        m.spawn("blue", (x, 0.1, -24), 180)
    for (x, y, z, yaw) in ((27, 0.1, 0, 0), (-27, 0.1, 0, 0), (0, 0.1, 2, 180), (0, F + 0.1, -16, 0), (-16, F + 0.1, -16, 90)):
        m.spawn("ffa", (x, y, z), yaw)
    for (label, pos, size) in (
            ("Street", (0, 2, 39), (60, 6, 18)),
            ("Lobby", (0, 3, 9), (20, 7, 42)),
            ("Reception", (0, 2, 16), (8, 4, 5)),
            ("Open Office", (17, 2, 9), (14, 3.4, 42)),
            ("Bombsite A", (15.5, 1.5, 15.5), (9, 3.4, 12)),
            ("Conference", (-17, 2, 22), (14, 3.4, 16)),
            ("Server Room", (-17, 1.5, -4), (14, 3.4, 16)),
            ("Bombsite B", (-17, 1.5, 2), (10, 3.4, 8)),
            ("Break Room", (-17, 1.5, -21), (14, 3.2, 18)),
            ("Storage", (17, 1.5, -21), (14, 3.2, 18)),
            ("Mezzanine", (0, 5.3, -16.5), (48, 3.4, 9)),
            ("Upper Offices", (0, 5.3, -25.5), (48, 3.4, 9)),
            ("East Alley", (27, 2, 0), (6, 6, 68)),
            ("West Alley", (-27, 2, 0), (6, 6, 68))):
        m.callout(label, pos, size)
    m.reverb((0, HT / 2, 9), (20, HT, 42), "hall", 0.35)
    m.reverb((17, 1.6, 9), (14, 3.2, 42), "room", 0.3, priority=1)
    m.reverb((-17, 1.6, 9), (14, 3.2, 42), "room", 0.35, priority=1)
    m.reverb((0, 1.6, -21), (48, 3.2, 18), "room", 0.35, priority=1)
    m.sign((12.5, 3.3, 30.2), "s", "A", toward=(26, 30))
    m.sign((-12.5, 3.3, 30.2), "s", "B", toward=(-26, 30))

    m.write("scenes/levels/office.tscn", sun_rot=(-40.0, 200.0), sky=(0.3, 0.5, 0.8), horizon=(0.7, 0.74, 0.8),
            sun_energy=1.1, ambient=0.9, ambient_color=(0.72, 0.72, 0.72))


def subway():
    """Underground station: two side platforms and an island between two
    track beds (drop down, climb out at the ends), a parked train you can
    walk through, ticket halls at both ends (CT north, T south)."""
    m = Map("Subway")
    X, Z, TOP, PIT, CEIL = 26.0, 44.0, 0.0, -1.2, 5.0
    # Track bed everywhere, platforms/concourses raised to 0.
    m.box((0, PIT - 0.5, 0), (2 * X + 2, 1, 2 * Z + 2), "gravel", "TrackBed")
    for (x0, x1) in ((-X, -7.8), (-4.2, 4.2), (7.8, X)):
        m.box(((x0 + x1) / 2, (PIT + TOP) / 2, 0), (x1 - x0, TOP - PIT, 60), "floor_dark", "Platform")
        for edge in (x0, x1):
            if abs(edge) < X:
                m.box((edge + (0.2 if edge == x0 else -0.2), 0.005, 0), (0.4, 0.01, 60), "yellow", "EdgeLine", collide=False)
    for zc in (-37.0, 37.0):
        m.box((0, (PIT + TOP) / 2, zc), (2 * X, TOP - PIT, 14), "tile", "Concourse")
    for x in (-6.0, 6.0):
        _rails(m, x, -30, 30, PIT, 2.4)
        for (a, b) in (((x, PIT, -24.0), (x + 0.001, TOP, -29.9)), ((x, PIT, 24.0), (x + 0.001, TOP, 29.9))):
            m.ramp(a, b, 2.2, "metal", thickness=0.3)
    # Walls, ceiling, tunnel mouths (dark) above the track ends.
    for (pos, size) in (((0, 2, -Z - 0.5), (2 * X + 2, 7, 1)), ((0, 2, Z + 0.5), (2 * X + 2, 7, 1)),
                        ((X + 0.5, 2, 0), (1, 7, 2 * Z)), ((-X - 0.5, 2, 0), (1, 7, 2 * Z))):
        m.box(pos, size, "tile", "Wall")
    for x in (-X + 0.02, X - 0.02):
        m.box((x, 1.2, 0), (0.06, 0.5, 60), "tile_band", "Band", collide=False)
        for z in (-20, 0, 20):
            m.box((x, 2.6, z), (0.06, 1.0, 4.0), "tile_band", "StationSign", collide=False)
    m.box((0, CEIL + 0.2, 0), (2 * X + 2, 0.4, 2 * Z + 2), "ceiling", "Ceiling")
    for x in (-6.0, 6.0):
        m.box((x, CEIL - 0.3, 0), (4.0, 0.6, 60), "concrete", "Duct", collide=False)
    # Pillars.
    for z in (-24, -16, -8, 0, 8, 16, 24):
        for x in (-12.5, 0.0, 12.5):
            m.box((x, (TOP + CEIL) / 2, z), (0.7, CEIL - TOP, 0.7), "tile", "Pillar")
    # Train: two cars on the west track (z -18..12), walk-through.
    def car(z0, z1):
        cx, w, L = -6.0, 3.4, z1 - z0
        zc = (z0 + z1) / 2
        m.box((cx, (PIT + TOP - 0.2) / 2, zc), (w - 0.4, TOP - 0.2 - PIT, L - 0.4), "floor_dark", "Bogies")
        m.box((cx, TOP - 0.1, zc), (w, 0.2, L), "floor_dark", "CarFloor")
        for side in (-1, 1):
            xw = cx + side * (w / 2 - 0.05)
            m.wall_with_gaps((xw, z0), (xw, z1), 2.4, 0.1, [(2.0, 1.4, 2.1), (6.6, 1.4, 2.1), (11.2, 1.4, 2.1)],
                             "silver", y0=TOP, name="CarWall")
            m.box((xw + side * 0.06, 0.9, zc), (0.02, 0.25, L), "red", "Stripe", collide=False)
            for off in (4.3, 8.9, 13.2):
                if off < L:
                    m.box((xw + side * 0.06, 1.55, z0 + off), (0.02, 0.7, 2.6), "glass", "CarWindow", collide=False)
            for (a0, a1) in ((0.3, 1.8), (3.6, 6.4), (8.2, 11.0), (12.8, L - 0.3)):
                m.box((cx + side * 1.35, 0.25, z0 + (a0 + a1) / 2), (0.5, 0.5, a1 - a0), "tile_band", "Seats")
        for zz in (z0, z1):
            m.wall_with_gaps((cx - w / 2, zz), (cx + w / 2, zz), 2.4, 0.1, [(1.2, 1.0, 2.1)], "silver", y0=TOP, name="CarEnd")
        m.box((cx, 2.5, zc), (w + 0.1, 0.2, L), "silver", "CarRoof")
        _strip_light(m, cx, 2.35, zc, L - 2.0)
    car(-18.0, -3.4)
    m.box((-6.0, TOP - 0.1, -3.0), (1.2, 0.2, 0.8), "floor_dark", "Gangway")
    car(-2.6, 12.0)
    # Platform furniture.
    for (x, z) in ((-18, -20), (-18, 4), (18, -12), (18, 16), (0, -12), (0, 12)):
        m.box((x, 0.25, z), (0.6, 0.5, 2.6), "wood", "Bench")
    for (x, z) in ((-24.5, -8), (24.5, 4), (24.5, -24)):
        m.box((x, 1.0, z), (1.0, 2.0, 1.2), "red", "Vending")
        m.box((x - 0.51 * (1 if x > 0 else -1), 1.3, z), (0.02, 0.8, 0.8), "lamp", "VendingFront", collide=False)
    for (x, z) in ((-12.5, -12), (12.5, 20), (0, 20)):
        m.cyl((x + 0.7, 0.45, z), 0.3, 0.9, "metal", "Bin")
    m.box((17.5, 0.5, -6), (2.4, 1.0, 0.4), "yellow", "Barrier")
    m.box((20, 0.5, -3.5), (0.4, 1.0, 2.4), "yellow", "Barrier")
    _crates(m, 21.5, -10, 2, size=1.0)
    m.box((-17, 0.6, 17), (2.2, 1.2, 1.2), "concrete", "Planter")
    _crates(m, -21.5, 10, 1)
    # Ticket halls: turnstiles, booths, stairs to the street (dead ends, cover).
    for zc, sgn in ((-31.0, -1), (31.0, 1)):
        for x in range(-24, 25, 3):
            if abs(x) not in (0, 12, 24):
                m.box((x, 0.5, zc), (0.3, 1.0, 1.0), "metal", "Turnstile")
        m.box((18, 1.4, zc + sgn * 7), (5, 2.8, 3), "glass", "Booth")
        m.ramp((-18.0, 0.0, zc + sgn * 5.0), (-18.001, 3.0, zc + sgn * 12.5), 3.4, "concrete")
        m.box((-18, 0.5, zc + sgn * 12.9), (3.6, 7, 0.4), "concrete", "StairWall")
        m.box((-18, 3.9, zc + sgn * 9.0), (3.6, 0.2, 7.0), "concrete", "StairCeiling", collide=False)
        for x in (-16.1, -19.9):
            m.box((x, 1.2, zc + sgn * 8.7), (0.2, 2.4, 7.6), "tile", "StairSide")
    # Strip lights everywhere (emissive: rooms stay lit on Low) + a few real lights.
    for z in range(-28, 29, 8):
        for x in (-17, 0, 17):
            _strip_light(m, x, CEIL - 0.05, z, 3.0)
    for z in (-38, 38):
        for x in (-12, 0, 12):
            _strip_light(m, x, CEIL - 0.05, z, 3.0, yaw=90)
    for (x, z) in ((-17, -16), (-17, 16), (17, -16), (17, 16), (0, 0), (0, -38), (0, 38)):
        m.omni((x, 4.2, z), 1.0, 14.0, (0.95, 0.97, 1.0))

    m.site("A", (18.0, 0.0, -18.0))
    m.site("B", (-17.0, 0.0, -6.0))
    for x in (-8, -4, 0, 4, 8):
        m.spawn("red", (x, 0.1, 38), 0)
    for x in (-6, -2, 2, 6):
        m.spawn("blue", (x, 0.1, -38), 180)
    for (x, y, z, yaw) in ((-6, 0.1, 5, 0), (6, PIT + 0.1, 0, 0), (20, 0.1, 8, 0), (-20, 0.1, -24, 180), (0, 0.1, -20, 0)):
        m.spawn("ffa", (x, y, z), yaw)
    for (label, pos, size) in (
            ("South Hall", (0, 2, 37), (52, 5, 14)),
            ("North Hall", (0, 2, -37), (52, 5, 14)),
            ("East Platform", (17, 2, 0), (18, 5, 60)),
            ("West Platform", (-17, 2, 0), (18, 5, 60)),
            ("Island", (0, 2, 0), (8.4, 5, 60)),
            ("Train", (-6, 1.2, -3), (3.4, 2.4, 30)),
            ("East Tracks", (6, 0, 0), (3.6, 3, 60)),
            ("West Tracks", (-6, -0.2, 0), (3.6, 2, 60)),
            ("Bombsite A", (18, 2, -18), (12, 5, 12)),
            ("Bombsite B", (-17, 2, -6), (12, 5, 12)),
            ("Stairs", (-18, 2, -40), (4, 5, 8)),
            ("Stairs", (-18, 2, 40), (4, 5, 8))):
        m.callout(label, pos, size)
    m.reverb((0, 2, 0), (2 * X, 7, 2 * Z), "hall", 0.5)
    m.reverb((-6, 1.2, -3), (3.4, 2.4, 30), "room", 0.3, priority=1)
    m.sign((-26.0, 2.6, -12.0), "e", "B", toward=(-17, -6))
    m.sign((26.0, 2.6, -28.0), "w", "A", toward=(18, -18))
    m.sign((-26.0, 2.6, 28.0), "e", "B", toward=(-26, 0))
    m.sign((26.0, 2.6, 28.0), "w", "A", toward=(26, 0))

    m.write("scenes/levels/subway.tscn", sun_rot=(-80.0, 0.0), sky=(0.1, 0.1, 0.12), horizon=(0.2, 0.2, 0.22),
            sun_color=(1, 1, 1), sun_energy=0.0, sun_shadow=False, ambient=1.1, ambient_color=(0.78, 0.8, 0.84))


def trainyard():
    """Freight yard: six tracks of parked box, tank and hopper cars with
    gaps to cut through, a maintenance shed (A) in the east, a signal tower
    with a balcony and a container stack (B) in the west."""
    import random
    rng = random.Random(3)
    m = Map("TrainYard")
    X, Z = 40.0, 46.0
    m.box((0, -0.5, 0), (2 * X + 4, 1, 2 * Z + 4), "gravel", "Ground")
    _ring(m, rng, -X, X, -Z, Z, ("brick", "concrete", "rust", "brick"), h=(7, 9))
    for x in (-20, -12, -4, 4, 12, 20):
        _rails(m, x, -38, 38)
    cars = [(-20, -24, "box", "rust"), (-20, -10, "tank", "floor_dark"), (-20, 16, "box", "blue"),
            (-12, -2, "hopper", "green"), (-12, 26, "box", "rust"),
            (-4, -26, "box", "red"), (-4, -12, "box", "rust"), (-4, 12, "tank", "tile"),
            (4, -4, "box", "blue"), (4, 22, "hopper", "rust"),
            (12, -22, "tank", "floor_dark"), (12, 8, "box", "green"), (12, 24, "box", "rust"),
            (20, -8, "box", "rust"), (20, 10, "box", "red")]
    for (x, z, kind, mat) in cars:
        _freight(m, x, z, kind, mat)
    # A: maintenance shed (open sides) with a locomotive.
    for x in (26, 38):
        for z in (-30, -22, -14, -6):
            m.box((x, 3.5, z), (0.5, 7.0, 0.5), "metal", "ShedPost")
    m.box((32, 7.2, -18), (13, 0.4, 25), "rust", "ShedRoof", collide=False)
    for z in (-30, -18, -6):
        m.box((32, 6.8, z), (12.5, 0.4, 0.4), "metal", "ShedTruss", collide=False)
    _rails(m, 35, -32, -4)
    m.box((35, 0.8, -23), (2.4, 0.8, 11), "floor_dark", "LocoFrame")
    m.box((35, 2.4, -24.5), (2.8, 2.6, 8), "yellow", "Loco")
    m.box((35, 2.9, -19), (3.0, 3.6, 3), "yellow", "LocoCab")
    m.box((35, 3.6, -17.45), (2.2, 1.0, 0.06), "glass", "LocoWindow", collide=False)
    _drum(m, 28, -28, "rust")
    _drum(m, 28.7, -27.3, "yellow")
    m.box((29, 0.6, -10), (2.4, 1.2, 1.2), "wood", "Sleepers")
    m.box((29, 1.5, -10), (2.4, 0.6, 1.2), "wood", "Sleepers", yaw=10)
    m.cyl((31, 0.9, -12.5), 0.9, 0.9, "wood", "CableDrum", roll=90)
    for (x, z) in ((32, -28), (32, -8)):
        _strip_light(m, x, 6.9, z, 4.0, yaw=90)
    m.omni((32, 6.0, -18), 1.2, 15.0)
    m.site("A", (30.0, 0.0, -17.0))
    # B: signal tower with balcony + ramp, container stack.
    m.box((-34, 4.0, -8), (8, 8, 8), "brick", "Tower")
    for z in (-10, -6):
        m.box((-29.97, 5.5, z), (0.06, 1.2, 1.6), "glass", "TowerWindow", collide=False)
    m.box((-28, 3.85, -8), (4, 0.3, 4), "metal", "Balcony")
    m.box((-26.05, 4.5, -8), (0.1, 1.0, 4), "metal", "BalconyRail")
    m.box((-28, 4.5, -9.95), (4, 1.0, 0.1), "metal", "BalconyRail")
    for (x, z) in ((-26.3, -9.7), (-26.3, -6.3)):
        m.box((x, 1.85, z), (0.25, 3.7, 0.25), "metal", "BalconyPost")
    m.ramp((-28.9, 0.0, 6.0), (-28.901, 4.0, -6.0), 1.8, "metal")
    _container(m, -36, -28, 0, "blue")
    _container(m, -36, -28, 0, "red", 1)
    _container(m, -30, -34, 90, "green")
    _container(m, -24, -20, 0, "rust")
    _crates(m, -32, -18, 2)
    m.box((-27, 0.5, -26), (0.5, 1.0, 3.0), "concrete", "Barrier")
    m.site("B", (-31.0, 0.0, -22.0))
    # Signals, buffer stops, huts.
    for (x, z) in ((-16, -36), (-8, 34), (8, -36), (16, 34)):
        m.cyl((x, 2.5, z), 0.1, 5.0, "metal", "SignalPost", collide=False)
        m.box((x, 4.6, z), (0.4, 0.8, 0.3), "floor_dark", "SignalHead", collide=False)
        m.box((x, 4.8, z + 0.16), (0.2, 0.2, 0.02), "lamp_red", "SignalLamp", collide=False)
    for x in (-20, -12, -4, 4, 12, 20):
        for z in (-38.5, 38.5):
            m.box((x, 0.6, z), (2.4, 1.2, 0.6), "red", "BufferStop")
    m.box((26, 1.5, 20), (4, 3, 6), "brick", "Hut")
    m.box((-28, 1.5, 24), (6, 3, 4), "concrete", "Hut")
    for (x, z) in ((28, 30), (-30, 34), (30, 6), (-34, 14)):
        m.box((x, 0.6, z), (1.2, 1.2, 1.2), "wood", "Crate")
    for (x, z) in ((-38, 0), (38, 16), (0, -44), (0, 44)):
        m.cyl((x, 5.0, z), 0.15, 10.0, "metal", "FloodPole", collide=False)
        m.box((x, 10.0, z), (1.6, 0.5, 0.4), "lamp", "Flood", collide=False)

    for x in (-8, -4, 0, 4, 8):
        m.spawn("red", (x, 0.1, 42), 0)
    for x in (-8, -1, 1, 8):
        m.spawn("blue", (x, 0.1, -42), 180)
    for (x, z, yaw) in ((34, 34, 0), (-34, 30, 0), (0, 0, 90), (-16, 0, 0), (24, -38, 180), (-28, 4.0, 180)):
        m.spawn("ffa", (x, 0.1, z), yaw)
    for (label, pos, size) in (
            ("T Spawn", (0, 2, 42), (80, 6, 8)),
            ("CT Spawn", (0, 2, -42), (80, 6, 8)),
            ("Tracks", (0, 2, 0), (48, 8, 76)),
            ("Shed", (32, 3, -18), (13, 7, 26)),
            ("Bombsite A", (30, 2, -17), (10, 6, 10)),
            ("Tower", (-28, 5, -8), (4, 3, 4)),
            ("Ramp", (-28.9, 2, 0), (2, 5, 12)),
            ("Bombsite B", (-31, 2, -22), (12, 6, 12)),
            ("Containers", (-32, 2, -30), (12, 6, 8)),
            ("East Side", (32, 2, 18), (16, 6, 50)),
            ("West Side", (-32, 2, 20), (16, 6, 50))):
        m.callout(label, pos, size)
    m.reverb((32, 3.5, -18), (13, 7, 26), "room", 0.25)
    m.sign((-30.0, 2.2, -5.0), "e", "B", toward=(-31, -22))
    m.sign((24.0, 1.9, 20.0), "w", "A", toward=(30, -17))

    m.write("scenes/levels/trainyard.tscn", sun_rot=(-35.0, 70.0), sky=(0.34, 0.48, 0.68), horizon=(0.76, 0.72, 0.66),
            sun_color=(1.0, 0.86, 0.68), sun_energy=1.2, ambient=0.8, ambient_color=(0.66, 0.64, 0.62),
            fog=0.003, fog_color=(0.8, 0.74, 0.66))


if __name__ == "__main__":
    warehouse()
    courtyard()
    rooftops()
    docks()
    bunker()
    kasbah()
    factory()
    office()
    subway()
    trainyard()
