# V13 — fifteen individual employee appearances

Three reviewable batches of five employees: each has its own transparent face, hairstyle, specialization-colored everyday clothing and full-body preview. These are baseline looks, separate from the paid V12 outfits.

- batch-1: mila, tim, zoe, ilya, oleg
- batch-2: sara, max, nika, den, aya
- batch-3: leo, vera, robo, ghost, legend

`batch-*/V13/` contains final PNGs and native Accessory RBXMXs. `batch-*/source-svg/` contains exact editable artwork. Each batch includes a contact sheet, README and VALIDATION. Shared source is in `source/`, with the exact official classic clothing UV map in `UV_MAP.json`. Runtime appearance exceptions are in `manifest.json`; local Part CFrames and target attachment assumptions are supplied separately for inspection.

Every face is unique,256×256 RGBA with transparent surroundings; clothing maps are585×559 RGBA; previews are512×512. Hairstyles are native Parts, each under30 Parts, outside the declared head envelope. Six female staff have real hair silhouettes: ponytail, twin buns, bob, long hair, high ponytail and bun. Small extras follow the individual V13 brief. No scripts, imported meshes, external accessory textures or PointLights.

Robo is a hollow monitor shell with a FaceScreen target and Neon eye geometry. Ghost has a hollow translucent hood with Neon eyes and explicit runtime body transparency. Legend has a pixel crown plus an additional torso-mounted cape; keep the cape's BodyBackAttachment separate from the head-mounted crown. Read the per-batch import instructions before integration.

These are prototype assets for the declared block R15 target: Head1.18×1.20×1.05, head-local HatAttachment(0,.5,0), torso2×2×1. Real game body/attachment scales and seated poses require Studio QA. The previews render actual UV textures and native accessory geometry; they are not Studio screenshots.

Rebuild from this kit directory:

1. `python3 source/build_staff.py`
2. `node source/rasterize.cjs` (install `source/package.json` dependencies if necessary)
3. `python3 source/render_validate.py`

Python dependencies: Pillow and numpy. SVG rasterization uses resvg, with a workspace installation preferred and the existing shared local installation as fallback. No image generation or third-party artwork was used. All artwork and geometry is original project-authored content. Official mapping reference: https://create.roblox.com/docs/avatar/classic-clothing .
