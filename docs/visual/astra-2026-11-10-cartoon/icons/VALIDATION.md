# Validation

- PASS: 15 PNGs, each 512×512 RGBA; transparent exterior and intermediate alpha present.
- PASS: nontransparent subject bounds have at least 6px clear edge padding; no clipped subject.
- PASS: inspected PREVIEW_80px.png on dark and light backgrounds: all 15 concepts recognizable at 80px, matching glossy cartoon palette and dark outlines, no visible letters/numbers/logos/watermarks.
- PASS: sources and exact independent generation prompts retained; reproducible normalization and hashes in VALIDATION.json.
- NOT RUN: Roblox Studio, phone emulator, image upload/moderation, actual menu/header rendering. Preview is an offline contact sheet, not a game screenshot.
