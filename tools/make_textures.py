#!/usr/bin/env python3
"""Surface detail textures, generated (no downloads).

    pip install numpy pillow
    python3 tools/make_textures.py

Writes two 2D texture arrays (layers stacked vertically, 512 x 512 each):
    assets/textures/surfaces_albedo.png   RGB = colour detail around a neutral
                                          0.5 grey (the level shader multiplies
                                          by 2 x the material colour), A = roughness
    assets/textures/surfaces_normal.png   tangent-space normal map
Layers (see LAYERS below): concrete, rusty metal, wood, plaster, stone,
corrugated sheet, fabric. Everything tiles seamlessly. The level shader
(assets/shaders/prototype_grid.gdshader) reads them through the global
uniforms `surface_albedo` / `surface_normal` when Surface detail is on.

Replace a layer with a real texture later (Poly Haven, ambientCG): keep the
same size and order, and store the colour relative to mid-grey.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SIZE = 512
LAYERS = ["concrete", "rust_metal", "wood", "plaster", "stone", "corrugated", "fabric"]


# --- tileable noise -----------------------------------------------------------
def value_noise(rng, fx, fy=None):
    """Periodic value noise with smooth (cubic) interpolation: fx x fy cells."""
    fy = fy or fx
    grid = rng.random((fy, fx))
    ys = np.arange(SIZE) * fy / SIZE
    xs = np.arange(SIZE) * fx / SIZE
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    ty = ys - y0
    tx = xs - x0
    ty = ty * ty * (3 - 2 * ty)
    tx = tx * tx * (3 - 2 * tx)
    y1 = (y0 + 1) % fy
    x1 = (x0 + 1) % fx
    y0 %= fy
    x0 %= fx
    a = grid[np.ix_(y0, x0)]
    b = grid[np.ix_(y0, x1)]
    c = grid[np.ix_(y1, x0)]
    d = grid[np.ix_(y1, x1)]
    tx = tx[None, :]
    ty = ty[:, None]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(rng, f=4, octaves=5, gain=0.5, stretch=(1, 1)):
    total, amp, norm = np.zeros((SIZE, SIZE)), 1.0, 0.0
    for o in range(octaves):
        fx = f * (2 ** o) * stretch[0]
        fy = f * (2 ** o) * stretch[1]
        total += value_noise(rng, max(1, int(fx)), max(1, int(fy))) * amp
        norm += amp
        amp *= gain
    return total / norm


def ridged(rng, f=6, octaves=4):
    """Thin crack-like lines."""
    n = fbm(rng, f, octaves)
    return 1.0 - np.abs(n - 0.5) * 2.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def dots(rng, count, radius):
    """Tileable round specks (pores, chips)."""
    img = np.zeros((SIZE, SIZE))
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    for _ in range(count):
        cx, cy = rng.random(2) * SIZE
        r = radius * (0.5 + rng.random())
        dx = np.minimum(np.abs(xx - cx), SIZE - np.abs(xx - cx))
        dy = np.minimum(np.abs(yy - cy), SIZE - np.abs(yy - cy))
        img = np.maximum(img, np.clip(1.0 - np.sqrt(dx * dx + dy * dy) / r, 0.0, 1.0))
    return img


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    n = np.stack([-dx, dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return (n * 0.5 + 0.5)


def grey(lum):
    return np.stack([lum, lum, lum], axis=-1)


# --- layers -------------------------------------------------------------------
def concrete(rng):
    low = fbm(rng, 3, 4)
    high = fbm(rng, 32, 3)
    pores = dots(rng, 260, 2.2)
    stains = fbm(rng, 3, 5)
    lum = 0.5 + (low - 0.5) * 0.18 + (high - 0.5) * 0.12 - pores * 0.18 - smoothstep(0.6, 0.8, stains) * 0.06
    rough = 0.5 + (high - 0.5) * 0.15 + pores * 0.1
    height = low * 0.4 + high * 0.6 - pores * 1.5
    return grey(lum), rough, height, 3.0


def rust_metal(rng):
    brushed = fbm(rng, 2, 3, stretch=(1, 48))
    rust_mask = smoothstep(0.56, 0.7, fbm(rng, 4, 5)) * (0.6 + 0.4 * fbm(rng, 24, 2))
    scratches = smoothstep(0.985, 0.998, ridged(rng, 12, 2)) * 0.6
    base = grey(0.5 + (brushed - 0.5) * 0.12 + scratches * 0.12)
    rust = np.stack([0.62, 0.36, 0.22]) * (0.8 + 0.4 * fbm(rng, 16, 3))[..., None]
    col = base * (1 - rust_mask[..., None]) + rust * rust_mask[..., None]
    rough = 0.42 + rust_mask * 0.5 - scratches * 0.1
    height = rust_mask * 0.8 * fbm(rng, 32, 2) - scratches * 0.5 + brushed * 0.1
    return col, rough, height, 2.5


def wood(rng):
    warp = fbm(rng, 3, 4) * 6.0
    y = np.arange(SIZE)[:, None] / SIZE
    grain = np.sin((y * 40.0 + warp) * np.pi * 2.0) * 0.5 + 0.5
    fibres = fbm(rng, 2, 3, stretch=(1, 64))
    knots = dots(rng, 5, 10)
    lum = 0.5 + (grain - 0.5) * 0.18 + (fibres - 0.5) * 0.15 - knots * 0.25
    col = grey(lum) * np.array([1.0, 0.97, 0.93])
    rough = 0.5 + (fibres - 0.5) * 0.2
    height = grain * 0.4 + fibres * 0.6 - knots
    return col, rough, height, 2.0


def plaster(rng):
    fine = fbm(rng, 24, 3)
    low = fbm(rng, 3, 4)
    cracks = smoothstep(0.965, 0.995, ridged(rng, 5, 4))
    speck = dots(rng, 120, 1.6)
    lum = 0.5 + (low - 0.5) * 0.12 + (fine - 0.5) * 0.1 - cracks * 0.15 - speck * 0.1
    rough = 0.5 + (fine - 0.5) * 0.1
    height = fine * 0.7 + low * 0.3 - cracks * 0.6
    return grey(lum), rough, height, 2.5


def stone(rng):
    grains = fbm(rng, 48, 3)
    mid = fbm(rng, 8, 4)
    chips = dots(rng, 90, 3.0)
    lum = 0.5 + (mid - 0.5) * 0.2 + (grains - 0.5) * 0.16 - chips * 0.2
    rough = 0.5 + (grains - 0.5) * 0.15
    height = grains * 0.5 + mid * 0.5 - chips * 1.3
    return grey(lum), rough, height, 3.5


def corrugated(rng):
    x = np.arange(SIZE)[None, :] / SIZE
    ribs = np.sin(x * 16 * np.pi * 2) * 0.5 + 0.5
    streaks = fbm(rng, 24, 2, stretch=(1, 0.1))
    rust = smoothstep(0.6, 0.75, fbm(rng, 6, 4, stretch=(1, 0.3)))
    base = grey(0.5 + (streaks - 0.5) * 0.25 + (ribs - 0.5) * 0.06)
    rust_col = np.stack([0.6, 0.38, 0.25]) * np.ones((SIZE, SIZE, 1))
    col = base * (1 - rust[..., None] * 0.8) + rust_col * rust[..., None] * 0.8
    rough = 0.45 + rust * 0.4 + (streaks - 0.5) * 0.1
    height = np.broadcast_to(ribs, (SIZE, SIZE)) * 1.0 + rust * 0.1
    return col, rough, height, 6.0


def fabric(rng):
    yy, xx = np.mgrid[0:SIZE, 0:SIZE] / SIZE
    weave = (np.sin(xx * 128 * np.pi) * np.sin(yy * 128 * np.pi)) * 0.5 + 0.5
    low = fbm(rng, 4, 4)
    lum = 0.5 + (weave - 0.5) * 0.12 + (low - 0.5) * 0.12
    rough = np.full((SIZE, SIZE), 0.55)
    height = weave
    return grey(lum), rough, height, 1.5


def main():
    rng = np.random.default_rng(1234)
    makers = {"concrete": concrete, "rust_metal": rust_metal, "wood": wood, "plaster": plaster, "stone": stone,
              "corrugated": corrugated, "fabric": fabric}
    albedo, normal = [], []
    for name in LAYERS:
        col, rough, height, strength = makers[name](rng)
        rgba = np.concatenate([np.clip(col, 0, 1), np.clip(rough, 0, 1)[..., None]], axis=-1)
        albedo.append((rgba * 255).astype(np.uint8))
        height = (height - height.min()) / max(height.max() - height.min(), 1e-6)
        normal.append((normal_from_height(height, strength) * 255).astype(np.uint8))
        print(f"layer {len(albedo) - 1}: {name}")
    out = os.path.join(ROOT, "assets", "textures")
    os.makedirs(out, exist_ok=True)
    Image.fromarray(np.concatenate(albedo, axis=0), "RGBA").save(os.path.join(out, "surfaces_albedo.png"), optimize=True)
    Image.fromarray(np.concatenate(normal, axis=0), "RGB").save(os.path.join(out, "surfaces_normal.png"), optimize=True)
    print("wrote assets/textures/surfaces_albedo.png, surfaces_normal.png")


if __name__ == "__main__":
    main()
