# 🎯 game-develop — FPS Desktop Game

A multiplayer **First-Person Shooter (FPS)** for desktop (Windows / Linux / macOS), built to **run smoothly on low-end PCs** while still scaling up to great visuals on powerful machines.

> **Status:** 🧪 **v0.9.0 beta** — builds for Windows, Linux, macOS and a Linux dedicated server: FFA, TDM, Bomb Defusal; 5 weapons; 11 maps with a map picker + end-of-match vote; keyboard/mouse **and controller**; Opus voice chat; 3D audio; anti-cheat. v1.0 follows after real-hardware reports and beta feedback.

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
| Voice codec | **Opus** (libopus 1.5, C++ GDExtension) with **IMA-ADPCM** fallback in pure GDScript | Opus: ~24 kbps with packet-loss recovery; ADPCM (64 kbps) keeps voice working for anyone without the extension. |
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

**Other display options:** window mode (windowed / borderless / exclusive fullscreen), window size, V-Sync, FPS cap (30–240 / unlimited), field of view (70–110), brightness, and a *Custom* preset — change any single option in **Settings → Graphics** and the preset becomes *Custom* (saved and restored on the next launch).

Presets are defined as data (`resources/settings/graphics_presets/*.tres`) so they can be tuned without code changes.

---

## 🔊 Audio & Voice Chat

### Game audio

- **3D positional audio** for gunfire (a different sound per weapon), footsteps, jumps, landings, slides, reloads, impacts and near-miss bullet whizzes.
- **Audio buses:** `Master` (with a limiter) → `Music`, `SFX`, `Voice`, `UI` — each with its own volume slider.
- **Occlusion & reverb zones** so sounds behind walls are muffled and indoor areas echo.
- **Audio quality setting:** Low (16 sounds at once, no reverb) / High (40 sounds, reverb, continuous occlusion).
- **Music:** menu theme and quiet in-match music, win/lose stings.
- Every sound works without audio files (generated placeholders); drop `.ogg`/`.wav` files into `assets/audio/` to replace them — see *Phase 3* below.

### Voice chat

| Feature | Details |
|---------|---------|
| Codec | **Opus** 16 kHz mono, 40 ms packets, **≈24 kbps only while talking** (was 64 kbps), with forward error correction + loss concealment. Falls back to **IMA-ADPCM** (pure GDScript, 64 kbps) automatically when any player lacks Opus — see *Phase 5b* |
| Channels | **Team** (all teammates), **Proximity** (3D — nearby players hear you, with distance falloff), **All** (lobby/post-match) |
| Activation | **Push-to-Talk** (default key: `V`) or **Voice Activation** with adjustable threshold |
| Processing | High-pass filter, noise gate, automatic gain control (toggle in Settings). **No echo cancellation — use headphones** |
| Controls | Microphone selection, mic volume, voice volume, activation level, live mic meter, "hear myself" mic test, per-player mute and mute-all (Esc menu) |
| Playback | Per-speaker jitter buffer (60 ms prebuffer, 300 ms cap); proximity voice is 3D-positioned at the speaker's head |
| Transport | ENet channel 2 (unreliable-ordered), relayed through the server, which only forwards to eligible listeners and rate-limits each speaker |
| Privacy | Voice is never recorded or stored; players can disable voice chat entirely |
| UI | "MIC" indicator while you transmit, list of who is talking, green name tag and `»` in the scoreboard for speakers |
| Teams | The game is free-for-all until Phase 6, so *team* voice currently reaches everyone |

**Key scripts:** `scripts/voice/voice_chat.gd` (autoload `VoiceChat`), `voice_codec.gd`, `voice_encoder.gd`, `voice_decoder.gd`, `voice_processor.gd`, `voice_playback.gd`.

### Phase 5b — Opus voice codec

