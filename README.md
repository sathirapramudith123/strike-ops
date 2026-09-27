# 🎯 game-develop — FPS Desktop Game

A multiplayer **First-Person Shooter (FPS)** for desktop (Windows / Linux / macOS), built to **run smoothly on low-end PCs** while still scaling up to great visuals on powerful machines.

> **Status:** 🚧 Pre-production — project setup stage.

---

## 📑 Table of Contents

1. [Project Goals](#-project-goals)
2. [Key Features](#-key-features)
3. [Tech Stack](#-tech-stack)
4. [System Requirements](#-system-requirements)
5. [Graphics Quality Presets](#-graphics-quality-presets)
6. [Audio & Voice Chat](#-audio--voice-chat)
7. [Project Structure](#-project-structure)
8. [Getting Started](#-getting-started)
9. [Building & Exporting](#-building--exporting)
10. [Controls](#-controls)
11. [Performance Guidelines](#-performance-guidelines)
12. [Git Workflow](#-git-workflow)
13. [Roadmap](#-roadmap)
14. [Contributing](#-contributing)
15. [License](#-license)

---

## 🎯 Project Goals

| Goal | Description |
|------|-------------|
| **Low-spec friendly** | Playable at **60 FPS on Low** preset with integrated graphics (Intel UHD 620 / AMD Vega 8) and 4 GB RAM. |
| **Scalable graphics** | Four presets — **Low, Medium, High, Ultra** — plus fully custom settings. |
| **Great audio** | 3D positional sound so players can hear footsteps, gunfire direction and distance. |
| **Voice chat** | Built-in in-game voice chat (team & proximity) with push-to-talk. |
| **Small download** | Target install size under **2 GB**. |

---

## ✨ Key Features

- 🔫 **Core FPS gameplay** — smooth first-person movement (walk, sprint, crouch, jump, slide), aim-down-sights, recoil & spread, hitscan and projectile weapons.
- 🌐 **Multiplayer** — client/server networking with lag compensation and client-side prediction.
- 🎮 **Game modes** (planned) — Team Deathmatch, Free-for-All, Bomb/Defuse.
- ⚙️ **Graphics presets** — Low / Medium / High / Ultra + auto-detect on first launch.
- 🔊 **3D spatial audio** — distance attenuation, occlusion, reverb zones.
- 🎙️ **Voice chat** — team channel, proximity chat, push-to-talk / voice activation, per-player mute.
- 🖱️ **Full input remapping** — keyboard/mouse and controller, mouse sensitivity & FOV sliders.
- 📊 **In-game performance overlay** — FPS, frame time, ping, packet loss.

---

## 🛠 Tech Stack

| Area | Technology | Why |
|------|------------|-----|
| Game engine | **[Godot 4.x](https://godotengine.org/)** | Free & open-source, tiny editor, excellent low-end support via the *Compatibility* (OpenGL 3.3) renderer, and *Forward+* (Vulkan) for High/Ultra. |
| Language | **GDScript** (gameplay) / **C#** (performance-critical systems) | Fast iteration + speed where needed. |
| Networking | Godot High-Level Multiplayer (**ENet**) | Reliable/unreliable UDP channels, built-in. |
| Voice codec | **Opus** (via GDExtension) | Industry standard, ~16–32 kbps per speaker, low latency. |
| Audio | Godot `AudioStreamPlayer3D` + Audio Buses | 3D positional audio, effects, per-bus volume. |
| 3D assets | **Blender** → `.glb` (glTF 2.0) | Open standard, imports natively. |
| Version control | **Git** + **Git LFS** | LFS for large binary assets. |

> The engine choice can be revisited during pre-production (Unity / Unreal are alternatives), but Godot is recommended because the editor and exported game both run well on weak hardware.

---

## 💻 System Requirements

### Minimum (Low preset, 720p–900p, 60 FPS target)

| Component | Requirement |
|-----------|-------------|
| OS | Windows 10 64-bit / Ubuntu 20.04+ / macOS 11+ |
| CPU | Dual-core 2.0 GHz (Intel Core i3 4th gen / AMD A8) |
| RAM | 4 GB |
| GPU | Intel HD 520 / UHD 620, AMD Vega 8 — **OpenGL 3.3** support |
| VRAM | 1 GB (shared OK) |
| Storage | 3 GB free |
| Network | Broadband, 256 kbps upload for voice chat |

### Recommended (High preset, 1080p, 60+ FPS)

| Component | Requirement |
|-----------|-------------|
| OS | Windows 10/11 64-bit / Ubuntu 22.04+ |
| CPU | Quad-core 3.0 GHz (Intel Core i5 8th gen / Ryzen 5 2600) |
| RAM | 8 GB |
| GPU | GTX 1050 Ti / RX 570 — **Vulkan** support |
| VRAM | 4 GB |
| Storage | 3 GB free (SSD recommended) |

### Ultra (1440p+, 100+ FPS)

GTX 1660 Super / RTX 2060 / RX 5600 XT or better, 16 GB RAM.

---

## 🖼 Graphics Quality Presets

The game picks a preset automatically on first launch (based on GPU & VRAM), and players can change it anytime in **Settings → Graphics**.

| Setting | 🟢 Low | 🟡 Medium | 🟠 High | 🔴 Ultra |
|---------|--------|-----------|---------|----------|
| Renderer | Compatibility (OpenGL 3.3) | Compatibility / Forward+ | Forward+ (Vulkan) | Forward+ (Vulkan) |
| Render scale | 70% | 85% | 100% | 100% |
| Upscaling | Bilinear | FSR 1.0 | FSR 2.2 (optional) | Off / FSR 2.2 Quality |
| Texture quality | Quarter-res (512 px max) | Half-res (1K) | Full (2K) | Full (4K) |
| Shadows | Off / blob shadows | 1 cascade, 1024 px | 2 cascades, 2048 px | 4 cascades, 4096 px, soft |
| Anti-aliasing | Off | FXAA | TAA / MSAA 2x | TAA + MSAA 4x |
| Draw distance | 50% | 75% | 100% | 125% |
| LOD bias | Aggressive | Normal | Detailed | Maximum |
| Foliage density | 25% | 50% | 100% | 100% |
| Ambient occlusion | Off | Off | SSAO | SSAO High |
| Global illumination | Baked lightmaps | Baked lightmaps | VoxelGI / SDFGI | SDFGI High |
| Reflections | Off | Reflection probes | SSR | SSR High |
| Post-processing | Off | Bloom | Bloom, tonemap | Bloom, DOF, motion blur (opt.) |
| Particles | 25% | 50% | 100% | 100% |
| Volumetric fog | Off | Off | On | On (high) |
| Target | 60 FPS @ iGPU | 60 FPS @ entry GPU | 60+ FPS @ mid GPU | 100+ FPS @ high-end GPU |

**Other display options:** resolution, window mode (fullscreen / borderless / windowed), V-Sync, FPS cap (30 / 60 / 120 / 144 / 240 / unlimited), field of view (70–110), brightness, and a *Custom* preset where every option can be changed individually.

Presets are defined as data (`resources/settings/graphics_presets/*.tres`) so they can be tuned without code changes.

---

## 🔊 Audio & Voice Chat

### Game audio

- **3D positional audio** for gunfire, footsteps, reloads and impacts.
- **Audio buses:** `Master` → `Music`, `SFX`, `Voice`, `UI` — each with its own volume slider.
- **Occlusion & reverb zones** so sounds behind walls are muffled and indoor areas echo.
- **Audio quality setting:** Low (22 kHz, fewer simultaneous voices) / High (48 kHz, up to 64 voices).
- Sound files: `.ogg` (Vorbis) for music & long sounds, `.wav` for short SFX.

### Voice chat

| Feature | Details |
|---------|---------|
| Codec | **Opus**, 16–32 kbps mono, 20 ms frames |
| Channels | **Team** (all teammates), **Proximity** (3D — nearby players hear you, with distance falloff), **All** (lobby/post-match) |
| Activation | **Push-to-Talk** (default key: `V`) or **Voice Activation** with adjustable threshold |
| Processing | Noise suppression, automatic gain control, echo cancellation (where supported) |
| Controls | Input/output device selection, mic volume, voice volume, per-player mute, mute-all |
| Transport | Unreliable-ordered ENet channel, relayed through the game server |
| Privacy | Voice is never recorded or stored; players can disable voice chat entirely |
| UI | Speaking indicator icon above players & in the scoreboard |

---

## 📁 Project Structure

```
game-develop/
├── addons/                  # Godot plugins / GDExtensions (e.g. Opus voice)
├── assets/
│   ├── audio/
│   │   ├── music/
│   │   ├── sfx/
│   │   └── ui/
│   ├── fonts/
│   ├── materials/
│   ├── models/              # .glb files exported from Blender
│   │   ├── characters/
│   │   ├── weapons/
│   │   └── environment/
│   ├── textures/
│   └── vfx/
├── resources/
│   ├── settings/
│   │   └── graphics_presets/   # low.tres, medium.tres, high.tres, ultra.tres
│   └── weapons/                # weapon stats as data resources
├── scenes/
│   ├── main/                # boot, main menu, loading screen
│   ├── levels/              # maps
│   ├── player/              # player controller, camera, viewmodel
│   ├── weapons/
│   └── ui/                  # HUD, settings menu, scoreboard
├── scripts/
│   ├── core/                # game manager, settings manager, save system
│   ├── player/              # movement, input, health
│   ├── weapons/             # shooting, recoil, ammo
│   ├── network/             # server, client, lag compensation
│   ├── audio/               # audio manager, occlusion
│   └── voice/               # voice capture, encode/decode, playback
├── tests/                   # automated tests (GUT)
├── tools/                   # build & helper scripts
├── docs/                    # design documents
├── .gitattributes           # Git LFS rules
├── .gitignore
├── export_presets.cfg
├── project.godot
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

1. **Git** — <https://git-scm.com/>
2. **Git LFS** — <https://git-lfs.com/> (for large models, textures & audio)
3. **Godot 4.x** (use the **.NET** build if working on C# code) — <https://godotengine.org/download>
4. *(Optional)* **.NET SDK 8+** — for C# scripts
5. *(Optional)* **Blender 4.x** — for 3D assets

### Clone & open

```bash
# 1. Install Git LFS once per machine
git lfs install

# 2. Clone the repository
git clone https://github.com/sathirapramudith123/game-develop.git
cd game-develop

# 3. Switch to the development branch
git checkout devlop

# 4. Pull LFS assets
git lfs pull
```

Then open **Godot → Import → select `project.godot` → Import & Edit**, and press **F5** to run the game.

### Testing multiplayer locally

In the Godot editor: **Debug → Customize Run Instances…** → enable multiple instances (e.g. 1 server + 2 clients), then press **F5**.

---

## 📦 Building & Exporting

1. In Godot: **Editor → Manage Export Templates → Download and Install**.
2. **Project → Export…** and choose a preset:
   - `Windows Desktop` → `builds/windows/`
   - `Linux/X11` → `builds/linux/`
   - `macOS` → `builds/macos/`
3. Click **Export Project** (uncheck *Export With Debug* for release builds).

Command-line export (for CI):

```bash
godot --headless --export-release "Windows Desktop" builds/windows/FPSGame.exe
godot --headless --export-release "Linux/X11"       builds/linux/FPSGame.x86_64
```

Dedicated server (no graphics, low CPU usage):

```bash
./FPSGame.x86_64 --headless -- --server --port 7777
```

> The `builds/` folder is git-ignored — share builds through GitHub Releases instead.

---

## 🎮 Controls

| Action | Default key |
|--------|-------------|
| Move | `W` `A` `S` `D` |
| Jump | `Space` |
| Crouch / Slide | `Left Ctrl` / `C` |
| Sprint | `Left Shift` |
| Shoot | `Left Mouse` |
| Aim down sights | `Right Mouse` |
| Reload | `R` |
| Switch weapon | `1`–`4` / `Mouse Wheel` |
| Interact | `E` |
| Throw grenade | `G` |
| **Push-to-talk (team)** | `V` |
| **Push-to-talk (proximity)** | `B` |
| Scoreboard | `Tab` |
| Text chat | `T` / `Y` (team) |
| Pause / Settings | `Esc` |

All keys can be remapped in **Settings → Controls**.

---

## ⚡ Performance Guidelines

Rules every contributor follows so the game stays playable on low-end PCs:

- **Frame budget:** 16.6 ms (60 FPS) on the minimum-spec machine with the Low preset.
- **Polygon budgets:** characters ≤ 15k tris (LOD0), weapons (first-person) ≤ 10k tris, every mesh must have **at least 2 LODs**.
- **Textures:** max 2048×2048 (4K only for Ultra), use VRAM-compressed formats, power-of-two sizes.
- **Draw calls:** keep under ~1,000 per frame on Low; use MultiMesh for repeated props and foliage.
- **Lighting:** prefer **baked lightmaps**; limit real-time shadow-casting lights.
- **Occlusion culling:** enable `OccluderInstance3D` in all maps.
- **Scripts:** avoid heavy work in `_process()`; use object pooling for bullets, decals and particles.
- **Network:** 30–60 Hz server tick, delta-compressed snapshots, target < 64 kbps per client (voice included).
- **Test every feature on the Low preset** before merging.

---

## 🌿 Git Workflow

| Branch | Purpose |
|--------|---------|
| `main` | Stable, playable releases only |
| `devlop` | Active development — all features merge here |
| `feature/<name>` | New features (e.g. `feature/voice-chat`) |
| `fix/<name>` | Bug fixes |

**Commit messages** follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(weapons): add recoil pattern for assault rifle
fix(voice): prevent echo when push-to-talk is released
perf(graphics): reduce shadow cascades on Low preset
docs: update system requirements
```

**Large files:** track binary assets with Git LFS, for example:

```bash
git lfs track "*.glb" "*.fbx" "*.blend" "*.png" "*.jpg" "*.psd" "*.wav" "*.ogg" "*.mp3" "*.ttf"
```

The `.gitignore` already excludes engine caches (`.godot/`), builds, logs, secrets (`.env`, keys) and IDE/OS files.

---

## 🗺 Roadmap

- [ ] **Phase 0 — Setup:** repository, `.gitignore`, README, Godot project, Git LFS
- [ ] **Phase 1 — Core gameplay:** player controller, camera, one weapon, test map
- [ ] **Phase 2 — Settings:** graphics presets (Low/Medium/High/Ultra), audio & control settings, save/load settings
- [ ] **Phase 3 — Audio:** 3D SFX, audio buses, occlusion, music
- [ ] **Phase 4 — Multiplayer:** dedicated server, lobby, player sync, lag compensation
- [ ] **Phase 5 — Voice chat:** mic capture, Opus encode/decode, team & proximity channels, push-to-talk
- [ ] **Phase 6 — Content:** more weapons, 2–3 maps, game modes, HUD & menus
- [ ] **Phase 7 — Optimization:** profiling on minimum-spec hardware, LODs, occlusion, auto-detect preset
- [ ] **Phase 8 — Release:** installers, anti-cheat basics, beta testing, v1.0

---

## 🤝 Contributing

1. Create a branch from `devlop`: `git checkout -b feature/my-feature devlop`
2. Make your changes and test them on the **Low** preset.
3. Commit using Conventional Commits.
4. Push and open a Pull Request into `devlop`.

Please keep scripts small and focused, name files in `snake_case`, and nodes/classes in `PascalCase`.

---

## 📄 License

License not yet selected. Until a `LICENSE` file is added, all rights are reserved by the project owner.

Third-party assets (models, sounds, fonts) must list their source and license in `docs/CREDITS.md`.
