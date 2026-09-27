#!/usr/bin/env python3
"""Turns players' hardware reports into preset tuning (Phase 7b).

Players run Settings → Graphics → "Full hardware test" and send the report
(GitHub issue "Hardware report", or the JSON from the game's user folder:
benchmarks/hardware_report_*.json). Put the JSON files in one folder, then:

    tools/tune_presets.py reports/*.json            # analysis + suggestions
    tools/tune_presets.py reports/*.json --apply    # also update gpu_tiers.cfg
    tools/tune_presets.py --self-test               # checks this script (CI)

What it tells you:
  • per GPU: which preset is smooth (≥ 60 FPS avg, ≥ 50 FPS 1% low)
  • the render scale the Low preset needs on minimum-spec GPUs
    (fitted from the 0.5 / 0.7 / 1.0 measurements; CPU-bound PCs are flagged)
  • whether OpenGL or Vulkan is faster for Low on weak GPUs
  • what every option costs on integrated vs discrete GPUs → what to drop
    from High first / what Low could afford
  • --apply writes the measured "GPU → starting preset" entries to
    resources/settings/gpu_tiers.cfg (used by the first-launch auto-detect)

Preset values themselves (resources/settings/graphics_presets/*.tres) are
only suggested, never changed automatically — review them first.
"""
import argparse
import datetime
import json
import math
import os
import re
import statistics
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TIERS_PATH = os.path.join(ROOT, "resources", "settings", "gpu_tiers.cfg")
PRESET_DIR = os.path.join(ROOT, "resources", "settings", "graphics_presets")
PRESETS = ["Low", "Medium", "High", "Ultra"]
TARGET_AVG_FPS = 60.0
TARGET_LOW_FPS = 50.0
TARGET_MS = 1000.0 / TARGET_AVG_FPS
# Minimum-spec class (README): Intel UHD 620 / AMD Vega 8 and similar iGPUs.
SOFTWARE = re.compile(r"llvmpipe|softpipe|swiftshader|software|basic render", re.I)
MIN_SPEC = re.compile(r"uhd graphics|hd graphics|iris|vega \d|radeon graphics|radeon\(tm\) graphics", re.I)


# ----------------------------------------------------------------------------
# Helpers shared with the game (keep normalize_gpu() in sync with
# SettingsManager.normalize_gpu_name()).
# ----------------------------------------------------------------------------

def normalize_gpu(name):
    """'Mesa Intel(R) UHD Graphics 620 (KBL GT2)' → 'intel uhd graphics 620'."""
    s = name.lower()
    s = re.sub(r"\((r|tm)\)", "", s)
    s = s.split("/")[0]
    while True:
        t = re.sub(r"\s*\([^()]*\)\s*$", "", s)
        if t == s:
            break
        s = t
    s = re.sub(r"^mesa\s+", "", s)
    return re.sub(r"\s+", " ", s).strip()


def load_reports(paths, include_quick=False):
    reports = []
    for p in paths:
        try:
            with open(p, encoding="utf-8") as f:
                r = json.load(f)
        except (OSError, ValueError) as e:
            print(f"! skipped {p}: {e}", file=sys.stderr)
            continue
        if "results" not in r or "system" not in r:
            print(f"! skipped {p}: not a hardware report", file=sys.stderr)
            continue
        if r.get("quick") and not include_quick:
            print(f"! skipped {p}: quick test (use --include-quick)", file=sys.stderr)
            continue
        r["_path"] = p
        r["_gpu"] = normalize_gpu(r["system"]["gpu"])
        reports.append(r)
    return reports


def by_name(report):
    return {e["name"]: e for e in report["results"]}


def verdict(e):
    if e["avg_fps"] >= TARGET_AVG_FPS and e["low_fps"] >= TARGET_LOW_FPS:
        return "smooth"
    return "playable" if e["low_fps"] >= 30 else "too slow"


def is_min_spec(report):
    return report["system"].get("gpu_type") == "integrated" or bool(MIN_SPEC.search(report["system"]["gpu"]))


def read_tres(name):
    values = {}
    try:
        with open(os.path.join(PRESET_DIR, name.lower() + ".tres"), encoding="utf-8") as f:
            for line in f:
                m = re.match(r"^(\w+) = (.+)$", line.strip())
                if m:
                    values[m.group(1)] = m.group(2).strip('"')
    except OSError:
        pass
    return values


