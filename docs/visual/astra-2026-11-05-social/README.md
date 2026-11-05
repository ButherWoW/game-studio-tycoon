# V18 UI Art

15 season, game-jam, hackathon, visit/rating, codes and menu assets. Season/game-jam headers1600×400; hackathon1600×300; all other icons/frames256×256.

Final PNGs are in V18/. ContactSheet.png previews the complete set; IconQA44.png shows small icons at44×44. VALIDATION.json records exact dimensions, alpha ranges, center-alpha checks and SHA256 hashes. Exact built-in ImageGen prompts and generated source paths are retained in prompts.json.

Export preserves aspect ratio: transparent assets fit inside the target canvas; opaque boards/headers use a centered cover crop. Daily card interiors are intentionally filled, with near-opaque alpha normalized to255; the season level frames have genuinely transparent centers for reward overlays. Backgrounds/headers are fully opaque. Transparent icon edges retain antialiasing.

Dev1: upload individual PNGs as Images in Creator Hub and pass each filename plus Image ID to Dev2. Dev2: connect images to the matching daily reward/season/social UI, preserve listed aspect ratios and draw dynamic reward/day/status text in code. Use season tier PNGs as frame overlays rather than filled cards. No game code or uploaded asset IDs are changed here.

QA: all assets visually reviewed; small icons checked at44px. Headers read SEASON 1, GAME JAM and HACKATHON NIGHT ×2 without clipped text. Studio/mobile integration play-test remains for the developers. The Game Jam header and menu icon received targeted ImageGen edits to fix headline cropping and remove a painted background; the edit history is retained in the social package.
