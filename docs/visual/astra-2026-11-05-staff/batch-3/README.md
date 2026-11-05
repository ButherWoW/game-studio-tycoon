# V13 employee appearance — batch 3

leo, vera, robo, ghost, legend. Five original baseline appearances, separate from paid V12 outfits. Every employee has a unique transparent256×256 face, native-Part hair Accessory,585×559 shirt/pants UV templates,512×512 full-body preview and exact SVG artwork sources. Specialization colors follow Employees.luau.

Use face_<id>.png as Head front Decal, hair_<id>.rbxmx through Humanoid:AddAccessory, and uploaded look_<id>_shirt/pants images as ShirtTemplate/PantsTemplate. All hair assemblies have one Handle, HatAttachment, rigid WeldConstraints, unanchored massless noncolliding native Parts; <=30 Parts and no scripts, external meshes/textures or lights. Standard attachment matches the declared prototype rig; align on the actual game NPC before release.

## Target assumptions and integration

Prototype head is a centered1.18×1.20×1.05 block, HatAttachment local(0,.5,0), front−Z; torso is2×2×1. Model Part coordinates are head-local. Every visible hair Part conservatively clears the entire head box; caps and crown sit above it rather than inside. Faces and clothing are mapped exactly from generated PNGs in the preview. Preview is CPU geometry rendering, not a Studio screenshot.

Robo uses a hollow monitor shell around the Head: place face_robo on FaceScreen front surface(−Z), not on the hidden default Head. Keep the Head itself for the rig. Native Neon eyes supply emissive shapes; the uploaded PNG alone cannot emit light. Ghost requires body color#9AD9EA and BasePart Transparency=.35 at runtime, including head, while keeping hair hood geometry at its authored transparency and Neon eyes visible. Its preview applies these appearance overrides. Legend includes an extra look_legend_cape.rbxmx, a separately welded BodyBackAttachment Accessory; attach it to torso with Humanoid:AddAccessory. Never weld the cape to the Head. Manifest records these overrides.

## QA

VALIDATION.json confirms atlas dimensions/alpha, unique facial textures, face/head bounds, Part budgets, no visible hair geometry inside the declared head envelope, allowed classes and weld references. Official template boundary coordinates match Roblox classic clothing maps. R15body scaling/HeadAttachment positions vary: Studio QA must verify actual NPC proportions, camera distance10studs, seated and walking animations, face target normals, arm/waist/ankle seams, hairstyle visibility, hats under custom heads and cape seating clearance. Transparency/clothing rendering and accessory physics must be tested in Studio; prototype acceptance is not a completed runtime test.

Original artwork authored as SVG and native geometry; no brands, third-party artwork or font-rendered lettering. SVGs rasterized with resvg. Faces, braids/buns/ponytails, clothing details and silhouettes are original.
