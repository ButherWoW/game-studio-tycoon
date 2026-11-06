# V35 — Pigeon

| File | Native geometry |
| --- | --- |
| models/Pigeon.rbxm + Pigeon.rbxmx | 53 native Parts: 46 Part + 7 WedgePart; one existing body Part is PrimaryPart, no invisible pivot helper |

Original walking park pigeon: rounded ellipsoid body and head, short inclined green neck with violet/blue shimmer plumes, amber eyes, pale cere and pointed beak. Each wing has an oval side lobe and four elongated flight feathers tangent to its actual ellipsoid surface. Two small dark caps on each feather form the two characteristic wing stripes; each cap is likewise tangent to the feather surface. No unsupported flat-plane layers or round covert beads remain. Six narrow tapered tail feathers; thin angled legs, one foot advanced, individual toes. Soft muted gray-blue colors follow the accepted park. Native shape tessellation in previews is increased to show Roblox's smooth primitives faithfully; this does not add meshes or change Part geometry.

Import one model format into ServerStorage; Dev2 places separate birds in the park. Front +Z, pivot center of the complete footprint at (0,0,0), lowest toes Y0. All 53 Parts anchored and noncolliding. No scripts, lights, decals, meshes, external textures or upload dependencies. No optional flock included.

Visual reference: accepted assets/models/astra-park/previews/Park_GardenView.png. Current V35 brief was read from GitHub docs/VISUAL.md. The earlier pigeon model/preview was unavailable; this is an original model, not a claimed reconstruction. Grass/fence/hedge assets are unchanged.

Reproduce with source/build_pigeon.py, source/audit.py, source/roundtrip.py, source/render.py. Scripts contain the configured Rojo path; NumPy/Pillow are required. The independent audit reads only final XML and verifies all 1378 actual convex shape pairs using analytic support mappings for ellipsoid Ball, elliptic Cylinder, boxes and six-vertex WedgeParts. A pair passes only with an explicit separating plane whose support gap is at least −0.000001 studs; unknown or unresolved pairs fail. SEPARATION_CERTIFICATES.json records every plane, gap and search method. Conservative OBBs may overlap at smooth tangent joins: the final claim concerns actual native convex solids, not zero OBB overlap. Surface tangency and tiny contact gaps are allowed; no positive-volume intersection is accepted above tolerance. The helper's GJK/gradient iterations search for candidate planes; analytic support reevaluates each certificate before acceptance.

VALIDATION.json records actual count, native classes, anchoring, footprint/pivot, geometric certificates and hashes. Binary roundtrip compares every exported property, treating float32 differences up to 0.000001 as numerical serialization tolerance. Three previews show exported geometry from front, profile and three-quarter. Runtime Studio appearance and park mobile FPS were not tested; Dev1 should check both before placing many copies. Artistic acceptance is separate from numeric validation.