Voice uses **[Opus](https://opus-codec.org/)**, the codec used by Discord, WebRTC and most games, through a small C++ **GDExtension** (`addons/opus_voice`, source in `native/opus_voice`).

| | ADPCM (before) | **Opus (now)** |
|---|---|---|
| Bandwidth while talking | 64 kbps (324 B / 40 ms) | **≈24 kbps** (~120 B / 40 ms) — about **⅓** |
| Lost packets | a 40 ms gap | rebuilt from the next packet (**in-band FEC**); longer gaps are smoothly **concealed** |
| Sound | 4-bit, slightly hissy | clear, made for speech |
| Needs | nothing | the extension (included for Windows, Linux, macOS) |

**Compatibility is automatic.** Every packet starts with a codec byte. When a player joins they tell the server whether they have Opus; if **everyone** in the match has it, voice is sent as Opus, otherwise everyone sends ADPCM, so one player without Opus (e.g. a source build for a platform without the library) never goes unheard. A dedicated server only relays packets, so it doesn't need Opus. The log shows the active codec at startup (`[voice] codec: Opus (libopus 1.5.2)`), and **Settings → Voice → Opus codec** can switch it off.

**Included libraries** (`addons/opus_voice/bin/`, committed so a fresh clone just works):

| Platform | File | Notes |
|----------|------|-------|
| Windows x86-64 | `libopus_voice.windows.x86_64.dll` | Only needs system DLLs |
| Linux x86-64 | `libopus_voice.linux.x86_64.so` | Runs on glibc 2.16+ (any distro Godot supports) |
| macOS Apple Silicon | `libopus_voice.macos.arm64.dylib` | Ad-hoc signed |
| macOS Intel | `libopus_voice.macos.x86_64.dylib` | |

libopus 1.5.2 and godot-cpp are linked in statically; their licenses (BSD-3 / MIT) ship in every package as `THIRD_PARTY_LICENSES.txt`.

**Rebuilding the libraries** (only needed if you change `native/opus_voice/src/`):

```bash
pip install ziglang            # Linux + macOS builds (portable glibc, cross-compiles macOS)
sudo apt install mingw-w64 cmake
tools/build_opus.sh            # all three platforms from Linux → addons/opus_voice/bin/
tools/build_opus.sh linux      # or one platform (on a Mac: macos; on Windows with CMake + VS: windows)
godot --headless --path . --import   # let Godot register the extension
```

The script downloads pinned sources (godot-cpp 4.4, libopus 1.5.2 with SHA-256 check). CI rebuilds all four libraries whenever `native/` changes (workflow *Opus extension*) and checks that Opus loads on real Windows and macOS runners (`tests/opus_check.gd`).

| Script / file | Role |
|---------------|------|
| `native/opus_voice/src/opus_voice.cpp` | `OpusVoiceEncoder` (VOIP mode, 24 kbps, FEC, complexity 5) and `OpusVoiceDecoder` (decode, FEC, concealment) |
| `scripts/voice/voice_encoder.gd` / `voice_decoder.gd` | Pick the codec per packet, pad/trim the last packet of a sentence, rebuild lost packets |
| `VoiceChat.use_opus_for()` | The "everyone has Opus?" rule |

> **macOS:** exported builds need the microphone permission (`Export → macOS → Privacy → Microphone Usage Description`).

---

## 📁 Project Structure

```
game-develop/
├── addons/opus_voice/       # Opus voice codec GDExtension (+ prebuilt libraries in bin/)
├── native/opus_voice/       # its C++ source + CMake build (tools/build_opus.sh)
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
│   ├── audio/               # Audio autoload (pooling, occlusion, music), sound synthesiser
│   ├── levels/              # level base script, target dummies
│   ├── ui/                  # menus, HUD, crosshair
│   └── voice/               # voice capture, encode/decode, playback
├── tests/                   # smoke test + two-process multiplayer test
├── tools/                   # build_release.sh, run_net_test.sh, run_benchmark.sh, greybox.py, build_opus.sh
├── installer/               # Windows (Inno Setup) + Linux (.desktop) + player README
├── server/                  # dedicated server: run script, README, Dockerfile, compose
├── .github/                 # CI + release workflows, issue templates
├── export_presets.cfg       # Windows, Linux, macOS, Linux Server
├── CHANGELOG.md
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
| `resources/audio/default_bus_layout.tres` | Audio buses; `MicCapture` (muted, with `AudioEffectCapture`) is where voice chat reads the microphone; `SFXOccluded` (low-pass), `ReverbRoom` / `ReverbHall` feed `SFX`; limiter on `Master` |
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

The smoke test drives the real player through the test map (walk, sprint, jump, crouch, slide, ADS, shooting, reload, ramp, stairs, pause, fall death + respawn, lag-compensation maths, voice codec quality, resampler, proximity voice rules, mic-test loopback, weapon switching, pistol semi-auto, shotgun pellets, sniper scope + one-shot, loadout on respawn, friendly fire, TDM scoring + match end, a full offline Bomb Defusal match — freeze, carry/drop/pickup, plant, defuse, explosion, elimination, halftime swap — the settings screen (custom graphics, rebinding + swap + persistence, the new key really jumps and the old one doesn't, toggle aim/crouch, crosshair, reset) and the end-of-match map vote, walking the ramps/bridges/gangways of every map, the Kasbah terrace, doors and covered corridor, routes through Factory, Office, Subway (platforms, track beds, the train) and Train Yard, the radar outline and location names, first-person arms and the reload animations, and spawns + bomb sites on all maps) and exits with code `0` when all checks pass. For the multiplayer test see *Testing multiplayer locally* below.

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
  # --mode: ffa | tdm | bomb      --map: test_map | warehouse | courtyard | rooftops | docks | bunker
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

**Anti-cheat (server-side):** the server keeps its own ammo count and reload timer for every weapon, and checks fire rate, muzzle position, movement speed and upward "fly" speed. Each impossible action is logged as `[anticheat]`; more than 25 within 10 s gets the player kicked with a message ("Kicked by anti-cheat (…)"). Limits are generous so bad connections never trip them (normal play in the tests logs zero violations).

**Known limitations (next steps):** players pass through each other; no NAT punch-through or encryption; no bans or admin commands yet.

### Phase 3 — audio

Everything goes through the **`Audio`** autoload (`scripts/audio/audio_manager.gd`):

| Feature | How it works |
|---------|--------------|
| **Gunfire** | Each weapon has its own shot (AR-7, V-10, M-12, LR-50, P-9); heard up to 150 m (sniper 300 m); distant shots lose their highs |
| **Footsteps** | One step per stride: walking normal, **sprinting loud (40 m)**, **crouch-walking nearly silent (8 m)** — also for other players, from their movement. Jump, landing (louder the harder you land) and slide sounds |
| **Reload & handling** | Mag out → mag in → bolt, timed to the reload; dry fire; weapon switch |
| **Bullets** | Impact sound where bullets hit; enemy bullets flying within 3 m of your head **whiz** past |
| **Feedback** | Hit marker, headshot "ding", kill confirm (can be turned off), hurt thump when you take damage |
| **Occlusion** | A ray from your ears to each sound: if a wall is in between, the sound goes to the `SFXOccluded` bus (low-pass + quieter). Long sounds re-check while they play (High quality) |
| **Reverb zones** | `Area3D`s on physics layer 7 (`audio_zone`) send indoor sounds to `ReverbRoom` or `ReverbHall`: Warehouse hall + drier offices, Courtyard buildings, Bunker rooms + atrium. Add one in `tools/greybox.py` with `m.reverb(pos, size, "room"/"hall", amount)` |
| **Music** | Menu theme (calm, A minor) and a quiet tense drone in matches (can be turned off); cross-fades between them; results screen plays a **win or lose sting**. Bomb Defusal: round start, bomb planted, defused, round won/lost stings |
| **UI** | Every button clicks and ticks on hover |
| **Voices** | Pooled players — Low: 16 at once, High: 40; when all are busy the oldest is reused. Sounds out of range aren't played at all. Nothing plays on a dedicated server |

**Settings → Audio:** five volume sliders, *Audio quality* (Low PCs get Low automatically), *Music during matches*, *Hit & kill sounds*.

**Placeholder sounds → real sounds.** All sounds are synthesised at startup on a background thread (`scripts/audio/procedural_sfx.gd`, `sfx_library.gd`, `music_synth.gd`), so the game needs no audio files. To use a real sound, add a file with the sound's name — it is picked up automatically, no code changes:

| Put the file in | Names |
|-----------------|-------|
| `assets/audio/sfx/` | `fire_rifle` `fire_smg` `fire_shotgun` `fire_sniper` `fire_pistol` `dry_fire` `mag_out` `mag_in` `bolt` `equip` `step1`–`step4` `land` `jump` `slide` `impact` `whiz` `hurt` `bomb_beep` `explosion` |
| `assets/audio/ui/` | `hitmarker` `headshot` `kill` `ui_click` `ui_hover` `bomb_planted` `bomb_defused` `round_start` `round_win` `round_lose` `match_win` `match_lose` |
| `assets/audio/music/` | `menu` `match` (enable *Loop* in the import settings) |

Formats: `.ogg` (music, long sounds), `.wav` (short sounds) or `.mp3`. Keep mono for 3D sounds. Audio files go through Git LFS, and their license goes in `docs/CREDITS.md`.

### Phase 7 — performance

**Built-in benchmark** — flies the camera through every map with 12 moving, shooting bots and reports average FPS, **1% low**, frame-time spikes, draw calls, triangles and node count (saved as JSON in `user://benchmarks/`).

```bash
tools/run_benchmark.sh /path/to/godot                           # current settings, all maps
tools/run_benchmark.sh godot --preset low --bots 16 --duration 15
tools/run_benchmark.sh godot --preset low --set dynamic_lights=true   # A/B any graphics option
tools/run_benchmark.sh godot --no-batching                       # A/B static batching
```

Or in game: **Settings → Graphics → Run benchmark** (the result and advice appear on the main menu). To compare *all* presets and options on a PC, use the **Full hardware test** (Phase 7b).

**What was optimised** (measured with the benchmark; numbers below are from a *software* renderer — Mesa llvmpipe, no GPU — so absolute FPS is far lower than any real PC, but the before/after differences are real):

| Change | Why | Measured effect |
|--------|-----|-----------------|
| Hide the full-screen damage-flash when transparent | A transparent full-screen quad still costs fill rate every frame | Warehouse (Low) **30.8 → 36.9 FPS (+20%)** |
| Shared `ImpactDecals` MultiMesh per level | Every weapon had 32 decal nodes (~160 per player) | **3,743 → 1,611 nodes** with 13 players (−57%); decals are 1 draw call |
| Pooled audio (Phase 3) | Weapons had their own players; now one shared pool of 16–40 voices, and out-of-range sounds are skipped | fewer nodes per player (budget 90); benchmark unchanged with 12 shooting bots |
| `dynamic_lights` preset option (off on Low) | In the OpenGL renderer every lamp adds a pass per lit object | Warehouse **27.9 → 31.0 FPS (+11%)** |
| **Dynamic resolution** (on by default, target 60 FPS) | Lowers the 3D resolution only while frames are slow; HUD stays sharp | reached 0.5 scale automatically: **30.8 → 37.4 FPS** in the stress test |
| Shader warm-up on level load | OpenGL compiles shaders on first use → hitch on the first shot / first enemy | worst 1% low **9.3 → 24 FPS**, no frames over 50 ms after warm-up |
| Static batching + occluders + detail draw distance | Merges greybox boxes per material and 16 m cell; big boxes occlude; small props fade out per *Draw distance* | draw calls **36–40 → 31–32** (small here — greybox maps are simple; matters with real art) |
| Auto-detect | Software renderers and PCs without Vulkan (OpenGL fallback) now get **Low** | Medium on OpenGL measured 16 FPS vs Low 37 FPS |
| Performance advisor | If even 50 % resolution can't hold the target for 20 s, the HUD suggests a lower preset | — |

Overall Low preset, 3 maps, 12 bots (llvmpipe): **avg 30.2 → 37.2 FPS**, worst 1% low **9.3 → 24.1 FPS**, nodes **~3,750 → ~1,600** — before dynamic resolution, which lifts it further.

*Checked and left alone:* the grid shader and the procedural sky cost < 2 % each; players' CPU cost is small (32 players ≈ 7 ms frames headless, ~7 ms one-off per player spawn).

**Budgets enforced by the smoke test:** ≤ 90 nodes per player, one decal node per level, static batching at least halves mesh count, occluders present, dynamic resolution drops/recovers, Low turns lights off.

### v0.9 — new look (built in code)

Until real art arrives, everything visible is generated — no texture or model files, so the download doesn't grow:

| What | How |
|------|-----|
| **Surfaces** | One level shader (`assets/shaders/prototype_grid.gdshader`) with material *kinds*: concrete (mottling, slab seams), brushed metal, wood planks with grain, painted plaster with grime near the floor, stone paving with per-tile tint, foliage. World-space, so any box tiles correctly. `tools/greybox.py` picks the kind per material |
| **Surface detail** | The noise is behind a real branch on the global `surface_detail`, off on Low (*Settings → Graphics → Surface detail*) — Low pays only for seams |
| **Guns** | `WeaponModel` builds each weapon (AR-7, V-10, M-12, LR-50, P-9) from ~15–25 boxes/cylinders: rails, handguards, muzzle devices, magazines, scope with lens, bolt, pump grooves… The iron sights keep their exact positions, so ADS alignment is unchanged |
| **Soldiers** | `PlayerModel`: helmet, visor, vest, shoulder pads (team colour), backpack, pouches, arms holding the current gun, legs that walk and crouch |
| **Draw calls** | `MeshBuilder` merges all parts into **one vertex-coloured surface** (+ one tinted armour surface) with a shared shader — a player is 5 draw calls, like the old capsule |
| **Lighting** | Filmic tonemapping, softer sky ambient, warm sun, subtle glow |

Measured on the software renderer (Low, 12 bots, back-to-back runs): average **35.7 → 34.4 FPS (−3.6 %)**, draw calls unchanged (~50), nodes 1,600 → 1,380. *Replacing with real art:* swap `WeaponModel` / `PlayerModel` for imported `.glb` scenes and the level materials for textured ones — the gameplay code only needs the `Muzzle` marker and hitboxes.

### New maps, CS-style HUD, hands and reload animations (in development)

| What | How |
|------|-----|
| **Kasbah map** | `kasbah()` in `tools/greybox.py`: a 3-lane bomb map, original layout. New generator helpers: `cyl()` (pots, barrels, sacks, wells), `beam()` (cables, palm fronds, poles), `blocker()` (one invisible collider for a pile of sandbags), rotated boxes (`pitch`/`roll`), facades with windows/shutters/doors/balconies, market stalls, palms, and `callout()` boxes that name places |
| **Desert materials** | New kinds in the level shader: sandstone blocks (running bond, per-block tint), weathered plaster (bricks show through patches, water stains), irregular flagstones (cellular), striped cloth. Seams stay on Low; the noise needs *Surface detail* |
| **Radar** | `scripts/ui/minimap.gd`: built once from the map's collision shapes (floor light, cover mid, walls dark; ceilings ignored), so every map gets one. Rotates with the view; teammates, bomb sites, carrier ring, dropped/planted bomb. `location()` reads the map's `Callouts` (falls back to "Bombsite A/B") |
| **Top bar** | `scripts/ui/top_bar.gd`: clock (red after the plant), round number, team scores and up to 5 player cards per team (+N), dead players greyed out, you outlined in yellow |
| **Hands** | `WeaponModel.get_arm_mesh()`: gloved hands at each gun's grip and fore-end / pump / front grip (pistol: two-handed), sleeved forearms — first person only |
| **Reload (first person)** | The viewmodel is 4 pieces (gun, magazine, right arm, left arm). `Weapon._animate_reload()` rolls the gun, moves the left hand + magazine out, down, back in (synced with the *mag in* sound at 55 %) and jolts for the bolt; the shotgun feeds three shells |
| **Reload (others)** | `PlayerNetSync` sends a `RELOADING` flag; `PlayerModel` tips the gun and swings its separate left arm; the *mag out* sound plays at the player |
| **More maps** | `factory()`, `office()`, `subway()`, `trainyard()` in `tools/greybox.py`; new helpers for trucks, containers, freight cars, rails, desks, strip lights; new materials (brick, tile, carpet, glass, gravel, sleepers…) and an emissive *lamp* kind so indoor maps stay lit on Low, where real lights are off |

Draw calls at the worst view on Low (after batching): Courtyard ~120, Kasbah ~185, Factory ~190, Office / Train Yard ~205, Subway ~235 — still well within what the minimum-spec GPUs handle.

### Phase 7b — real-hardware tuning

The presets can only be tuned on real PCs, so the game measures itself and players send the results.

**1. Players run the full hardware test** — *Settings → Graphics → Full hardware test* (≈5 min; don't touch the mouse). It plays Warehouse and Courtyard with 12 bots and measures:

| Stage | Measured |
|-------|----------|
| OpenGL (Compatibility) | Low; Low at render scale 0.5 and 1.0; Low + shadows / lamps / glow / FXAA |
| Vulkan (Forward+) | Medium, High, Ultra, Low on Vulkan; Medium + SSAO / SSR / volumetric fog / TAA / MSAA 2× / 2048 shadows / full resolution / SDFGI |

The renderer can only change at startup, so the game **restarts itself once** between the stages (and once more back to your own settings). Progress is saved: if a stage crashes (e.g. a broken Vulkan driver) the test records that and carries on; a PC without Vulkan is reported as "Vulkan unsupported".

At the end the main menu shows the results — every preset as *smooth* (≥ 60 FPS average and ≥ 50 FPS 1% low), *playable* (≥ 30 FPS 1% low) or *too slow*, what each option costs on this PC, and the recommended preset — with **Use this preset**, **Copy report**, **Send to the developers** (opens a pre-filled *Hardware report* issue on GitHub; the report is also on the clipboard) and **Open folder** (`hardware_report_*.json` + `.md` in the benchmarks folder). From the command line: `FPSGame -- --hardware-test [--quick] [--quit]`.

**2. Tune from the reports** — save the JSON files in a folder and run:

```bash
tools/tune_presets.py reports/*.json            # analysis + suggestions
tools/tune_presets.py reports/*.json --apply    # also update resources/settings/gpu_tiers.cfg
```

It prints each GPU's results and suggests:
- the **render scale Low needs** on minimum-spec GPUs (fitted from the 0.5 / 0.7 / 1.0 runs), or that a PC is **CPU-bound** (lower resolution won't help);
- whether **OpenGL or Vulkan is faster** for Low on integrated GPUs;
- the **cost of each option** on integrated vs discrete GPUs → what to drop from High first, and what Low could afford for free;
- a **starting preset per GPU model**. With `--apply` these go into `resources/settings/gpu_tiers.cfg`, which the first-launch auto-detect reads (GPU names are normalised, so *Mesa Intel(R) UHD Graphics 620 (KBL GT2)* on Linux and *Intel(R) UHD Graphics 620* on Windows are the same entry).

Preset files themselves are only *suggested* — review and edit `resources/settings/graphics_presets/*.tres` by hand.

**Status:** the tools are ready and tested, but **no real-hardware reports exist yet** — the presets are still the Phase 7 values and `gpu_tiers.cfg` only lists the README's minimum-spec GPUs (UHD 620, Vega 8, older Intel HD) as *not measured yet*. Reports from a minimum-spec laptop are the next step.

**Found on the way:** ENet's packet throttle dropped *unreliable* packets (voice and player movement) whenever round-trip times fluctuated — under CPU load a listener received only a fraction of the voice packets. Every connection now keeps unreliable traffic at full rate; voice now arrives complete (125 of 125 packets in the tests).

### Phase 2 — settings

**Settings** is one screen (`scenes/ui/settings_menu.tscn`) used by both the main menu and the in-game `Esc` menu. Every change applies and saves immediately.

| Tab | What you can change |
|-----|---------------------|
| **Graphics** | Preset (Low / Medium / High / Ultra / Custom), *Auto-detect for this PC*, *Run benchmark*, *Full hardware test*, renderer (restart), render scale, upscaler (FSR 1 / FSR 2.2), MSAA, FXAA, TAA, texture & model detail, draw distance, foliage, particles, shadows (on/off, resolution, filtering, cascades), SSAO, SSIL, SSR, SDFGI, bloom, volumetric fog, depth of field |
| **Display** | Window mode, window size, V-Sync, FPS limit, field of view, brightness, performance overlay |
| **Audio** | Master, music, effects, voice chat and interface volume |
| **Voice** | On/off, push-to-talk or voice activation, microphone, mic volume, activation level, live mic meter, noise suppression, proximity chat, "hear myself" test |
| **Controls** | Mouse and ADS sensitivity, invert Y, **hold or toggle** for aim and crouch, **key bindings** for 23 actions (click → press a key or mouse button; a key already in use swaps with the other action; `Esc` cancels; *Reset key bindings*) |
| **Gameplay** | Player name, crosshair colour / size / centre dot with live preview |

*Reset tab* restores that tab's defaults. Settings live in `user://settings.cfg` (key bindings in its `[bindings]` section, stored by physical key position so they work on any keyboard layout). Tests use a separate `settings_test.cfg`, so running them never changes your settings. `Esc`/Pause stays fixed so you can always reach the menu.

### Phase 6 — modes, weapons & maps

**Game modes** (chosen by the host; the map is picked on the **map selection screen** — see *Maps* below)

| Mode | Rules |
|------|-------|
| **Practice** | Offline, any map, target dummies, no limits |
| **Free-for-All** | First to **20** kills, or most kills after **10 min** |
| **Team Deathmatch** | Blue vs Red, auto-balanced on join, **friendly fire off** (bullets pass through teammates), first team to **50** kills or most after **10 min** |
| **Bomb Defusal** | Rounds, first team to **5 round wins**; sides swap after round 4. See below |

Match flow: the server runs the clock and score → **results screen** (winner + scoreboard, 10 s) → **map vote**: the results screen offers 3 maps (the next one in the rotation + 2 random maps that support the mode); press **`1` / `2` / `3`** to vote (you can change your vote). The map with the most votes wins; ties and no votes keep the normal rotation (Test Range → Warehouse → Courtyard → Rooftops → Docks → Bunker → Kasbah → Factory → Office → Subway → Train Yard → …). Everyone stays connected. Players get **1.5 s spawn protection**, and respawn at the spawn point furthest from living enemies (team spawns in TDM). Enemy name tags are hidden behind walls; teammates' are always visible. In TDM, *team* voice (`V`) only reaches your team; use proximity (`B`) to talk to nearby enemies.

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
| Rooftops | Vertical, long range | Four flat roofs linked by two bridges, ramps up from the street, parked cars as cover, sites A/B in the street |
| Docks | Outdoor, lanes | Container stacks on a quay, a moored ship (Red spawns on its deck) with two gangways, a crane |
| Bunker | Indoor, small (2–8 players) | Central atrium with four doors, four corner rooms, tight corridors — fast rounds |
| Kasbah | Desert town, bomb defusal | Three lanes (A Long, Mid with doors, covered B Apartments), Connector and Short; A is a raised terrace, B a courtyard round a well |
| Factory | Industrial, halls + yard | Machine hall with a catwalk (A), storage hall (B), CT offices between them, a yard of trucks, pipes and tanks, loading docks |
| Office | Indoor, two floors | Lobby with reception, open-plan office (A), conference + server room (B), break room and storage under a mezzanine reached by two stairs, side alleys |
| Subway | Underground | Two side platforms and an island, track beds to drop into (climb out at the ends), a two-car train to walk through, ticket halls with turnstiles |
| Train Yard | Outdoor, rail lanes | Six tracks of box, tank and hopper cars, a maintenance shed with a locomotive (A), a signal tower with a balcony and containers (B) |

**Map selection screen** — main menu → **Map: … ▸** opens a grid of map cards with a live top-down **preview** (rendered once from the real map and cached), players, style, supported modes and a description. Maps without bomb sites are greyed out in Bomb Defusal. The choice is saved in your settings. Map metadata lives in `GameConfig.MAPS` (`scripts/core/game_config.gd`); the screen is `scenes/ui/map_select.tscn` + `scripts/ui/map_select.gd`, previews come from `scripts/ui/map_preview.gd`.

**Add a map:** build it in `tools/greybox.py` (or by hand in the editor with `scripts/levels/level.gd` on the root, Blue/Red/FFA spawn markers and `A`/`B` bomb site markers), then add one entry to `GameConfig.MAPS` — it then appears in the picker, the rotation, the vote, `--map <id>` and the benchmark automatically.

All maps except the Test Range are generated by **`tools/greybox.py`** (boxes, ramps, doors, spawns, lights). Edit the layout in Python and run `python3 tools/greybox.py` to rebuild the `.tscn` files; replace the greybox with real art later.

**Key scripts:** `scripts/core/match_manager.gd` (autoload `Match`), `scripts/core/bomb_rules.gd` (`Match.bomb`), `scripts/core/game_config.gd`, `scripts/levels/level.gd` (team + safe spawns, spectator), `scripts/levels/bomb_visual.gd`, `scripts/ui/hud.gd`, `scripts/ui/scope_overlay.gd`.

### Testing multiplayer locally

- **Automated:** `tools/run_net_test.sh /path/to/godot` runs three host + client pairs on localhost. First, it plays a **Team Deathmatch** round: teams auto-balance, the client walks, both talk over **proximity voice** (test tones must arrive at the right frequency, speaking indicators on/off), the client kills the host, the score limit ends the match on both sides, the server **rotates to Warehouse**, both players respawn there, and the client disconnects cleanly. A second pair then plays **Bomb Defusal** with real key presses: the client walks to site B and plants, the host walks over and defuses (Blue 1–0), the client eliminates the host (1–1), then plants again and the bomb explodes — Red wins 2–1 on both sides. A third pair is a **hacked client** that fires at the legal rate but never reloads: the server accepts exactly one magazine (30 hits) and kicks it, and the kick reason appears in its main menu.
- **By hand:** in the Godot editor use **Debug → Customize Run Instances…** → 2–3 instances, press **F5**, then *Host* in one window and *Join* `127.0.0.1` in the others.

---

## 📦 Building & Exporting

`export_presets.cfg` (committed) has four presets:

| Preset | Output | Notes |
|--------|--------|-------|
| **Windows Desktop** | `builds/windows/FPSGame.exe` | single exe (PCK embedded) |
| **Linux** | `builds/linux/FPSGame.x86_64` | single binary |
| **macOS** | `builds/macos/FPSGame.zip` | universal (Intel + Apple Silicon), ad-hoc signed, microphone permission text included |
| **Linux Server** | `builds/server/FPSGame-server.x86_64` | *dedicated server* export: meshes/textures stripped, starts as a server automatically |

**One command builds every release package** (needs the Godot 4.4.1 export templates — *Editor → Manage Export Templates*):

```bash
tools/build_release.sh /path/to/godot --verify
```

→ `dist/FPSGame-<version>-windows-x86_64.zip`, `-linux-x86_64.tar.gz` (with `.desktop` file), `-macos-universal.zip`, `-server-linux-x86_64.tar.gz`, and `SHA256SUMS`. `--verify` boots the exported server, connects a client to it, and loads every map in the exported Linux game. The Windows **installer** (`installer/windows/FPSGame.iss`, Inno Setup: Start-menu + desktop shortcut, optional firewall rule for hosting, uninstaller) is built by CI on Windows.

**Automated releases:** push a tag → the *Release* workflow runs all tests, builds every package + the installer and publishes a GitHub Release (tags containing `-` are pre-releases). *CI* runs the smoke and multiplayer tests on every push and pull request. Maintainer steps: [`docs/RELEASE.md`](docs/RELEASE.md).

```bash
git tag v0.9.0-beta && git push origin v0.9.0-beta
```

**Code signing** — the Release workflow signs the Windows exe, Opus DLL and installer (Azure Trusted Signing or a `.pfx`) and signs + notarizes the macOS app as soon as the certificates are added as GitHub secrets; until then builds are unsigned (Windows: *More info → Run anyway*, macOS: right-click → *Open*). Costs and step-by-step: [`docs/SIGNING.md`](docs/SIGNING.md).

**Dedicated server** — [`server/README.md`](server/README.md): `./run_server.sh --mode tdm --map warehouse` or Docker (`server/Dockerfile`, `server/docker-compose.yml`). Measured: ~96 MB RAM and ~8 % of one CPU core with 4 players.

**Command line**

| Command | Does |
|---------|------|
| `FPSGame -- --connect 1.2.3.4:7777 --name Bob` | join a server directly (shortcuts, server lists) |
| `FPSGame-server.x86_64 --port 7777 --mode bomb --map courtyard` | dedicated server (options also work after `--`) |
| `FPSGame -- --benchmark --preset low --quit` | built-in benchmark |

> `builds/` and `dist/` are git-ignored — builds are shared through GitHub Releases.

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

All keys (except `Esc`) can be remapped in **Settings → Controls**; aim and crouch can be set to *toggle*.

**Controller** (Xbox names — PlayStation: A = ✕, B = ○, X = □, Y = △, LB/RB = L1/R1, LT/RT = L2/R2):

| Action | Button | Action | Button |
|--------|--------|--------|--------|
| Move / look | Left / right stick | Shoot / aim | RT / LT |
| Jump / crouch | A / B | Reload / next weapon | X / Y |
| Sprint / slide | L3 / R3 (stick clicks) | Interact (plant, defuse) | LB |
| Primary / pistol | D-pad ← / → | Team / proximity voice | D-pad ↑ / ↓ |
| Scoreboard | View (Back) | Pause | Menu (Start) |

Menus: D-pad / left stick to move, **A** to select, **B** to go back. **Settings → Controls → Controller:** look sensitivity (°/s), stick deadzone, response curve (Linear / Default / Precise), invert Y, **aim assist** (slows the aim while the crosshair is on an enemy — controller only), vibration; every action has a keyboard *and* a controller binding, both remappable (`scripts/core/gamepad_input.gd`).

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
- **Network:** 30 Hz player state, target < 64 kbps per client excluding voice; voice adds ~24 kbps per active speaker (Opus; 64 kbps if someone lacks Opus and ADPCM is used).
- **Test every feature on the Low preset** before merging, and run `tools/run_benchmark.sh --preset low` before/after anything that could affect performance.
- **Never leave invisible full-screen UI visible** (alpha 0 still costs fill rate) — hide it.
- **No per-object node pools** — share one per level (see `ImpactDecals`).

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
- [x] **Phase 2 — Settings:** full settings screen (6 tabs), custom graphics editor, key remapping, hold/toggle aim & crouch, crosshair options
- [x] **Phase 3 — Audio:** 3D SFX for guns/footsteps/impacts, audio buses + limiter, occlusion, reverb zones, music + stings, audio quality setting (generated placeholders, replaceable by files)
- [x] **Phase 4 — Multiplayer:** dedicated server, lobby, player sync, lag compensation, scoreboard, kill feed
- [x] **Phase 5 — Voice chat:** mic capture, ADPCM encode/decode, team & proximity channels, push-to-talk, voice activation, mute
- [x] **Phase 5b — Opus codec:** C++ GDExtension (libopus 1.5.2) for Windows/Linux/macOS, ~24 kbps instead of 64, FEC + loss concealment, automatic ADPCM fallback
- [x] **Phase 6 — Content:** 5 weapons + loadouts, 6 maps + map selection screen + map vote, FFA & TDM with teams, match flow & map rotation, HUD & menus
- [x] **Phase 6b — Bomb Defusal:** rounds, freeze time, bomb carry/drop/plant/defuse/explode, no respawns + spectating, halftime side swap
- [x] **Phase 7 — Optimization:** built-in benchmark, dynamic resolution, performance advisor, static batching + occluders + detail distance, shared decals, shader warm-up, Low-preset light cuts, better auto-detect
- [ ] **Phase 7b — Real-hardware pass:** ✅ tools done (full hardware test with renderer restarts, shareable reports, `tools/tune_presets.py`, measured GPU tiers for auto-detect) · ⏳ waiting for reports from the minimum-spec PCs (Intel UHD 620 / Vega 8) to tune the presets
- [x] **Phase 8 — Release (beta):** export presets, release packages + checksums, Windows installer, dedicated-server package + Docker, CI + release workflows, anti-cheat, bug reporting, changelog
- [x] **v0.9 — toward v1.0:** controller support (look curve, aim assist, rumble, remapping), new look from code (procedural materials, gun + soldier models, lighting), code-signing pipeline (off until certificates exist)
- [x] **Maps + CS-style HUD:** Kasbah, Factory, Office, Subway and Train Yard; radar with location names, top bar with player cards; first-person hands, new sniper model; reload animations in first and third person
- [ ] **v1.0:** beta feedback, presets tuned from hardware reports (Phase 7b), real art (CC0 packs or an artist), certificates for signing

---

## 🤝 Contributing

1. Create a branch from `devlop`: `git checkout -b feature/my-feature devlop`
2. Make your changes and test them on the **Low** preset.
3. Commit using Conventional Commits.
4. Push and open a Pull Request into `devlop`.

Please keep scripts small and focused, name files in `snake_case`, and nodes/classes in `PascalCase`.

---

## 🐞 Reporting bugs

In game: **Esc → Report a bug** (or on the main menu). It opens a pre-filled GitHub issue (version, OS, CPU, GPU, renderer, graphics settings, log folder) and copies the same details to the clipboard — nothing is sent automatically. Logs: Windows `%APPDATA%\FPSGame\logs`, Linux `~/.local/share/FPSGame/logs`, macOS `~/Library/Application Support/FPSGame/logs`.

## 📄 License

License not yet selected — **choose one before the public release** (e.g. MIT for the code). Until a `LICENSE` file is added, all rights are reserved by the project owner.

Third-party assets (models, sounds, fonts) must list their source and license in `docs/CREDITS.md`.
