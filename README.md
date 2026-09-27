# 🎯 game-develop — FPS Desktop Game

A multiplayer **First-Person Shooter (FPS)** for desktop (Windows / Linux / macOS), built to **run smoothly on low-end PCs** while still scaling up to great visuals on powerful machines.

> **Status:** 🚧 Phase 6b — playable multiplayer shooter: Free-for-All, Team Deathmatch & Bomb Defusal, 5 weapons, 3 greybox maps, voice chat, host / join / dedicated server.

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
- 🎮 **Game modes** — Free-for-All, Team Deathmatch, Bomb Defusal (rounds, plant/defuse), offline Practice.
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
| Voice codec | **IMA-ADPCM** in pure GDScript (Opus GDExtension planned) | No native dependencies — runs everywhere Godot does; 16 kHz, 64 kbps only while talking. |
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
| Codec | **IMA-ADPCM** 4-bit, 16 kHz mono, 20 ms frames, 40 ms packets (≈64 kbps **only while talking**). Pure GDScript — an Opus GDExtension can replace `VoiceCodec` later to drop to ~24 kbps |
| Channels | **Team** (all teammates), **Proximity** (3D — nearby players hear you, with distance falloff), **All** (lobby/post-match) |
| Activation | **Push-to-Talk** (default key: `V`) or **Voice Activation** with adjustable threshold |
| Processing | High-pass filter, noise gate, automatic gain control (toggle in Settings). **No echo cancellation — use headphones** |
| Controls | Microphone selection, mic volume, voice volume, activation level, live mic meter, "hear myself" mic test, per-player mute and mute-all (Esc menu) |
| Playback | Per-speaker jitter buffer (60 ms prebuffer, 300 ms cap); proximity voice is 3D-positioned at the speaker's head |
| Transport | ENet channel 2 (unreliable-ordered), relayed through the server, which only forwards to eligible listeners and rate-limits each speaker |
| Privacy | Voice is never recorded or stored; players can disable voice chat entirely |
| UI | "MIC" indicator while you transmit, list of who is talking, green name tag and `»` in the scoreboard for speakers |
| Teams | The game is free-for-all until Phase 6, so *team* voice currently reaches everyone |

**Key scripts:** `scripts/voice/voice_chat.gd` (autoload `VoiceChat`), `voice_codec.gd`, `voice_processor.gd`, `voice_playback.gd`.

> **macOS:** exported builds need the microphone permission (`Export → macOS → Privacy → Microphone Usage Description`).

---

## 📁 Project Structure

```
game-develop/
├── addons/                  # Godot plugins / GDExtensions (e.g. Opus voice)
├── assets/
│   ├── shaders/             # prototype grid shader, etc.
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
│   ├── audio/
│   │   └── default_bus_layout.tres  # Master, Music, SFX, Voice, UI, MicCapture
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
│   ├── network/             # NetworkManager, player state sync, lag compensation
│   ├── audio/               # audio manager, occlusion, placeholder SFX
│   ├── levels/              # level base script, target dummies
│   ├── ui/                  # menus, HUD, crosshair
│   └── voice/               # voice capture, encode/decode, playback
├── tests/                   # smoke test + two-process multiplayer test
├── tools/                   # run_net_test.sh, greybox.py (map generator)
├── docs/                    # design documents
├── .editorconfig            # tabs for GDScript, LF line endings
├── .gitattributes           # line endings + Git LFS rules
├── .gitignore
├── icon.svg
├── project.godot
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

1. **Git** — <https://git-scm.com/>
2. **Git LFS** — <https://git-lfs.com/> (for large models, textures & audio)
3. **Godot 4.4+** (use the **.NET** build if working on C# code) — <https://godotengine.org/download>
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

### What is already set up

| File | Purpose |
|------|---------|
| `project.godot` | Project config: Forward+ renderer with automatic OpenGL fallback, Jolt physics, microphone input enabled, full input map, physics layer names |
| `scripts/core/settings_manager.gd` | **SettingsManager** autoload: graphics presets, display, audio, voice chat & controls; saves to `user://settings.cfg`; auto-detects a preset on first launch |
| `scripts/core/graphics_preset.gd` | `GraphicsPreset` resource type (render scale, FSR, AA, shadows, LOD, SSAO/SSR/SDFGI, fog…) |
| `resources/settings/graphics_presets/*.tres` | The Low / Medium / High / Ultra presets (edit in the Inspector) |
| `resources/audio/default_bus_layout.tres` | Audio buses; `MicCapture` (muted, with `AudioEffectCapture`) is where voice chat reads the microphone |
| `scenes/main/main_menu.tscn` | Main menu (offline / host / join) + settings panel (quality, fullscreen, V-Sync, volumes, voice chat & microphone) |

