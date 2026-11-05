# V26 — game pass and developer product icons

Thirteen original shop icons for Build Your Game Studio Tycoon. Final assets are in V26/, each opaque PNG512×512. Visual family: royal blue background, gold #FFC93C, blue #3D7BFF and thick #1E1E2E outlines. No brands or real console designs. Text is limited to ×2, + and +1 where the specification explicitly permits it.

## Asset mapping

| Filename | Product |
| --- | --- |
| gp_doubleCash.png | Double cash |
| gp_autoRelease.png | Auto release |
| gp_fastDev.png | Fast development |
| gp_extraSlot.png | Second project slot |
| gp_vipOffice.png | VIP office |
| gp_legendaryEmployee.png | Master Pixel employee, own V13 character |
| dp_instantFinish.png | Instant finish |
| dp_patch.png | Patch +1 |
| dp_coffee.png | Coffee boost |
| dp_income10.png | Small income bundle |
| dp_income30.png | Medium income bundle |
| dp_income90.png | Large income bundle |
| dp_ads.png | Shared advertisement icon for four campaigns |

Made using built-in OpenAI ImageGen, one call per requested icon. Exact prompts and source paths are preserved in the three prompt manifests. Final dimensions and opacity are checked in VALIDATION.json. Contact sheets provide the full-square version, the420px circle crop and small-size review. Circle safety is also visually reviewed; it is not inferred from image dimensions alone.

## Handoff

Dev1: use the six gp_ icons as the images for the existing game passes, and the seven dp_ icons as the images for the corresponding existing developer products. These images do not create products or alter prices. Keep production and v2 universe IDs separate; do not create duplicate products merely to replace an icon. Update art for the four advertising campaigns with the shared dp_ads icon.

Roblox crops product icons to circles. Keep the supplied square backgrounds; do not trim transparent padding (there is none), enlarge foreground artwork or crop out the safety margin. The circle QA sheet previews the intended safe region.

Dev2: no gameplay code changes are included. If these icons are also shown in a custom in-game shop, assign returned Image IDs to the appropriate config keys. Purchase/receipt verification remains the existing server logic. Verify final moderated uploads at small size in the actual Roblox purchase window.
