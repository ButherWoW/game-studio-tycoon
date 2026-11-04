# Employee skins V12 — batch 3

Four original skins: neon_streamer, cyber_dev, space_dev, wizard_dev. Premium tier with native Neon accessories.

Each includes 585×559 transparent PNG shirt/pants mapped to the official classic Roblox R15 layout, a native-part accessory collection, and a 512×512 preview. SVG artwork sources are included. UV map/reference and shared generators are provided in the parent directory. No third-party artwork, brands, text, scripts, meshes or external textures are embedded in accessories. Clothing uses original geometric artwork authored as exact SVG panels and rasterized with resvg; no image model generated or guessed the UV layout.

Preview is a local depth render using the actual exported clothing textures and the same accessory geometry on a segmented block rig, not a Roblox Studio screenshot or moderation guarantee.

## Import and test

Upload shirt/pants images and send IDs to Dev 2. For runtime Shirt/Pants, use ShirtTemplate/PantsTemplate texture IDs as appropriate; verify on Studio Block Avatar R15. The root skin_<id>_acc is a Model containing one or two Accessory instances. Extract children and add each using Humanoid:AddAccessory, rather than parenting the outer collection as one accessory. Each Accessory has Handle, one standard Attachment, unanchored massless noncolliding geometry and rigid welds. The collection PrimaryPart points to the first Handle. Maximum40 Parts total per skin.

Preview uses explicit canonical block-rig attachment coordinates and targetAttachment × inverse(localAttachment); actual NPC attachment frames/body scales may differ. Test attachment alignment on the game's actual NPC body/head scale, idle and seated poses, sleeve/waist/ankle seams, transparency, item clipping and phone readability. Head size variants can need attachment adjustments. Classic clothing cannot emit light; only the premium native accessories use Neon. No PointLights. No Studio/runtime test performed here.

Official mapping/testing reference: https://create.roblox.com/docs/avatar/classic-clothing
