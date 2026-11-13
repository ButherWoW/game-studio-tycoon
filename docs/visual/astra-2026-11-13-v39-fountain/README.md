# V39 Fountain — sloping native bowls, following the cartoon direction

Replacement `Fountain` for #26 V39 (6740315194). Bowls use continuous inclined wedge panels instead of stacked opaque disks. Mortar joints, a broad basin rim, twelve gold rim pearls and eight pedestal medallions provide large readable detail. Muted periwinkle stone, darker base and restrained gold; no bright-white finish, textures or third-party assets. This is native faceted geometry, not a smooth imported mesh or photorealistic stone.

## Deliverables

- `models/Fountain.rbxm` and `.rbxmx`: **306 native Parts**, 303 visible and three invisible effect proxies. All Anchored; no scripts, lights, external mesh/texture IDs or plugins.
- Bounds: **10.8 × 4.155 × 10.8 studs**, bottom Y=0; base-center pivot, identity orientation. Circular composition has no required facing direction. Foundation matches the accepted model's 10.8-stud footprint.
- `previews/`: front, three-quarter and top views rendered from the exported geometry. Static previews omit runtime particles, not game screenshots.
- `source/`: original parametric geometry, exporter, renderer, validation, binary roundtrip check and proposed integration patch.

## Integration — Dev 1 / Dev 2

Dev 1: back up the existing `ServerStorage.Fountain`, import ONE of the two model formats, retain the exact name `Fountain`. Do not import the source reference or roundtrip files into the game. Model scale starts at 1. Current WorldService uses relative `ScaleTo(GetScale() * World.fountainScale)`; keep its 1.7 multiplier (world footprint 18.36 studs). Verify both template consumers and remove the previous live fountain instance before rebuilding. Do not stack old/new fountains.

Preserved FountainFx contracts: `JetTop` (world-Y thickness .03), `LowerBowl`, `UpperBowl`, `LowerWater`, `UpperWater`, `BasinWater`. Bowl names now refer to invisible full-width emitter proxies, so sprays originate across the whole bowl rather than one narrow wedge.

**Dev 2: apply `source/FountainFx.proposed.patch` separately.** It makes the existing water-color lookup prefer `<name>Surface` and fall back to the old name. The actual basin water is `BasinWaterSurface`; invisible `BasinWater` supplies correct diameter and world-Y thickness for the existing ripple formula. Without the one-line patch, particles/ripples work but the basin color pulse affects its invisible proxy. Lower/UpperWater retain their original names and work with the existing lookup. No client gameplay file is changed by this art PR. Reference is the current client controller, not a replacement to import.

No static WaterCascade droplets are included: the current FountainFx already makes animated water. Water and stems occupy adjacent height ranges rather than overlapping solids. Tiny angular mortar joints separate bowl panels; this is deliberate native construction, not a seamless mesh. All physical panel colliders are anchored; water, ornament and effect proxies have collision disabled.

## Validation and limits

45,753 visible-part pairs have explicit convex support-plane separation, tolerance 0.000003 studs; zero unresolved pairs. Invisible effect volumes are metadata, not solid geometry, and are excluded. RBXM roundtrip checks part names, shapes, transforms and pivot. Details in VALIDATION.md/json and ROUNDTRIP_VALIDATION.json.

**306 parts is a material increase over the previous fountain.** V39 gives no fountain-specific cap (the ~60 limit belongs to Pigeon). Phone FPS and rendering cost have NOT been tested; mobile review is required before replacing the published place. If too costly, reduce radial segment counts in build.py and rerun geometry validation. Do not treat CI lint as an FPS result.

Rebuild: Python 3.9+, `numpy==2.0.2`, `scipy==1.13.1`, `Pillow==11.3.0`; Rojo 7.4.4. Set `ROJO=/path/to/rojo` if not using the author's tool path. Run source/build.py, source/validate.py and source/roundtrip.py. source/render.py regenerates the three previews.
