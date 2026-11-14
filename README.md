# ZoneGlow

Sync your PC's RGB lighting with the zone your character is in on WoW Forever.
Snowy zones light your rig icy blue, forests green, deserts orange.

## How it works

```
WoW addon ──► 2 pixels in the screen corner ──► Python script (PipeWire) ──► OpenRGB SDK server ──► RGB
```

1. **The addon** (`addon/ZoneGlow`) draws two 8×8 px squares in the top-left corner
   of the screen: `[magenta marker][zone type color]`.
2. **A Python script** (work in progress) captures the screen through the PipeWire
   screencast portal (Wayland/KDE), reads the color of the second square and sends
   it to OpenRGB through its SDK server (`openrgb-python`).
3. The color is sent only while the magenta marker is visible. Loading screens,
   menus and alt-tabbing leave your lighting unchanged.

The addon scales its frame so that 1 UI unit equals 1 physical pixel, regardless of
UI scale and resolution. The marker covers pixels x 0–7 and the zone color covers
x 8–15, both on rows y 0–7. The script samples the center of each square (4,4 and
12,4).

## Zone colors

| Type      | Color      | Hex       | Example zones                                |
|-----------|------------|-----------|----------------------------------------------|
| `snow`    | icy blue   | `#00C8FF` | Dun Morogh, Winterspring                     |
| `forest`  | green      | `#00FF40` | Elwynn Forest, Ashenvale, Stranglethorn Vale |
| `plains`  | gold       | `#FFBF00` | Westfall, The Barrens, Mulgore               |
| `desert`  | orange     | `#FF6600` | Durotar, Tanaris, Badlands                   |
| `city`    | purple     | `#A140FF` | Stormwind City, Orgrimmar                    |
| `default` | dark blue  | `#0040FF` | unknown zone                                 |
| marker    | magenta    | `#FF00FF` | always                                       |

Zones and colors live in the `ZONES` and `PALETTE` tables at the top of
[`ZoneGlow.lua`](addon/ZoneGlow/ZoneGlow.lua). Zone names are for the enUS client,
exactly as returned by `GetRealZoneText()`. Other client languages need their own
zone names in `ZONES`.

## Installing the addon

Requirements: WoW Forever (Interface 16001), enUS client.

The simplest option is to copy `addon/ZoneGlow` into your
`World of Warcraft/_forever_/Interface/AddOns/` folder.

If you want to edit the addon, symlink it instead, so changes in the repository take
effect after a `/reload`. Example for Battle.net running under Wine (adjust the path
to your install):

```bash
ln -s "$PWD/addon/ZoneGlow" \
  "$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/ZoneGlow"
```

## In-game usage

- `/zoneglow` prints the current zone and its type.
- When the addon enters a zone it doesn't know, it prints the zone name to chat once
  and uses the `default` color. Add the zone to the `ZONES` table to map it.
- The squares have no parent frame, so they stay visible when you hide the UI
  (Alt+Z).

## Status

- [x] Addon: draws the marker and the zone color
- [x] Kalimdor and Eastern Kingdoms zones mapped to types
- [ ] Python script: screen capture through the PipeWire portal
- [ ] Python script: sending the color to the OpenRGB SDK server
- [ ] Smooth color transitions between zones
