# Changelog

## Unreleased — 5 new maps, CS-style HUD, hands and reload animations

**Names over players:** bigger name tags. Teammates always show their name
— through walls — with a health bar under it; an enemy's name appears when
your crosshair is on them or they're within 6 m (never through walls or
smoke). Far-away tags fade a little.

**Bomb Defusal overtime:** regulation is 8 rounds (first to 5); if it ends
4–4 the match goes to overtime — halves of 3 rounds with sides swapping and
$10,000 each — and the first team to win 4 overtime rounds takes it. Level
again, another overtime. The HUD shows "OVERTIME 1 — first to 8".

**Doors and glass:** doorways in houses and offices have real doors now
(19 across Docks, Oasis, Factory and Office). Press F looking at one to
open it — it swings away from you — or close it. Doors are made of wooden
pieces: bullets splinter the piece they hit and shoot it out, so the door
breaks where you shoot it and you can see and fire through the holes; HE
grenades blow pieces out too. House windows and the office glass walls are
glass panes: the first shot cracks the glass, the second shatters it into
falling shards (a knife, sniper round, HE or a flash nearby breaks it at
once), and bullets fly on through. Everything is server-side and synced,
including for players who join later.

**Docks rebuilt** from concept art as a 3-lane bomb map at sunset. Mid
runs through the Port Authority warehouse; A is the container yard off
its north door under a gantry crane (the red container with the A), and T
reach it along A Long — a raised loading platform with a rail track; B is
on the quay beside the moored ship and two ship-to-shore cranes (the blue
container with the B), reached along B Long, the quay. T spawn is the gate
road under a walkway, CT spawn a harbour office with a pickup. A fence
along the quay edge keeps everyone out of the water.

**Map line-up:** Warehouse, Courtyard and Rooftops are gone; **Kasbah is
now called Oasis** (a saved "kasbah" choice or `--map kasbah` still opens
it). Rotation: Test Range → Docks → Bunker → Oasis → Factory → Office →
Subway → Train Yard. The full hardware test now plays Office and Docks.

**Climbing:** press Space facing a crate, car, sandbag wall, low wall or
other climbable prop up to 2.2 m high and you pull yourself up on top (or
keep Space held after a jump to grab the ledge). Only those props can be
climbed — buildings and tall walls can't. Jumping is now predictable too:
no map has a ledge in the 1.25–1.55 m "sometimes works" range any more
(decorative pots on walls lost their collision), and a new check
(`tools/ledge_check.gd`, also in the smoke test) keeps it that way.

**Grenade wheel and throw path:** hold 4 to open a wheel with your
grenades round the crosshair; move the mouse (or right stick) towards one
and let go to take it (a quick tap still takes the next one). While a
grenade is in hand, its flight is drawn ahead of time — bounces included —
with a ring where it will go off (turn off in Settings → Gameplay).

**Money and the buy menu (Bomb Defusal):** everyone starts a half with
$800 and only the pistol and knife. Press **X** near your spawn during the
freeze time and the first 20 s of a round to buy guns (AR-7 $2700, SMG
$1250, shotgun $1100, sniper $4750), armour ($650, with helmet $1000) and
grenades (HE $300, flash $200, smoke $300, Molotov $400). Earn money for
kills ($300; knife $1500, shotgun $900, SMG $600, sniper $100), plants and
defuses ($300), round wins ($3250, $3500 by the bomb) and losses ($1400,
growing by $500 per loss in a row up to $3400, +$800 for attackers who
planted). Survivors keep their gun, armour and grenades into the next
round; halftime resets everything. Armour is no longer free, and head hits
only hit armour with a helmet. Money shows over your health, with a line
for every reward. The other modes keep free loadouts.

**New control layout:** WASD, hold Shift to sprint, C crouch, Ctrl slide,
Space jump, **Q / E lean**, **Caps Lock walk toggle**, 1 / 2 guns, **3 knife**,
**4 grenades** (press again to switch, click to throw, right click to lob,
G quick-throws the HE), R reload, **B fire mode** (AR-7 auto / burst / semi,
V-10 auto / semi), **F use / plant / defuse**, **M big map**, Y / T chat,
U / V voice, and the **mouse wheel zooms the sniper scope** (4× / 8×)
while scoped. Leaning moves your head hitbox on the server too, and
can't poke through walls. Settings now only save keys you changed; an old
settings file picks up the new layout once.

**The gun no longer goes through walls:** walking up stairs and ramps (or
standing close to any wall or ceiling) used to push the first-person gun
through it. Now it pulls back and dips down when something is in the way
and comes back when there's room.

**Bunker and Train Yard rebuilt** from concept art as 3-lane bomb maps
(T west, CT east, A north, B south). Bunker is an underground base on
three levels: A Long climbs to an upper corridor and a balcony over A, B
is a level down through the rock tunnel or the stairs from the reactor
hall in Mid. Train Yard has trains parked in Mid under a gantry crane, A
inside a warehouse off the raised loading dock, B in a lower yard at the
end of the rail cut, and a water tower on the CT side.

