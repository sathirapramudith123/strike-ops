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
import re

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
    "rock": {"kind": 5, "base_color": (0.34, 0.3, 0.26), "line_color": (0.24, 0.21, 0.18), "cell_size": 2.2,
             "roughness_value": 1.0, "grime": 0.4},
    "bunker": {"kind": 1, "base_color": (0.46, 0.47, 0.45), "line_color": (0.34, 0.35, 0.34), "cell_size": 2.0,
               "grime": 0.45},
    "water": {"kind": 4, "base_color": (0.07, 0.16, 0.22), "line_color": (0.07, 0.16, 0.22), "roughness_value": 0.08,
              "grime": 0.0},
    "sack": {"kind": 10, "base_color": (0.66, 0.6, 0.46), "line_color": (0.62, 0.56, 0.43), "cell_size": 0.5,
             "roughness_value": 1.0, "grime": 0.0},
}
SITE_RADIUS = 3.5  # keep in sync with BombRules.SITE_RADIUS
# Bodies players can climb onto (Jump facing them; see scripts/player/climb.gd)
# go in the "climbable" group: props named with one of these prefixes, no
# taller than CLIMB_MAX_HEIGHT. Everything else is only reached by jumping
# (up to ~1.4 m) or by stairs and ramps.
CLIMBABLE = ("Crate", "Pallet", "Desk", "Stall", "Barrel", "Drum", "Sack", "BagCollider", "Car", "Cart",
             "Forklift", "ACUnit", "Tarp", "TankDeck", "Underframe", "LowWall", "Ledge")
CLIMB_MAX_HEIGHT = 2.3


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
        self.doors = []  # (bottom-centre pos, yaw, width, height) — scripts/levels/door.gd
        self.panes = []  # (centre pos, yaw, width, height) — breakable glass, scripts/levels/glass_pane.gd
        self.barrels = []  # bottom-centre pos — explosive red drums, scripts/levels/explosive_barrel.gd
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

    def door(self, pos, yaw, width, height):
        """A door that opens (Interact) and breaks where it is shot. pos is
        the bottom centre of the doorway; yaw 0 = the door spans X."""
        self.doors.append((pos, yaw, width, height))

    def pane(self, pos, yaw, width, height):
        """A breakable glass pane centred on pos; yaw 0 = it spans X."""
        self.panes.append((pos, yaw, width, height))

    def barrel(self, pos):
        """An explosive red oil drum (shoot it and it blows up); pos is its
        bottom centre."""
        self.barrels.append(pos)

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

    def wall_with_gaps(self, a, b, height, thickness, gaps, mat="wall", y0=0.0, name="Wall", doors=False):
        """Straight wall from a=(x,z) to b=(x,z) (axis-aligned) with door gaps:
        gaps = [(offset_from_a, gap_width, gap_height)]; gap_height >= height = full.
        doors=True puts a door (Map.door) in every door-sized gap; a "glass"
        wall is made of breakable panes (Map.pane)."""
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
            if doors and gh < height and w <= 2.2 and gh <= 2.6:
                mid = (off + w / 2) * sign
                self.door((ax + mid, y0, az) if along_x else (ax, y0, az + mid), 0.0 if along_x else 90.0, w, gh)
            pos = off + w
        if pos < total:
            segments.append((pos, total, 0.0, height))
        for s0, s1, h0, h1 in segments:
            mid = (s0 + s1) / 2 * sign
            length = s1 - s0
            cy = y0 + (h0 + h1) / 2
            if mat == "glass":
                # Breakable panes, at most ~3 m wide each.
                n = max(1, math.ceil(length / 3.0))
                for k in range(n):
                    pm = (s0 + (k + 0.5) * length / n) * sign
                    self.pane((ax + pm, cy, az) if along_x else (ax, cy, az + pm), 0.0 if along_x else 90.0,
                              length / n - 0.04, h1 - h0 - 0.04)
                continue
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
            tall = shape[1][1] if shape[0] == "box" else shape[3]
            climb = collide and re.sub(r"\d+$", "", name) in CLIMBABLE and tall <= CLIMB_MAX_HEIGHT
            groups = ' groups=["climbable"]' if climb else ""
            nodes.append(f'[node name="{name}" type="StaticBody3D" parent="Geometry"{groups}]\ntransform = Transform3D({b}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n')
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
[ext_resource type="Script" path="res://scripts/levels/door.gd" id="7_door"]
[ext_resource type="Script" path="res://scripts/levels/glass_pane.gd" id="8_glass"]
[ext_resource type="Script" path="res://scripts/levels/explosive_barrel.gd" id="9_barrel"]

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
        door_nodes = []
        for i, (pos, yaw, w, h) in enumerate(self.doors):
            b = ", ".join(f"{v:.6f}" for v in self._basis(yaw))
            door_nodes.append(f'[node name="Door{i + 1}" type="Node3D" parent="Doors"]\n'
                              f'transform = Transform3D({b}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n'
                              f'script = ExtResource("7_door")\nwidth = {w:.3f}\nheight = {h:.3f}\n')
        pane_nodes = []
        for i, (pos, yaw, w, h) in enumerate(self.panes):
            b = ", ".join(f"{v:.6f}" for v in self._basis(yaw))
            pane_nodes.append(f'[node name="Pane{i + 1}" type="Node3D" parent="Glass"]\n'
                              f'transform = Transform3D({b}, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n'
                              f'script = ExtResource("8_glass")\nwidth = {w:.3f}\nheight = {h:.3f}\n')
        barrel_nodes = []
        for i, pos in enumerate(self.barrels):
            barrel_nodes.append(f'[node name="Barrel{i + 1}" type="Node3D" parent="Barrels"]\n'
                                f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]:.3f}, {pos[1]:.3f}, {pos[2]:.3f})\n'
                                f'script = ExtResource("9_barrel")\n')
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
               + ('\n[node name="Doors" type="Node3D" parent="."]\n\n' + "\n".join(door_nodes) if door_nodes else "")
               + ('\n[node name="Glass" type="Node3D" parent="."]\n\n' + "\n".join(pane_nodes) if pane_nodes else "")
               + ('\n[node name="Barrels" type="Node3D" parent="."]\n\n' + "\n".join(barrel_nodes) if barrel_nodes else "")
               + "\n" + tail)
        with open(os.path.join(ROOT, path), "w") as f:
            f.write(out)
        print(f"wrote {path}: {len(self.boxes)} boxes, spawns blue={len(self.spawns['blue'])} red={len(self.spawns['red'])} ffa={len(self.spawns['ffa'])}")


# ======================================================================
def bunker():
    """Bunker (bomb map, 3 lanes, all indoors). T spawn west, CT spawn east.
    A in the north, reached from T by A Long — a raised corridor that ends
    on a balcony over the site; B in the south, one level down, reached by
    B Long (a ramp down) and the rock-walled Tunnel (B2). Mid is a tall hall
    around a red-lit reactor with a catwalk; Storage / Utility is a flank
    room between T Mid and Mid. Short connectors join Mid to both sites."""
    m = Map("Bunker")
    U, L = 2.5, -3.0  # upper level (A Long, balcony), lower level (B)
    W, F = "bunker", "floor_dark"

    def room(name, x0, x1, z0, z1, y=0.0, top=5.0, wall=W, floor=F):
        return dict(name=name, x0=x0, x1=x1, z0=z0, z1=z1, y=y, top=top, wall=wall, floor=floor)

    rooms = [
        room("TSpawn", -46, -34, -8, 8),
        room("TMid", -34, -18, -3, 3, top=4.5),
        room("Mid", -18, 18, -13, 13, top=10.0),
        room("CTMid", 18, 34, -3, 3, top=4.5),
        room("CTSpawn", 34, 46, -8, 8),
        # A side.
        room("ALongRise", -44, -38, -22, -8, top=6.5),
        room("ALongUpperW", -44, -38, -35, -22, y=U, top=7.5),
        room("ALongUpper", -38, -14, -35, -28, y=U, top=7.5),
        room("ASite", -14, 14, -40, -19, top=8.0),
        room("ABalcony", -14, -8, -35, -28, y=U, top=8.0),
        room("AShort", -3, 3, -19, -13, top=4.0),
        room("CTNorth", 38, 44, -26, -8),
        room("CTA", 14, 44, -32, -26),
        # B side (one level down).
        room("BLong", -44, -38, 8, 22, y=L, top=3.5),
        dict(room("Tunnel", -44, -14, 22, 28, y=L, top=1.5, wall="rock", floor="gravel"), ceil="rock"),
        room("BSite", -14, 14, 20, 40, y=L, top=5.0),
        room("BStairs", -3, 3, 13, 20, y=L, top=4.0),
        room("CTSouth", 38, 44, 8, 22, y=L, top=3.5),
        room("CTB", 14, 44, 22, 28, y=L, top=2.0),
        # Storage / Utility: T Mid <-> Mid flank (doors through 1 m walls).
        room("Storage", -32, -19, -15, -4, top=4.0),
        room("StorageDoorS", -27, -24, -4, -3, top=2.6),
        room("StorageDoorE", -19, -18, -10, -7, top=2.6),
    ]
    _rooms(m, rooms, trim=("floor_dark", "hazard"))

    # --- Ramps between the levels ------------------------------------------------
    m.ramp((-41, 0.0, -9.0), (-41.001, U, -22.0), 6.0, "metal")          # A Long up
    m.ramp((-11, U, -28.0), (-11.001, 0.0, -21.5), 2.4, "metal")         # balcony down into A
    m.ramp((-41, 0.0, 8.0), (-41.001, L, 21.0), 6.0, "metal")            # B Long down
    m.ramp((0, 0.0, 13.0), (0.001, L, 20.0), 6.0, "metal")               # Mid -> B stairs
    m.ramp((41, 0.0, 8.0), (41.001, L, 21.0), 6.0, "metal")              # CT -> B
    for (x, z0, z1, y0, y1) in ((-41, -9.0, -22.0, 0.0, U), (-41, 8.0, 21.0, 0.0, L), (41, 8.0, 21.0, 0.0, L),
                                (0, 13.0, 20.0, 0.0, L)):
        for dz in range(int(abs(z1 - z0))):   # step nosing lines (visual)
            z = z0 + (dz + 0.5) * (1 if z1 > z0 else -1)
            y = y0 + (y1 - y0) * (z - z0) / (z1 - z0)
            m.box((x, y + 0.02, z), (5.8 if x != 0 else 5.8, 0.03, 0.1), "hazard", "StepLine", collide=False)
    # Balcony and A Long railings (a gap where the ramp comes down).
    _rail(m, (-8.0, U + 0.5, -31.5), (0.06, 1.0, 7.0), "yellow")
    _rail(m, (-11.0, U + 0.5, -35.0), (6.0, 1.0, 0.06), "yellow")
    _rail(m, (-13.1, U + 0.5, -28.0), (1.8, 1.0, 0.06), "yellow")
    _rail(m, (-8.9, U + 0.5, -28.0), (1.8, 1.0, 0.06), "yellow")
    for x in (-12.2, -9.8):
        _rail(m, (x, U / 2 + 0.5, -24.8), (0.06, 1.0, 6.2), "yellow")

    # --- Mid: reactor, catwalk, grate --------------------------------------------
    m.cyl((0, 4.75, 1.5), 4.2, 9.5, "silver", "Reactor", segments=20)
    for y in (1.5, 4.5, 7.5):
        m.cyl((0, y, 1.5), 4.3, 0.25, "floor_dark", "ReactorBand", segments=20, collide=False)
    m.box((0, 5.0, 1.5 + 4.25), (3.0, 3.0, 0.05), "paint_red", "ReactorPanel", collide=False)
    m.sign((0.0, 5.3, 5.85), "s", "B", color=(0.7, 0.1, 0.07), pixel=0.012)
    for (x, z) in ((-4.3, 1.5), (4.3, 1.5), (0, -2.8)):
        m.box((x, 9.0, z), (0.4, 0.3, 0.4), "lamp_red", "RedLamp", collide=False)
    m.omni((0, 8.5, 1.5), 1.6, 14.0, (1.0, 0.2, 0.15))
    CW = 3.5
    m.box((-2, CW - 0.15, -11.5), (28, 0.3, 3.0), "metal", "Catwalk")
    for x in (-14, -6, 2, 10):
        m.box((x, (CW - 0.3) / 2, -10.2), (0.3, CW - 0.3, 0.3), "metal", "CatwalkPost")
    _rail(m, (-0.5, CW + 0.5, -10.0), (25.0, 1.0, 0.06), "yellow")
    m.ramp((-16.5, 0.0, -2.0), (-16.501, CW, -10.0), 2.4, "metal")
    _rail(m, (-15.2, CW / 2 + 0.5, -6.0), (0.06, 1.0, 8.0), "yellow")
    m.box((-6, 0.02, 7.5), (6, 0.04, 4), "metal", "Grate", collide=False)
    for k in range(7):
        m.box((-9 + k, 0.05, 7.5), (0.08, 0.02, 4), "floor_dark", "GrateBar", collide=False)
    _forklift(m, -12, 7, 30)
    for (x, z) in ((-10, 10.5), (-8.8, 10.8), (9, -6), (10.2, -6.2)):
        _crates(m, x, z, 1)
    _crates(m, 12, 9, 2)
    _crates(m, 13.2, 10.2, 1)
    for (x, z) in ((7, 10.5), (7.7, 11.2)):
        _drum(m, x, z, "green")
    for x in (-16, 16):
        m.box((x, 0.01, 0), (0.15, 0.02, 24), "yellow", "FloorLine", collide=False)

    # --- Sites -----------------------------------------------------------------------
    for (x, z) in ((4, -35.5), (5.3, -35.8), (9, -24), (-2, -27)):
        m.box((x, 0.6, z), (1.2, 1.2, 1.2), "green", "AmmoCrate")
    m.box((9, 1.8, -24), (1.2, 1.2, 1.2), "green", "AmmoCrate")
    m.box((-4, 0.5, -37.5), (4, 1.0, 1.4), "metal", "Workbench")
    m.site("A", (3.0, 0.0, -30.0))
    m.sign((2.0, 4.8, -40.0), "s", "A", color=(0.7, 0.1, 0.07), pixel=0.02)
    for (x, z) in ((-7, 36), (-5.8, 36.3), (8, 25), (9.2, 25.1)):
        m.box((x, L + 0.6, z), (1.2, 1.2, 1.2), "green", "AmmoCrate")
    m.box((8, L + 1.8, 25), (1.2, 1.2, 1.2), "green", "AmmoCrate")
    m.box((0, L + 1.0, 38.8), (3.2, 2.0, 0.4), "steel_blue", "BlastDoor")
    m.box((0, L + 1.0, 38.55), (0.1, 2.0, 0.05), "floor_dark", "BlastDoorSeam", collide=False)
    m.box((-10, L + 1.1, 30), (1.0, 2.2, 3.0), "dark", "Generator")
    m.site("B", (2.0, L, 31.0))
    m.sign((-14.0, L + 3.0, 34.0), "e", "B", color=(0.7, 0.1, 0.07), pixel=0.018)
    m.sign((-44.0, L + 2.4, 25.0), "e", "B2", color=(0.9, 0.9, 0.85), pixel=0.012)
    m.sign((-38.0, 3.0, -15.0), "e", "A", toward=(0, -30), color=(0.7, 0.1, 0.07))
    m.sign((-38.0, 2.2, 15.0), "e", "B", toward=(0, 30), color=(0.7, 0.1, 0.07))
    m.sign((-46.0, 2.6, 0.0), "e", "T", color=(0.85, 0.6, 0.1), pixel=0.012)
    m.sign((46.0, 2.6, 0.0), "w", "CT", color=(0.25, 0.45, 0.85), pixel=0.012)
    m.sign((18.0, 3.2, -8.0), "w", "SECTOR B", toward=(0, 30), color=(0.7, 0.1, 0.07))

    # --- Storage / Utility, spawns ----------------------------------------------------
    for (x, z) in ((-30, -13), (-30, -10.5), (-30, -8)):
        m.box((x, 1.5, z), (1.0, 3.0, 2.0), "steel_blue", "Shelf")
        m.box((x, 1.0, z), (0.9, 0.6, 1.6), "wood", "ShelfBox", collide=False)
    _forklift(m, -23, -12, -80)
    _pallets(m, -21, -6.5)
    for (x, z) in ((-44, -5), (-44, 5), (44, -5), (44, 5)):
        m.box((x, 0.6, z), (1.2, 1.2, 1.2), "green", "AmmoCrate")
    _drum(m, -36, 6.3, "rust")
    _drum(m, 36, -6.3, "blue")

    # --- Lights (real + emissive strips so Low still reads) -------------------------
    for (x, y, z, e, r, c) in ((-40, 4.4, 0, 1.0, 11, (0.95, 0.9, 0.8)), (40, 4.4, 0, 1.0, 11, (0.8, 0.9, 1.0)),
                               (-26, 4.0, 0, 0.8, 9, (1.0, 0.9, 0.75)), (26, 4.0, 0, 0.8, 9, (1.0, 0.9, 0.75)),
                               (-10, 8.5, -7, 1.2, 14, (1.0, 0.95, 0.85)), (10, 8.5, 8, 1.2, 14, (1.0, 0.95, 0.85)),
                               (-26, 6.8, -31, 1.0, 12, (1.0, 0.92, 0.8)), (-41, 6.0, -15, 0.8, 9, (1.0, 0.92, 0.8)),
                               (0, 7.4, -30, 1.3, 16, (0.95, 0.97, 1.0)), (0, 4.4, 30, 1.2, 15, (0.95, 0.97, 1.0)),
                               (-29, 1.0, 25, 0.8, 10, (1.0, 0.75, 0.45)), (-41, 3.0, 15, 0.7, 9, (1.0, 0.9, 0.8)),
                               (29, 1.5, 25, 0.7, 10, (0.85, 0.9, 1.0)), (29, 4.4, -29, 0.8, 10, (0.85, 0.9, 1.0)),
                               (-25, 3.6, -9, 0.8, 9, (1.0, 0.9, 0.75)), (0, 3.6, -16, 0.6, 7, (1.0, 0.9, 0.8))):
        m.omni((x, y, z), e, r, c)
    for (x, y, z, yaw) in ((-40, 4.9, 0, 0), (40, 4.9, 0, 0), (-26, 4.4, 0, 90), (26, 4.4, 0, 90),
                           (-26, 7.4, -31.5, 90), (-14, 7.4, -31.5, 90), (-41, 6.4, -15, 0), (-41, 7.4, -29, 0),
                           (-6, 7.9, -30, 90), (6, 7.9, -30, 90), (-6, 7.9, -24, 90), (6, 7.9, -24, 90),
                           (-6, 4.9, 27, 90), (6, 4.9, 27, 90), (-6, 4.9, 34, 90), (6, 4.9, 34, 90),
                           (-26, 3.9, -9.5, 90), (41, 4.9, -17, 0), (29, 4.9, -29, 90), (0, 3.9, -16, 90),
                           (-41, 3.4, 15, 0), (41, 3.4, 15, 0), (29, 1.9, 25, 90), (-12, 9.9, 0, 0), (12, 9.9, 0, 0)):
        _strip_light(m, x, y, z, 2.4, yaw)
    for x in range(-40, -16, 6):   # tunnel: dim bulbs on a cable
        m.box((x, 1.2, 25), (0.25, 0.25, 0.25), "lamp", "Bulb", collide=False)
    m.beam((-44, 1.35, 25), (-14, 1.35, 25), 0.04, "cable", "TunnelCable")
    for z in (-12.5, 12.5):   # pipes along the Mid hall
        m.box((0, 9.2, z), (36, 0.35, 0.35), "rust", "Pipe", collide=False)
        m.box((0, 8.6, z), (36, 0.25, 0.25), "steel_blue", "Pipe", collide=False)

    for (x, z) in ((-44, -3), (-44, 0), (-44, 3), (-41, -5), (-41, 5)):
        m.spawn("red", (x, 0.1, z), 90)
    for (x, z) in ((44, -3), (44, 0), (44, 3), (41, -5), (41, 5)):
        m.spawn("blue", (x, 0.1, z), -90)
    for (x, y, z, yaw) in ((0, 0.1, -8, 0), (0, 0.1, 10, 180), (-26, 0.1, -9, 90), (-26, U + 0.1, -31.5, -90),
                           (0, L + 0.1, 28, 0), (-30, L + 0.1, 25, -90), (26, 0.1, -29, 90), (10, 0.1, -30, 90)):
        m.spawn("ffa", (x, y, z), yaw)
    for (label, pos, size) in (
            ("T Spawn", (-40, 2, 0), (12, 6, 16)),
            ("CT Spawn", (40, 2, 0), (12, 6, 16)),
            ("T Mid", (-26, 2, 0), (16, 5, 6)),
            ("CT Mid", (26, 2, 0), (16, 5, 6)),
            ("Mid", (0, 4, 0), (36, 10, 26)),
            ("Catwalk", (-2, 5, -11.5), (28, 3, 3)),
            ("A Long", (-41, 3, -15), (6, 7, 14)),
            ("A Long Upper", (-28, 4.5, -31.5), (32, 5, 7)),
            ("Bombsite A", (0, 3, -29.5), (28, 8, 21)),
            ("Balcony", (-11, 4.5, -31.5), (6, 4, 7)),
            ("A Short", (0, 2, -16), (6, 4, 6)),
            ("CT A", (32, 2, -22), (24, 6, 20)),
            ("B Long", (-41, 0, 15), (6, 6, 14)),
            ("Tunnel", (-29, -1, 25), (30, 5, 6)),
            ("Bombsite B", (0, 0, 30), (28, 8, 20)),
            ("B Stairs", (0, -1, 16.5), (6, 6, 7)),
            ("CT B", (32, -1, 22), (24, 6, 16)),
            ("Storage", (-25.5, 2, -9.5), (13, 4, 11))):
        m.callout(label, pos, size)
    m.reverb((0, 5, 0), (36, 10, 26), "hall", 0.5)
    for (pos, size) in (((-40, 2.5, 0), (12, 5, 16)), ((40, 2.5, 0), (12, 5, 16)), ((0, 4, -29.5), (28, 8, 21)),
                        ((0, 1, 30), (28, 8, 20)), ((-25.5, 2, -9.5), (13, 4, 11)), ((-28, 4.5, -31.5), (32, 5, 7))):
        m.reverb(pos, size, "room", 0.4, priority=1)
    m.reverb((-29, -1, 25), (30, 5, 6), "room", 0.55, priority=2)
    m.write("scenes/levels/bunker.tscn", sun_rot=(-70.0, 10.0), sky=(0.12, 0.13, 0.15), horizon=(0.2, 0.2, 0.22),
            sun_energy=0.08, sun_shadow=False, ambient=0.7, ambient_color=(0.6, 0.62, 0.66))


