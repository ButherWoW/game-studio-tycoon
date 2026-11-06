# Office / Floor / Skyscraper window fix

12 canonical models: Classic, Aurora, Sakura, ObsidianGold. All 66 Glass panes retain material Glass and use Transparency 0.4. In each Office only the two NicheArt and two NicheArtFrame Parts at X16/20,Y5,Z−29.x were removed because they covered the rear window. Also removed 33 premium Skyscraper ornaments covering PanoramicRear: 5 AuroraRibbon, 6 ArtDeco details, 22 Sakura/Shoji details. The ArtDecoFrieze at Y12 is retained above the pane. ALLOWED_DELETIONS.json lists all 49 removed Parts with original referents and positions. Mandatory lighting normalization: retain the first PointLight in each model; delete the other three. Retained light uses Shadows=false, Range=60, Brightness=1; color, parent and all lamp geometry remain unchanged. No other properties changed. Frames remain opaque. All surviving geometry, seats, pivots and PrimaryPart references remain unchanged. No new geometry is introduced; this does not assert absence of pre-existing decorative joins.

CANONICAL_MAPPING.json maps model names to repository binary paths. Each model is supplied as RBXM and RBXMX; import one format. Repository source code is not part of this patch. Baseline snapshots match origin/main 0d12517866032fbaadf2031dc4dc7fa9c2c78469.

Reproduce with source/build.py; independently validate with source/independent_audit.py. Both require Rojo at the configured ROJO path. Audit compares all surviving properties and only permits the named removals and glass transparency change; checks dangling removed references and roundtrips every binary through Rojo. VALIDATION.json records hashes.

Four preview sheets group the three floors by finish. They are inspection cutaways: glass panes and roof are deliberately hidden to expose the window openings and interior. The renderer does not simulate Roblox Glass; Studio appearance and stacked-floor integration require runtime review. No Studio test was performed.

The initial 3%-area audit is superseded. Final zero-threshold review checks every positive projected overlap, including tiny art; window mullions/transoms and edge architecture remain permitted.
