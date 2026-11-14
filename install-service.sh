#!/bin/sh
# Installs ZoneGlow sync as a systemd user service that starts with the desktop
# session. Arguments are passed to the sync script, e.g.:
#
#   ./install-service.sh --profile "cold blue"
#
# Run again after moving the project (paths are absolute) or to change arguments.
# Remove with: ./install-service.sh --uninstall
set -eu

cd "$(dirname "$0")"
DIR=$(pwd)
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/zoneglow.service"

# Inside a Flatpak terminal (VS Code from Flathub) run on the host.
if [ -f /.flatpak-info ]; then
    exec flatpak-spawn --host "$DIR/install-service.sh" "$@"
fi

if [ "${1:-}" = "--uninstall" ]; then
    systemctl --user disable --now zoneglow.service 2>/dev/null || true
    rm -f "$UNIT"
    systemctl --user daemon-reload
    echo "ZoneGlow service removed."
    exit 0
fi

if [ ! -x "$DIR/.venv/bin/python" ]; then
    echo "Missing .venv, create it first:" >&2
    echo "  python3 -m venv --system-site-packages .venv && .venv/bin/pip install -r sync/requirements.txt" >&2
    exit 1
fi

# Quote every argument for the systemd ExecStart line.
ARGS=""
for a in "$@"; do
    ARGS="$ARGS \"$(printf '%s' "$a" | sed 's/[\\"]/\\&/g')\""
done

mkdir -p "$UNIT_DIR"
cat > "$UNIT" <<EOF
[Unit]
Description=ZoneGlow: sync OpenRGB lighting with the zone in WoW
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart="$DIR/.venv/bin/python" "$DIR/sync/zoneglow_sync.py"$ARGS
Environment=PYTHONUNBUFFERED=1
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable zoneglow.service
systemctl --user restart zoneglow.service
echo "Installed $UNIT"
echo "Logs:   journalctl --user -u zoneglow -f"
echo "Status: systemctl --user status zoneglow"
