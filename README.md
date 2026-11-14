# ZoneGlow

Synchronizace RGB podsvícení PC se zónou, ve které se postava nachází ve WoW Forever.
Ve sněhu svítí počítač ledově modře, v lese zeleně, v poušti oranžově.

## Jak to funguje

```
WoW addon ──► 2 pixely v rohu obrazovky ──► Python skript (PipeWire) ──► OpenRGB SDK server ──► RGB
```

1. **Addon** (`addon/ZoneGlow`) vykreslí v levém horním rohu dva čtverečky 8×8 px:
   `[magenta marker][barva typu zóny]`.
2. **Python skript** (zatím ve vývoji) snímá obrazovku přes PipeWire portal
   (Wayland/KDE), přečte barvu druhého čtverečku a pošle ji do OpenRGB přes
   SDK server (`openrgb-python`).
3. Barva se pošle jen tehdy, když je vidět magenta marker. Na načítací obrazovce,
   v menu nebo mimo hru se podsvícení nezmění.

Addon nastavuje měřítko tak, aby 1 jednotka UI byla 1 fyzický pixel, nezávisle na
UI scale a rozlišení. Marker je tedy na pixelech x 0–7 a barva zóny na x 8–15,
v řádcích y 0–7. Skript čte střed čtverečků (4,4 a 12,4).

## Barvy zón

| Typ      | Barva        | Hex      | Příklady zón                          |
|----------|--------------|----------|---------------------------------------|
| `snow`   | ledově modrá | `#00C8FF` | Dun Morogh, Winterspring              |
| `forest` | zelená       | `#00FF40` | Elwynn Forest, Ashenvale, Stranglethorn Vale |
| `plains` | zlatožlutá   | `#FFBF00` | Westfall, The Barrens, Mulgore        |
| `desert` | oranžová     | `#FF6600` | Durotar, Tanaris, Badlands            |
| `city`   | fialová      | `#A040FF` | Stormwind City, Orgrimmar             |
| `default`| tmavě modrá  | `#0040FF` | neznámá zóna                          |
| marker   | magenta      | `#FF00FF` | vždy                                  |

Zóny a paleta jsou v tabulkách `ZONES` a `PALETTE` na začátku
[`ZoneGlow.lua`](addon/ZoneGlow/ZoneGlow.lua). Názvy zón jsou pro enUS klienta,
přesně tak, jak je vrací `GetRealZoneText()`.

## Instalace addonu

Addon se do WoW nekopíruje. Nalinkuje se symlinkem, takže změny v repozitáři se
projeví hned po `/reload`:

```bash
ln -s "$PWD/addon/ZoneGlow" \
  "$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/ZoneGlow"
```

Požadavky: WoW Forever (Interface 16001) a enUS klient.

## Použití ve hře

- `/zoneglow` vypíše aktuální zónu a její typ.
- Když addon narazí na zónu, kterou nezná, vypíše ji do chatu jednou za změnu zóny
  (a použije barvu `default`). Takovou zónu stačí doplnit do tabulky `ZONES`.
- Čtverečky nemají rodičovský frame, takže zůstanou vidět i po skrytí UI (Alt+Z).

## Stav

- [x] Addon: vykreslení markeru a barvy zóny
- [x] Mapování zón Kalimdoru a Eastern Kingdoms na typ
- [ ] Python skript: snímání přes PipeWire portal
- [ ] Python skript: odesílání barvy do OpenRGB SDK serveru
- [ ] Plynulé přechody barev mezi zónami