def fit_render_scale(points, target_ms=TARGET_MS):
    """points: [(scale, frame_ms)]. Frame time ≈ a + b·scale² (fixed cost +
    per-pixel cost). Returns (scale for target or None, a, b)."""
    xs = [s * s for s, _ in points]
    ys = [ms for _, ms in points]
    n = len(points)
    mx, my = sum(xs) / n, sum(ys) / n
    var = sum((x - mx) ** 2 for x in xs)
    if var <= 0:
        return None, my, 0.0
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / var
    a = my - b * mx
    if b <= 0 or a >= target_ms:
        return None, a, b  # not pixel-bound (CPU / driver limit)
    s = math.sqrt((target_ms - a) / b)
    return max(0.5, min(1.0, round(s * 20) / 20)), a, b


# ----------------------------------------------------------------------------
# Analysis
# ----------------------------------------------------------------------------

def analyse(reports, out=print):
    suggestions = []
    tiers = {}
    out(f"{len(reports)} report(s)\n")
    out(f"{'GPU':40} {'type':10} {'Low':>9} {'Medium':>9} {'High':>9} {'Ultra':>9}  best")
    for r in reports:
        names = by_name(r)
        cells = []
        for p in PRESETS:
            e = names.get(p)
            cells.append(f"{e['avg_fps']:.0f}/{e['low_fps']:.0f}" if e else "—")
        best = r.get("recommended") or "Low*"
        out(f"{r['system']['gpu'][:40]:40} {r['system'].get('gpu_type', '?'):10} "
            + " ".join(f"{c:>9}" for c in cells) + f"  {best}")
        # Most conservative preset per GPU model (software renderers are
        # already forced to Low by the game).
        if SOFTWARE.search(r["system"]["gpu"]) or r["system"].get("gpu_type") in ("cpu", "virtual"):
            continue
        want = r.get("recommended") or "Low"
        old = tiers.get(r["_gpu"])
        if old is None or PRESETS.index(want) < PRESETS.index(old["preset"]):
            low = names.get("Low", {})
            tiers[r["_gpu"]] = {"preset": want, "reports": 1 + (old["reports"] if old else 0),
                                "detail": f"Low {low.get('avg_fps', 0):.0f}/{low.get('low_fps', 0):.0f} fps"}
        else:
            old["reports"] += 1
    out("  (cells: average FPS / 1% low FPS; * = nothing smooth)\n")

    # 1. Minimum-spec GPUs: is Low good enough, and at which render scale?
    low_scale = float(read_tres("Low").get("render_scale", 0.7))
    min_spec = [r for r in reports if is_min_spec(r)]
    out(f"Minimum-spec GPUs (integrated): {len(min_spec)}")
    scales = []
    for r in min_spec:
        n = by_name(r)
        low = n.get("Low")
        if not low:
            continue
        pts = [(low_scale, low["avg_frame_ms"])]
        for s in (0.5, 1.0):
            e = n.get(f"Low, render scale {s}")
            if e:
                pts.append((s, e["avg_frame_ms"]))
        scale, a, b = fit_render_scale(pts) if len(pts) >= 2 else (None, 0, 0)
        state = verdict(low)
        line = f"  {r['system']['gpu']}: Low {low['avg_fps']:.0f} avg / {low['low_fps']:.0f} 1% low ({state})"
        if scale is None and a >= TARGET_MS:
            line += f" — CPU/driver bound (~{a:.1f} ms even at tiny resolution): render scale can't fix it"
            suggestions.append(f"{r['system']['gpu']}: CPU-bound on Low ({a:.1f} ms fixed cost) — "
                               "reduce draw calls / node count / bots, not resolution")
        elif scale is not None:
            line += f" — 60 FPS at render scale ≈ {scale:.2f}"
            scales.append(scale)
        out(line)
    if scales:
        target = min(scales)
        if abs(target - low_scale) >= 0.05:
            suggestions.append(f"low.tres: render_scale {low_scale:.2f} → {target:.2f} "
                               f"(the slowest minimum-spec GPU reaches 60 FPS there)")
        else:
            out(f"  Low's render scale {low_scale:.2f} fits the minimum spec.")

    # 2. OpenGL vs Vulkan for Low on weak GPUs.
    faster = []
    for r in min_spec:
        n = by_name(r)
        if "Low" in n and "Low (Vulkan)" in n:
            faster.append(n["Low (Vulkan)"]["avg_frame_ms"] / max(n["Low"]["avg_frame_ms"], 0.01))
    if faster:
        ratio = statistics.median(faster)
        out(f"  Vulkan / OpenGL frame time for Low (median): {ratio:.2f}")
        if ratio < 0.9:
            suggestions.append(f"low.tres: Vulkan is {100 * (1 - ratio):.0f}% faster than OpenGL on these iGPUs — "
                               "consider rendering_method = forward_plus for Low")

    # 3. Option costs by GPU class.
    out("\nOption costs (median extra frame time)")
    costs = {}
    for r in reports:
        cls = "integrated" if is_min_spec(r) else "discrete"
        for c in r.get("option_costs", []):
            costs.setdefault(c["name"], {}).setdefault(cls, []).append((c["delta_ms"], c["delta_pct"]))
    out(f"  {'option':28} {'integrated':>18} {'discrete':>18}")
    ranked = []
    for name, per in costs.items():
        cols = []
        for cls in ("integrated", "discrete"):
            v = per.get(cls)
            cols.append(f"{statistics.median(x for x, _ in v):+.1f} ms {statistics.median(p for _, p in v):+.0f}%"
                        if v else "—")
        out(f"  {name:28} {cols[0]:>18} {cols[1]:>18}")
        if "discrete" in per:
            ranked.append((statistics.median(p for _, p in per["discrete"]), name))
        if name.startswith("Low +") and "integrated" in per:
            pct = statistics.median(p for _, p in per["integrated"])
            if pct < 3.0:
                suggestions.append(f"low.tres: '{name[6:]}' costs only {pct:+.0f}% on minimum-spec GPUs — could be enabled")
    ranked.sort(reverse=True)
    high = [r for r in reports if "High" in by_name(r) and not is_min_spec(r)]
    if high and ranked:
        not_smooth = [r for r in high if verdict(by_name(r)["High"]) != "smooth"]
        if len(not_smooth) * 2 > len(high):
            order = ", ".join(n.replace("Medium + ", "").replace("Medium, ", "") for _, n in ranked[:3])
            suggestions.append(f"high.tres: High isn't smooth on most discrete GPUs tested — drop the most expensive first: {order}")

    out("\nSuggested starting presets (gpu_tiers.cfg)")
    for gpu, t in sorted(tiers.items()):
        out(f"  [{gpu}] preset={t['preset'].lower()}  ({t['reports']} report(s), {t['detail']})")
    out("\nSuggestions")
    for s in suggestions or ["(none — presets fit the measured PCs)"]:
        out(f"  • {s}")
    return tiers, suggestions


