# V14 — VIP status and monetization artwork

Five original PNG assets: vip_crown (256×256 transparent), starter_pack_banner (1024×512), deal_badge (256×256 transparent), gift_icon (256×256 transparent), group_banner (1024×512). Blue #3D7BFF, gold #FFC93C, violet/pink #D65CA8, thick outline #1E1E2E. Text appears only as STARTER PACK and -30%, where requested. Group banner has no writing. The starter cartridge shows an original peaceful astronaut; no weapon illustration is retained.

Made with built-in OpenAI ImageGen; exact prompts and the starter revision chain are in prompts.json. Original aspect ratios are preserved during final PNG normalization. V14_ContactSheet.png supports review.

## Native overlay models

V14/models contains VipSignFrame (16 Parts) and VipChair (19 Parts), each RBXM/RBXMX, with no Seat, scripts, external meshes/textures or lights. Native original geometry and source are included. Templates are overlays, not replacements for the functional Chair or sign board.

VipSignFrame pivot is the **board center**, an explicit V14 exception to the floor-base rule. Its outer ring is14.9×3.85×.32, around the live14×2.2 board. The entire name area stays open. It clears the code-generated side strips at X±7.1 and top/bottom strips at Y±1.2; check_overlay.py conservatively tests horizontal length14.4 rather than the actual14.3.

VipChair pivot matches the accepted Chair base(0,0,0). Gold arm, seat and back piping plus the five-spoke wheel trim sit outside the original solids. Actual native Part OBB SAT against the accepted Chair reports no intersections. The functional Chair, its PcSeat and seating position remain in place; do not substitute this open trim skeleton for the chair. source/reference/Chair.rbxmx is only a reproduction/QA reference, not an additional model to import.

## Integration and verification

Dev1: put VipSignFrame and VipChair in ServerStorage or ServerStorage.Upgrades. VipService clones them at board.CFrame and Chair:GetPivot(), disables collisions and supplies existing effects. Upload PNGs as Images, send IDs to Dev2; vip_crown maps to Images.vip. Other button/banner keys belong to the integrating developer.

Rebuild models with python3 source/build_vip.py and python3 source/check_overlay.py; Python numpy/Pillow and Rojo are required. Previews show actual generated geometry, including VipChair_OnAcceptedChair.png. MODELS_VALIDATION.json plus VALIDATION.json record bounds, part budgets, pivots, clear name area, no Seat/lights/scripts and solid-overlap checks.

Studio playtest has not been performed. Verify two sign faces, name length, crown particles at32px, actual VIP activation/deactivation, sitting, transitions between floors/styles and phone readability/FPS. Graphic banners do not create products or change prices.
