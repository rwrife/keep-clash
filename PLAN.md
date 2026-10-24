# Keep Clash plan

## Architecture and scope

Godot 4.7.2-stable, GDScript. Scene tree: arena, four shield/keep seats, ball, destructible rampart segments, HUD; pure rules model for impacts/round scoring and versioned JSON save. `InputMap` actions unify keyboard, mouse, gamepad and touch controls; on-screen controls for touch. Bot difficulty seeded and reproducible. Solo versus bots first; couch multiplayer via separate controllers/keyboard slots second. Local-only.

**UX strategy B: custom branded game UI.** Godot `Control` nodes with bespoke colors, typography, motion and responsive anchors; neither Material nor Cupertino. Windows keyboard focus, hover, resize and quit confirmation; Android/iOS system back and safe areas, touch targets, reduced motion, contrast, readable scaling, pause on interruption. Tablet layout uses available area; no fixed phone viewport. Test HUD at 360×800, 800×1280 and resizable 1280×720; verify input prompts for touch, mouse/keyboard and gamepad.

## Visual and asset contract

Modern 3D arena with Forward+ renderer on Windows: PBR `StandardMaterial3D`, baked LightmapGI or SDFGI where measured, physically coherent lighting, glow/bloom, SSAO where performant, impact `GPUParticles3D`, camera framing, transitions, LODs. Mobile renderer with scaled/optional effects for Android/iOS; Compatibility renderer considered for Web. Never ship greybox as finished art. Reference image via `~/.local/bin/spark-media --project keep-clash image --prompt ...` (OpenAI Images API), then `spark-media --project keep-clash mesh --image ...` (Hunyuan3D); inspect mesh, decimate to budget, assign PBR, collision, LOD, track in `assets/README.md` and Git LFS. If mesh unusable, use clean primitives and open labeled `art-asset` issue specifying reference, dimensions/pivot, material, tri budget, collision/animation needs and failure evidence; track `manual-pending`. Avoid GPU-heavy mesh jobs while Qwen service active. Icon already generated via spark-media and saved to `AppStore/icon.png`; platform icon wiring pending.

## Milestones (dependency order)

1. Pinned Godot project/import, GUT tests and CI Windows headless editor checks; Android/iOS export presets without secrets.
2. Deterministic impact rules, shield arcs, wall health, bot decisions with unit tests.
3. Playable solo round and pause/restart, four seats with gamepad/keyboard/touch routing.
4. 3D generated art import and PBR arena, audio, particles, readable camera; fallback issues for unusable meshes.
5. Progression, three arenas, settings/remapping/accessibility and save/load.
6. Adaptive HUD and touch/keyboard/controller journeys, screen-size and platform input tests.
7. Versioned backup/export/import and privacy checks.
8. Windows `v*` release Action, zip Windows Desktop build, store copy review and platform icon wiring.

## Match rules (#2)

`scripts/match_rules.gd` is a node-free `RefCounted` model. The scene calls `step(1.0 / 120.0)` once per fixed tick, aims shields with `set_shield_angle(seat, angle)` (angle measured from the keep's centre, same frame as `bot_target`), and calls `serve(angle)` after a parked (non-winning) core hit. `step()` returns ordered shield/wall/core/win events; each keep has three angular wall sectors with independent one-hit destruction; the last standing keep wins and the match latches `over`. Seeded bot decisions consume RNG only on explicit `bot_target(seat, difficulty)` calls. Stars: 1 for winning, +1 intact-ramparts, +1 for three or more deflections. Earliest contact per tick is solved with an analytic circle sweep (`sweep_circle`) rather than endpoint overlap, so fast balls cannot tunnel; `MAX_IMPACTS=32` bounds ricochet chains within one tick. This is deterministic gameplay-rule verification only — no renderer, physics-engine or frame-budget claim.

## Verification

Issue #1 local verification (2026-10-23, Linux arm64 pinned Godot 4.7.2-stable): `--headless --import --quit` exited 0; GUT 9.6.1 ran 5 tests/22 assertions, all passed. CI checks project load + GUT on Linux x86_64 and `windows-latest`, using editor binaries downloaded with SHA512 verification. Linux and Windows CI results must be checked on the PR head; neither platform has a gameplay journey yet. Windows export build is reserved for issue #8. Android/iOS have unsigned, credential-free export presets but **no export build was run**; Android export build in CI when feasible, iOS export on macOS later. Linux/macOS/Web exports are planned, not tested; Compatibility renderer for Web is unmeasured. Manual real-device touch, tablet safe-area and controller tests needed; never mark planned exports tested. Compare renderer effects and frame budgets on devices, fallback to mobile renderer where needed.

## Distribution

`.github/workflows/release.yml` to run on `v*` tag/manual dispatch, build pinned Godot Windows Desktop on `windows-latest`, zip and attach artifact to GitHub release. Android/iOS phones and tablets first-class compile targets; TestFlight/Play publication later and opt-in. `com.infinityball.keepclash` required for Android `application/unique_name`, iOS bundle ID and any MSIX identity. ASC registration: CREATED. ASC secrets available by name only: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`. Review `AppStore/description.txt` against actual shipped features before release. No credentials in `export_presets.cfg`.

## Risks and exclusions

Shield-ball collision tunneling at high speed: fixed physics step plus sweep/continuous checks. Four-seat input conflicts: explicit device-seat mapping and single touch seat. Generated topology may fail as game mesh: reject, track primitive/manual-pending fallback in `assets/README.md`. Mobile GI and particles may overheat: scale/disable by renderer. No copied classic boards/art/IP; no internet accounts or online play. Engine non-goals, explicit: no Unity, no Flutter, no React Native, no Expo, no Kotlin Multiplatform, no .NET MAUI, no custom or browser-only engine — Godot 4 only.
