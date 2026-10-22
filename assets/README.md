# Asset origin tracker

Every shipped asset gets a row here. Origins: `ai-generated` (spark-media image → mesh pipeline), `primitive` (clean Godot primitive/simple shape, deliberate), or `manual-pending` (AI attempt failed; a "Manual 3D asset: <name>" `art-asset` issue carries the spec and stays open until the manual model lands).

| Asset | Origin | Source / issue | Notes |
|---|---|---|---|
| AppStore/icon.png | ai-generated | `gpt-image-2.5-flare` via spark-media, 2026-10-22 (`~/media/keep-clash/images/20261022T050732Z_openai_181ed0.png`) | 1024×1024, no text; platform icon wiring = issue #8 |
| Keep mesh | pending (issue #4) | — | image→mesh attempt tracked in #4 |
| Shield mesh | pending (issue #4) | — | |
| Ball/orb material | pending (issue #4) | — | likely procedural/emissive, not a mesh |
| Arena set ×3 | pending (issue #4/#5) | — | primitives acceptable for layouts |

Large binaries (`.png .jpg .webp .glb .fbx .ogg .wav .woff2`) go through Git LFS configured in issue #1. No third-party CC assets are currently included; LICENSE is MIT (code + original assets).