**Using the settings in a level:**

```gdscript
func _ready() -> void:
	SettingsManager.apply_to_environment($WorldEnvironment.environment)
	SettingsManager.apply_to_directional_light($Sun)
	SettingsManager.graphics_changed.connect(func(_p): SettingsManager.apply_to_environment($WorldEnvironment.environment))
```

> **Renderer note:** the Low preset uses the *Compatibility* (OpenGL 3.3) renderer. Godot can only pick the renderer at startup, so the game restarts itself once when needed (never from the editor). To test Low in the editor, run with `--rendering-method gl_compatibility`.

### Phase 1 — what you can play now

Press **Play (Test Map)** in the main menu:

| Feature | Details |
|---------|---------|
| Movement | Walk 5 m/s, sprint 8 m/s, crouch, **slide** (crouch while sprinting), jump with coyote time + jump buffer, air control |
| Camera | Mouse look (sensitivity/invert from settings), head bob, sprint FOV kick, recoil that recovers |
| Weapon | **AR-7 Assault Rifle** — hitscan, 650 RPM, spread + bloom, recoil, damage falloff, headshots ×2, ADS zoom, 30/120 ammo, 2 s reload |
| Targets | Dummies with body + head hitboxes; flash on hit, fall on death, respawn after 3 s; one strafing target |
| Test map | Cover boxes, ramp to a platform, stairs, crouch tunnel (1.4 m), jump blocks, long-range target |
| HUD | Dynamic crosshair (matches real spread), hit/kill markers, health, ammo, reload bar, damage flash, `F3` performance overlay |
| Pause (`Esc`) | Sensitivity, FOV, graphics preset, main menu, quit — game keeps running (multiplayer-ready) |

**Key scripts:** `scripts/player/player_controller.gd`, `scripts/weapons/weapon.gd`, `scripts/weapons/weapon_data.gd`, `scripts/core/health.gd`, `scripts/core/hitbox.gd`, `scripts/levels/level.gd`.
New weapons = new `WeaponData` `.tres` in `resources/weapons/` + a viewmodel scene using `weapon.gd`.

### Running the tests

```bash
godot --headless --path . res://tests/smoke_test.tscn
```

The smoke test drives the real player through the test map (walk, sprint, jump, crouch, slide, ADS, shooting, reload, ramp, stairs, pause, fall death + respawn, lag-compensation maths, voice codec quality, resampler, proximity voice rules, mic-test loopback, weapon switching, pistol semi-auto, shotgun pellets, sniper scope + one-shot, loadout on respawn, friendly fire, TDM scoring + match end, a full offline Bomb Defusal match — freeze, carry/drop/pickup, plant, defuse, explosion, elimination, halftime swap — and walking the ramps of Warehouse and Courtyard) and exits with code `0` when all checks pass. For the multiplayer test see *Testing multiplayer locally* below.

### Phase 4 — multiplayer

**Playing online**

| Main menu button | What it does |
|------------------|--------------|
| **Play Offline** | Single player on the test map (no network) |
| **Host Game** | Starts a *listen server* on the chosen port (default **7777/UDP**) and joins it yourself |
| **Join** | Connects to `IP` or `IP:port` (e.g. `192.168.1.20:7777`) |

- **LAN:** friends join with your local IP (`ipconfig` / `ip a`).
- **Internet:** forward **UDP 7777** on your router to the host PC, or use a VPN such as Tailscale / ZeroTier / Radmin VPN.
- **Dedicated server** (no graphics, very low CPU/RAM — good for a cheap VPS):
  ```bash
  ./FPSGame.x86_64 --headless -- --server --port 7777 --max-players 16 --mode tdm --map warehouse
  # from source:
  godot --headless --path . -- --server --port 7777 --mode ffa --map courtyard
  # --mode: ffa | tdm | bomb      --map: test_map | warehouse | courtyard
  ```

**How it works**

