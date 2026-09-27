# Changelog

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
