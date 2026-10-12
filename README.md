# Guise

A lightweight, Masque-compatible button skinning engine for **World of Warcraft: Forever** (interface `16001`).

Guise restyles action buttons, pet/stance bars, bag buttons and any add-on button that supports Masque. It ships with skins built entirely from stock game art, so it adds no texture files.

> Guise is an independent, from-scratch implementation. It is **not** Masque and is not affiliated with or endorsed by Masque's authors. It implements the same public API so that existing add-ons can use it.

## Features

- **Masque API compatible.** Guise registers the `LibStub("Masque")` API, so add-ons with Masque support (Bartender4, Dominos, aura and bag add-ons...) skin through it automatically. Skins in the Masque format can be added with `LibStub("Masque"):AddSkin(...)`.
- **Skins the default UI.** All eight action bars, the pet, stance and possess bars, the extra action button and the bag buttons. Each bar is its own group.
- **Built-in skins:** `Classic` (the original 2004 quickslot art, the default), `Clean` (thin outline, trimmed icons), `Zoomed` (edge-to-edge icons), and `Blizzard` (leave the game's art alone).
- **Per-group settings** with inheritance: Global → Add-on → Bar. Set a skin once on Global, or untick *Inherit* on any group to style it separately. Backdrop, Gloss, Shadow and Off toggles per group.
- **Exact restore.** Turning a skin off puts every region back to precisely what the game had, including art the game changed while the skin was active.

## How it is optimized

| | |
|---|---|
| **No-op re-skins** | Each button stores a signature (settings epoch + size). Add-ons that call `Group:ReSkin()` frequently cost a table lookup instead of a full re-layout. |
| **Batched updates** | Option changes and size changes are queued and applied once on the next frame, however many happen together. |
| **Compiled skins** | Skin templates are flattened once, and per-layer/per-button-type lookups are memoized. |
| **Combat safe** | Re-anchoring protected (secure) buttons is deferred until combat ends instead of risking blocked actions. |
| **Taint free** | No fields are written onto Blizzard's secure buttons; all state lives in a weak-keyed table that also lets discarded buttons be garbage collected. |
| **No OnUpdate** | Guise reacts only to secure hooks and events; it does no per-frame work. |
| **Fault isolated** | A broken third-party skin or callback is reported, not propagated into the calling add-on. |

## Installation

1. Download or clone this repository.
2. Copy it into the `Interface/AddOns/` folder of your WoW Forever install and rename the folder to **`!Guise`** (the folder name must match `!Guise.toc`).
   The leading `!` makes Guise load before other add-ons, so add-ons that look for Masque when they load find it.
3. Restart the game.

Packaged builds made with the BigWigs packager are named correctly via `.pkgmeta`.

## Usage

- **Options:** *Esc → Options → AddOns → Guise*, or click Guise in the add-on compartment.
- `/guise` – open the options
- `/guise skins` – list installed skins
- `/guise skin <name>` – use a skin everywhere
- `/guise blizzard on|off` – toggle skinning of the default bars
- `/guise reset` – forget all settings

## Compatibility notes

- If the real **Masque** is installed and enabled, Guise stands down so the two never fight.
- **Masque skin packs** (Caith, Apathy, ...) declare `## Dependencies: Masque`, and the game won't load them unless an add-on folder named `Masque` exists. For personal use, copy `Compat/Masque` from this repository into your `AddOns` folder. It is an empty stub that depends on Guise and is **not** Masque; Guise recognises it and keeps running. Delete it if you install the real Masque. It is deliberately left out of packaged builds.
- Guise understands the current Masque skin format: layer aliases (`SlotHighlight = "Checked"`), `DebuffBorder`/`EnchantBorder`, solid-colour layers (`UseColor` without a texture), offset-only text layers, and Masque's shared textures (backdrops, square/circle masks and cooldown edges are mapped to stand-ins).
- On Midnight-era clients, some Blizzard-owned buttons (such as aura container buttons) report "secret" layout values. Guise skips those parts and skins the rest.
- Forever's API is based on the modern client. Interface numbers for retail (`120100`, `120105`) are also listed, so the add-on loads there too.

## Development

```sh
luacheck .            # lint
lua5.1 tests/run.lua  # unit tests against a small WoW API mock
```