| Topic | Implementation |
|-------|----------------|
| Transport | Godot High-Level Multiplayer over **ENet** (UDP). Channel 0 = reliable events, 1 = player state (unreliable-ordered), 2 = voice chat (unreliable-ordered) |
| Authority | **Server-authoritative** health, damage, kills, deaths and respawns (`Health` only changes on the server and syncs to clients) |
| Movement | The owner simulates its own movement instantly (no input lag) and sends state 30×/s; the server **validates speed** and snaps cheaters back |
| Remote players | Snapshot buffer rendered **100 ms in the past** with interpolation → smooth even with jitter |
| Shooting | Shooter predicts effects locally; the server re-traces the shot with **lag compensation** (rewinds other players up to 400 ms to what the shooter saw), checks fire rate and muzzle position, then applies damage |
| Clock | Clients estimate server time from ping round-trips (used for interpolation and rewind) |
| Join flow | connect → register name → server sends map → client loads it → server sends existing players + health → spawns the new player everywhere |
| UI | Scoreboard (**Tab**: kills, deaths, ping), kill feed, ping in the `F3` overlay, name tags above players |

**Key scripts:** `scripts/network/network_manager.gd` (autoload), `scripts/network/player_net_sync.gd`, `scripts/network/lag_compensation.gd`, `scripts/weapons/weapon.gd` (`_server_fire`), `scripts/levels/level.gd`.

**Known limitations (next steps):** players pass through each other; ammo is not validated server-side yet (fire rate is); no NAT punch-through or encryption.

### Phase 6 — modes, weapons & maps

**Game modes** (chosen by the host; the main menu also picks the map)

| Mode | Rules |
|------|-------|
| **Practice** | Offline, any map, target dummies, no limits |
| **Free-for-All** | First to **20** kills, or most kills after **10 min** |
| **Team Deathmatch** | Blue vs Red, auto-balanced on join, **friendly fire off** (bullets pass through teammates), first team to **50** kills or most after **10 min** |
| **Bomb Defusal** | Rounds, first team to **5 round wins**; sides swap after round 4. See below |

Match flow: the server runs the clock and score → **results screen** (winner + scoreboard, 10 s) → **next map in the rotation** (Test Range → Warehouse → Courtyard → …), everyone stays connected. Players get **1.5 s spawn protection**, and respawn at the spawn point furthest from living enemies (team spawns in TDM). Enemy name tags are hidden behind walls; teammates' are always visible. In TDM, *team* voice (`V`) only reaches your team; use proximity (`B`) to talk to nearby enemies.

**Bomb Defusal**

