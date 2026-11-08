# Asset origin tracker

Every shipped asset gets a row here. Origins: `ai-generated` (spark-media image → mesh pipeline), `primitive` (clean Godot primitive/simple shape, deliberate), `manual` (original hand-authored geometry, including scripted modeling), or `manual-pending` (AI attempt failed; a "Manual 3D asset: <name>" `art-asset` issue carries the spec and stays open until the manual model lands).

| Asset | Origin | Source / issue | Notes |
|---|---|---|---|
| AppStore/icon.png | ai-generated | `gpt-image-2.5-flare` via spark-media, 2026-10-22 (`~/media/keep-clash/images/20261022T050732Z_openai_181ed0.png`) | 1024×1024, no text; platform icon wiring = issue #8 |
| Keep LOD0/LOD1/LOD2 | manual | `assets/references/keep.png` (mood only), #4, #14; `tools/gen_keep.gd` → `assets/models/keep_lod0.glb`, `keep_lod1.glb`, `keep_lod2.glb` | Original crenellated masonry tower with seat-metal band and forged details; imported counts 5,344 / 1,376 / 384 against ceilings 6,000 / 1,500 / 400. Pinned Godot import and GUT pass; rendered/device review and performance remain unverified. |
| Shield LOD0/LOD1/LOD2 | manual | `assets/references/shield.png`, #4, #15; `tools/gen_shield.gd` → `assets/models/shield_lod0.glb`, `shield_lod1.glb`, `shield_lod2.glb` | Original layered horizontal arc: beveled seat-metal plates, stone backing, forged perimeter bands/end caps and dome rivets. 1,532 / 556 / 268 triangles against ceilings of 4,000 / 1,000 / 300. Runtime GLB wiring verified with pinned Godot import/GUT; rendered/device review remains unverified. |
| Orb | ai-generated | `assets/references/orb.png` → `assets/models/orb.glb` | OpenAI Images `gpt-image-2.5-flare` → Hunyuan3D 2.1; largest connected body simplified from 556,894 to 2,039 triangles; 0.35m radius scale; metallic PBR amber emission; gameplay collision remains deterministic `MatchRules` sphere. One LOD only; no device frame budget measured. |
| Arena set ×3 | primitive (issue #5) | — | layout variants remain pending; #5 tracks them |

All reference PNGs and exported GLBs are Git LFS. Generated references were created on 2026-10-26 (keep) and 2026-11-03 (shield/orb); output source paths: `~/media/keep-clash/3d/20261103T042346Z_mesh_85de9b_00002_.glb`, `~/media/keep-clash/3d/20261103T043056Z_mesh_b7f822_00002_.glb`, `~/media/keep-clash/3d/20261103T043249Z_mesh_1dc05a_00002_.glb`. The original full-resolution meshes stay outside the repo. The workflow had a dangling CLIPVisionEncode input `15`; repaired local helper graph to reference `LoadImage` node `2` before generation. Headless Godot import and GUT prove resource wiring, not visual quality or GPU frame performance. Impact tones are procedural PCM, not audio asset files.

Large binaries (`.png .jpg .webp .glb .fbx .ogg .wav .woff2`) go through Git LFS configured in issue #1. No third-party CC assets are currently included; LICENSE is MIT (code + original assets).

## Manual battle shield (#15)

The rejected AI shield had 260,210 faces and an upright prop orientation; it is not used. The replacement is original geometry modeled with explicit cross sections and rivet placement in `tools/gen_shield.gd`, using `assets/references/shield.png` as a broad metal/rim design reference, not as input to another generation job. No new image/AI-mesh generation, textures, Blender or third-party art is required.

All three static GLBs have an identity-transform keep-origin pivot. At zero rotation the arc faces local +X, with X/Z radial distance centered on `MatchRules.SHIELD_RADIUS` (2.3 m), inner/outer vertex radii 2.14 / 2.46 m, angular endpoints `±MatchRules.SHIELD_HALF_ARC * 0.95` (±42.75 degrees), and Y from 0 to 0.7 m. Nominal thickness is 0.32 m. Surfaces are seat-metal (metallic 0.75, roughness 0.24, emissive), stone (0.0 / 0.86), and forged rim/rivets (0.85 / 0.30), imported as `StandardMaterial3D`. Only the metal surface gets the existing per-seat PBR/emissive/rim-light material override, preserving the stone and rim layers. Aurora retains brighter tint/emission and a 1.0 m height by scaling Y only; the 0.7 m baseline model and collision rules remain unchanged.

The round retains `_shield_nodes` keep-origin pivots and `_shield_mats` seat references, rotating each pivot by `-shield_angle` about Y. Explicit LOD instances have 40 and 60 m visibility thresholds; actual switching and device frame budgets remain unmeasured. Models contain no physics bodies, collision meshes, skeletons or animations. Deterministic collision remains entirely in `MatchRules`.

Reproduce with the pinned Godot 4.7.2-stable editor, from this worktree:

```sh
godot --headless --path . --import --quit
godot --headless --path . -s res://tools/gen_shield.gd
godot --headless --path . --import --quit
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Local #15 verification (2026-11-05): pinned Godot 4.7.2-stable Linux arm64 editor (official `ed1daf0bf`) imported all three GLBs, regenerated them twice from `tools/gen_shield.gd` with identical SHA-256 hashes, and passed GUT (87/87 tests, 1,968 assertions) plus the 10-round headless smoke (`SUCCESS: 10 consecutive rounds completed cleanly`). The GUT tests inspect actual imported surfaces/materials/dimensions, generator topology parity, all seat/layout pivots and rotations, LOD wiring, aurora, and live contrast. All three GLBs use Git LFS. Generation and smoke report a two-ObjectDB-instance leak warning at exit; no failures. No visual, screenshot, GPU/frame-budget, mobile or device checks are claimed; these still need measured review.

## Manual castle keep (#14; renderer/device review pending)

The rejected AI keep (943,544 faces, 322,666 disconnected bodies) is not used. The new source is hand-authored in `tools/gen_keep.gd`: staggered stone blocks around a flared tower foot, eight separated crown teeth, metal caps, a seat-colored band/plates and forged slit-window frames/studs. The reference contributes only a stone/metal mood; its pointed roof and turret arrangement are not copied. No new image/AI-mesh generation, textures, Blender, third-party assets or dependencies are used.

All LODs target an identity-transform ground-center pivot at (0,0,0), Y up, Y bounds 0–1.6 m and X/Z bounds ±0.65 m. LOD1 removes stone bevels and reduces courses/segments; LOD2 keeps the complete crenellated silhouette, seat band and simplified window details. The four non-emissive `StandardMaterial3D` surfaces are `SeatMetal` (metallic 0.5 / roughness 0.32), `Limestone` (0.0 / 0.86), `Mortar` (0.0 / 0.95) and `ForgedIron` (0.85 / 0.30). Only surface 0 receives the existing four-seat material override. Human gilded seats retain gold-blended tint and a 2.0 m height through Y scaling (ground contact stays at 0); stone and forged materials stay intact. High contrast, elimination and reset continue using the shared per-seat material across all LODs.

Runtime ranges match the shield: [0,40), [40,60), [60,∞) m, without range margins/fades. Meshes are static visuals only: no physics bodies, collision shapes, skeletons or animations. `scripts/match_rules.gd` is untouched; its analytic 0.45 m core collision is independent of the 0.65 m visual base radius and skin height.

Local verification (2026-11-06): official Godot 4.7.2-stable Linux arm64 (`ed1daf0bf`) generated and imported all three GLBs. Re-running `tools/gen_keep.gd` produced identical SHA-256 hashes for each GLB. GUT passed 92/92 tests and 3,141 assertions across 8 scripts; `tools/smoke_ten_rounds.gd` printed `SUCCESS: 10 consecutive rounds completed cleanly`. Generator and smoke emitted two ObjectDB-instance leak warnings at exit. All three GLBs are stored through Git LFS.

```sh
godot --headless --path . --import --quit
godot --headless --path . -s res://tools/gen_keep.gd
godot --headless --path . --import --quit
godot --headless --path . -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
godot --headless --path . -s res://tools/smoke_ten_rounds.gd
```

`tests/test_keep_model.gd` inspects imported triangle counts/materials/bounds, generator topology parity, crown gaps, seat/layout/skin wiring, contiguous LOD ranges and core contact distance. A Linux llvmpipe/OpenGL Compatibility Xvfb render probe (`tools/capture_keep_review.gd`) now checks projected keep centers and tips stay inside phone 360×800, tablet 800×1280 and desktop 1280×720 frames, and writes actual PNGs under `assets/captures/keep/`. On 2026-11-08 it exposed clipped left/right keeps at 360×800 and 800×1280 before the camera-FOV correction; after the correction all three capture checks passed. This is software-rendered framing evidence, not human visual approval, native Mobile/Forward+ performance, observed LOD switches, or physical device review. #14 stays open until those remaining checks are measured.