# ----------------------------------------------------------------------
# Desert town dressing helpers (used by oasis()).

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
    # Pots up on walls and terraces are decoration only (no awkward half-jumpable ledges).
    m.cyl((x, y + 0.24 * k, z), 0.2 * k, 0.48 * k, "clay", "Pot", top=0.34 * k, collide=y <= 0.0)
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


def oasis():
    """Desert town, bomb-defusal layout: attackers (red) in the south,
    defenders (blue) in the north. Three lanes — A Long on the east, Mid,
    and the covered B Apartments on the west — with a Connector from Mid to
    A and a Short from Mid to B. A is a raised terrace with pots and sacks,
    B a walled courtyard around a well."""
    import random
    rng = random.Random(7)
    m = Map("Oasis")
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
        (18, 30, 4, 20, 7, "sandstone", "se"),           # (north part is an enterable house)
        (4, 30, 24, 34, 6, "sandstone", "nsw"),         # Palace
        (-18, -4, -9, 20, 7, "plaster", "nse"),          # between Mid and B Apartments
        (-30, -18, 3, 20, 7, "plaster", "w"),           # (north-west part is an enterable house)
        (-30, -4, 24, 34, 6, "plaster_warm", "nse"),
        (14, 28, 38, 46, 7, "plaster", "nw"),           # T spawn sides
        (-28, -14, 38, 46, 7, "sandstone", "ne"),
        (20, 38, -46, -38, 7, "plaster_warm", "sw"),    # CT spawn sides
        (-38, -20, -46, -38, 7, "plaster", "se"),
    ]
    for (x0, x1, z0, z1, h, mat, faces) in blocks:
        _building(m, rng, x0, x1, z0, z1, h, mat, faces)
    # Enterable houses: doors, stairs, upstairs windows over A and over B.
    _house(m, 18, 30, -10, 4, "sandstone", doors=[("e", 3.0, 1.6), ("n", 6.0, 1.6)], windows="ne", stair_side="w")
    _house(m, -30, -18, -9, 3, "plaster", doors=[("w", 8.5, 1.6), ("n", 5.0, 1.6)], windows="nw", stair_side="s")

    # --- B Apartments: a covered corridor (west lane, z 0..18) ----------
    m.box((-34, 3.5, 9), (8, 0.4, 18), "plaster", "ApartmentsCeiling")
    m.box((-34, 7.3, 9), (8, 7.2, 18), "plaster", "ApartmentsUpper")
    _facade(m, rng, -38, -30, 0, 18, 10.9, "", spacing=4)
    m.wall_with_gaps((-34, 3), (-34, 15), 3.3, 0.4, [(3.0, 2.2, 99.0), (8.0, 1.6, 2.4)], "plaster_warm", name="AptWall",
                     doors=True)
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
            ("CT Street", (0, 2, -35), (76, 6, 6)),
            ("A House", (24, 4, -3), (12, 8, 14)),
            ("B House", (-24, 4, -3), (12, 8, 12))):
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

    m.write("scenes/levels/oasis.tscn", sun_rot=(-52.0, 150.0), sky=(0.22, 0.47, 0.85), horizon=(0.62, 0.74, 0.88),
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


def _pallets(m, x, z, yaw=0.0, y=0.0):
    m.box((x, y + 0.08, z), (1.2, 0.16, 1.0), "wood", "Pallet", yaw=yaw)
    m.box((x, y + 0.61, z), (1.1, 0.9, 0.9), "sack", "Goods", yaw=yaw)


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


def _container(m, x, z, yaw=0.0, mat="blue", level=0, length=6.0, y=0.0):
    m.box((x, y + 1.3 + level * 2.6, z), (2.4, 2.6, length), mat, "Container", yaw=yaw)
    for dz in (-length / 2 + 0.05, length / 2 - 0.05):
        ox, oz = _off(yaw, 0, dz)
        m.box((x + ox, y + 1.3 + level * 2.6, z + oz), (2.44, 2.64, 0.08), "metal", "ContainerEnd", yaw=yaw,
              collide=False)


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


def _freight(m, x, z, kind="box", mat="rust", length=12.0, axis="z", y=0.0):
    """Freight car on a track along Z (or X): box car, tank car, open hopper
    or a locomotive ("loco")."""
    def B(dx, dy, dz, sx, sy, sz, mt, name, collide=True):
        if axis == "x":
            dx, dz, sx, sz = dz, dx, sz, sx
        m.box((x + dx, y + dy, z + dz), (sx, sy, sz), mt, name, collide=collide)
    B(0, 0.75, 0, 2.2, 0.7, length - 0.6, "floor_dark", "Underframe")
    for dz in (-length / 2 + 2.0, length / 2 - 2.0):
        B(0, 0.45, dz, 2.4, 0.6, 2.4, "floor_dark", "Bogie", collide=False)
    if kind == "tank":
        if axis == "x":
            m.cyl((x, y + 2.5, z), 1.45, length - 1.0, mat, "Tank", segments=14, roll=90)
        else:
            m.cyl((x, y + 2.5, z), 1.45, length - 1.0, mat, "Tank", segments=14, pitch=90)
        B(0, 1.3, 0, 2.6, 0.3, length - 0.4, mat, "TankDeck")
        m.cyl((x, y + 4.05, z), 0.35, 0.3, mat, "Dome", collide=False)
    elif kind == "hopper":
        B(0, 2.3, 0, 2.8, 2.4, length, mat, "Hopper")
        for dz in (-3.0, 0.0, 3.0):
            B(0, 1.2, dz, 2.2, 0.4, 1.8, mat, "Chute", collide=False)
    elif kind == "loco":
        B(0, 2.3, -1.2, 2.7, 2.4, length - 3.0, mat, "LocoHood")
        B(0, 2.9, length / 2 - 1.6, 3.0, 3.6, 3.0, mat, "LocoCab")
        B(0, 3.6, length / 2 - 0.08, 2.2, 1.0, 0.06, "glass", "LocoWindow", collide=False)
        B(0, 1.45, 0, 3.0, 0.1, length - 0.2, "hazard", "LocoStripe", collide=False)
        B(0, 3.7, -1.2, 0.5, 0.4, 1.2, "floor_dark", "Exhaust", collide=False)
    else:
        B(0, 2.7, 0, 2.8, 3.2, length, mat, "BoxCar")
        B(1.42, 2.5, 0, 0.06, 2.6, 2.6, "metal", "Door", collide=False)
        B(-1.42, 2.5, 0, 0.06, 2.6, 2.6, "metal", "Door", collide=False)
        B(0, 4.35, 0, 2.6, 0.1, length - 0.2, "metal", "Roof", collide=False)


def _rails_x(m, z, x0, x1, y=0.0, width=2.6):
    """Track along X: ballast, a sleeper every 1.2 m, two rails."""
    L = x1 - x0
    m.box(((x0 + x1) / 2, y + 0.02, z), (L, 0.04, width + 0.4), "gravel", "Ballast", collide=False)
    for k in range(int(L // 1.2)):
        m.box((x0 + 0.6 + k * 1.2, y + 0.06, z), (0.3, 0.08, width), "wood", "Sleeper", collide=False)
    for side in (-0.72, 0.72):
        m.box(((x0 + x1) / 2, y + 0.13, z + side), (L, 0.14, 0.08), "metal", "Rail", collide=False)


def _water_tower(m, x, z, h=14.0):
    """Tall water tower on four braced legs (legs collide) with a ladder."""
    for (dx, dz) in ((-2.2, -2.2), (2.2, -2.2), (-2.2, 2.2), (2.2, 2.2)):
        m.box((x + dx, h / 2, z + dz), (0.35, h, 0.35), "rust", "TowerLeg")
    for y in (h * 0.35, h * 0.7):
        for (a, b) in (((-2.2, -2.2), (2.2, -2.2)), ((-2.2, 2.2), (2.2, 2.2)), ((-2.2, -2.2), (-2.2, 2.2)),
                       ((2.2, -2.2), (2.2, 2.2))):
            m.beam((x + a[0], y, z + a[1]), (x + b[0], y, z + b[1]), 0.15, "rust", "TowerBrace")
    m.box((x, h + 0.2, z), (6.0, 0.4, 6.0), "metal", "TowerDeck", collide=False)
    m.cyl((x, h + 2.4, z), 3.0, 4.0, "rust", "WaterTank", segments=16, collide=False)
    m.cyl((x, h + 5.0, z), 3.1, 1.2, "rust", "TankRoof", top=0.4, segments=16, collide=False)
    m.box((x + 2.4, h * 0.5, z), (0.08, h, 0.5), "metal", "Ladder", collide=False)


def _pylon(m, x, z, h=18.0):
    """Electricity pylon in the background (visual)."""
    for (dx, dz) in ((-1.5, -1.5), (1.5, -1.5), (-1.5, 1.5), (1.5, 1.5)):
        m.beam((x + dx, 0.0, z + dz), (x + dx * 0.25, h, z + dz * 0.25), 0.18, "metal", "PylonLeg")
    for y in (h * 0.6, h * 0.85):
        m.box((x, y, z), (7.0 - y / h * 3, 0.2, 0.3), "metal", "PylonArm", collide=False)


# ----------------------------------------------------------------------
def _forklift(m, x, z, yaw=0.0, y=0.0):
    """Yellow forklift: body, cab frame, mast and forks."""
    m.box((x, y + 0.75, z), (1.2, 1.1, 2.0), "yellow", "Forklift", yaw=yaw)
    for (dx, dz) in ((-0.55, 0.3), (0.55, 0.3), (-0.55, 0.95), (0.55, 0.95)):
        ox, oz = _off(yaw, dx, dz)
        m.box((x + ox, y + 1.9, z + oz), (0.06, 1.3, 0.06), "cable", "ForkliftFrame", collide=False)
    ox, oz = _off(yaw, 0, 0.6)
    m.box((x + ox, y + 2.55, z + oz), (1.2, 0.06, 0.8), "cable", "ForkliftRoof", collide=False)
    ox, oz = _off(yaw, 0, -1.1)
    m.box((x + ox, y + 1.5, z + oz), (1.0, 2.6, 0.12), "cable", "ForkliftMast", collide=False)
    for dx in (-0.3, 0.3):
        ox, oz = _off(yaw, dx, -1.6)
        m.box((x + ox, y + 0.25, z + oz), (0.12, 0.06, 1.0), "metal", "Fork", collide=False)
    for (dx, dz) in ((-0.62, -0.6), (0.62, -0.6), (-0.62, 0.7), (0.62, 0.7)):
        ox, oz = _off(yaw, dx, dz)
        m.cyl((x + ox, y + 0.3, z + oz), 0.3, 0.2, "floor_dark", "ForkliftWheel", collide=False, yaw=yaw, roll=90)


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


# ----------------------------------------------------------------------
# Enterable buildings: real door and window openings, floors, stairs.

def _wall_openings(m, a, b, y0, h, t, openings, mat, name="HouseWall", fill=False):
    """Straight axis-aligned wall band from a=(x,z) to b=(x,z), height h
    starting at y0, with rectangular holes: openings = [(offset, width,
    bottom, top)] measured from a and from y0. fill=True puts a door in
    holes that reach the floor and a breakable glass pane in the others."""
    ax, az = a
    bx, bz = b
    along_x = abs(bx - ax) > abs(bz - az)
    total = abs(bx - ax) if along_x else abs(bz - az)
    sign = 1 if (bx - ax if along_x else bz - az) > 0 else -1

    def piece(s0, s1, h0, h1):
        if s1 - s0 < 0.01 or h1 - h0 < 0.01:
            return
        mid = (s0 + s1) / 2 * sign
        cy = y0 + (h0 + h1) / 2
        if along_x:
            m.box((ax + mid, cy, az), (s1 - s0, h1 - h0, t), mat, name)
        else:
            m.box((ax, cy, az + mid), (t, h1 - h0, s1 - s0), mat, name)

    pos = 0.0
    for off, w, bottom, top in sorted(openings):
        piece(pos, off, 0.0, h)
        piece(off, off + w, 0.0, bottom)
        piece(off, off + w, top, h)
        # Sill / lintel trim (visual).
        if bottom > 0.05:
            mid = (off + w / 2) * sign
            if along_x:
                m.box((ax + mid, y0 + bottom - 0.04, az), (w + 0.2, 0.08, t + 0.12), "sandstone", "Sill", collide=False)
            else:
                m.box((ax, y0 + bottom - 0.04, az + mid), (t + 0.12, 0.08, w + 0.2), "sandstone", "Sill", collide=False)
        if fill:
            mid = (off + w / 2) * sign
            yaw = 0.0 if along_x else 90.0
            at = (lambda y: (ax + mid, y, az) if along_x else (ax, y, az + mid))
            if bottom < 0.05:
                m.door(at(y0), yaw, w, top)
            else:
                m.pane(at(y0 + (bottom + top) / 2), yaw, w - 0.04, top - bottom - 0.04)
        pos = off + w
    piece(pos, total, 0.0, h)


def _rail(m, pos, size, mat="metal"):
    """Railing: invisible collider plus a top bar, a mid bar and posts."""
    m.blocker(pos, size)
    long_x = size[0] > size[2]
    length = size[0] if long_x else size[2]
    for dy in (0.5, 0.0):
        m.box((pos[0], pos[1] + dy - 0.03, pos[2]), (length if long_x else 0.05, 0.05, 0.05 if long_x else length), mat,
              "RailBar", collide=False)
    n = max(int(length // 1.2), 1)
    for k in range(n + 1):
        t = -length / 2 + k * length / n
        m.box((pos[0] + (t if long_x else 0), pos[1], pos[2] + (0 if long_x else t)), (0.05, 1.0, 0.05), mat,
              "RailPost", collide=False)


def _house(m, x0, x1, z0, z1, mat, floors=2, fh=4.0, doors=(), windows="nsew", stair_side="s",
           floor_mat="wood", light=(1.0, 0.85, 0.65), stair_angle=25.0, roof_access=False):
    """A building you can walk into: doors = [(face, offset, width[, floor])]
    (ground floor unless a floor index is given), windows on `windows` faces
    (every ~3 m, every floor), floors joined by a ramp stair along the
    `stair_side` wall ("n"/"s" run along X, "e"/"w" along Z), and a flat
    roof with a parapet — closed, or with a stair up to it (roof_access)."""
    t = 0.3
    faces = {"n": ((x0, z0), (x1, z0)), "s": ((x0, z1), (x1, z1)),
             "w": ((x0, z0), (x0, z1)), "e": ((x1, z0), (x1, z1))}
    for face, (a, b) in faces.items():
        length = abs(b[0] - a[0]) + abs(b[1] - a[1])
        for f in range(floors):
            ops = []
            ops += [(d[1], d[2], 0.0, 2.4) for d in doors if d[0] == face and (d[3] if len(d) > 3 else 0) == f]
            if face in windows:
                count = int(length // 3.0)
                for k in range(count):
                    off = (k + 0.5) * length / count - 0.6
                    if all(off + 1.2 < o[0] - 0.3 or off > o[0] + o[1] + 0.3 for o in ops):
                        ops.append((off, 1.2, 1.1, 2.3))
            _wall_openings(m, a, b, f * fh, fh, t, ops, mat, fill=True)
    # Stair: a ramp along one wall (about 25 degrees) up to each floor.
    run = fh / math.tan(math.radians(stair_angle))
    along_x = stair_side in "ns"
    inner = (z0 + t / 2 + 1.0) if stair_side == "n" else (z1 - t / 2 - 1.0) if stair_side == "s" \
        else (x0 + t / 2 + 1.0) if stair_side == "w" else (x1 - t / 2 - 1.0)
    start = (x0 + 0.8) if along_x else (z0 + 0.8)
    for f in range(1, floors + (1 if roof_access else 0)):
        y_lo, y_hi = (f - 1) * fh, f * fh
        if along_x:
            m.ramp((start, y_lo, inner), (start + run, y_hi, inner + 0.001), 1.8, floor_mat)
        else:
            m.ramp((inner, y_lo, start), (inner + 0.001, y_hi, start + run), 1.8, floor_mat)
        # Floor slab with a hole over the stair.
        y = y_hi - 0.12
        if along_x:
            hole0, hole1 = (inner - 1.0, inner + 1.0)
            zz0, zz1 = z0 + t / 2, z1 - t / 2
            if hole0 - zz0 > 0.05:
                m.box(((x0 + x1) / 2, y, (zz0 + hole0) / 2), (x1 - x0 - t, 0.24, hole0 - zz0), floor_mat, "Floor")
            if zz1 - hole1 > 0.05:
                m.box(((x0 + x1) / 2, y, (hole1 + zz1) / 2), (x1 - x0 - t, 0.24, zz1 - hole1), floor_mat, "Floor")
            rest = x1 - t / 2 - (start + run)
            if rest > 0.05:
                m.box(((start + run + x1 - t / 2) / 2, y, inner), (rest, 0.24, 2.0), floor_mat, "Floor")
            # Railing round the stair hole (upstairs).
            _rail(m, ((x0 + start + run) / 2, y + 0.62, hole0 if stair_side == "s" else hole1),
                  (start + run - x0 - 0.3, 1.0, 0.06))
        else:
            hole0, hole1 = (inner - 1.0, inner + 1.0)
            xx0, xx1 = x0 + t / 2, x1 - t / 2
            if hole0 - xx0 > 0.05:
                m.box(((xx0 + hole0) / 2, y, (z0 + z1) / 2), (hole0 - xx0, 0.24, z1 - z0 - t), floor_mat, "Floor")
            if xx1 - hole1 > 0.05:
                m.box(((hole1 + xx1) / 2, y, (z0 + z1) / 2), (xx1 - hole1, 0.24, z1 - z0 - t), floor_mat, "Floor")
            rest = z1 - t / 2 - (start + run)
            if rest > 0.05:
                m.box((inner, y, (start + run + z1 - t / 2) / 2), (2.0, 0.24, rest), floor_mat, "Floor")
            _rail(m, (hole0 if stair_side == "e" else hole1, y + 0.62, (z0 + start + run) / 2),
                  (0.06, 1.0, start + run - z0 - 0.3))
        _strip_light(m, (x0 + x1) / 2, y - 0.1, (z0 + z1) / 2, 1.6)
    top = floors * fh
    if not roof_access:
        m.box(((x0 + x1) / 2, top + 0.15, (z0 + z1) / 2), (x1 - x0, 0.3, z1 - z0), mat, "HouseRoof")
    for (pos, size) in ((((x0 + x1) / 2, top + 0.6, z0 + 0.15), (x1 - x0, 0.6, 0.3)),
                        (((x0 + x1) / 2, top + 0.6, z1 - 0.15), (x1 - x0, 0.6, 0.3)),
                        ((x0 + 0.15, top + 0.6, (z0 + z1) / 2), (0.3, 0.6, z1 - z0)),
                        ((x1 - 0.15, top + 0.6, (z0 + z1) / 2), (0.3, 0.6, z1 - z0))):
        m.box(pos, size, mat, "Parapet", collide=False)
    _strip_light(m, (x0 + x1) / 2, fh - 0.25, (z0 + z1) / 2 + 1.5, 1.6)
    m.omni(((x0 + x1) / 2, fh - 0.6, (z0 + z1) / 2), 0.8, 8.0, light)
    m.reverb(((x0 + x1) / 2, top / 2, (z0 + z1) / 2), (x1 - x0, top, z1 - z0), "room", 0.35, priority=1)



# ----------------------------------------------------------------------
# Indoor levels from rooms on a 1 m grid (Bunker, Train Yard's warehouse).

def _rooms(m, rooms, base=-4.0, t=0.4, lintel=True, trim=None, windows=False):
    """Builds floors, walls and ceilings for a set of rooms on a 1 m grid.
    rooms = [dict(x0, x1, z0, z1, y=floor, top=ceiling or None, floor="mat",
    wall="mat", ceil="mat", name="Room")] with integer bounds. Later rooms
    win where they overlap. Walls go wherever a room cell meets a non-room
    cell (so a 1 m gap between two rooms is a wall; bridge it with a small
    "door" room); where neighbouring cells have different ceilings a lintel
    fills the step. Floors are solid from `base` up to y (a raised room is a
    solid platform, a lower room a pit); ramps are added separately.
    open="s" (any of "nsew") leaves out the outer wall on those sides (a quay
    edge over water, for example).
    trim = (band_mat, stripe_mat): a dark lower band + stripe and pipes on
    the walls. windows: rows of windows high up on tall open-air walls
    (they read as the buildings round a yard)."""
    cell = {}
    for r in rooms:
        for x in range(int(r["x0"]), int(r["x1"])):
            for z in range(int(r["z0"]), int(r["z1"])):
                cell[(x, z)] = r
    for r in rooms:
        y = r.get("y", 0.0)
        m.box(((r["x0"] + r["x1"]) / 2, (base + y) / 2, (r["z0"] + r["z1"]) / 2),
              (r["x1"] - r["x0"], y - base, r["z1"] - r["z0"]), r.get("floor", "concrete"), "Floor")
        if r.get("top") is not None:
            m.box(((r["x0"] + r["x1"]) / 2, r["top"] + 0.2, (r["z0"] + r["z1"]) / 2),
                  (r["x1"] - r["x0"], 0.4, r["z1"] - r["z0"]), r.get("ceil", "ceiling"), "Ceiling")
    # Wall segments per grid edge, merged along runs: key = (axis, line, lo, hi, mat) -> [cells].
    runs = {}
    for (x, z), r in cell.items():
        for (dx, dz) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            other = cell.get((x + dx, z + dz))
            y0 = r.get("y", 0.0)
            top = r.get("top")
            if other is None:
                if {(1, 0): "e", (-1, 0): "w", (0, 1): "s", (0, -1): "n"}[(dx, dz)] in r.get("open", ""):
                    continue
                lo, hi = y0 - 0.05, (top if top is not None else y0 + r.get("wall_h", 4.0))
            elif lintel and top is not None and other.get("top") is not None and other["top"] > top + 0.01:
                lo, hi = top, other["top"]
            else:
                continue
            if dx != 0:
                key = ("x", x + (1 if dx > 0 else 0), dx, round(lo, 2), round(hi, 2), r.get("wall", "wall"))
                runs.setdefault(key, []).append(z)
            else:
                key = ("z", z + (1 if dz > 0 else 0), dz, round(lo, 2), round(hi, 2), r.get("wall", "wall"))
                runs.setdefault(key, []).append(x)
    for (axis, line, side, lo, hi, mat), cells in runs.items():
        cells.sort()
        start = prev = cells[0]
        for c in cells[1:] + [None]:
            if c is not None and c == prev + 1:
                prev = c
                continue
            a, b = start, prev + 1
            off = side * t / 2  # the wall sits outside the room
            if axis == "x":
                m.box((line + off, (lo + hi) / 2, (a + b) / 2), (t, hi - lo, b - a), mat, "RoomWall")
            else:
                m.box(((a + b) / 2, (lo + hi) / 2, line + off), (b - a, hi - lo, t), mat, "RoomWall")
            if windows and hi - lo >= 6.5 and b - a >= 4:
                inner = line - side * 0.03
                n = int((b - a) // 4.5)
                for k in range(n):
                    c0 = a + (b - a) * (k + 0.5) / n
                    for wy in ((lo + 4.6, lo + 7.4) if hi - lo >= 9.0 else (lo + 4.6,)):
                        if axis == "x":
                            m.box((inner, wy, c0), (0.06, 1.3, 2.2), "glass", "Window", collide=False)
                            m.box((inner - side * 0.02, wy - 0.72, c0), (0.12, 0.1, 2.4), "concrete", "Sill", collide=False)
                        else:
                            m.box((c0, wy, inner), (2.2, 1.3, 0.06), "glass", "Window", collide=False)
                            m.box((c0, wy - 0.72, inner - side * 0.02), (2.4, 0.1, 0.12), "concrete", "Sill", collide=False)
            # Dressing on full walls (not lintels): a dark lower band with a
            # hazard stripe, and a pipe near the top on long runs.
            if trim and hi - lo > 2.0:
                inner = line - side * 0.02
                band, stripe = trim
                for (y0, y1, mt) in ((lo + 0.05, lo + 1.25, band), (lo + 1.25, lo + 1.37, stripe)):
                    if axis == "x":
                        m.box((inner, (y0 + y1) / 2, (a + b) / 2), (0.04, y1 - y0, b - a), mt, "WallBand", collide=False)
                    else:
                        m.box(((a + b) / 2, (y0 + y1) / 2, inner), (b - a, y1 - y0, 0.04), mt, "WallBand", collide=False)
                if b - a >= 5 and hi - lo > 3.5 and not windows:
                    pipe_in = line - side * 0.25
                    if axis == "x":
                        m.box((pipe_in, hi - 0.45, (a + b) / 2), (0.22, 0.22, b - a), "steel_blue", "WallPipe", collide=False)
                    else:
                        m.box(((a + b) / 2, hi - 0.45, pipe_in), (b - a, 0.22, 0.22), "steel_blue", "WallPipe", collide=False)
            if c is not None:
                start = prev = c


def _press(m, x, z, yaw=0.0):
    """Hydraulic stamping press (solid cover, too tall to climb): a base,
    two columns, the crown on top, the ram and a yellow guard rail."""
    m.box((x, 0.6, z), (4.0, 1.2, 3.0), "steel_blue", "PressBase", yaw=yaw)
    for dx in (-1.6, 1.6):
        ox, oz = _off(yaw, dx, 0)
        m.box((x + ox, 3.0, z + oz), (0.7, 6.0, 2.2), "steel_blue", "PressColumn", yaw=yaw)
    m.box((x, 6.4, z), (4.4, 1.6, 3.0), "steel_blue", "PressCrown", yaw=yaw, collide=False)
    m.box((x, 3.6, z), (2.4, 1.4, 1.8), "metal", "PressRam", yaw=yaw, collide=False)
    m.box((x, 1.3, z), (2.6, 0.2, 2.0), "rust", "PressDie", yaw=yaw, collide=False)
    for dz in (-1.9, 1.9):
        ox, oz = _off(yaw, 0, dz)
        m.box((x + ox, 0.55, z + oz), (4.6, 0.08, 0.08), "yellow", "PressGuard", yaw=yaw, collide=False)
    ox, oz = _off(yaw, 0, -1.55)
    m.box((x + ox, 1.9, z + oz), (0.8, 0.6, 0.12), "hazard", "PressPanel", yaw=yaw, collide=False)


def _conveyor(m, x0, x1, z, y=0.0):
    """Conveyor line along X (waist-high cover you can jump onto): the belt
    bed on legs, rollers and side rails."""
    m.box(((x0 + x1) / 2, y + 0.5, z), (x1 - x0, 1.0, 1.4), "metal", "LedgeConveyor")
    m.box(((x0 + x1) / 2, y + 1.02, z), (x1 - x0, 0.04, 1.1), "floor_dark", "Belt", collide=False)
    for side in (-0.68, 0.68):
        m.box(((x0 + x1) / 2, y + 1.1, z + side), (x1 - x0, 0.12, 0.06), "yellow", "BeltRail", collide=False)
    x = x0 + 1.0
    while x < x1:
        m.box((x, y + 0.45, z), (0.12, 0.9, 1.5), "floor_dark", "BeltLeg", collide=False)
        x += 3.0


def _pipe_rack(m, x0, x1, z, y=6.0, mat="rust"):
    """Overhead pipe rack along X (visual)."""
    for (dz, r, mt) in ((-0.5, 0.25, mat), (0.0, 0.18, "steel_blue"), (0.5, 0.3, mat)):
        m.cyl(((x0 + x1) / 2, y + 0.3, z + dz), r, x1 - x0, mt, "RackPipe", segments=8, collide=False, roll=90)
    m.box(((x0 + x1) / 2, y, z), (x1 - x0, 0.15, 1.6), "metal", "RackBeam", collide=False)


def _pipe_rack_z(m, x, z0, z1, y=6.0, mat="rust"):
    """Overhead pipe rack along Z (visual)."""
    for (dx, r, mt) in ((-0.5, 0.25, mat), (0.0, 0.18, "steel_blue"), (0.5, 0.3, mat)):
        m.cyl((x + dx, y + 0.3, (z0 + z1) / 2), r, z1 - z0, mt, "RackPipe", segments=8, collide=False, pitch=90)
    m.box((x, y, (z0 + z1) / 2), (1.6, 0.15, z1 - z0), "metal", "RackBeam", collide=False)


def _shutter_door(m, x, y, z, face, w=4.0, h=4.2):
    """Closed roller shutter on a wall face (visual): slats, posts, a box on top."""
    n = {"s": (0, 1), "n": (0, -1), "e": (1, 0), "w": (-1, 0)}[face]
    along_x = face in "ns"
    ox, oz = n[0] * 0.06, n[1] * 0.06
    size = (w, h, 0.06) if along_x else (0.06, h, w)
    m.box((x + ox, y + h / 2, z + oz), size, "shutter", "Shutter", collide=False)
    box = (w + 0.4, 0.5, 0.4) if along_x else (0.4, 0.5, w + 0.4)
    m.box((x + n[0] * 0.2, y + h + 0.25, z + n[1] * 0.2), box, "metal", "ShutterBox", collide=False)
    for s in (-1, 1):
        px = x + (s * (w / 2 + 0.1) if along_x else 0) + ox
        pz = z + (0 if along_x else s * (w / 2 + 0.1)) + oz
        m.box((px, y + h / 2, pz), (0.2, h, 0.2), "yellow", "ShutterPost", collide=False)


def _delivery_truck(m, x, z, yaw=0.0, mat="steel_blue"):
    """Box delivery truck (one solid body, too tall to jump on), its front
    towards local -Z. The art puts a real truck model over it."""
    m.box((x, 1.4, z), (2.4, 2.8, 6.5), mat, "Truck", yaw=yaw)


def _palm_tree(m, x, z, h=8.0):
    """Coconut palm: the trunk collides; the art puts a real palm over it."""
    m.cyl((x, h / 2, z), 0.22, h, "wood", "PalmTrunk", segments=8)


def _aircon(m, x, z, yaw=0.0):
    """Outdoor air-conditioning unit against a wall (low cover)."""
    m.box((x, 0.465, z), (0.8, 0.93, 0.37), "metal", "AirCon", yaw=yaw)


def _facade_block(m, x, y0, y1, z, face, w, mat, name="Facade"):
    """Wall panel above a covered doorway (from y0 to y1), on the boundary
    at x or z, `w` wide along the wall."""
    if face in "ns":
        m.box((x, (y0 + y1) / 2, z), (w, y1 - y0, 0.4), mat, name)
    else:
        m.box((x, (y0 + y1) / 2, z), (0.4, y1 - y0, w), mat, name)


def factory():
    """Factory - the Lanka Steel works (bomb map, CS-style, 3 lanes). T spawn
    in the truck yard in the south, CT spawn behind the gate in the north.
    Mid is the long central yard, closed towards CT by the half-open Mid
    Doors. A (west) is the open silo yard under a gantry crane, with a
    loading dock: T reach it along A Long and through the Long Doors, or by
    Short through the Lanka Steel hall. B (east) is indoors in the Press
    Hall, among the presses and a conveyor line, overlooked by a mezzanine:
    T reach it through the Tunnel or from Mid through the Workshop. CT get
    to A by CT A, to B by B Back, and hold Mid from the doors."""
    m = Map("Factory")

    def area(name, x0, x1, z0, z1, y=0.0, wall="concrete", floor="concrete", h=8.0, top=None, ceil="corrugated"):
        return dict(name=name, x0=x0, x1=x1, z0=z0, z1=z1, y=y, wall=wall, floor=floor, wall_h=h, top=top, ceil=ceil)

    rooms = [
        # Spawns and Mid (one line north - south).
        area("TSpawn", -14, 14, 32, 46, wall="brick", h=9.0),
        area("TMid", -4, 4, 22, 32, wall="brick"),
        area("Mid", -10, 10, -18, 22, wall="corrugated", h=9.0),
        area("MidDoors", -3, 3, -22, -18, top=5.0, wall="concrete"),
        area("CTMid", -6, 6, -36, -22, wall="concrete"),
        area("CTSpawn", -12, 12, -48, -36, wall="concrete", floor="paving", h=9.0),
        # A: A Long (west), the Long Doors, Short through Lanka Steel, CT A.
        area("TWest", -34, -14, 36, 44, wall="brick"),
        area("ALong", -44, -34, -6, 44, wall="corrugated", h=9.0),
        area("LongDoors", -42, -38, -10, -6, top=4.5, wall="corrugated"),
        area("AYard", -50, -20, -40, -10, wall="brick", h=10.0),
        area("AShort", -22, -10, -4, 2, wall="plaster", h=7.0),
        area("Lanka", -30, -22, -10, 2, top=4.5, wall="steel_blue", floor="floor_dark", ceil="metal"),
        area("CTA", -20, -12, -46, -34, wall="concrete"),
        # B: the Tunnel, the Workshop, the Press Hall, B Back.
        area("TEast", 14, 28, 36, 44, wall="brick"),
        area("Tunnel", 22, 28, 4, 36, top=3.6, wall="concrete", floor="floor_dark", ceil="concrete"),
        area("BHall", 18, 50, -34, 4, top=10.0, wall="corrugated", floor="concrete", ceil="corrugated"),
        area("Workshop", 10, 18, -10, -4, top=3.8, wall="brick", floor="floor_dark", ceil="concrete"),
        area("CTB", 12, 24, -46, -38, wall="concrete"),
        area("BBack", 24, 34, -46, -34, wall="concrete"),
    ]
    _rooms(m, rooms, windows=True)
    # Ground under everything (the gaps between areas, seen from above).
    m.box((0, -0.3, 0), (130, 0.5, 130), "concrete", "Ground", collide=False)

    # Wall panels over covered doorways that open onto open-air areas.
    _facade_block(m, -22.0, 4.5, 7.0, -1.0, "e", 6.0, "steel_blue")        # Lanka Steel from Short
    _facade_block(m, -26.0, 4.5, 10.0, -10.0, "n", 8.0, "steel_blue")      # Lanka Steel from A
    _facade_block(m, -40.0, 4.5, 9.0, -6.0, "n", 4.0, "corrugated")        # Long Doors, A Long side
    _facade_block(m, -40.0, 4.5, 10.0, -10.0, "n", 4.0, "corrugated")      # Long Doors, A side
    _facade_block(m, 0.0, 5.0, 9.0, -18.0, "n", 6.0, "concrete")           # Mid Doors, Mid side
    _facade_block(m, 0.0, 5.0, 8.0, -22.0, "n", 6.0, "concrete")           # Mid Doors, CT side
    _facade_block(m, 10.0, 3.8, 9.0, -7.0, "e", 6.0, "brick")              # Workshop from Mid
    _facade_block(m, 25.0, 3.6, 8.0, 36.0, "s", 6.0, "concrete")           # Tunnel mouth (T)
    # Inside the Press Hall, over its three ways in (hall-coloured walls).
    _facade_block(m, 25.0, 3.6, 10.0, 3.75, "s", 6.0, "corrugated")        # the Tunnel
    _facade_block(m, 18.25, 3.8, 10.0, -7.0, "e", 6.0, "corrugated")       # the Workshop
    _facade_block(m, 29.0, 4.5, 10.0, -33.8, "n", 10.0, "corrugated")      # B Back
    m.sign((25.0, 5.4, 36.22), "s", "TUNNEL", color=(0.9, 0.86, 0.7), pixel=0.003)
    m.sign((10.22, 5.2, -7.0), "e", "WORKSHOP", color=(0.9, 0.86, 0.7), pixel=0.003)

    # --- T spawn: the truck yard ------------------------------------------------------
    _delivery_truck(m, -8.5, 42.6, 90)
    _delivery_truck(m, 9.5, 42.4, -90)
    _container(m, -1, 44.5, 90, "green")
    _crates(m, 4, 34.5, 2)
    _pallets(m, -6, 34)
    for x in (-10.5, 10.5):
        _shutter_door(m, x, 0.0, 45.98, "n", 5.0, 5.0)
    m.box((0, 0.01, 39), (0.25, 0.02, 12), "yellow", "RoadLine", collide=False)
    _flood_light(m, -13, 33)
    _flood_light(m, 13, 45)
    m.sign((0.0, 4.2, 45.98), "n", "T", color=(0.85, 0.6, 0.1), pixel=0.014)
    # Outside Long / Outside Tunnel: lanes off the yard.
    _pallets(m, -24, 37.2)
    _drum(m, -30, 42.6, "blue")
    m.barrel((-29.2, 0.0, 43.1))
    _crates(m, -18, 42.8, 1)
    _crates(m, 19, 37.3, 1)
    m.barrel((16, 0.0, 42.8))
    _aircon(m, 5.0, 45.6)

    # --- A Long and the Long Doors ----------------------------------------------------
    _pipe_rack_z(m, -35.6, -4, 42, 6.5)
    _delivery_truck(m, -41.6, 30, 0)
    _container(m, -36.6, 14, 0, "rust")
    _crates(m, -42.5, 3, 2)
    _crates(m, -36, -3.5, 1)
    _drum(m, -43, 20, "blue")
    _drum(m, -42.3, 20.7, "teal")
    _flood_light(m, -43.3, 38)
    _flood_light(m, -34.7, 6)
    # The two door leaves, swung open against the walls.
    for x in (-41.85, -38.15):
        m.box((x, 1.9, -7.4), (0.12, 3.8, 1.9), "steel_blue", "LongDoorLeaf", collide=False)
    m.omni((-40, 3.6, -8), 0.6, 6.0, (1.0, 0.88, 0.7))

    # --- A: the silo yard -------------------------------------------------------------
    _silo(m, -45.5, -35.5, 3.6, 15.0)
    _silo(m, -37.5, -36.2, 3.0, 13.0)
    m.beam((-45.5, 13.5, -35.5), (-37.5, 12.0, -36.2), 0.35, "rust", "SiloPipe")
    m.beam((-37.5, 11.0, -36.2), (-24, 8.0, -39.6), 0.35, "rust", "SiloPipe")
    _gantry(m, -48.5, -22.5, -23.0, 10.0)
    # Loading dock along the west wall (jump or walk the ramp onto it).
    DOCK = 1.2
    m.box((-47.5, DOCK / 2, -21.0), (5.0, DOCK, 14.0), "concrete", "LedgeDock")
    m.box((-44.97, DOCK - 0.05, -21.0), (0.06, 0.1, 14.0), "hazard", "DockEdge", collide=False)
    m.ramp((-47.5, 0.0, -10.2), (-47.501, DOCK, -14.0), 5.0, "concrete")
    for z in (-26, -17):
        _shutter_door(m, -49.98, DOCK, z, "e", 3.6, 4.0)
    _pallets(m, -48, -25, y=DOCK)
    m.box((-48.3, DOCK + 0.6, -18.5), (1.2, 1.2, 1.2), "wood", "Crate")
    # Cover round the site.
    _container(m, -29, -31, 0, "blue")
    _container(m, -29, -31, 0, "red", 1)
    _container(m, -38, -15.5, 90, "green")
    for (x, z, n) in ((-38.5, -26.5, 2), (-33, -22, 1), (-25.5, -21.5, 1), (-41, -30.5, 1)):
        _crates(m, x, z, n)
    _forklift(m, -24.5, -28, 15)
    for (x, z) in ((-31.5, -38.8), (-30.3, -38.9)):
        _drum(m, x, z, "blue")
    m.barrel((-31.6, 0.0, -22.4))
    m.barrel((-44.2, 0.0, -29.0))
    m.site("A", (-35.0, 0.0, -25.0))
    _pipe_rack(m, -49, -21, -39.2, 7.0)
    _flood_light(m, -21, -11)
    _flood_light(m, -49, -39)
    m.omni((-35, 7.0, -25), 1.2, 18.0, (1.0, 0.9, 0.75))

    # --- Short: the alley and the Lanka Steel hall ---------------------------------------
    _crates(m, -15, 1.2, 1)
    m.barrel((-19.5, 0.0, -3.2))
    _aircon(m, -13.0, -3.6)
    # Lanka Steel: a workbench, a lathe and shelves (a clear path down the middle).
    m.box((-28.4, 0.5, -4), (1.2, 1.0, 6.0), "steel_blue", "LedgeBench")
    m.box((-23.6, 0.6, -6.5), (1.0, 1.2, 2.5), "metal", "Lathe")
    m.box((-23.4, 1.6, 0.5), (0.6, 3.2, 2.0), "steel_blue", "Shelving")
    for z in (-7, -2):
        _strip_light(m, -26, 4.25, z, 2.4, 90)
    m.omni((-26, 3.6, -4), 0.8, 9.0, (0.95, 0.97, 1.0))
    m.reverb((-26, 2.2, -4), (8, 4.5, 12), "room", 0.4, priority=1)

    # --- Mid ------------------------------------------------------------------------------
    _container(m, 0, 14.0, 90, "rust")                    # blocks the long view from T Mid
    _container(m, -6.5, 3, 0, "blue")
    _container(m, 6.5, -6, 0, "steel_blue")
    _container(m, 6.5, -6, 0, "green", 1)
    _crates(m, 2.5, -12.5, 2)
    _crates(m, -7.8, -12, 1)
    m.barrel((-6.4, 0.0, -13.3))
    _forklift(m, 3.5, 6, -30)
    _pallets(m, -8, 18.5)
    _pipe_rack(m, -10, 10, -2.0, 6.8)
    for x in (-9.6, 9.6):
        m.box((x, 3.4, -2.0), (0.3, 6.8, 0.3), "metal", "RackPost")
    # Mid Doors: two sliding gate leaves, one half shut.
    m.box((-1.9, 2.2, -20.3), (2.2, 4.4, 0.12), "rust", "MidGate")
    m.box((2.6, 2.2, -20.5), (0.8, 4.4, 0.12), "rust", "MidGateOpen", collide=False)
    m.box((0, 4.65, -20.4), (6.0, 0.2, 0.3), "metal", "GateRail", collide=False)
    _flood_light(m, 9, 21)
    _flood_light(m, -9, -17)

    # --- CT Mid / CT spawn -------------------------------------------------------------------
    _crates(m, 3.5, -30, 1)
    _drum(m, -4.5, -25, "blue")
    _house(m, -11.5, -5.5, -47.5, -42.5, "plaster", floors=1, fh=3.4, doors=[("e", 1.5, 1.4)], windows="es")
    _delivery_truck(m, 7.5, -44.2, 90)
    m.box((0, 0.5, -37.5), (4.0, 1.0, 0.6), "hazard", "LowWall")
    m.sign((0.0, 4.2, -47.98), "s", "CT", color=(0.25, 0.45, 0.85), pixel=0.014)
    _flood_light(m, 11, -37)
    _crates(m, -15, -43.8, 1)
    _container(m, 18, -44.6, 90, "rust")
    _crates(m, 31.5, -37.5, 1)
    _aircon(m, 33.6, -42.0, 90)
    _aircon(m, 13.0, -45.6)

    # --- The Tunnel and the Workshop -----------------------------------------------------------
    for (z, side) in ((30, 1), (21, -1), (12, 1)):
        _crates(m, 25 + side * 1.9, z, 1)
    for z in (32, 24, 16, 8):
        _strip_light(m, 25, 3.55, z, 2.0, 90)
    m.omni((25, 3.0, 26), 0.8, 9.0, (1.0, 0.85, 0.6))
    m.omni((25, 3.0, 12), 0.8, 9.0, (1.0, 0.85, 0.6))
    m.box((25.5, 0.005, 18), (1.4, 0.01, 2.2), "water", "Puddle", collide=False)
    m.reverb((25, 1.8, 20), (6, 3.6, 32), "room", 0.5, priority=1)
    m.box((16.6, 0.5, -9.2), (2.4, 1.0, 1.2), "steel_blue", "LedgeWorkbench")
    m.box((11.2, 1.0, -4.6), (1.6, 2.0, 0.8), "metal", "Cabinet")
    _strip_light(m, 14, 3.75, -7, 2.0)
    m.omni((14, 3.2, -7), 0.7, 7.0, (1.0, 0.9, 0.75))
    m.reverb((14, 1.9, -7), (8, 3.8, 6), "room", 0.4, priority=1)

    # --- B: the Press Hall --------------------------------------------------------------------
    _press(m, 27, -20, 0)
    _press(m, 43, -6.5, 90)
    _conveyor(m, 21, 38, -2.5)
    _crates(m, 38.5, -21, 2)
    _crates(m, 32, -10.5, 1)
    _pallets(m, 22, -29)
    _forklift(m, 31, -28.5, 90)
    for x in (21, 26):
        m.box((x, 2.0, -33.2), (4.0, 4.0, 1.2), "steel_blue", "Shelving")
    # Mezzanine along the east wall, a stair up from the south end.
    MZ = 4.0
    m.box((47, MZ - 0.12, -24), (6.0, 0.24, 20.0), "metal", "Mezzanine")
    m.ramp((47, 0.0, -1.0), (47.001, MZ, -14.0), 2.2, "metal")
    _rail(m, (44.05, MZ + 0.5, -24), (0.06, 1.0, 20.0), "yellow")
    _rail(m, (47, MZ + 0.5, -33.9), (6.0, 1.0, 0.06), "yellow")
    _rail(m, (45.85, MZ / 2 + 0.6, -7.5), (0.06, 1.0, 13.0), "yellow")
    for z in (-32, -24, -16):
        m.box((44.3, (MZ - 0.24) / 2, z), (0.3, MZ - 0.24, 0.3), "metal", "MezzPost")
    m.box((48.5, MZ + 1.0, -30), (1.6, 2.0, 2.4), "metal", "Cabinet", collide=False)
    # Overhead crane rails, skylights, lights.
    for x in (19.5, 48.5):
        m.box((x, 8.2, -15), (0.5, 0.6, 38), "yellow", "CraneRail", collide=False)
    m.box((34, 8.6, -12), (29.0, 0.9, 1.4), "yellow", "HallCrane", collide=False)
    m.box((30, 7.8, -12), (1.6, 0.8, 1.8), "metal", "Trolley", collide=False)
    for z in (-28, -18, -8, 2):
        m.box((34, 10.0, z), (26, 0.06, 2.0), "glass", "Skylight", collide=False)
        m.box((34, 9.6, z + 2.6), (31.0, 0.4, 0.3), "metal", "Truss", collide=False)
    for (x, z) in ((26, -26), (40, -26), (26, -8), (40, -8)):
        _strip_light(m, x, 9.5, z, 3.0)
        m.omni((x, 7.5, z), 1.0, 14.0, (1.0, 0.94, 0.85))
    m.reverb((34, 5, -15), (32, 10, 38), "hall", 0.45)
    m.barrel((33.4, 0.0, -10.0))
    m.barrel((22.5, 0.0, -21.0))
    m.site("B", (35.0, 0.0, -14.0))
    m.sign((34.0, 6.5, 3.98), "n", "PRESS HALL", color=(0.92, 0.94, 0.96), pixel=0.004)

    # --- Background: chimneys, water tower, pylons -------------------------------------------
    _chimney(m, -56, -54, 0.0, 26.0, 1.2)
    _chimney(m, 58, -50, 0.0, 22.0, 1.0)
    _chimney(m, 54, 50, 0.0, 20.0, 0.9)
    _water_tower(m, -58, 20, 16.0)
    for (x, z) in ((-62, -10), (62, 0), (0, 62)):
        _pylon(m, x, z)
    for (x, z) in ((11.0, 35.0), (8.5, -38.6), (-24.5, 38.8)):
        _palm_tree(m, x, z)

    # --- Spawns, callouts -----------------------------------------------------------------------
    for (x, z) in ((-6, 38), (-2, 36.5), (2, 38), (6, 36.5), (0, 40.5)):
        m.spawn("red", (x, 0.1, z), 0)
    for (x, z) in ((-6, -40), (-2, -41.5), (2, -40), (6, -41.5), (0, -44)):
        m.spawn("blue", (x, 0.1, z), 180)
    for (x, y, z, yaw) in ((0, 0.1, 8, 0), (-39, 0.1, 20, 0), (-35, 0.1, -18, 0), (-26, 0.1, -2, 0),
                           (25, 0.1, 20, 0), (30, 0.1, -12, 90), (47, MZ + 0.1, -26, 90), (0, 0.1, -28, 180),
                           (-16, 0.1, -40, 90), (28, 0.1, -40, 180), (-24, 0.1, 40, 90), (20, 0.1, 40, -90)):
        m.spawn("ffa", (x, y, z), yaw)
    for (label, pos, size) in (
            ("T Spawn", (0, 3, 39), (28, 6, 14)),
            ("CT Spawn", (0, 3, -42), (24, 6, 12)),
            ("T Mid", (0, 3, 27), (8, 6, 10)),
            ("Mid", (0, 3, 2), (20, 8, 40)),
            ("Mid Doors", (0, 2.5, -20), (6, 5, 4)),
            ("CT Mid", (0, 3, -29), (12, 6, 14)),
            ("Outside Long", (-24, 3, 40), (20, 6, 8)),
            ("A Long", (-39, 3, 19), (10, 8, 50)),
            ("Long Doors", (-40, 2.2, -8), (4, 4.5, 4)),
            ("Bombsite A", (-35, 4, -25), (30, 10, 30)),
            ("Short", (-16, 3, -1), (12, 6, 6)),
            ("Lanka Steel", (-26, 2.2, -4), (8, 4.5, 12)),
            ("CT A", (-16, 3, -40), (8, 6, 12)),
            ("Outside Tunnel", (21, 3, 40), (14, 6, 8)),
            ("Tunnel", (25, 1.8, 20), (6, 3.6, 32)),
            ("Workshop", (14, 1.9, -7), (8, 3.8, 6)),
            ("Bombsite B", (34, 5, -15), (32, 10, 38)),
            ("B Mezzanine", (47, 5.5, -24), (6, 3, 20)),
            ("CT B", (18, 3, -42), (12, 6, 8)),
            ("B Back", (29, 3, -40), (10, 6, 12))):
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
    m.wall_with_gaps((W1, Z0), (W1, Z1), HT, 0.4, [(10.0, 2.0, 2.4), (36.0, 2.0, 2.4)], "concrete", name="Facade",
                     doors=True)
    m.wall_with_gaps((W0, Z0), (W0, Z1), HT, 0.4, [(10.0, 2.0, 2.4), (36.0, 2.0, 2.4)], "concrete", name="Facade",
                     doors=True)
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
                     "glass", y0=F, name="GlassWall", doors=True)
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
    m.wall_with_gaps((-10, -12), (-10, 30), 3.2, 0.2, [(6.0, 3.0, 99.0), (30.0, 2.0, 2.4)], "office_wall", name="WestWall", doors=True)
    m.wall_with_gaps((-24, 14), (-10, 14), 3.2, 0.2, [(9.0, 1.8, 2.4)], "glass", name="ConfWall", doors=True)
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
    m.wall_with_gaps((-24, -12), (-10, -12), 3.2, 0.2, [(9.0, 1.8, 2.4)], "office_wall", name="BreakWall", doors=True)
    m.wall_with_gaps((10, -12), (24, -12), 3.2, 0.2, [(3.0, 1.8, 2.4)], "office_wall", name="StoreWall", doors=True)
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


def _metro_car(m, x0, x1, zc, pit, stripe="red", w=3.4, doors_open=True):
    """Metro car along X at track centre zc: floor level with the platforms
    (y 0), sliding-door gaps on both sides (walk through it from one
    platform to the other), windows, seats, a gangway door at each end."""
    L = x1 - x0
    xc = (x0 + x1) / 2
    m.box((xc, (pit + 0.0 - 0.2) / 2, zc), (L - 0.6, -0.2 - pit, w - 0.8), "floor_dark", "Underframe")
    m.box((xc, -0.1, zc), (L, 0.2, w), "floor_dark", "CarFloor")
    doors = [(off, 1.4, 2.1) for off in (L * 0.18, L * 0.5 - 0.7, L * 0.82 - 1.4)] if doors_open else []
    for side in (-1, 1):
        zw = zc + side * (w / 2 - 0.05)
        m.wall_with_gaps((x0, zw), (x1, zw), 2.4, 0.1, doors, "silver", y0=0.0, name="CarWall")
        m.box((xc, 0.75, zw + side * 0.06), (L, 0.22, 0.02), stripe, "Stripe", collide=False)
        m.box((xc, 2.25, zw + side * 0.06), (L, 0.08, 0.02), "tile_band", "Stripe", collide=False)
        # Windows between the doors, seats under them.
        cuts = [0.0] + [c for (off, dw, _) in doors for c in (off, off + dw)] + [L]
        for k in range(0, len(cuts), 2):
            a, b = cuts[k] + 0.4, cuts[k + 1] - 0.4
            if b - a > 0.8:
                m.box((x0 + (a + b) / 2, 1.5, zw + side * 0.06), (b - a, 0.75, 0.02), "glass", "CarWindow",
                      collide=False)
                m.box((x0 + (a + b) / 2, 0.25, zc + side * (w / 2 - 0.4)), (b - a, 0.5, 0.5), "tile_band", "Seats")
    for (xx, face) in ((x0, -1), (x1, 1)):
        m.wall_with_gaps((xx, zc - w / 2), (xx, zc + w / 2), 2.4, 0.1, [(w / 2 - 0.5, 1.0, 2.1)], "silver",
                         y0=0.0, name="CarEnd")
        for dz in (-1.1, 1.1):
            m.box((xx + face * 0.07, 0.55, zc + dz), (0.03, 0.18, 0.25), "lamp_red", "TailLight", collide=False)
    m.box((xc, 2.5, zc), (L + 0.05, 0.2, w + 0.1), "silver", "CarRoof")
    m.box((xc, 2.7, zc), (L - 1.0, 0.2, w - 1.0), "metal", "RoofUnit", collide=False)
    _strip_light(m, xc, 2.35, zc, L - 2.0, yaw=90)


def _tunnel_mouth(m, x, zc, face, pit, top=4.2, w=4.0):
    """Tunnel mouth on the end wall at x (face "e"/"w" = the way it looks):
    a dark recess with a red signal. Visual only (the wall behind is solid)."""
    s = 1 if face == "e" else -1
    m.box((x + s * 0.03, (pit + top) / 2, zc), (0.04, top - pit, w - 0.6), "dark", "TunnelMouth", collide=False)
    for dz in (-w / 2, w / 2):
        m.box((x + s * 0.1, (pit + top) / 2, zc + dz), (0.2, top - pit, 0.3), "concrete", "TunnelFrame", collide=False)
    m.box((x + s * 0.1, top, zc), (0.2, 0.5, w + 0.3), "concrete", "TunnelFrame", collide=False)
    m.box((x + s * 0.12, top - 0.6, zc + w / 2 - 0.5), (0.06, 0.18, 0.18), "lamp_red", "Signal", collide=False)


def _poster(m, x, y, z, face, mat="blue"):
    """Advert on a tiled wall (framed)."""
    along_x = face in ("n", "s")
    n = {"n": -1, "s": 1, "e": 1, "w": -1}[face]
    if along_x:
        m.box((x, y, z + n * 0.03), (2.2, 1.5, 0.04), "metal", "PosterFrame", collide=False)
        m.box((x, y, z + n * 0.05), (2.0, 1.3, 0.02), mat, "Poster", collide=False)
    else:
        m.box((x + n * 0.03, y, z), (0.04, 1.5, 2.2), "metal", "PosterFrame", collide=False)
        m.box((x + n * 0.05, y, z), (0.02, 1.3, 2.0), mat, "Poster", collide=False)


def _luggage(m, x, z, n=1, mat="green", yaw=0.0):
    """The dark green equipment cases on the platforms (cover)."""
    for i in range(n):
        m.box((x, 0.55 + i * 1.1, z), (1.6, 1.1, 1.0), mat, "Crate", yaw=yaw + i * 8)
        m.box((x, 1.12 + i * 1.1, z), (1.64, 0.04, 1.04), "metal", "CrateLid", yaw=yaw + i * 8, collide=False)


def subway():
    """Subway (bomb map, 3 lanes) after the concept art: Riverside station.
    CT spawn west (the ticket hall, stairs up "To All Trains"), T spawn east
    (the Exit stairs). Three platforms run east-west between the spawns: A
    Long (upper, north), Mid (the central island) and B Long (lower, south),
    with parked trains on the tracks between them — drop into a track bed
    and jump out, or walk through a train's open doors. A (north) and B
    (south) are platforms of their own beside a terminating train, reached
    from A / B Long through two openings each and by CT from the ticket
    hall. Tunnel mouths with red signals at the ends of every track."""
    m = Map("Subway")
    PIT = -1.2

    def area(name, x0, x1, z0, z1, y=0.0, wall="tile", floor="floor_dark", h=5.0, top=5.0, ceil="ceiling"):
        return dict(name=name, x0=x0, x1=x1, z0=z0, z1=z1, y=y, wall=wall, floor=floor, wall_h=h, top=top, ceil=ceil)

    rooms = [
        area("CTSpawn", -56, -40, -10, 10, floor="tile", top=6.0),
        area("MidDoorW", -40, -36, -3, 3, floor="tile", top=3.6),
        area("CTA", -48, -42, -28, -10, floor="tile", top=4.0),
        area("CTADoor", -42, -40, -27, -22, floor="tile", top=3.6),
        area("CTB", -48, -42, 10, 28, floor="tile", top=4.0),
        area("CTBDoor", -42, -40, 22, 27, floor="tile", top=3.6),
        area("TSpawn", 40, 56, -10, 10, floor="tile", top=6.0),
        area("MidDoorE", 38, 40, -3, 3, floor="tile", top=3.6),
        area("TA", 40, 46, -19, -10, floor="tile", top=4.0),
        area("TB", 40, 46, 10, 19, floor="tile", top=4.0),
        # The station: platforms (y 0) and track beds (pits).
        area("ATrack", -40, 14, -36, -32, y=PIT, floor="gravel", top=6.0),
        area("ASite", -40, 14, -32, -20, top=6.0),
        area("ADoor1", -28, -22, -20, -19, top=3.6),
        area("ADoor2", 0, 6, -20, -19, top=3.6),
        area("ALong", -30, 40, -19, -12),
        area("TrackN", -36, 36, -12, -8, y=PIT, floor="gravel"),
        area("Mid", -36, 38, -8, 8),
        area("TrackS", -36, 36, 8, 12, y=PIT, floor="gravel"),
        area("BLong", -30, 40, 12, 19),
        area("BDoor1", -28, -22, 19, 20, top=3.6),
        area("BDoor2", 0, 6, 19, 20, top=3.6),
        area("BSite", -40, 14, 20, 32, top=6.0),
        area("BTrack", -40, 14, 32, 36, y=PIT, floor="gravel", top=6.0),
    ]
    _rooms(m, rooms, trim=("tile_band", "tile_band"))

    # --- Tracks: rails, the yellow platform edges, ramps out at the ends -------------
    tracks = (("ATrack", -34, -40, 14), ("TrackN", -10, -36, 36), ("TrackS", 10, -36, 36), ("BTrack", 34, -40, 14))
    for (_, zc, x0, x1) in tracks:
        _rails_x(m, zc, x0, x1, PIT, 2.4)
        for edge in (zc - 2, zc + 2):
            if abs(edge) == 36:
                continue  # the wall side of the A / B tracks
            s = 1 if edge < zc else -1  # towards the platform
            m.box(((x0 + x1) / 2, 0.005, edge - s * 0.35), (x1 - x0, 0.01, 0.5), "yellow", "EdgeLine", collide=False)
            m.box(((x0 + x1) / 2, 0.005, edge - s * 0.75), (x1 - x0, 0.01, 0.3), "hazard", "Tactile", collide=False)
        # Maintenance ramps out of the bed at both ends (and the tunnel mouths).
        for (xe, face) in ((x0, "e"), (x1, "w")):
            s = 1 if face == "e" else -1
            m.ramp((xe + s * 6.0, PIT, zc), (xe + s * 0.05, 0.0, zc + 0.001), 3.9, "metal", thickness=0.3)
            _tunnel_mouth(m, xe, zc, face, PIT)
    # Island-edge ramps would block the trains' doors: none in the middle.

    # --- Trains --------------------------------------------------------------------
    _metro_car(m, -34, -20, -34, PIT, "red", doors_open=True)
    _metro_car(m, -19.2, -5, -34, PIT, "red")
    _metro_car(m, -26, -12, -10, PIT, "tile_band")
    _metro_car(m, 6, 20, -10, PIT, "tile_band")
    _metro_car(m, -16, -2, 10, PIT, "red")
    _metro_car(m, 14, 28, 10, PIT, "red")
    _metro_car(m, -34, -20, 34, PIT, "tile_band")
    _metro_car(m, -19.2, -5, 34, PIT, "tile_band")
    for (x, z) in ((-19.6, -34), (-19.6, 34)):
        m.box((x, -0.1, z), (0.8, 0.2, 1.2), "floor_dark", "Gangway")

    # --- Pillars (tiled, a blue band) ---------------------------------------------------
    for x in range(-32, 37, 8):
        for z in (-15.5, -4.0, 4.0, 15.5):
            if -30 < x < 38 or abs(z) < 8:
                m.box((x, 2.5, z), (0.8, 5.0, 0.8), "tile", "Pillar")
                m.box((x, 1.2, z), (0.84, 0.3, 0.84), "tile_band", "PillarBand", collide=False)
    for x in (-32, -20, -8, 4):
        for z in (-26, 26):
            m.box((x, 3.0, z), (0.8, 6.0, 0.8), "tile", "Pillar")
            m.box((x, 1.2, z), (0.84, 0.3, 0.84), "tile_band", "PillarBand", collide=False)

    # --- Mid: the central island --------------------------------------------------------
    # A stairwell block in the middle ("To Platform 2") breaks the long sightline.
    m.box((0, 2.5, 0), (8.0, 5.0, 4.0), "tile", "Stairwell")
    m.box((0, 1.2, 0), (8.04, 0.3, 4.04), "tile_band", "Band", collide=False)
    for s in (-1, 1):
        m.sign((0, 3.2, s * 2.0), "s" if s > 0 else "n", "PLATFORM 2 ->", color=(0.9, 0.9, 0.86), pixel=0.004)
    for (x, z, n) in ((-14, 3.5, 2), (-13, -3.8, 1), (14, -3.2, 2), (15.2, 3.6, 1), (27, 0, 1), (-26, 0.5, 1)):
        _luggage(m, x, z, n, "green" if n == 1 else "steel_blue")
    for (x, z) in ((-22, -5), (22, 5), (8, -5.5), (-8, 5.5)):
        m.box((x, 0.25, z), (2.6, 0.5, 0.6), "wood", "Bench")
    for (x, z) in ((-31, 5.5), (31, -5.5)):
        m.box((x, 1.0, z), (1.2, 2.0, 1.0), "red", "Vending")
    m.box((34.5, 0.6, 3.5), (1.2, 1.2, 1.2), "wood", "Crate")
    m.box((-33.5, 0.6, -4), (1.2, 1.2, 1.2), "wood", "Crate")

    # --- A Long (upper) -----------------------------------------------------------------
    for (x, z, n) in ((34, -16.5, 2), (22, -13.8, 1), (9, -17.5, 1), (-6, -14, 2), (-18, -17.5, 1)):
        _luggage(m, x, z, n)
    for (x, z) in ((28, -18.5), (-12, -18.5), (14, -18.5)):
        m.box((x, 0.25, z), (2.6, 0.5, 0.6), "wood", "Bench")
    m.cyl((3, 0.45, -18.3), 0.3, 0.9, "metal", "Bin")
    for x in (-14, 20):
        _poster(m, x, 2.4, -19.0, "s", "blue" if x < 0 else "red")
    m.sign((38.0, 3.2, -19.0), "s", "PLATFORM 1 ->", color=(0.9, 0.9, 0.86), pixel=0.004)

    # --- A site -------------------------------------------------------------------------
    for (x, z, n) in ((-12, -24, 2), (-4, -28.5, 1), (-2.8, -28.2, 1), (6, -24.5, 1), (-26, -29, 2), (-33, -23, 1)):
        _luggage(m, x, z, n)
    m.box((-18, 0.6, -22.5), (3.0, 1.2, 1.2), "concrete", "LowWall")
    for (x, z) in ((10.5, -29), (-36, -29.5)):
        m.box((x, 1.0, z), (1.2, 2.0, 1.0), "red", "Vending")
    m.site("A", (-14.0, 0.0, -25.5))
    m.sign((-14.0, 3.4, -20.0), "n", "A", color=(0.75, 0.1, 0.07), pixel=0.024)
    m.sign((14.0, 3.0, -26.0), "w", "A", color=(0.75, 0.1, 0.07), pixel=0.016)
    m.sign((-40.0, 3.0, -30.0), "e", "RIVERSIDE", color=(0.9, 0.9, 0.86), pixel=0.008)
    for x in (-30, 8):
        _poster(m, x, 3.0, -36.0, "s", "green" if x < 0 else "blue")

    # --- B Long (lower) and B site ------------------------------------------------------
    for (x, z, n) in ((33, 16.5, 1), (21, 13.8, 2), (8, 17.5, 1), (-8, 14, 1), (-19, 16.5, 2)):
        _luggage(m, x, z, n)
    for (x, z) in ((27, 18.5), (-13, 18.5)):
        m.box((x, 0.25, z), (2.6, 0.5, 0.6), "wood", "Bench")
    for x in (-14, 18):
        _poster(m, x, 2.4, 19.0, "n", "red" if x < 0 else "green")
    for (x, z, n) in ((-12, 24, 2), (-5, 28.5, 1), (4, 23, 2), (-27, 29, 1), (-33, 23.5, 1), (10, 29, 1)):
        _luggage(m, x, z, n, "green" if n == 1 else "steel_blue")
    m.box((-19, 0.6, 22.5), (3.0, 1.2, 1.2), "concrete", "LowWall")
    m.box((13.3, 1.2, 25), (0.6, 0.5, 0.4), "red", "FireAlarm", collide=False)
    m.site("B", (-14.0, 0.0, 25.5))
    m.sign((-14.0, 3.4, 20.0), "s", "B", color=(0.75, 0.1, 0.07), pixel=0.024)
    m.sign((14.0, 3.0, 26.0), "w", "B", color=(0.75, 0.1, 0.07), pixel=0.016)
    m.sign((-40.0, 3.0, 30.0), "e", "RIVERSIDE", color=(0.9, 0.9, 0.86), pixel=0.008)
    m.omni((6, 4.2, 30), 0.7, 10.0, (1.0, 0.2, 0.15))   # the red glow at B

    # --- CT spawn: ticket hall, stairs up "To All Trains" -------------------------------
    for z in range(-8, 9, 2):
        if abs(z) > 3:
            m.box((-43, 0.5, z), (0.9, 1.0, 0.25), "metal", "Turnstile")
    m.box((-43, 0.5, -3.3), (0.9, 1.0, 0.25), "metal", "Turnstile")
    m.box((-43, 0.5, 3.3), (0.9, 1.0, 0.25), "metal", "Turnstile")
    m.ramp((-50.0, 0.0, 6.0), (-55.9, 2.6, 6.001), 3.6, "concrete")      # dead-end stairs (cover)
    m.box((-53, 1.3, 3.9), (6.0, 2.6, 0.3), "tile", "StairSide")
    m.box((-51, 1.4, -7), (3.0, 2.8, 2.4), "glass", "Booth")
    m.sign((-40.0, 3.6, -6.0), "w", "TO ALL TRAINS ->", color=(0.9, 0.9, 0.86), pixel=0.004)
    _poster(m, -56.0, 2.6, -2.0, "e", "red")
    m.sign((-55.98, 4.2, 0.0), "e", "CT", color=(0.25, 0.45, 0.85), pixel=0.014)
    m.sign((-48.0, 3.0, -28.0), "s", "A", toward=(-44, -24), color=(0.75, 0.1, 0.07))
    m.sign((-48.0, 3.0, 28.0), "n", "B", toward=(-44, 24), color=(0.75, 0.1, 0.07))

    # --- T spawn: the Exit stairs ----------------------------------------------------
    m.ramp((50.0, 0.0, -6.0), (55.9, 2.6, -6.001), 3.6, "concrete")
    m.box((53, 1.3, -3.9), (6.0, 2.6, 0.3), "tile", "StairSide")
    m.sign((56.0, 3.8, -6.0), "w", "EXIT", color=(0.95, 0.85, 0.3), pixel=0.008)
    for (x, z, n) in ((46, 5, 2), (51, 7.5, 1), (44, -6, 1)):
        _luggage(m, x, z, n)
    m.sign((55.98, 4.2, 2.0), "w", "T", color=(0.85, 0.6, 0.1), pixel=0.014)
    m.sign((46.0, 3.0, -16.0), "w", "A", toward=(40, -16), color=(0.75, 0.1, 0.07))
    m.sign((46.0, 3.0, 16.0), "w", "B", toward=(40, 16), color=(0.75, 0.1, 0.07))

    # --- Lights: strip lights everywhere (emissive: lit on Low) + a few real ones ------
    for x in range(-28, 37, 8):
        for z in (-15.5, 0.0, 15.5):
            if not (abs(z) < 1 and abs(x) < 5):
                _strip_light(m, x + 4, 4.95, z if z else -6.0, 3.0, yaw=90)
                if z == 0.0:
                    _strip_light(m, x + 4, 4.95, 6.0, 3.0, yaw=90)
    for x in range(-36, 13, 8):
        for z in (-26.0, 26.0):
            _strip_light(m, x + 4, 5.95, z, 3.0, yaw=90)
    for (x, z) in ((-48, 0), (48, 0)):
        for dz in (-6, 0, 6):
            _strip_light(m, x, 5.95, z + dz, 3.0, yaw=90)
    for (x, z) in ((-45, -19), (-45, 19), (43, -14), (43, 14)):
        _strip_light(m, x, 3.95, z, 3.0)
    for (x, z) in ((-12, -26), (-12, 26), (-20, 0), (20, 0), (10, -15.5), (10, 15.5), (-48, 0), (48, 0)):
        m.omni((x, 4.0, z), 1.0, 14.0, (0.92, 0.96, 1.0))

    # --- Spawns, callouts, sound --------------------------------------------------------
    for (x, z) in ((50, -2), (50, 2), (47, 0), (53, 0), (47, -4)):
        m.spawn("red", (x, 0.1, z), 90)
    for (x, z) in ((-50, -2), (-50, 2), (-47, 0), (-53, 0), (-47, 4)):
        m.spawn("blue", (x, 0.1, z), -90)
    for (x, y, z, yaw) in ((-20, 0.1, 2, -90), (20, 0.1, -2, 90), (-10, 0.1, -28, 0), (-10, 0.1, 28, 180),
                           (24, 0.1, -16, 90), (24, 0.1, 16, 90), (-24, 0.1, -15, -90), (-24, 0.1, 15, -90)):
        m.spawn("ffa", (x, y, z), yaw)
    for (label, pos, size) in (
            ("CT Spawn", (-48, 2.5, 0), (16, 6, 20)),
            ("T Spawn", (48, 2.5, 0), (16, 6, 20)),
            ("CT A", (-45, 2, -19), (6, 5, 18)),
            ("CT B", (-45, 2, 19), (6, 5, 18)),
            ("T A", (43, 2, -14.5), (6, 5, 9)),
            ("T B", (43, 2, 14.5), (6, 5, 9)),
            ("Mid", (1, 2.5, 0), (74, 5, 16)),
            ("A Long", (5, 2.5, -15.5), (70, 5, 7)),
            ("B Long", (5, 2.5, 15.5), (70, 5, 7)),
            ("Tracks", (0, 0.5, -10), (72, 4, 4)),
            ("Tracks", (0, 0.5, 10), (72, 4, 4)),
            ("Bombsite A", (-13, 3, -26), (54, 6, 12)),
            ("Bombsite B", (-13, 3, 26), (54, 6, 12)),
            ("A Train", (-13, 1, -34), (54, 5, 4)),
            ("B Train", (-13, 1, 34), (54, 5, 4))):
        m.callout(label, pos, size)
    m.reverb((0, 2.5, 0), (80, 7, 72), "hall", 0.5)
    for (x0, x1, z) in ((-34, -5, -34), (-26, -12, -10), (6, 20, -10), (-16, -2, 10), (14, 28, 10), (-34, -5, 34)):
        m.reverb(((x0 + x1) / 2, 1.2, z), (x1 - x0, 2.4, 3.4), "room", 0.3, priority=1)

    m.write("scenes/levels/subway.tscn", sun_rot=(-80.0, 0.0), sky=(0.1, 0.1, 0.12), horizon=(0.2, 0.2, 0.22),
            sun_color=(1, 1, 1), sun_energy=0.0, sun_shadow=False, ambient=0.8, ambient_color=(0.72, 0.75, 0.82))


def trainyard():
    """Train Yard (bomb map, 3 lanes). T spawn west, CT spawn east. Mid is
    the rail yard: parked freight cars and a locomotive on three tracks under
    a gantry crane, the C1 warehouse along its south side. A (north) is
    inside a warehouse on a raised floor, reached from T by A Long — the
    loading dock (upper) — and from Mid by A Main; B (south) is a lower
    yard, reached from T by B Long — a rail cut down beside a track — and
    from Mid by the B stairs. CT gets to A past the water tower and down a
    ramp to B."""
    import random
    rng = random.Random(3)
    m = Map("TrainYard")
    D, L = 1.2, -2.5  # dock / warehouse floor, lower yard

    def area(name, x0, x1, z0, z1, y=0.0, wall="corrugated", floor="concrete", h=8.0, top=None, ceil="corrugated"):
        return dict(name=name, x0=x0, x1=x1, z0=z0, z1=z1, y=y, wall=wall, floor=floor, wall_h=h, top=top, ceil=ceil)

    rooms = [
        area("TSpawn", -48, -36, -10, 10, wall="brick", h=9.0),
        area("TMid", -36, -24, -5, 5, wall="brick"),
        area("Mid", -24, 30, -12, 12, floor="gravel", h=10.0),
        area("CTMid", 30, 36, -5, 5, wall="concrete"),
        area("CTSpawn", 36, 48, -12, 8, wall="concrete", h=9.0),
        # A: dock (upper), warehouse, A Main, CT side.
        area("ALongRamp", -46, -40, -24, -10, wall="brick"),
        area("ALong", -46, -21, -32, -24, y=D, wall="brick", h=7.0),
        area("ADoorW", -21, -20, -30, -26, y=D, top=D + 3.6, wall="corrugated"),
        area("AWarehouse", -20, 8, -44, -22, y=D, top=D + 8.0, wall="corrugated"),
        area("AMain", -10, -2, -22, -12, wall="brick"),
        area("ADoorE", 8, 9, -40, -34, y=D, top=D + 3.6, wall="corrugated"),
        area("CTA", 9, 48, -44, -30, wall="concrete", h=9.0),
        area("CTNorth", 38, 46, -30, -12, wall="concrete"),
        # B: rail cut (lower), B yard, stairs, CT ramp.
        area("BLongDrop", -46, -40, 10, 34, y=L, wall="brick", h=10.0),
        area("BLong", -40, -16, 30, 38, y=L, wall="brick", h=10.0, floor="gravel"),
        area("BSite", -16, 10, 24, 44, y=L, wall="corrugated", h=10.5),
        area("BStairs", -4, 2, 12, 24, y=L, wall="brick", h=10.0),
        area("CTSouth", 38, 46, 8, 30, y=L, wall="concrete", h=10.0),
        area("CTB", 10, 46, 30, 38, y=L, wall="concrete", h=10.0, floor="gravel"),
    ]
    _rooms(m, rooms, windows=True)

    # --- Ramps -----------------------------------------------------------------------
    m.ramp((-43, 0.0, -11.0), (-43.001, D, -23.9), 6.0, "concrete")      # up to the dock
    m.ramp((-6, D, -22.0), (-6.001, 0.0, -15.0), 8.0, "concrete")        # warehouse -> A Main
    m.ramp((9.0, D, -37), (16.0, 0.0, -37.001), 6.0, "concrete")         # warehouse -> CT A yard
    m.ramp((-43, 0.0, 10.0), (-43.001, L, 22.0), 6.0, "concrete")        # B Long down
    m.ramp((-1, 0.0, 12.0), (-1.001, L, 22.0), 6.0, "metal")             # B stairs
    m.ramp((42, 0.0, 8.0), (42.001, L, 20.0), 8.0, "concrete")           # CT -> B
    for x in (-3.9, 1.9):
        _rail(m, (x, L / 2 + 0.6, 17.5), (0.06, 1.0, 10.5), "yellow")
    for z in range(13, 22):   # stair nosing on the B stairs
        m.box((-1, L * (z + 0.5 - 12) / 10 + 0.03, z + 0.5), (5.9, 0.03, 0.12), "hazard", "StepLine", collide=False)
    m.box((-33.5, D + 0.01, -24.15), (25, 0.02, 0.3), "hazard", "DockEdge", collide=False)
    for x in range(-44, -22, 4):
        m.box((x, D - 0.3, -23.8), (0.4, 0.6, 0.3), "floor_dark", "DockBumper", collide=False)

    # --- Mid: tracks, trains, gantry crane ----------------------------------------------
    for z in (-7, 0, 7):
        _rails_x(m, z, -24, 30)
    for (x, z, kind, mat, length) in ((-12, -7, "box", "rust", 12.0), (14, -7, "tank", "floor_dark", 12.0),
                                     (2, 0, "loco", "yellow", 12.0), (19, 0, "box", "green", 10.0),
                                     (-15, 7, "hopper", "green", 12.0), (6, 7, "box", "steel_blue", 12.0),
                                     (24, 7, "box", "red", 8.0)):
        _freight(m, x, z, kind, mat, length, axis="x")
    for z in (-11.3, 11.3):
        for x in (-19.8, -18.2):
            m.box((x, 5.0, z), (0.6, 10.0, 0.6), "yellow", "GantryLeg")
    m.box((-19, 10.3, 0), (2.4, 0.6, 23.2), "yellow", "GantryBeam", collide=False)
    m.box((-19, 9.8, -2), (1.6, 0.8, 1.4), "metal", "Trolley", collide=False)
    for dx in (-0.8, 0.8):
        m.box((-19 + dx, 8.2, -2), (0.05, 2.4, 0.05), "cable", "HookCable", collide=False)
    m.box((-19, 5.8, -2), (2.4, 2.6, 6.0), "rust", "HangingContainer", collide=False)
    for (x, z) in ((-9, -3.2), (-8, 3.6), (9.5, 3.4), (27, -3.5)):
        _crates(m, x, z, 1)
    _crates(m, -21.5, -10.5, 2)
    _pallets(m, 26.5, 10.5)
    _forklift(m, 27, -10, 180)
    for (x, z) in ((-22, 0), (28.5, 0)):
        m.box((x, 0.6, z + 3.5), (1.2, 1.2, 1.2), "wood", "Crate")
    # C1 warehouse front (Mid's south wall) and the building north of Mid.
    for x in (-18, -10, 8, 18):
        m.box((x, 2.2, 12.08), (4.0, 4.4, 0.12), "shutter", "Shutter", collide=False)
        m.box((x, 4.7, 12.1), (4.4, 0.3, 0.15), "metal", "ShutterBox", collide=False)
    for x in range(-20, 30, 5):
        m.box((x, 7.2, 12.08), (2.4, 1.2, 0.06), "glass", "Window", collide=False)
        m.box((x, 7.2, -12.08), (2.4, 1.2, 0.06), "glass", "Window", collide=False)
    m.sign((24.0, 4.6, 12.0), "n", "C1", color=(0.85, 0.85, 0.82), pixel=0.018)
    m.box((13, 6.0, 12.12), (0.8, 0.8, 0.1), "yellow", "Emblem", collide=False)
    for (x, z, face) in ((13, 12.2, "n"), (-12, -12.2, "s")):
        m.box((x, 7.6, z), (0.5, 0.2, 0.4), "lamp", "WallLamp", collide=False)

    # --- A: dock and the warehouse --------------------------------------------------
    for (x, z) in ((-38, -30.5), (-36.8, -30.4), (-30, -25.5), (-26, -30.8)):
        m.box((x, D + 0.6, z), (1.2, 1.2, 1.2), "wood", "Crate")
    m.box((-38, D + 1.8, -30.5), (1.2, 1.2, 1.2), "wood", "Crate")
    _pallets(m, -33, -30.8, y=D)
    _rails_x(m, -40, -20, 8, D)
    _freight(m, -9, -40, "box", "yellow", 10.0, axis="x", y=D)
    for (x, z) in ((2, -27), (3.3, -27.2), (-16, -26), (5, -42.5)):
        m.box((x, D + 0.6, z), (1.2, 1.2, 1.2), "wood", "Crate")
    m.box((2.6, D + 1.8, -27.1), (1.2, 1.2, 1.2), "wood", "Crate")
    m.box((-4, D + 0.7, -30), (2.2, 1.4, 1.6), "green", "Tarp")
    _forklift(m, 4, -35, 90, y=D)
    for (x, z) in ((-18.4, -38), (6.4, -28)):
        m.box((x, D + 1.6, z), (1.0, 3.2, 8.0), "steel_blue", "Shelving")
    m.site("A", (-4.0, D, -34.0))
    m.sign((-4.0, D + 4.8, -44.0), "s", "A", color=(0.75, 0.1, 0.07), pixel=0.022)
    m.sign((-20.0, D + 3.0, -36.0), "e", "A", color=(0.75, 0.1, 0.07), pixel=0.012)
    for (x, z) in ((-12, -36), (0, -36), (-12, -28), (0, -28)):
        _strip_light(m, x, D + 7.9, z, 3.0, 90)
    m.omni((-6, D + 6.5, -33), 1.3, 16.0, (1.0, 0.92, 0.78))
    m.omni((-6, 3.0, -24.5), 0.8, 8.0, (1.0, 0.85, 0.6))
    m.reverb((-6, D + 4.0, -33), (28, 8, 22), "hall", 0.4)
    # CT A yard: the water tower, containers.
    _water_tower(m, 30, -38)
    _container(m, 20, -42, 90, "blue")
    _container(m, 20, -42, 90, "red", 1)
    _container(m, 42, -34, 0, "green")
    _crates(m, 24, -32, 1)
    m.box((14, 0.5, -31.5), (3.0, 1.0, 0.5), "concrete", "Barrier")

    # --- B: rail cut, yard, stairs -------------------------------------------------------
    _rails_x(m, 34, -46, -16, L)
    _freight(m, -27, 34, "box", "rust", 10.0, axis="x", y=L)
    _rails_x(m, 40, -16, 10, L)
    _freight(m, -6, 40, "box", "steel_blue", 12.0, axis="x", y=L)
    m.sign((-6.0, L + 2.7, 38.6), "n", "CARGO", color=(0.85, 0.85, 0.8), pixel=0.006)
    for (x, z) in ((5, 28), (6.2, 28.3), (-12, 27), (4, 34)):
        m.box((x, L + 0.6, z), (1.2, 1.2, 1.2), "wood", "Crate")
    m.box((5.6, L + 1.8, 28.1), (1.2, 1.2, 1.2), "wood", "Crate")
    _pallets(m, -10, 31, y=L)
    m.site("B", (-3.0, L, 32.0))
    m.sign((-16.0, L + 4.0, 30.0), "e", "B", color=(0.75, 0.1, 0.07), pixel=0.02)
    m.sign((-40.0, 3.2, 20.0), "e", "B", toward=(-3, 32), color=(0.75, 0.1, 0.07))
    m.sign((-40.0, 3.4, -18.0), "e", "A", toward=(-4, -34), color=(0.75, 0.1, 0.07))
    m.sign((-48.0, 3.0, 0.0), "e", "T", color=(0.85, 0.6, 0.1), pixel=0.014)
    m.sign((48.0, 3.0, -2.0), "w", "CT", color=(0.25, 0.45, 0.85), pixel=0.014)
    for (x, y, z) in ((-28, L + 6.0, 34), (-3, L + 7.0, 34), (30, L + 6.0, 34), (-43, 3.0, 22)):
        m.omni((x, y, z), 0.9, 14.0, (1.0, 0.88, 0.7))

    # --- Spawns' dressing, background ----------------------------------------------------
    _truck(m, -42, -4, 0, "steel_blue")
    _container(m, -38, 6, 90, "rust")
    _container(m, 42, -8, 90, "blue")
    _container(m, 42, -8, 90, "green", 1)
    _forklift(m, 38, 4, 90)
    for (x, z) in ((-50, -48), (0, -50), (52, -20), (52, 30), (-52, 48), (20, 50)):
        _pylon(m, x, z)
    for (x, z, h) in ((-30, -52, 24.0), (-22, -53, 20.0), (34, 52, 22.0)):
        _chimney(m, x, z, 0.0, h, 1.1)
    for (x, z) in ((-30, 0), (34, -30), (-30, 30)):
        m.cyl((x, 5.5, z if x != -30 or z != 0 else -12.0), 0.15, 11.0, "metal", "FloodPole", collide=False)

    for (x, z) in ((-46, -6), (-46, -2), (-46, 2), (-46, 6), (-40, 0)):
        m.spawn("red", (x, 0.1, z), -90)
    for (x, z) in ((46, -8), (46, -4), (46, 0), (46, 4), (40, -2)):
        m.spawn("blue", (x, 0.1, z), 90)
    for (x, y, z, yaw) in ((-20, 0.1, -3, -90), (26, 0.1, 3, 90), (-30, D + 0.1, -28, -90), (-4, D + 0.1, -28, 0),
                           (-4, L + 0.1, 28, 180), (-28, L + 0.1, 31, -90), (30, 0.1, -34, 90), (28, L + 0.1, 32, 90)):
        m.spawn("ffa", (x, y, z), yaw)
    for (label, pos, size) in (
            ("T Spawn", (-42, 2, 0), (12, 6, 20)),
            ("CT Spawn", (42, 2, -2), (12, 6, 20)),
            ("T Mid", (-30, 2, 0), (12, 6, 10)),
            ("CT Mid", (33, 2, 0), (6, 6, 10)),
            ("Mid", (3, 3, 0), (54, 10, 24)),
            ("A Long", (-43, 2, -17), (6, 6, 14)),
            ("A Long Upper", (-33.5, 3, -28), (25, 5, 8)),
            ("Bombsite A", (-6, 4, -33), (28, 8, 22)),
            ("A Main", (-6, 2, -17), (8, 6, 10)),
            ("Water Tower", (28, 2, -37), (38, 6, 14)),
            ("CT A", (42, 2, -21), (8, 6, 18)),
            ("B Long", (-34, 0, 26), (24, 6, 24)),
            ("Bombsite B", (-3, 0, 34), (26, 8, 20)),
            ("B Stairs", (-1, -1, 18), (6, 6, 12)),
            ("CT B", (32, 0, 28), (28, 6, 20))):
        m.callout(label, pos, size)

    m.write("scenes/levels/trainyard.tscn", sun_rot=(-28.0, 75.0), sky=(0.3, 0.42, 0.62), horizon=(0.86, 0.66, 0.5),
            sun_color=(1.0, 0.8, 0.6), sun_energy=1.25, ambient=0.8, ambient_color=(0.68, 0.64, 0.62),
            fog=0.004, fog_color=(0.82, 0.7, 0.6))

def _quay_crane(m, x, z, h=20.0, mat="yellow"):
    """Ship-to-shore crane on the quay edge: four legs (collide), a portal
    frame and a boom reaching out over the water (visual)."""
    for dx in (-3.5, 3.5):
        for dz in (-2.0, 2.0):
            m.box((x + dx, h / 2 * 0.55, z + dz), (0.7, h * 0.55, 0.7), mat, "CraneLeg")
    m.box((x, h * 0.55 + 0.4, z), (8.4, 0.8, 5.0), mat, "CranePortal", collide=False)
    for dz in (-2.0, 2.0):
        m.box((x - 3.5, h * 0.78, z + dz), (0.5, h * 0.45, 0.5), mat, "CraneTower", collide=False)
    m.box((x - 3.5, h + 0.3, z + 9.0), (1.4, 1.0, 26.0), mat, "CraneBoom", collide=False)
    m.box((x - 3.5, h - 0.4, z + 16.0), (1.8, 1.0, 2.4), "metal", "CraneTrolley", collide=False)
    m.box((x - 3.5, h - 4.5, z + 16.0), (0.05, 7.0, 0.05), "cable", "CraneCable", collide=False)
    m.box((x, h * 0.55 + 2.2, z - 1.5), (3.0, 2.6, 2.6), "metal", "CraneCab", collide=False)
    m.box((x, h * 0.55 + 2.4, z - 2.82), (2.6, 1.2, 0.05), "glass", "CraneWindow", collide=False)


def _van(m, x, z, yaw=0.0, mat="silver"):
    """Delivery van (one solid body, too tall to jump on)."""
    m.box((x, 1.2, z), (2.1, 2.2, 5.0), mat, "Van", yaw=yaw)
    fx, fz = _off(yaw, 0, -2.51)
    m.box((x + fx, 1.55, z + fz), (1.8, 0.8, 0.05), "glass", "VanWindow", yaw=yaw, collide=False)
    for dz in (-1.6, 1.6):
        for side in (-1, 1):
            ox, oz = _off(yaw, side * 1.0, dz)
            m.cyl((x + ox, 0.38, z + oz), 0.38, 0.3, "floor_dark", "Wheel", collide=False, yaw=yaw, roll=90)


def _pickup(m, x, z, yaw=0.0, mat="steel_blue"):
    """Pickup truck: a climbable bed and body, the cab on top (visual height)."""
    m.box((x, 0.6, z), (2.0, 1.0, 5.0), mat, "Car", yaw=yaw)
    cx, cz = _off(yaw, 0, -0.9)
    m.box((x + cx, 1.45, z + cz), (1.9, 0.8, 1.8), mat, "CarCab", yaw=yaw)
    wx, wz = _off(yaw, 0, -1.81)
    m.box((x + wx, 1.5, z + wz), (1.7, 0.6, 0.05), "glass", "Windscreen", yaw=yaw, collide=False)


def _flood_light(m, x, z, h=11.0):
    m.cyl((x, h / 2, z), 0.16, h, "metal", "FloodPole")
    m.box((x, h + 0.3, z), (1.8, 0.5, 0.4), "metal", "FloodHead", collide=False)
    m.box((x, h + 0.1, z), (1.6, 0.12, 0.3), "lamp", "FloodLamp", collide=False)


def docks():
    """Docks (bomb map, 3 lanes) after the concept art. CT spawn west (a
    small office and a pickup), T spawn east (the gate road with a walkway
    over it and a van). Mid runs through the Port Authority warehouse. A
    (north) is the container yard off the warehouse's north door, under a
    gantry crane; T reach it along A Long — a raised loading platform with a
    rail track (upper). B (south) is on the quay beside the moored ship, with
    the ship-to-shore cranes; T reach it along B Long — the quay (lower)."""
    import random
    rng = random.Random(8)
    m = Map("Docks")

    def area(name, x0, x1, z0, z1, y=0.0, wall="concrete", floor="concrete", h=7.0, top=None, ceil="corrugated",
             open_sides=""):
        return dict(name=name, x0=x0, x1=x1, z0=z0, z1=z1, y=y, wall=wall, floor=floor, wall_h=h, top=top,
                    ceil=ceil, open=open_sides)

    UP = 2.0  # A Long platform
    rooms = [
        area("TSpawn", 40, 54, -12, 12, wall="brick", floor="paving", h=8.0),
        area("TMid", 19, 40, -6, 6, wall="corrugated"),
        area("MidDoorE", 18, 19, -3, 3, top=5.0, wall="corrugated"),
        area("Warehouse", -18, 18, -12, 12, top=9.0, wall="corrugated", floor="concrete"),
        area("MidDoorW", -19, -18, -3, 3, top=5.0, wall="corrugated"),
        area("CTMid", -40, -19, -5, 5, wall="concrete"),
        area("CTSpawn", -54, -40, -12, 12, wall="concrete", floor="paving", h=8.0),
        # A: short from the warehouse, the yard, A Long, CT side.
        area("MidDoorN", -7, -3, -13, -12, top=5.0, wall="corrugated"),
        area("AShort", -9, -1, -20, -13, wall="corrugated"),
        area("ASite", -32, 6, -42, -20, wall="corrugated", h=8.0),
        area("ALong", 6, 52, -34, -26, y=UP, wall="corrugated", h=6.0),
        area("ALongRamp", 44, 52, -26, -12, wall="brick"),
        area("CTA", -50, -42, -30, -12, wall="concrete"),
        area("CTAYard", -50, -32, -40, -30, wall="concrete"),
        # B: short from the warehouse, the quay, B Long, CT side.
        area("MidDoorS", 2, 6, 12, 13, top=5.0, wall="corrugated"),
        area("BShort", 0, 8, 13, 20, wall="corrugated"),
        area("BSite", -14, 30, 20, 40, wall="corrugated", h=8.0, open_sides="s"),
        area("BLong", 30, 54, 20, 40, wall="brick", open_sides="s"),
        area("BLongRoad", 44, 52, 12, 20, wall="brick", floor="paving"),
        area("CTB", -50, -42, 12, 24, wall="concrete"),
        area("CTBQuay", -50, -14, 24, 40, wall="concrete", open_sides="s"),
    ]
    _rooms(m, rooms, windows=True)
    m.ramp((48, 0.0, -13.0), (48.001, UP, -25.9), 8.0, "concrete")        # T spawn up onto A Long
    m.ramp((6.0, UP, -30), (0.0, 0.0, -30.001), 4.0, "metal")             # A Long down into A
    for z in (-32.1, -27.9):
        _rail(m, (3.0, UP / 2 + 0.55, z), (6.0, 1.0, 0.06), "yellow")

    # --- The sea, the quay edge, the ship ------------------------------------------------
    m.box((0, -1.6, 70), (150, 1.0, 60), "water", "Sea", collide=False)
    m.box((2, -0.7, 40.25), (104, 0.5, 0.5), "concrete", "QuayLip", collide=False)
    m.blocker((2, 1.5, 40.2), (104, 3.0, 0.3), "QuayFence")
    for x in range(-48, 54, 3):
        m.box((x, 0.5, 39.9), (0.06, 1.0, 0.06), "yellow", "RailPost", collide=False)
    m.box((2, 1.0, 39.9), (104, 0.06, 0.06), "yellow", "RailBar", collide=False)
    m.box((2, 0.55, 39.9), (104, 0.06, 0.06), "yellow", "RailBar", collide=False)
    for x in range(-46, 54, 8):
        m.cyl((x, 0.3, 39.2), 0.25, 0.6, "floor_dark", "Bollard", top=0.3)
    m.box((2, 0.01, 38.6), (104, 0.02, 0.25), "hazard", "EdgeLine", collide=False)
    # Ship: hull, deck containers, bridge at the stern.
    m.box((0, 1.5, 51), (78, 7.0, 14), "floor_dark", "Hull", collide=False)
    m.box((0, 5.3, 51), (78, 0.6, 14.4), "red", "HullBand", collide=False)
    m.box((34, 11.0, 51), (9, 11.0, 12), "silver", "Bridge", collide=False)
    for yy in (8.5, 11.5, 14.5):
        m.box((29.45, yy, 51), (0.05, 1.2, 10), "glass", "BridgeWindow", collide=False)
    m.box((36, 18.0, 51), (1.2, 4.0, 1.2), "red", "Funnel", collide=False)
    for i, x in enumerate(range(-34, 26, 7)):
        for lvl in range(rng.randint(1, 3)):
            for dz in (-3.0, 0.0, 3.0):
                mat = rng.choice(["red", "blue", "steel_blue", "rust", "green"])
                m.box((x, 6.9 + lvl * 2.6, 51 + dz), (6.2, 2.6, 2.5), mat, "ShipContainer", collide=False)
    _quay_crane(m, -6, 36)
    _quay_crane(m, 22, 36, mat="accent")

    # --- Mid: the Port Authority warehouse ----------------------------------------------
    # Racks along both long walls, clear of the north (A) and south (B) doors.
    for x in (-13, 5, 12):
        m.box((x, 1.8, -8.0), (6.0, 3.6, 1.0), "steel_blue", "Shelving")
    for x in (-12, -4, 13):
        m.box((x, 1.8, 8.0), (6.0, 3.6, 1.0), "steel_blue", "Shelving")
    for (x, z) in ((-13, -10.5), (-12, 10.6), (9, -10.4), (14, 10.4), (-6, 3), (7, -3)):
        _crates(m, x, z, 1)
    _crates(m, 0, 2.5, 2)
    _forklift(m, -9, -2, 90)
    _pallets(m, 11, 2.5)
    for (x, z) in ((-10, -4), (-10, 4), (10, -4), (10, 4)):
        _strip_light(m, x, 8.9, z, 3.0, 90)
    m.omni((0, 7.0, 0), 1.3, 20.0, (1.0, 0.93, 0.8))
    m.reverb((0, 4.5, 0), (36, 9, 24), "hall", 0.4)
    # Facades over the east / west doors, with the name on them.
    for (x, face) in ((18.8, "e"), (-18.8, "w")):
        m.box((x, 7.0, 0), (0.4, 4.0, 6.4), "corrugated", "Facade")
        m.sign((x + (0.22 if face == "e" else -0.22), 6.4, 0.0), face, "PORT AUTHORITY", color=(0.9, 0.9, 0.86),
               pixel=0.0022)
    for (x, z, face) in ((-5, -12.45, "n"), (4, 12.45, "s"), (18.45, 0, "e"), (-18.45, 0, "w")):
        m.box((x, 5.6, z), (0.5, 0.2, 0.4), "lamp", "WallLamp", collide=False)

    # --- T spawn: the gate road, a walkway over it, a van ----------------------------------
    for z in (-11.5, 11.5):
        m.box((42, 3.5, z), (1.0, 7.0, 1.0), "steel_blue", "GatePillar")
    m.box((42, 6.6, 0), (2.4, 0.4, 24.0), "steel_blue", "Walkway", collide=False)
    for dx in (-1.1, 1.1):
        m.box((42 + dx, 7.3, 0), (0.06, 1.0, 24.0), "yellow", "WalkwayRail", collide=False)
    m.box((42, 7.9, -11.5), (2.4, 2.2, 2.4), "corrugated", "GateHut", collide=False)
    _van(m, 49, 7, 0, "silver")
    for z in (-8, -4, 0, 4):
        m.box((47, 0.01, z), (0.15, 0.02, 2.0), "hazard", "RoadLine", collide=False)
    m.box((53.5, 0.5, -6), (1.0, 1.0, 3.0), "concrete", "Barrier")

    # --- CT spawn: the harbour office and a pickup -------------------------------------
    _house(m, -53, -46, -11, -4, "wall", floors=1, fh=3.6, doors=[("e", 3.5, 1.6)], windows="se")
    _pickup(m, -45, 5, 20, "steel_blue")
    _crates(m, -52, 9, 1)
    _flood_light(m, -41, -11)

    # --- TMid / CTMid yards -------------------------------------------------------------
    _container(m, 30, -4.7, 90, "red")
    _container(m, 25, 4.7, 90, "blue")
    _container(m, 25, 4.7, 90, "steel_blue", 1)
    _crates(m, 35, 0, 1)
    _forklift(m, 21, -3.5, 0)
    _container(m, -30, 3.8, 90, "green")
    _container(m, -30, 3.8, 90, "rust", 1)
    _crates(m, -24, -3.5, 1)
    _drum(m, -36, -4)

    # --- A: the container yard under the gantry crane ----------------------------------
    _gantry(m, -30, 4, -41.0, h=12.0)
    _container(m, -20, -26, 0, "red")                 # the red container with the A
    m.sign((-18.78, 1.6, -26.0), "e", "A", color=(0.95, 0.95, 0.92), pixel=0.02)
    _container(m, -27, -36, 90, "blue")
    _container(m, -27, -36, 90, "red", 1)
    _container(m, -4, -37, 90, "steel_blue")
    _container(m, 2, -24, 0, "rust")
    for (x, z) in ((-9, -30), (-8, -29.2), (-22, -38.5), (3, -33)):
        _crates(m, x, z, 1)
    _crates(m, -14, -23, 2)
    _pallets(m, -6, -40)
    _forklift(m, -24, -31, 0)
    m.site("A", (-14.0, 0.0, -32.0))
    m.sign((-14.0, 5.0, -41.98), "s", "A", color=(0.75, 0.1, 0.07), pixel=0.022)
    m.sign((-8.98, 3.2, -16.5), "e", "A", toward=(-14, -32), color=(0.75, 0.1, 0.07))
    for (x, z) in ((-20, -20.5), (4, -41)):
        _flood_light(m, x, z)
    m.omni((-14, 7.0, -31), 1.2, 18.0, (1.0, 0.9, 0.75))
    # A Long: the raised loading platform with a rail track.
    _rails_x(m, -30, 6, 52, UP)
    _freight(m, 30, -30, "box", "rust", 10.0, axis="x", y=UP)
    _container(m, 16, -32.6, 90, "blue", y=UP)
    _container(m, 16, -32.6, 90, "red", 1, y=UP)
    _container(m, 41, -32.6, 90, "steel_blue", y=UP)
    for x in (10, 24, 36, 48):
        m.box((x, UP + 3.2, -25.8), (0.12, 0.8, 0.06), "metal", "RailPost", collide=False)
    m.box((29, UP + 3.6, -25.8), (46, 0.06, 0.06), "yellow", "RailBar", collide=False)
    for (x, z) in ((46, -33), (11, -33), (22, -32.8)):
        m.box((x, UP + 0.6, z), (1.2, 1.2, 1.2), "wood", "Crate")
    m.box((6.05, UP + 0.01, -30), (0.3, 0.02, 8.0), "hazard", "DockEdge", collide=False)
    _flood_light(m, 50, -33, 10.0)
    m.omni((28, UP + 5.5, -30), 0.9, 16.0, (1.0, 0.88, 0.7))

    # --- B: the quay by the ship --------------------------------------------------------
    _container(m, 8, 34.3, 0, "blue")                  # the blue container with the B
    m.sign((8.0, 1.6, 31.28), "n", "B", color=(0.95, 0.95, 0.92), pixel=0.02)
    _container(m, 8, 34.3, 0, "red", 1)
    _container(m, -8, 26, 90, "red")
    _container(m, 24, 24, 90, "steel_blue")
    _container(m, 24, 24, 90, "blue", 1)
    for (x, z) in ((0, 27), (1.2, 27.3), (16, 33), (-10, 35)):
        _crates(m, x, z, 1)
    _forklift(m, 15, 25, 90)
    _pallets(m, -2, 36)
    m.site("B", (4.0, 0.0, 29.0))
    m.sign((20.0, 4.5, 20.02), "s", "B", color=(0.75, 0.1, 0.07), pixel=0.02)
    m.sign((0.02, 3.2, 16.5), "e", "B", toward=(4, 29), color=(0.75, 0.1, 0.07))
    # B Long: containers along the quay road.
    _container(m, 38, 25, 90, "red")
    _container(m, 46, 31, 0, "blue")
    _crates(m, 34, 34, 1)
    _drum(m, 50, 24)
    # CT B quay.
    _container(m, -30, 28, 90, "green")
    _container(m, -22, 34, 90, "rust")
    _crates(m, -40, 30, 1)
    for (x, z) in ((-36, 25), (40, 21), (12, 21)):
        _flood_light(m, x, z)
    for (x, z) in ((-30, 32), (4, 32), (40, 30)):
        m.omni((x, 7.0, z), 0.9, 16.0, (1.0, 0.86, 0.68))

    # --- Signs, background ------------------------------------------------------------
    m.sign((53.98, 3.2, 0.0), "w", "T", color=(0.85, 0.6, 0.1), pixel=0.014)
    m.sign((-53.98, 3.2, 0.0), "e", "CT", color=(0.25, 0.45, 0.85), pixel=0.014)
    m.sign((44.02, 3.2, -18.0), "e", "A", toward=(48, -30), color=(0.75, 0.1, 0.07))
    m.sign((44.02, 3.2, 16.0), "e", "B", toward=(48, 30), color=(0.75, 0.1, 0.07))
    for (x, z) in ((-60, -50), (0, -54), (60, -40), (-62, 10)):
        _pylon(m, x, z)
    for (x, z, h) in ((-40, -56, 22.0), (30, -58, 26.0), (64, 10, 18.0)):
        _chimney(m, x, z, 0.0, h, 1.1)
    for i in range(14):
        x = -70 + i * 11 + rng.uniform(-2, 2)
        hgt = rng.uniform(12, 30)
        m.box((x, hgt / 2, -70 - rng.uniform(0, 8)), (rng.uniform(6, 10), hgt, 8), "concrete", "Skyline",
              collide=False)

    for (x, z) in ((48, -8), (48, -4), (48, 0), (48, 4), (44, -2)):
        m.spawn("red", (x, 0.1, z), 90)
    for (x, z) in ((-44, -8), (-44, -3), (-44, 2), (-48, 0), (-48, 6)):
        m.spawn("blue", (x, 0.1, z), -90)
    for (x, y, z, yaw) in ((0, 0.1, 0, 0), (30, 0.1, 0, 90), (-30, 0.1, -2, -90), (-14, 0.1, -26, 0),
                           (26, UP + 0.1, -28, 90), (4, 0.1, 24, 180), (40, 0.1, 36, 90), (-36, 0.1, 36, -90)):
        m.spawn("ffa", (x, y, z), yaw)
    for (label, pos, size) in (
            ("T Spawn", (47, 2, 0), (14, 6, 24)),
            ("CT Spawn", (-47, 2, 0), (14, 6, 24)),
            ("T Mid", (29, 2, 0), (21, 6, 12)),
            ("CT Mid", (-29, 2, 0), (21, 6, 10)),
            ("Mid", (0, 3, 0), (38, 9, 26)),
            ("A Short", (-5, 2, -16), (8, 6, 8)),
            ("Bombsite A", (-13, 3, -31), (38, 8, 22)),
            ("A Long", (29, 4, -30), (46, 6, 8)),
            ("A Long Ramp", (48, 2, -19), (8, 6, 14)),
            ("CT A", (-44, 2, -30), (16, 6, 20)),
            ("B Short", (4, 2, 16), (8, 6, 8)),
            ("Bombsite B", (8, 2, 30), (44, 8, 20)),
            ("B Long", (44, 2, 28), (24, 6, 24)),
            ("CT B", (-34, 2, 30), (34, 6, 20))):
        m.callout(label, pos, size)

    m.write("scenes/levels/docks.tscn", sun_rot=(-14.0, 200.0), sky=(0.3, 0.36, 0.55), horizon=(0.98, 0.6, 0.36),
            sun_color=(1.0, 0.72, 0.48), sun_energy=1.2, ambient=0.8, ambient_color=(0.62, 0.58, 0.62),
            fog=0.004, fog_color=(0.85, 0.62, 0.48))


if __name__ == "__main__":
    docks()
    bunker()
    oasis()
    factory()
    office()
    subway()
    trainyard()
