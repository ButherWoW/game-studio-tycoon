# Premium interior finishes — integration contract

Owner requested additional paid interior skins (floors, walls and architectural trim). Deliver three independent premium finish sets, separate from furniture V15: ObsidianGold, Sakura and Aurora. No prices or product IDs are assigned by the asset pack.

## Preserve two independent choices

Current StyleModels reads profile.furniture.selected and applies one suffix to every model. Do not add these themes only to that list: choosing a floor must not reset a player's purchased furniture style. Use a separate persisted interior-finish ownership/selection and a separate studio-shop category. Apply finish suffixes only to Garage, GarageWalls, Office, Floor and Skyscraper; ordinary furniture and V9 decor keep the existing furniture choice.

Templates use GarageWalls_<suffix>, Office_<suffix>, Floor_<suffix>, Skyscraper_<suffix>. For the early stage model named Garage, resolve GarageWalls_<suffix> as the garage finish template if appropriate; retain the live clone name Garage. Once GarageWalls upgrade exists, preserve PlotService's existing superseded-shell rule so the scene does not contain both shells. Never append a premium shell over the original: replace the selected template once.

## Floors and ceilings

Keep templates at their local base origin. Stage placement remains the game's responsibility (office0, floor14, top28, plus current plot/base offsets). Do not bake stage height into the templates. Furniture, NPCs, lift, upper-entry glazing and purchase buttons keep their existing placement.

OfficeFloors.buildSlab creates dense structural slabs whose top is localY−0.01, below the decorative upper floor volume0..0.02. Keep those structural slabs: they prevent furniture from showing through. Set the underside/ceiling Color and Material from the selected finish's ceiling palette instead of adding a second ceiling panel. Office and Floor finish templates have no full roof; only Skyscraper has its roof at13..14.

The reserved lift area is X−23..−17, Z21..27, Y0..7 above the common floor. It contains only the continuous decorative floor; no panels, mouldings or props. Upper entrance glass remains supplied by OfficeFloors. Garage keeps its accepted shell geometry and floor volume, as documented in its validation.

## Paid ownership

Dev2 should connect the separate finish selection and server-authoritative purchase receipt to the three finish IDs. Product creation, final Robux prices and product IDs belong to the owner/Dev1. While IDs are absent, present the theme as unavailable/coming soon using the existing game convention. Product granting and ownership should be idempotent, and changing finish should not alter money production, purchased furniture, staff assignments or floor unlocks.

## Dev1 import/test

Import one format per template into ServerStorage.Upgrades, keeping exact names. Do not import assembled showcases as upgrades. Upload the three shop preview PNGs as Images and pass the Image IDs to Dev2.

Test every theme on garage and all three stacked floors, then combine with Classic/Neon/Cozy/Minimal furniture. Check floor coverage and seams, wall/window clearances, doors and lift, room approach paths, NPC sitting, VIP trim, long studio names, camera hiding of upper floors and mobile FPS. Also test rejoin, moving to the next floor, Rebirth and switching themes without losing furniture style. Asset checks are not a Studio playtest.
