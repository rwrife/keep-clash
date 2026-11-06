# Keep Clash

Offline 3D castle-shield ball battle: deflect fireballs, smash rival keeps, and win couch or solo rounds on Windows, tablets, and phones.

**Status:** Godot 4.7.2-stable. Playable solo-vs-bots/local-seat rounds, pause/restart/rematch, per-device seat mapping and Windows/Android-aware back/quit handling. #4 PBR primitives, impact effects and imported generated orb are implemented; #15 adds an original modeled shield with three GLB LODs; pinned Linux Godot import and GUT pass, but rendered/device checks remain pending. #14 adds an original modeled keep with three imported GLB LODs; pinned Linux Godot import, GUT and 10-round smoke pass. Rendered/device checks remain pending. Three arena variants, star unlocks, cosmetic palettes and versioned local save/settings are implemented for #5, subject to its #4 dependency. See [PLAN.md](PLAN.md) and [issues](https://github.com/rwrife/keep-clash/issues).

## Why / for whom

For friends wanting short couch competitions, and solo players wanting an arcade duel without accounts, ads, or paid upgrades. Inspired by a general corner-defense arcade mechanic; all names, rules, art, sound, geometry, and levels are original. No Atari assets, trademarks, or copied boards.

## Intended play

Choose solo versus three configurable bot shields or local pass-and-play/paired-controller mode; steer a shield on an arc around your keep and redirect a shared energy orb through rivals' destructible ramparts. Last keep standing wins. Earn local stars for clean deflections and survival, unlock arena variants and cosmetics, then retry with changed bot difficulty. Mouse/keyboard/gamepad on Windows; touch drag and on-screen buttons on phones/tablets. No multiplayer server. Four-human input needs distinct devices/controllers; touch is one local player in MVP.

MVP: deterministic ball/shield collision rules, four keeps and destructible wall segments, AI opponents, short rounds, local scores/progression, three arenas, pause/settings (audio/remap/accessibility), save/restore, adaptive HUD, impact audio/particles/camera feedback. Non-goals: copied classic levels, online matchmaking, user accounts, purchases, social features, physics-perfect retro emulation, or medical/safety claims. Engine non-goals, explicit: no Unity, no Flutter, no React Native, no Expo, no Kotlin Multiplatform, no .NET MAUI, no custom or browser-only engine — Godot 4 only.

## Privacy / permissions / storage

Local versioned JSON under Godot user data for settings, stars, and records. No network or device permissions required; no telemetry. Deleting app data clears records. Corrupt, unsupported, or externally changed saves are preserved rather than silently replaced. User-triggered backup/import remains issue #7.

## Platforms and development

Godot 4.7.2-stable, GDScript, Windows Desktop primary build; Android and iOS phones/tablets committed builds later. Linux/macOS/Web exports planned, not verified. `com.infinityball.keepclash` is Android `application/unique_name`, iOS bundle ID, and prospective MSIX identity. App Store Connect: `CREATED com.infinityball.keepclash`; repository ASC secret names: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` (values never stored here).

Install pinned Godot 4.7.2-stable editor and matching export templates, then run `godot --headless --path . --import --quit` and `godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`. Local Linux arm64 import + GUT pass in issue #1; CI covers Linux x86_64 and Windows editor import/tests. `export_presets.cfg` configures unsigned Windows/Android/iOS outputs, but does **not** prove Android/iOS export builds. Windows `v*` GitHub release workflow is issue #8; mobile store submissions come later.

## Play this build

Install pinned Godot 4.7.2-stable and run `godot --path .` (or open project in editor). Choose **SOLO ROUND** for bottom keyboard seat versus three bots; cycle bot difficulty on menu. **SEAT MAPPING / COUCH PLAY** lets you claim distinct keyboard, mouse, touch or connected gamepads for any of four seats (D-pad/shoulder press claims a gamepad); unclaimed seats fill with bots. Keyboard A/D or ←/→ rotates your shield; mouse aims toward arena point near claimed keep; gamepad left-stick X rotates; touch drag rotates. Esc/P pauses or resumes; pause menu offers restart/menu; round-over offers rematch/menu. Stars and records save to versioned `user://keep_clash.json`; arena variants unlock at 3 and 8 stars, shield/keep cosmetics at 3 and 6. Settings menu adjusts audio, control bindings, HUD scale, contrast and motion live; changes persist across restarts. Device mapping is local; real phone/controller inputs remain to be checked on hardware. Run `godot --headless -s tools/smoke_ten_rounds.gd` for the 10-round headless smoke and the GUT command above for tests. Bot-only courtyard rounds in the current smoke end on the 90 s clock, not a knockout; balance remains open.

`AppStore/description.txt` is draft listing copy. `AppStore/icon.png` is real generated OpenAI Images art (`gpt-image-2.5-flare` via spark-media); platform icon wiring remains issue #8. Assets and license status: [assets/README.md](assets/README.md). Forward+ PBR materials, glow/SDFGI configuration, impact particles, camera shake and procedural tones are implemented with headless unit-test coverage only, not GPU/rendering verification. Mobile renderer effect scaling and device frame budgets remain unmeasured. Image-to-mesh proof landed as a decimated orb; #15 replaces the primitive shield with hand-authored layered metal/stone GLBs and a reproducible GDScript modeler. #14's original crenellated masonry keep is authored in `tools/gen_keep.gd`, with stone/metal surfaces, four seat tints and the taller gold-blended gilded skin; pinned Linux import/GUT/smoke pass (commands and limits in asset tracker). Rendered frame budgets and audio assets remain pending. No new image/AI-mesh generation was used for the manual keep or shield.