def apply_tiers(tiers, path=TIERS_PATH):
    """Adds / updates measured GPUs at the top of gpu_tiers.cfg (they are more
    specific than the seeded patterns below them)."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    head, _, body = text.partition("\n[")
    body = "[" + body if body else ""
    sections = re.split(r"\n(?=\[)", body.strip()) if body.strip() else []
    existing = {}
    order = []
    for sec in sections:
        m = re.match(r"\[(.+?)\]", sec)
        if m:
            existing[m.group(1)] = sec.strip()
            order.append(m.group(1))
    today = datetime.date.today().isoformat()
    new = []
    for gpu, t in sorted(tiers.items()):
        new.append(gpu)
        existing[gpu] = (f"[{gpu}]\npreset=\"{t['preset'].lower()}\"\n"
                         f"source=\"measured {today}: {t['reports']} report(s), {t['detail']}\"")
    final = new + [g for g in order if g not in new]
    with open(path, "w", encoding="utf-8") as f:
        f.write(head.rstrip() + "\n\n" + "\n\n".join(existing[g] for g in final) + "\n")
    return final


# ----------------------------------------------------------------------------
# Self-test (CI)
# ----------------------------------------------------------------------------

def _fake_report(gpu, gpu_type, low_ms, pixel_ms, presets_fps, costs=()):
    def entry(name, ms, preset=0):
        return {"name": name, "renderer": "gl_compatibility", "preset": preset, "vs": "",
                "avg_fps": round(1000 / ms, 1), "low_fps": round(1000 / ms * 0.8, 1),
                "avg_frame_ms": ms, "low_frame_ms": ms / 0.8}
    res = [entry("Low", low_ms + pixel_ms * 0.49),
           entry("Low, render scale 0.5", low_ms + pixel_ms * 0.25),
           entry("Low, render scale 1.0", low_ms + pixel_ms * 1.0)]
    for i, fps in enumerate(presets_fps, start=1):
        res.append(entry(PRESETS[i], 1000 / fps, i))
    r = {"format": 1, "quick": False, "system": {"gpu": gpu, "gpu_type": gpu_type},
         "results": res, "option_costs": [{"name": n, "delta_ms": d, "delta_pct": p} for n, d, p in costs]}
    best = ""
    for p in reversed(PRESETS):
        e = next((x for x in res if x["name"] == p), None)
        if e and verdict(e) == "smooth":
            best = p
            break
    r["recommended"] = best
    r["_gpu"] = normalize_gpu(gpu)
    return r


def self_test():
    ok = True

    def check(cond, label):
        nonlocal ok
        print(("  ✔ " if cond else "  ✘ ") + label)
        ok = ok and cond

    check(normalize_gpu("Mesa Intel(R) UHD Graphics 620 (KBL GT2)") == "intel uhd graphics 620", "normalize Mesa name")
    check(normalize_gpu("NVIDIA GeForce GTX 1050/PCIe/SSE2") == "nvidia geforce gtx 1050", "normalize NVIDIA name")
    check(normalize_gpu("AMD Radeon(TM) Vega 8 Graphics") == "amd radeon vega 8 graphics", "normalize AMD name")
    s, a, b = fit_render_scale([(0.5, 10 + 20 * 0.25), (0.7, 10 + 20 * 0.49), (1.0, 30)])
    check(s is not None and abs(s - 0.6) < 0.051 and abs(a - 10) < 0.01, f"render-scale fit (scale {s})")
    s, a, _ = fit_render_scale([(0.5, 20), (0.7, 20.2), (1.0, 20.5)])
    check(s is None and a > TARGET_MS, "CPU-bound PC detected")

    reports = [
        # Weak iGPU: 10 ms fixed + 20 ms per full-res frame → Low (0.7) = 19.8 ms.
        _fake_report("Intel(R) UHD Graphics 620", "integrated", 10, 20, [30, 20, 12],
                     [("Low + glow", 0.1, 1.0), ("Low + shadows", 4.0, 20.0)]),
        _fake_report("NVIDIA GeForce GTX 1650/PCIe/SSE2", "discrete", 3, 4, [90, 45, 30],
                     [("Medium + SSAO", 3.0, 25.0), ("Medium + SSR", 1.0, 8.0), ("Medium + MSAA 2×", 2.0, 15.0)]),
    ]
    lines = []
    tiers, sugg = analyse(reports, out=lines.append)
    text = "\n".join(lines) + "\n" + "\n".join(sugg)
    check(tiers.get("intel uhd graphics 620", {}).get("preset") == "Low", "iGPU tier = Low")
    check(tiers.get("nvidia geforce gtx 1650", {}).get("preset") == "Medium", "GTX 1650 tier = Medium")
    check("render_scale" in text and "→ 0.60" in text, "suggests Low render scale 0.60")
    check("glow" in text and "could be enabled" in text, "cheap Low option suggested")
    check("drop the most expensive first: SSAO" in text, "High: drop SSAO first")

    tmp = tempfile.NamedTemporaryFile("w", suffix=".cfg", delete=False, encoding="utf-8")
    tmp.write("; header\n\n[uhd graphics 6]\npreset=\"low\"\nsource=\"spec\"\n")
    tmp.close()
    order = apply_tiers(tiers, tmp.name)
    with open(tmp.name, encoding="utf-8") as f:
        cfg = f.read()
    os.unlink(tmp.name)
    check(order[-1] == "uhd graphics 6" and cfg.startswith("; header")
          and "[nvidia geforce gtx 1650]\npreset=\"medium\"" in cfg, "--apply keeps header + seeds, adds measured GPUs first")
    print("PASSED" if ok else "FAILED")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reports", nargs="*", help="hardware_report_*.json files")
    ap.add_argument("--apply", action="store_true", help="write measured GPU tiers to gpu_tiers.cfg")
    ap.add_argument("--include-quick", action="store_true", help="also use quick (short) test runs")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    reports = load_reports(args.reports, args.include_quick)
    if not reports:
        print("No hardware reports. Players: Settings → Graphics → Full hardware test → Send / Open folder.")
        return 1
    tiers, _ = analyse(reports)
    if args.apply:
        apply_tiers(tiers)
        print(f"\nUpdated {os.path.relpath(TIERS_PATH)} ({len(tiers)} GPU(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
