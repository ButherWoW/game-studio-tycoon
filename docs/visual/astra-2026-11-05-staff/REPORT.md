# V13 validation and integration report

All15 face textures are pixel-distinct and fully transparent outside the artwork. Thirty clothing PNGs follow the exact official585×559 UV rectangles. Real neckline masks remove alpha rather than paint a transparent shape over an opaque fill. Hair XML has an Accessory root, one Handle, HatAttachment, Massless unanchored noncolliding Parts and valid WeldConstraints to Handle. No hair assembly exceeds30 Parts.

A conservative native-Part bounding-box test checks every visible hairstyle component against the entire declared Head box. All15 pass with zero intersections, including caps, glasses, monitor shell, hood and crown. Handle is intentionally tiny, invisible and centered inside Head; it is excluded from visual overlap checks. Intentional overlaps between connected hairstyle pieces form continuous assemblies. The optional cape is separately attached to the torso, not the head.

Three contact sheets and15 card previews use the generated clothing and face PNGs on a segmented block rig, with the same local Part transforms exported to XML. Robo's face maps to the actual monitor screen; Ghost body transparency is explicitly rendered as the required runtime override. No PointLights are present; emissive eyes use Neon. Colors follow Employees specializations, with robot/ghost special-material exceptions from the V13 brief. The skull/hair envelope test is for the declared prototype dimensions only.

Studio work remains: upload image IDs, attach hairstyles through Humanoid:AddAccessory, apply FaceScreen mapping for Robo and body appearance for Ghost, apply the extra cape to Legend, then verify target R15 proportions, hat/head attachment alignment, seating/walking animation, cape/chair clearance, clothing seams and visibility at10studs/phone size. These are actual integration requirements; no gameplay code or NPC scale settings were changed in this package.

The generator source, per-batch SVG artwork, UV map, placement/CFrame manifest, PNGs and validation outputs make the assets reproducible and reviewable. All assets are original, with no brands or third-party art.
