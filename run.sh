#!/bin/sh
# Runs the ZoneGlow sync script from the project's .venv.
# Inside a Flatpak terminal (e.g. VS Code from Flathub) it runs on the host, because
# the sandbox has a different Python without the system GStreamer/PipeWire bindings.
cd "$(dirname "$0")" || exit 1
if [ -f /.flatpak-info ]; then
    exec flatpak-spawn --host "$PWD/.venv/bin/python" "$PWD/sync/zoneglow_sync.py" "$@"
fi
exec .venv/bin/python sync/zoneglow_sync.py "$@"
