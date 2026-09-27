# Changelog

## v0.9.0 beta — controllers, new look, sound, 6 maps

**Play with a controller:** Xbox / PlayStation / generic gamepads work
everywhere — right-stick look with deadzone, response curve and sensitivity,
light aim assist (slows your aim over enemies, can be turned off), vibration,
menus with the D-pad / A / B, and every button remappable in Settings →
Controls (keyboard and controller bindings side by side). Prompts show the
button of the device you're using.

**New look:** detailed guns and soldier models (team-coloured helmet and
vest, walking animation), concrete, metal, wood, plaster and stone surfaces,
softer lighting — all built in code, no bigger download, about 3 % slower on
the Low preset (Settings → Graphics → *Surface detail* is off on Low).

**6 maps:** new Rooftops (vertical, roof bridges), Docks (containers, a
ship with gangways) and Bunker (small, 2–8 players), all with FFA, TDM and
Bomb Defusal. Pick maps on the new **map selection screen** (live previews);
after each match everyone **votes for the next map** (1 / 2 / 3, or Y on a
controller).

**Sound:** a different gunshot per weapon, footsteps you can hear through
the map (sprinting is loud, crouch-walking nearly silent), reloads, impacts,
bullets whizzing past, hit / headshot / kill sounds; walls muffle sounds and
rooms echo; menu and match music with win/lose stings. Settings → Audio:
audio quality, match music, hit sounds.

**Voice chat:** now uses the **Opus** codec — about a third of the bandwidth
(≈24 kbps instead of 64), clearer, and lost packets are rebuilt. Players
without Opus are handled automatically.

**Help tune the game:** Settings → Graphics → **Full hardware test** (≈5 min)
measures every preset on your PC, recommends one and lets you send the
report to the developers.

**Fixed:** voice cutting out and players stuttering when ping fluctuated
(busy PC, Wi-Fi); hosting briefly "ended" the match before the map loaded;
made-up audio at the edge of proximity-chat range.

**Compatibility:** network protocol 4 — v0.8 players can't join v0.9 games
(they get a "version mismatch" message).

**Known limitations:** greybox level layouts and code-built models (real
art later); presets not yet tuned from real low-end hardware (please run the
hardware test!); builds are not code-signed yet (Windows: *More info → Run
anyway*; macOS: right-click → Open); players pass through each other; no NAT
punch-through (forward UDP 7777 or use a VPN).

For developers: Opus GDExtension (`native/opus_voice`, `tools/build_opus.sh`),
`tools/tune_presets.py`, code-signing steps in the release workflow
(`docs/SIGNING.md`), smoke test fails CI on script errors.

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
