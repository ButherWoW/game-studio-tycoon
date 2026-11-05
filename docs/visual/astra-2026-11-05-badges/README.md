# V11 Roblox Achievement Badges

Twenty individually generated PNGs in `V11/`, 512×512 RGBA with transparent exterior. Built-in ImageGen was used once for each badge; exact prompts and original source paths are retained in `prompts.json`.

The whole medal is centered with a transparent margin. Export size normalization preserves the generated artwork; alpha pixels above 16 stay inside the central 420px diameter safety circle. `VALIDATION.json` records per-file measurements. `V11_ContactSheet.png` previews all twenty.

The rim shows bronze, silver, gold or special violet tier. No text or digits; the secret badge uses its required question-mark pictogram. The score badge contains exactly ten stars. Office lighting represents one, two and three unlocked floors.

Dev 1 creates Roblox Badges from the individual PNGs and records the resulting IDs in `src/shared/Config/Achievements.luau`. These files do not upload or modify game configuration automatically.
