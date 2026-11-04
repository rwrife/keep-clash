# Asset origin tracker

Every shipped asset gets a row here. Origins: `ai-generated` (spark-media image → mesh pipeline), `primitive` (clean Godot primitive/simple shape, deliberate), or `manual-pending` (AI attempt failed; a "Manual 3D asset: <name>" `art-asset` issue carries the spec and stays open until the manual model lands).

| Asset | Origin | Source / issue | Notes |
|---|---|---|---|
| AppStore/icon.png | ai-generated | `gpt-image-2.5-flare` via spark-media, 2026-10-22 (`~/media/keep-clash/images/20261022T050732Z_openai_181ed0.png`) | 1024×1024, no text; platform icon wiring = issue #8 |
| Keep | manual-pending | `assets/references/keep.png`, #4, #14 | The generated model had 943,544 faces and 322,666 disconnected bodies; keep the seat-tinted CylinderMesh until a manual model meets the art spec (#14). |
| Shield | manual-pending | `assets/references/shield.png`, #4, #15 | The image-to-mesh result (260,210 faces) is an upright prop, not the required horizontal arc gameplay collision silhouette; keep ArcMesh with emissive rim (#15). |
| Orb | ai-generated | `assets/references/orb.png` → `assets/models/orb.glb` | OpenAI Images `gpt-image-2.5-flare` → Hunyuan3D 2.1; largest connected body simplified from 556,894 to 2,039 triangles; 0.35m radius scale; metallic PBR amber emission; gameplay collision remains deterministic `MatchRules` sphere. One LOD only; no device frame budget measured. |
| Arena set ×3 | primitive (issue #5) | — | layout variants remain pending; #5 tracks them |

All reference PNGs and exported GLBs are Git LFS. Generated references were created on 2026-10-26 (keep) and 2026-11-03 (shield/orb); output source paths: `~/media/keep-clash/3d/20261103T042346Z_mesh_85de9b_00002_.glb`, `~/media/keep-clash/3d/20261103T043056Z_mesh_b7f822_00002_.glb`, `~/media/keep-clash/3d/20261103T043249Z_mesh_1dc05a_00002_.glb`. The original full-resolution meshes stay outside the repo. The workflow had a dangling CLIPVisionEncode input `15`; repaired local helper graph to reference `LoadImage` node `2` before generation. Headless Godot import and GUT prove resource wiring, not visual quality or GPU frame performance. Impact tones are procedural PCM, not audio asset files.

Large binaries (`.png .jpg .webp .glb .fbx .ogg .wav .woff2`) go through Git LFS configured in issue #1. No third-party CC assets are currently included; LICENSE is MIT (code + original assets).