| Rule | Detail |
|------|--------|
| Sides | Red attacks first, Blue defends; **sides swap at halftime** (after `rounds to win − 1` rounds) |
| Round | **5 s freeze** (can't move or shoot — pick your loadout) → **1:45** to plant → bomb timer **40 s** → 5 s round result |
| Bomb | Given to a random attacker when the round goes live; carried on their back (visible to others); **dropped where the carrier dies**, any attacker can walk over it to pick it up |
| Plant | Carrier stands still inside site **A** or **B** (orange floor + big letter) and **holds `E` for 3 s** |
| Defuse | A defender stands still next to the bomb and **holds `E` for 5 s** (anyone can interrupt by killing them) |
| Win a round | Attackers: bomb explodes (blast radius 15 m) or all defenders dead. Defenders: bomb defused, all attackers dead before a plant, or time runs out |
| Death | **No respawn during a round** — you spectate living teammates (`Shoot` = next); no health regen; next round revives everyone with full ammo |
| Joining | Freeze time waits until both teams have a player; joining mid-round = spectate until the next round |

Everything is server-authoritative (`scripts/core/bomb_rules.gd`): clients only send "holding E / released" and the server checks site, distance, standing still and timers. Bomb sites are `Marker3D`s in the level's `bomb_sites` list (`tools/greybox.py` → `m.site("A", pos)`).

**Weapons** — loadout = one primary + the pistol. Switch with `1` / `2` / mouse wheel; pick your primary in the `Esc` menu (applies on your next spawn).

| Weapon | Type | Damage | RPM | Mag | Notes |
|--------|------|--------|-----|-----|-------|
| AR-7 | Assault rifle | 24 | 650 | 30 | All-rounder |
| V-10 | SMG | 17 | 900 | 32 | Fast, accurate while moving, short range |
| M-12 | Shotgun | 9 × 13 | 70 | 6 | Pellets in one packet, deadly up close |
| LR-50 | Sniper | 110 | 45 | 5 | One-shot body kill, **scope overlay** (4× zoom) |
| P-9 | Pistol | 30 | 400 (semi) | 12 | Secondary for everyone |

All stats live in `resources/weapons/*.tres` (edit in the Inspector). Add a weapon: new `WeaponData` `.tres` + viewmodel scene using `weapon.gd`, register it in `scripts/core/game_config.gd`, and add an instance under the player's `WeaponHolder`.

**Maps**

| Map | Style | Features |
|-----|-------|----------|
| Test Range | Shooting range | Targets, ramp, stairs, crouch tunnel |
| Warehouse | Close quarters | Shelf aisles, crate stacks, raised catwalk with ramps, two offices |
| Courtyard | Outdoor, mid-range | Fountain plaza, pillars, low walls, two 2-storey buildings with roof access |

Warehouse and Courtyard are generated by **`tools/greybox.py`** (boxes, ramps, doors, spawns, lights). Edit the layout in Python and run `python3 tools/greybox.py` to rebuild the `.tscn` files; replace the greybox with real art later.

**Key scripts:** `scripts/core/match_manager.gd` (autoload `Match`), `scripts/core/bomb_rules.gd` (`Match.bomb`), `scripts/core/game_config.gd`, `scripts/levels/level.gd` (team + safe spawns, spectator), `scripts/levels/bomb_visual.gd`, `scripts/ui/hud.gd`, `scripts/ui/scope_overlay.gd`.

### Testing multiplayer locally

- **Automated:** `tools/run_net_test.sh /path/to/godot` starts a host and a client on localhost; it plays a **Team Deathmatch** round: teams auto-balance, the client walks, both talk over **proximity voice** (test tones must arrive at the right frequency, speaking indicators on/off), the client kills the host, the score limit ends the match on both sides, the server **rotates to Warehouse**, both players respawn there, and the client disconnects cleanly. A second pair then plays **Bomb Defusal** with real key presses: the client walks to site B and plants, the host walks over and defuses (Blue 1–0), the client eliminates the host (1–1), then plants again and the bomb explodes — Red wins 2–1 on both sides.
- **By hand:** in the Godot editor use **Debug → Customize Run Instances…** → 2–3 instances, press **F5**, then *Host* in one window and *Join* `127.0.0.1` in the others.

---

## 📦 Building & Exporting

1. In Godot: **Editor → Manage Export Templates → Download and Install**.
2. **Project → Export…**, add presets (first time only — this creates `export_presets.cfg`, commit it), then choose one:
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
| Switch weapon | `1` primary / `2` pistol / `Mouse Wheel` |
| Interact / plant / defuse (hold) | `E` |
| Throw grenade | `G` |
| **Push-to-talk (team)** | `V` |
| **Push-to-talk (proximity)** | `B` |
| Scoreboard | `Tab` |
| Text chat | `T` / `Y` (team) |
| Pause / Settings | `Esc` |
| Performance overlay | `F3` |

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
- **Network:** 30 Hz player state, target < 64 kbps per client excluding voice; voice adds ~64 kbps per active speaker (ADPCM) until Opus lands.
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

- [x] **Phase 0 — Setup:** repository, `.gitignore`, README, Godot project, Git LFS rules
- [x] **Phase 1 — Core gameplay:** player controller, camera, one weapon, test map, HUD, pause menu
- [ ] **Phase 2 — Settings:** ~~graphics presets, save/load settings~~ (base done) → full settings UI, key remapping, custom preset editor
- [ ] **Phase 3 — Audio:** 3D SFX, audio buses, occlusion, music
- [x] **Phase 4 — Multiplayer:** dedicated server, lobby, player sync, lag compensation, scoreboard, kill feed
- [x] **Phase 5 — Voice chat:** mic capture, ADPCM encode/decode, team & proximity channels, push-to-talk, voice activation, mute
- [ ] **Phase 5b — Opus codec** via GDExtension (lower bandwidth)
- [x] **Phase 6 — Content:** 5 weapons + loadouts, 3 maps, FFA & TDM with teams, match flow & map rotation, HUD & menus
- [x] **Phase 6b — Bomb Defusal:** rounds, freeze time, bomb carry/drop/plant/defuse/explode, no respawns + spectating, halftime side swap
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
