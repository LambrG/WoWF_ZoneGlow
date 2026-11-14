# ZoneGlow

Sync your PC's RGB lighting with the zone your character is in on WoW Forever.
Snowy zones light your rig icy blue, forests green, deserts orange.

## How it works

```
WoW addon ──► 2 pixels in the screen corner ──► Python script (PipeWire) ──► OpenRGB SDK server ──► RGB
```

1. **The addon** (`addon/ZoneGlow`) draws two 8×8 px squares in the top-left corner
   of the screen: `[magenta marker][zone type color]`.
2. **A Python script** (`sync/zoneglow_sync.py`) captures the screen through the PipeWire
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
| `alliance`| alliance blue | `#0070DE` | Stormwind City, Ironforge, Darnassus      |
| `horde`   | horde red  | `#CC0000` | Orgrimmar, Thunder Bluff, Undercity          |
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
- `/zoneglow lang en|cs` switches the addon's chat messages between English
  (default) and Czech. The choice is saved per account in `ZoneGlowDB`.
- `/zoneglow help` lists the commands.
- When the addon enters a zone it doesn't know, it prints the zone name to chat once
  and uses the `default` color. Add the zone to the `ZONES` table to map it.
- The squares have no parent frame, so they stay visible when you hide the UI
  (Alt+Z).

## Running the sync script

Requirements (Ubuntu package names):

- Wayland session with xdg-desktop-portal (tested on KDE Plasma)
- `python3-gi`, `python3-dbus`, GStreamer with the PipeWire plugin
  (`gstreamer1.0-pipewire`) and `gstreamer1.0-plugins-good` (videocrop)
- [OpenRGB](https://openrgb.org) with the SDK server running
  (SDK Server tab → Start Server, or start OpenRGB with `--server`)

Setup:

```bash
python3 -m venv --system-site-packages .venv
.venv/bin/pip install -r sync/requirements.txt
```

The script is meant to run all the time. It waits for the game process (`Wow.exe`)
and only captures the screen while the game is running. When the game exits, capture
stops and the `--profile` you choose is loaded.

Start it with the desktop session (systemd user service):

```bash
./install-service.sh --profile "my profile"   # install, enable and start
journalctl --user -u zoneglow -f              # logs
./install-service.sh --uninstall              # remove
```

Or run it by hand:

```bash
./run.sh --profile "my profile"
./run.sh --dry-run --always       # test: capture right away, only print the colors
```

When the game starts for the first time, the desktop asks which monitor to share.
Pick the one with the game. The choice is remembered (`~/.config/zoneglow/`), use
`--reset` to choose again. If you cancel the dialog or stop sharing from the tray,
the script won't ask again until the game is restarted.

| Option | Default | Meaning |
|---|---|---|
| `--host`, `--port` | `127.0.0.1`, `6742` | OpenRGB SDK server |
| `--profile NAME` | none | OpenRGB profile loaded when the game exits and when the script stops |
| `--process NAME…` | `Wow.exe` | Game process names to wait for |
| `--always` | | Capture right away instead of waiting for the game; exit when capture stops |
| `--fps N` | `10` | Checks per second |
| `--source monitor\|window` | `monitor` | Capture a whole monitor or only the game window |
| `--offset X Y` | `0 0` | Position of the game's top-left corner in the capture (windowed game on a captured monitor) |
| `--reset` | | Forget the saved monitor/window choice |
| `--config FILE` | `~/.config/zoneglow/config.toml` | Colors per device role and zone type, see below |
| `--correct DEVICE=R,G,B` | | Per-device channel gains, `DEVICE` is part of the OpenRGB device name (e.g. `--correct ASUS=1,0.5,1`). Can be repeated |
| `--dry-run` | | Print colors only |

Different LEDs show the same RGB value differently. For example, case fans often
have a stronger green and look whiter than RAM. Use `--correct` to tune a device
until it matches the others.

The script switches devices that have a Direct mode to it, so color updates are
fast. Only a 64×32 px corner of the screen is converted, so CPU use doesn't depend
on the screen resolution. The squares can be scaled up to 4× (e.g. when the
compositor upscales the game). The script measures the marker and reads the middle
of both squares.

### Device roles

By default every device shows the zone color. A config file can split devices into
roles and give each role its own color per zone type. For example, Alliance cities
can have blue fans and gold RAM:

```toml
# ~/.config/zoneglow/config.toml
[roles]
Kingston = "secondary"    # part of the OpenRGB device name; unlisted devices are "main"

[alliance]
main = "#0070DE"
secondary = "#FFB000"
```

A role without a color in a zone's section gets the zone color from the addon. The
script picks up changes within a few seconds. See
[`sync/config.example.toml`](sync/config.example.toml).

## Translations

Chat messages are defined in the `LOCALES` table in
[`ZoneGlow.lua`](addon/ZoneGlow/ZoneGlow.lua). To add a language, copy the `en`
entry under a new key (for example `de`), translate the strings and update the
`lang` usage hints. Avoid characters the default game fonts can't display. That's
why the Czech strings have no diacritics.

Translations only cover the addon's messages. Zone matching still uses the enUS
zone names.

## Status

- [x] Addon: draws the marker and the zone color
- [x] Kalimdor and Eastern Kingdoms zones mapped to types
- [x] Python script: screen capture through the PipeWire portal
- [x] Python script: sending the color to the OpenRGB SDK server
- [ ] Smooth color transitions between zones
