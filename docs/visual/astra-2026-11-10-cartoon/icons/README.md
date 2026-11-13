# Cartoon UI icons — batch 1, brief #359 / #26 (10 November)

15 original glossy cartoon PNGs, 512×512 RGBA. The ten menu symbols are reused for corresponding window headers; five additional symbols cover financial windows. No lettering, numbers, third-party logos or copied game assets. `PREVIEW_80px.png` shows every symbol at actual 80px size on dark and light backgrounds.

| File | Meaning | Existing key or integration instruction |
|---|---|---|
| icon_studio.png | Studio, garage + computer | Images.menu.menu_studio |
| icon_create_game.png | Create game | New slot: Dev 2 connects after Dev 1 upload |
| icon_upgrades.png | Upgrades | New slot: Dev 2 connects after upload |
| icon_team.png | Team | Images.menu.menu_team |
| icon_shop.png | Shop | Images.menu.menu_shop |
| icon_rebirth.png | Rebirth | Images.menu.menu_rebirth |
| icon_collection.png | Collection | New slot; not the guides book |
| icon_quests.png | Quests | Images.menu.menu_quests |
| icon_rating.png | Rating | Rating window; do not automatically replace achievement art |
| icon_settings.png | Settings | New slot: Dev 2 connects after upload |
| icon_bank.png | Bank | Images.menu.menu_bank and bank header |
| icon_taxes.png | Taxes | Images.menu.menu_tax and tax header |
| icon_exchange.png | Exchange | Images.menu.menu_stock and stock header |
| icon_contracts.png | Contracts | Images.contracts.contract / relevant header |
| icon_safe.png | Safe | Images.safe.icon |

Dev 1: upload the 15 root `icon_*.png` files as images, return IDs. Dev 2: assign IDs to menu/header slots, retain translated labels and responsive sizing. Art only: no code or existing image IDs are changed by this batch. The ten menu files also serve header use; duplicate uploads are unnecessary.

Built-in image_gen, transparent_background=true, one separate request per icon. Exact prompts: PROMPTS.md. Original generated images: source/. Delivered files are Lanczos-downsampled to 512 without painting, alpha removal or background extraction. Outline thickness is a visual generation target (~3–4px at 512), not a mathematically uniform vector stroke. Glossy colored bevels are intentional.

Reproduce normalization and checks: `python3 prepare.py` (Pillow 11.3.0). manifest.json uses portable source paths. VALIDATION.json includes dimensions, transparency, visible bounds and SHA-256 hashes. Roblox upload, moderation and live UI checks remain with Dev 1.
