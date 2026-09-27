# Changelog

## Unreleased

- **3 new maps:** Rooftops (vertical, bridges between roofs), Docks
  (containers + a ship with gangways) and Bunker (small indoor, 2–8 players).
  All support FFA, TDM and Bomb Defusal.
- **Map selection screen** in the main menu with live previews, player
  counts, style and supported modes.
- **End-of-match map vote:** 3 candidates on the results screen, vote with
  1 / 2 / 3; ties keep the normal rotation.
- Network protocol version 3 (older clients get a version-mismatch message).
- **Audio (Phase 3):** a different gunshot per weapon, footsteps (sprinting
  is loud, crouch-walking nearly silent) for you and other players, jump /
  land / slide, reload sequence, bullet impacts and near-miss whizzes, hit
  marker / headshot / kill sounds, hurt sound.
- Walls muffle sounds behind them (occlusion); indoor areas echo (reverb
  zones in Warehouse, Courtyard buildings and Bunker).
- Menu music, quiet in-match music, win/lose and Bomb Defusal stings; every
  button clicks.
- Settings → Audio: *Audio quality* (Low / High), *Music during matches*,
  *Hit & kill sounds*.
- Sounds are generated placeholders; drop files into `assets/audio/` to
  replace them (see README → Phase 3).

## v0.8.0 beta — first public beta

**Play:** Free-for-All, Team Deathmatch and Bomb Defusal on three maps
(Test Range, Warehouse, Courtyard) — offline practice, host / join, or a
dedicated server. Five weapons (AR-7, V-10 SMG, M-12 shotgun, LR-50 sniper,
P-9 pistol), loadouts, in-game voice chat (team + proximity).

**Runs on low-end PCs:** Low / Medium / High / Ultra + custom graphics,
dynamic resolution (holds 60 FPS), automatic preset detection, built-in
benchmark (Settings → Graphics → Run benchmark).

**Settings:** full settings screen, key remapping, hold/toggle aim and
crouch, crosshair options, audio and microphone settings.

**Multiplayer:** server-authoritative damage with lag compensation,
anti-cheat (server-side ammo and reload, fire-rate, speed and fly checks —
offenders are kicked), map rotation, scoreboard, kill feed.

**Downloads:** Windows installer or zip, Linux tar.gz, macOS zip
(unsigned: right-click → Open the first time), Linux dedicated server
(also as a Docker image — see `server/`). Verify files with `SHA256SUMS`.

**Known limitations:** greybox art; players pass through each other; no
NAT punch-through (forward UDP 7777 or use a VPN to host over the
internet); voice uses ADPCM (~64 kbps while talking) until Opus lands;
controller/gamepad not supported yet.

Found a bug? In game: **Esc → Report a bug**.
