# Asset origin tracker

Every shipped asset gets a row here. Origins: `ai-generated` (spark-media image → mesh pipeline), `primitive` (clean Godot primitive/simple shape, deliberate), or `manual-pending` (AI attempt failed; a "Manual 3D asset: <name>" `art-asset` issue carries the spec and stays open until the manual model lands).

| Asset | Origin | Source / issue | Notes |
|---|---|---|---|
| AppStore/icon.png | ai-generated | `gpt-image-2.5-flare` via spark-media, 2026-10-22 (`~/media/keep-clash/images/20261022T050732Z_openai_181ed0.png`) | 1024×1024, no text; platform icon wiring = issue #8 |
| Keep mesh | primitive | Godot CylinderMesh / #4 | Deliberate seat-tinted PBR metal |
| Shield mesh | primitive | ArcMesh / #4 | Deliberate PBR metal, emissive tint and edge rim lighting |
| Ball/orb material | primitive | Godot SphereMesh / #4 | Deliberate polished PBR metal with amber emission |
| Arena set ×3 | pending (issue #4/#5) | — | primitives acceptable for layouts |

Image→mesh pipeline proof is still pending in #4: GPU contention with shared inference blocks that work; no generated gameplay meshes have landed. A keep reference image was generated via OpenAI Images `gpt-image-2.5-flare` at `~/media/keep-clash/images/20261026T041556Z_openai_01bba5.png` (1024×1024, 1,086,158 bytes); it remains outside this repo, unreviewed for modeling, not an accepted mesh. Impact tones are procedural PCM, not audio asset files.

Large binaries (`.png .jpg .webp .glb .fbx .ogg .wav .woff2`) go through Git LFS configured in issue #1. No third-party CC assets are currently included; LICENSE is MIT (code + original assets).
