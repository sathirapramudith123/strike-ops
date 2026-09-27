# FPS Game — dedicated server

A headless server with no graphics (meshes and textures are stripped from this
build), small enough for a cheap Linux VPS — measured with 4 players: **~96 MB
RAM and ~8 % of one CPU core** (plan roughly 1 core for a full 16-player server).

Options work with or without the `--` separator
(`./FPSGame-server.x86_64 --port 7777` or `./run_server.sh --port 7777`).

```bash
./run_server.sh                                   # FFA on the Test Range, port 7777
./run_server.sh --mode tdm --map warehouse        # Team Deathmatch
./run_server.sh --mode bomb --map courtyard --max-players 10 --port 7777
```

| Option | Values | Default |
|--------|--------|---------|
| `--port` | UDP port | 7777 |
| `--max-players` | 2–32 | 16 |
| `--mode` | `ffa`, `tdm`, `bomb` | `ffa` |
| `--map` | `test_map`, `warehouse`, `courtyard`, `rooftops`, `docks`, `bunker` | `test_map` |

Open **UDP 7777** in the firewall / cloud security group. Players join with
the server's IP (`Join` in the main menu, or `FPSGame -- --connect IP:7777`).

After every match players vote for the next map (keys 1–3 on the results screen); with no votes the map rotates. The server log prints joins, leaves,
kills of the match result and `[anticheat]` lines; players who send
impossible actions (shooting without ammo, speed/fly hacks) are kicked.

**Docker:** see `server/Dockerfile` and `server/docker-compose.yml` in the
source repository.
