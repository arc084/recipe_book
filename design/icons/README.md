# App icon

The masters from the design handoff's icon spec, kept here so the platform
files can be regenerated instead of hunted for in a zip. Nothing in this
folder is bundled into the app — the built icons live in the platform trees.

## The mark

A pot with a dipped lid. Drawn on a 512 grid, tile radius 112, mark bounds
118–394 wide and 120–412 tall, clearing the 66% mask-safe circle so no launcher
mask can clip it.

**One icon leaves the app**, on both platforms: a flat `#e9e9ed` mark on a
full-bleed `#f8621f` tile. It follows neither the in-app theme setting nor the
system light/dark one, so it reads the same in a taskbar, a notification and a
home screen — and, having a ground, it stays legible on any background.

The other two colourways are the *in-app* ones and no longer leave the app:

| | |
| --- | --- |
| Shipping | `#e9e9ed` on `#f8621f` |
| Nocturne, in-app | `#9184d9` on `#161826` |
| Organic, in-app | `#c67139` on `#f5ead8` |

**Below 32px the mark is a different drawing**, not the same one made smaller —
steam and handles dropped, lid heavier, body wider. The handoff ships those
rasters separately, so small sizes are used as supplied and never downscaled
from a larger one.

## Where each master goes

| Master | Used for |
| --- | --- |
| `app-icon-mono-dark-orange.svg` | **the shipping icon** — Windows file, shortcut, taskbar, title bar, and the Android legacy tile |
| `app-icon-mono-dark-orange-small.svg` | the same tile with the small drawing; source of the 24 and 16 rasters |
| `android-adaptive-foreground.svg` | adaptive foreground — the light mark alone. Byte-identical to `app-icon-mono.svg` |
| `android-adaptive-background.svg` | adaptive background — a flat `#f8621f`, so it ships as a colour resource rather than five identical squares |
| `app-icon-mono.svg` | light ink on transparency; the source the orange tile is cut from, never shipped alone |
| `app-icon-dark.svg` | Nocturne colourway — reference only, nothing outside the app uses it |
| `app-icon-light.svg` | Organic colourway — reference only |
| `icon-pot-mark.svg` | the mark in `currentColor`, for in-app use |
| `icon-pot-mark-small.svg` | the same below 32px |

## What was generated

| File | From |
| --- | --- |
| `windows/runner/resources/app_icon.ico` | `png/mono-orange-` at 256, 48, 32, 16 — PNG-compressed entries |
| `android/.../mipmap-*/ic_launcher.png` | the orange tile at 48, 72, 96, 144, 192 |
| `android/.../mipmap-*/ic_launcher_foreground.png` | the light mark at 108dp: 108, 162, 216, 324, 432 |
| `android/.../mipmap-anydpi-v26/ic_launcher.xml` | the two-layer adaptive icon |
| `android/.../values/ic_launcher_background.xml` | `#f8621f` |

The `mono-orange-*` ladder is shipped and used as supplied. The mark rasters
for the adaptive foreground are not shipped, but need no renderer: the new
`android-adaptive-foreground.svg` is byte-identical to `app-icon-mono.svg`,
which is the `android-foreground-*` ladder recoloured to `#e9e9ed` and shifted
back by the 10 units that ladder sits high.

## Two more things

- **The icon follows nothing.** Not the in-app theme, not the system light/dark
  setting — which is why the background colour sits in `values/` and
  deliberately not in `values-night/`.
- **In-app is the exception.** There, `icon-pot-mark.svg` in `currentColor` is
  meant to pick up the theme accent. Not wired up yet.

The mark is still a placeholder: it carries the category, not the name. If the
app is ever called something other than Recipe Book, the pot is worth revisiting.
