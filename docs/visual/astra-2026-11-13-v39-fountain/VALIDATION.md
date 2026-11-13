# Validation — V39 Fountain

- PASS: Model + Part + WedgePart only, all 306 Parts anchored; no scripts, lights, MeshId or texture references in the exported model.
- PASS: 303 visible solids; 45,753 pairs checked using analytic convex support functions for boxes, wedges, ellipsoids and native cylinders. Every accepted separation axis is re-evaluated as a support-plane certificate; zero unresolved pairs at 3e-6 studs tolerance. Three invisible effect proxy volumes are excluded explicitly.
- PASS: local bounds [-5.4,0,-5.4] to [5.4,4.155,5.4], foundation footprint retained, pivot at base center with identity rotation. No arbitrary facing requirement for the circular fountain.
- PASS: RBXMX → RBXM → RBXMX roundtrip, 306 matching part names/shapes/transforms; pivot verified in both files (2e-6 transform tolerance).
- PASS: front, three-quarter and top geometry previews inspected. Two inclined faceted bowls, open water areas, relief and rim ornament visible; no static water-drop swarm or baked lettering.
- INTEGRATION: exact JetTop/UpperBowl/LowerBowl/water lookup names verified against the current FountainFx snapshot. Proposed one-line fallback patch is supplied separately so the basin water color pulse reaches the visible surface; it is not applied to client code by this art batch.
- NOT RUN: Studio import/Play, live water animation or phone FPS. Offline native geometry validation does not establish device performance. This 306-part model requires mobile acceptance before publishing.