**Grippier movement:** you stop almost on the spot (about 0.2 m from a
sprint instead of gliding), reversing brakes hard, and crouching while
running no longer turns into a slide — only the Slide key (`C`) slides.

**Flashbang and smoke grenade:** two flashes (`F`) and one smoke (`Z`)
per life. A flash whites out the screen of anyone who sees it — up to 4 s
looking straight at it, less further away or looking away, nothing
through walls — with ringing ears. A smoke makes a thick 3.5 m cloud for
15 s that hides players (their name tags and aim assist too), puts out
Molotov fires and makes a Molotov thrown into it fizzle.

**HE grenade and Molotov:** one of each per life (per round in Bomb
Defusal), quick-thrown with `G` / `Q` (controller: RB for the HE). The HE
bounces and goes off after 1.6 s — up to 98 damage, gone by 6 m, blocked
by walls, half of it through armour — with a flash, fireball, smoke and a
screen shake. The Molotov smashes on the floor and leaves a 3 m fire for
7 s that burns 25 health a second (armour doesn't help). Teammates are
safe, the thrower is not. The server decides where each goes off; the HUD
lists what you have left and the kill feed names the grenade.

**Armour (Bomb Defusal):** everyone starts each round with 100 armour. It
takes 40 % of every bullet (and wears down by that much); falls and the
bomb ignore it. Shown next to health with a shield icon.

**HUD like the concept art:** health and armour side by side with bars,
ammo as `30 / 120` plus bullet marks for the magazine, a little face on
every player card in the top bar (helmets and caps for Blue, beanies and
balaclavas for Red), a big **map name banner** ("KASBAH — BOMB DEFUSAL")
when a map loads and at each round start, and a warmer radar with boxed
site letters, teammates' view direction and a ring on the planted bomb.

**Factory rebuilt** to a 3-lane plan: A under a gantry crane by two silos
(with a flat roof overlooking it), B in a walled yard, West Lane past the
Warehouse, Mid with a catwalk under the **Lanka Steel** building, Tunnels
to Lower Mid and a Rail Yard along the east. Painted T / CT at the
spawns, coconut palms, red-and-white chimneys and a Sri Lankan flag.

**Hit locations and armour penetration:** where you hit matters — head
(the weapon's headshot multiplier), chest ×1, stomach ×1.25, legs ×0.75.
Each weapon has its own armour penetration: rifle 78 %, sniper 95 %, SMG
60 %, pistol 50 %, shotgun 45 % (the rest is soaked by armour). Armour
doesn't cover the legs.

**Buildings you can enter:** two houses in Kasbah (one on A Long looking
over A, one by B looking over Short and the B Apartments exit) and the
Lanka Steel building in Factory (walk through it from Mid to A), the signal
tower in Train Yard (room downstairs, stairs, a door out onto the
balcony), two of the Rooftops buildings (go in and climb inside to the
roof) and a two-floor harbour office in Docks with roof access. Real doors,
stairs up to an upper floor, and windows you can shoot through.

**Detail textures:** walls, floors and props now have texture and depth
on Medium and higher: stained concrete with pores, rusty metal with
scratches, wood grain, cracked plaster, grainy stone, corrugated sheets
with rust streaks and woven fabric, each with a normal map. They are
generated by `tools/make_textures.py` (no downloads) and can be swapped for
real photo textures later. Low stays as before.

**Map dressing:** red **"A →" / "B →" signs painted on the walls** of all
new maps, hanging rugs, fruit stalls (oranges, tomatoes), wooden barrels,
more sandbags, fuller palm trees and castle towers over Kasbah.

**Four more maps:** **Factory** (a machine hall with a catwalk and a
storage hall around a yard of trucks, pipes and tanks), **Office** (lobby,
open-plan office, server room, a mezzanine with two stairs), **Subway** (an
underground station: platforms, track beds you can drop into, a parked
train to walk through) and **Train Yard** (rows of freight cars, a
maintenance shed, a signal tower with a balcony). All support FFA, TDM and
Bomb Defusal.

**Reload animations:** in first person the gun rolls over, the left hand
pulls the magazine out, fetches a new one and pushes it in (the shotgun
loads shells one by one); other players now visibly reload too — the
soldier tips the gun and swings the left arm down — and you hear it.

**New map — Kasbah:** a sun-baked desert town made for Bomb Defusal (also
FFA and TDM): A Long, Mid with its doors, and the covered B Apartments;
A is a raised terrace with pots, sacks and barrels, B a courtyard round a
well. Sandstone blocks, plaster that has fallen off in patches, flagstone
streets, shuttered windows, balconies, awnings, market stalls, palm trees
and cables overhead — still all built in code.

**New HUD:** a round **radar** in the top-left that turns with you (walls,
cover, bomb sites, teammates, the bomb) with the **name of the place** you
are in under it ("Bombsite A", "Mid", …); a **top bar** with the round
clock, team scores and a card per player (greyed out when dead); health and
ammo in dark boxes; the weapon list on the right; kill-feed entries in boxes
(red outline for your own kills and deaths).

**Hands:** first-person gloved hands and sleeves on every gun, and a new
big-scope LR-50 sniper model (thumbhole stock, turrets, muzzle brake,
bipod).

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
