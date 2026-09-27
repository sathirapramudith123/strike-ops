# Release checklist (maintainers)

1. **Version** — bump `config/version` (numbers only, e.g. `0.9.0`) and
   `config/release_channel` (`beta`, `rc` or empty for stable) in
   `project.godot`. Bump `NetworkManager.PROTOCOL_VERSION` if the network
   protocol changed (old clients then get a clear "version mismatch").
2. **Changelog** — replace `CHANGELOG.md` with this version's notes (the
   release workflow uses it as the release text).
3. **Tests** — CI must be green (smoke test + multiplayer tests).
4. **Performance** — on the minimum-spec PC (Intel UHD 620 / Vega 8):
   `tools/run_benchmark.sh godot --preset low` → worst 1% low ≥ 50 FPS
   with dynamic resolution on. Attach the JSON to the release PR.
5. **Local build** (optional) — `tools/build_release.sh godot --verify`
   builds every package into `dist/` and boots the server + game.
6. **Beta test** — hand the builds to testers; collect "Report a bug" issues.
7. **Tag** — `git tag v0.9.0-beta && git push origin v0.9.0-beta`.
   The *Release* workflow tests, exports Windows / Linux / macOS / server,
   builds the Windows installer, and publishes a GitHub Release (tags with
   `-` are marked pre-release) with `SHA256SUMS`.
8. **Server** — update running dedicated servers (`docker compose pull/up`
   or replace the binary) at the same time as the client release.

Signing (future): the Windows exe and macOS app are not code-signed yet, so
SmartScreen / Gatekeeper warn on first launch. Add certificates to the
workflow (`codesign/*` export options, `signtool`) when available.
