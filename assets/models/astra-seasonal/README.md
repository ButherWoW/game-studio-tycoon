# V7 seasonal props and exterior office preview

Four original native Roblox models: Pumpkin, HalloweenSign, HolidayTree and OfficeBuilding. Exact names are provided in RBXM and RBXMX. Import one format per model into ServerStorage.Upgrades for ModelFactory. No scripts, text, external meshes/textures or brands.

| Model | Parts | Width × height × depth |
|---|---:|---|
| Pumpkin | 20 | 2.64 × 2.5244 × 2.6051 |
| HalloweenSign | 18 | 2.8 × 3.95 × 0.75 |
| HolidayTree | 75 | 5.61 × 10.745 × 5.61 |
| OfficeBuilding | 146 | 60 × 39.6 × 60 |

Props face+Z with pivot at footprint center/baseY0. Seasonal props each contain one low-brightness PointLight, Shadows=false; ornaments and outlines are Neon with no individual lights. OfficeBuilding contains no lights. The pumpkin and sign use friendly original expressions without scary elements or lettering.

HolidayService already supplies placement and ghosting (CanCollide/CanQuery/CanTouch=false). It scales Pumpkin1.3 at plot corners and HolidayTree1.5 at spawn. Listed dimensions are original templates; the spawned tree can therefore reach about16.12stud high and8.42stud wide. This is existing runtime behavior, not a mesh/model size error. HalloweenSign is the persistent halloween_sign quest cosmetic. These models replace fallback primitives and require no gameplay changes.

**OfficeBuilding is an exterior preview/move model, not a gameplay shell.** It reuses the accepted Office/Floor/Skyscraper geometry with three storeys compressed uniformly inY by39.6/42. Storey pitch is13.2. This resolves the separate V7 preview height limit≤40 while runtime floor shells remain on0/14/28 with their normal42-stud total height. Upper entry apertures contain preview-only glass since no runtime code fills this standalone model. Thin separator bands close inter-storey gaps; ground facade side windows complete the open original office frontage. It contains no furniture, game elevator, roof access or code. Do not substitute it for Office/Floor/Skyscraper or stack it above gameplay floors.

`VALIDATION.json` checks native class allowlist, bounds, baseY0, budgets, lighting, three exterior storeys and Rojo binary conversion. `previews/` renders actual generated geometry with the in-house depth renderer; no generated concept images. Studio/gameplay placement, seasonal scale and mobile FPS still require tester verification.

Build with Python3, numpy, Pillow and Rojo:

```sh
python3 source/build_seasonal.py
python3 source/validate_seasonal.py
```

Rojo executable path is in build_seasonal.py. Copied office_base.py/floor_base.py/sky_base.py preserve the accepted geometry recipes used by this standalone kit. No repository/runtime source is changed by rebuilding.
