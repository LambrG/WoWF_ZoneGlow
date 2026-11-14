#!/usr/bin/env python3
"""ZoneGlow sync: reads the zone color drawn by the ZoneGlow WoW addon and sends it
to OpenRGB.

The addon draws two squares in the top-left corner of the game:
[magenta marker][zone color]. This script captures the screen through the
xdg-desktop-portal ScreenCast interface (Wayland), reads both squares and sends the
zone color to every device on the OpenRGB SDK server. Nothing is sent while the
marker is not visible (loading screens, menus, alt-tab).

The script waits for the game process (Wow.exe): capture starts when the game starts
and stops when it exits, then an optional OpenRGB profile is loaded. It is meant to
run all the time, e.g. as a systemd user service (see install-service.sh).

Requirements (system packages): python3-gi, python3-dbus, GStreamer with the
PipeWire plugin (pipewiresrc). Python package: openrgb-python.
"""

import argparse
import logging
import os
import secrets
import signal
import sys
import time
from pathlib import Path

import dbus
import gi
from dbus.mainloop.glib import DBusGMainLoop

gi.require_version("Gst", "1.0")
from gi.repository import GLib, Gst  # noqa: E402

log = logging.getLogger("zoneglow")

# Captured region in the top-left corner. Big enough for squares scaled up to 4x
# (e.g. when the game is upscaled by the compositor).
REGION_W, REGION_H = 64, 32

PORTAL_BUS = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
SCREENCAST_IFACE = "org.freedesktop.portal.ScreenCast"
SOURCE_TYPES = {"monitor": 1, "window": 2}
CURSOR_HIDDEN = 1
PERSIST_UNTIL_REVOKED = 2

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "zoneglow"


# ---------------------------------------------------------------------------
# Pixel reading
# ---------------------------------------------------------------------------

def is_magenta(px) -> bool:
    r, g, b = px
    return r >= 200 and g <= 60 and b >= 200


def read_zone_color(data: bytes, width: int, height: int):
    """Returns the zone color (r, g, b) from an RGB frame of the top-left corner,
    or None when the marker is not visible.

    The marker size is measured, so the squares can be scaled. Colors are sampled in
    the middle of each square, away from blurred edges."""

    def px(x, y):
        i = (y * width + x) * 3
        return data[i], data[i + 1], data[i + 2]

    if not is_magenta(px(1, 1)):
        return None
    mw = 1
    while mw < width and is_magenta(px(mw, 1)):
        mw += 1
    mh = 1
    while mh < height and is_magenta(px(1, mh)):
        mh += 1
    if mw < 3 or mh < 3 or mw * 2 > width or not is_magenta(px(mw // 2, mh // 2)):
        return None
    color = px(mw + mw // 2, mh // 2)
    if is_magenta(color):
        return None
    return color


def color_close(a, b, tolerance: int = 3) -> bool:
    return a is not None and b is not None and all(abs(x - y) <= tolerance for x, y in zip(a, b))


def hex_color(c) -> str:
    return "#%02X%02X%02X" % tuple(c)


# ---------------------------------------------------------------------------
# Screen capture: xdg-desktop-portal ScreenCast + PipeWire
# ---------------------------------------------------------------------------

class PortalError(RuntimeError):
    pass


class ScreenCast:
    """Opens a ScreenCast portal session. The monitor/window choice is remembered
    with a restore token, so the KDE dialog is shown only the first time."""

    def __init__(self, bus: dbus.SessionBus, source: str, token_file: Path):
        self.bus = bus
        self.source = source
        self.token_file = token_file
        self.portal = bus.get_object(PORTAL_BUS, PORTAL_PATH)
        self.screencast = dbus.Interface(self.portal, SCREENCAST_IFACE)
        self.sender = bus.get_unique_name()[1:].replace(".", "_")
        self.session = None

    def _prop(self, name):
        return self.portal.Get(SCREENCAST_IFACE, name, dbus_interface=dbus.PROPERTIES_IFACE)

    def _request(self, name: str, *args, options: dict) -> dict:
        """Calls a portal method and waits for its Request.Response signal."""
        token = "zoneglow_" + secrets.token_hex(8)
        path = f"/org/freedesktop/portal/desktop/request/{self.sender}/{token}"
        loop = GLib.MainLoop()
        result = {}

        def on_response(code, results):
            result["code"], result["results"] = int(code), results
            loop.quit()

        match = self.bus.add_signal_receiver(
            on_response, "Response", "org.freedesktop.portal.Request", PORTAL_BUS, path
        )
        try:
            opts = dbus.Dictionary(options, signature="sv")
            opts["handle_token"] = token
            getattr(self.screencast, name)(*args, opts)
            loop.run()
        finally:
            match.remove()

        if result["code"] == 1:
            raise PortalError("screen sharing was cancelled")
        if result["code"] != 0:
            raise PortalError(f"portal {name} failed (code {result['code']})")
        return result["results"]

    def start(self):
        """Returns (pipewire_fd, node_id)."""
        version = int(self._prop("version"))
        res = self._request(
            "CreateSession",
            options={"session_handle_token": "zoneglow_" + secrets.token_hex(8)},
        )
        self.session = str(res["session_handle"])

        select = {
            "types": dbus.UInt32(SOURCE_TYPES[self.source]),
            "multiple": dbus.Boolean(False),
        }
        if int(self._prop("AvailableCursorModes")) & CURSOR_HIDDEN:
            select["cursor_mode"] = dbus.UInt32(CURSOR_HIDDEN)
        if version >= 4:
            select["persist_mode"] = dbus.UInt32(PERSIST_UNTIL_REVOKED)
            if self.token_file.exists():
                select["restore_token"] = dbus.String(self.token_file.read_text().strip())
        self._request("SelectSources", self.session, options=select)

        res = self._request("Start", self.session, "", options={})
        if "restore_token" in res:
            self.token_file.parent.mkdir(parents=True, exist_ok=True)
            self.token_file.write_text(str(res["restore_token"]))
        streams = res.get("streams") or []
        if not streams:
            raise PortalError("the portal returned no stream")
        node_id = int(streams[0][0])

        fd = self.screencast.OpenPipeWireRemote(
            self.session, dbus.Dictionary({}, signature="sv")
        ).take()
        return fd, node_id

    def on_closed(self, callback):
        self.bus.add_signal_receiver(
            lambda *_: callback(), "Closed", "org.freedesktop.portal.Session", PORTAL_BUS, self.session
        )

    def close(self):
        if self.session:
            try:
                self.bus.get_object(PORTAL_BUS, self.session).Close(
                    dbus_interface="org.freedesktop.portal.Session"
                )
            except dbus.DBusException:
                pass
            self.session = None


def build_pipeline(fd: int, node_id: int, offset_x: int, offset_y: int):
    """pipewiresrc -> crop the top-left corner -> RGB -> appsink.

    Only the small region is converted, so the cost does not depend on the screen
    resolution. videocrop with -1 on the right/bottom crops to the size requested by
    the caps that follow it."""
    src = Gst.ElementFactory.make("pipewiresrc")
    if src is None:
        raise RuntimeError("GStreamer element pipewiresrc is missing (PipeWire GStreamer plugin)")
    src.set_property("fd", fd)
    if src.find_property("target-object"):
        src.set_property("target-object", str(node_id))
    else:
        src.set_property("path", str(node_id))

    rest = Gst.parse_bin_from_description(
        f"videocrop left={offset_x} top={offset_y} right=-1 bottom=-1 "
        f"! video/x-raw,width={REGION_W},height={REGION_H} "
        "! videoconvert ! video/x-raw,format=RGB "
        "! appsink name=sink max-buffers=1 drop=true sync=false",
        True,
    )
    pipeline = Gst.Pipeline.new("zoneglow")
    pipeline.add(src)
    pipeline.add(rest)
    src.link(rest)
    return pipeline, rest.get_by_name("sink")


# ---------------------------------------------------------------------------
# OpenRGB
# ---------------------------------------------------------------------------

class Lights:
    """Sends colors to every device on the OpenRGB SDK server. Reconnects when the
    server goes away and can load a profile when the game exits."""

    RETRY_SECONDS = 5

    def __init__(self, host: str, port: int, profile: str | None, dry_run: bool):
        self.host, self.port, self.profile, self.dry_run = host, port, profile, dry_run
        self.client = None
        self.direct = False   # devices switched to Direct mode
        self.next_try = 0.0

    def _connect(self) -> bool:
        if self.client is not None:
            return True
        if time.monotonic() < self.next_try:
            return False
        from openrgb import OpenRGBClient

        try:
            self.client = OpenRGBClient(self.host, self.port, name="ZoneGlow")
            names = ", ".join(d.name for d in self.client.devices) or "no devices"
            log.info("connected to OpenRGB %s:%d (%s)", self.host, self.port, names)
            self.direct = False
            return True
        except (OSError, ConnectionError, TimeoutError) as e:
            log.warning("OpenRGB %s:%d not reachable (%s), retrying in %ds",
                        self.host, self.port, e, self.RETRY_SECONDS)
            self.next_try = time.monotonic() + self.RETRY_SECONDS
            return False

    def _drop(self, error):
        log.warning("OpenRGB connection lost: %s", error)
        try:
            self.client.disconnect()
        except Exception:
            pass
        self.client = None
        self.next_try = time.monotonic() + self.RETRY_SECONDS

    def set_color(self, color) -> bool:
        if self.dry_run:
            return True
        if not self._connect():
            return False
        from openrgb.utils import RGBColor

        try:
            if not self.direct:
                for dev in self.client.devices:
                    if any(m.name.lower() == "direct" for m in dev.modes):
                        dev.set_mode("direct")
                self.direct = True
            rgb = RGBColor(*color)
            for dev in self.client.devices:
                dev.set_color(rgb)
            return True
        except (OSError, ConnectionError, TimeoutError) as e:
            self._drop(e)
            return False

    def load_profile(self) -> bool:
        if not self.profile or self.dry_run:
            return True
        if not self._connect():
            return False
        try:
            self.client.load_profile(self.profile)
            self.direct = False
            log.info("loaded OpenRGB profile %r", self.profile)
            return True
        except (OSError, ConnectionError, TimeoutError) as e:
            self._drop(e)
            return False

    def close(self):
        if self.client is not None:
            try:
                self.client.disconnect()
            except Exception:
                pass
            self.client = None


# ---------------------------------------------------------------------------
# Game process
# ---------------------------------------------------------------------------

def game_running(names: set[str]) -> bool:
    """True when a process with one of the names is running (Wine keeps the Windows
    executable name, e.g. Wow.exe, as the process name)."""
    for comm in Path("/proc").glob("[0-9]*/comm"):
        try:
            if comm.read_text().strip() in names:
                return True
        except OSError:
            pass  # process exited meanwhile
    return False


# ---------------------------------------------------------------------------
# Capture session: portal + pipeline + reading colors
# ---------------------------------------------------------------------------

class Capture:
    """One screen capture: started when the game starts, stopped when it exits."""

    def __init__(self, args, lights: Lights, on_stopped):
        self.args = args
        self.lights = lights
        self.on_stopped = on_stopped   # called when capture ends on its own (error, sharing stopped)
        self.cast = None
        self.pipeline = None
        self.sink = None
        self.timer = None
        self.sent = None               # last color sent to OpenRGB
        self.visible = False

    def start(self):
        """Raises PortalError / dbus.DBusException / RuntimeError on failure."""
        token_file = CONFIG_DIR / f"restore_token_{self.args.source}"
        self.cast = ScreenCast(dbus.SessionBus(), self.args.source, token_file)
        try:
            fd, node_id = self.cast.start()
            self.pipeline, self.sink = build_pipeline(fd, node_id, *self.args.offset)
        except Exception:
            self.cast.close()
            self.cast = None
            raise
        log.info("capturing PipeWire node %d", node_id)

        gst_bus = self.pipeline.get_bus()
        gst_bus.add_signal_watch()
        gst_bus.connect("message", self._on_bus_message)
        self.cast.on_closed(lambda: self._stop_self("screen sharing was stopped"))

        self.sent, self.visible = None, False
        self.timer = GLib.timeout_add(max(1, int(1000 / self.args.fps)), self._tick)
        self.pipeline.set_state(Gst.State.PLAYING)

    def stop(self):
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = None
        if self.pipeline:
            self.pipeline.get_bus().remove_signal_watch()
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = self.sink = None
        if self.cast:
            self.cast.close()
            self.cast = None

    @property
    def active(self) -> bool:
        return self.pipeline is not None

    def _stop_self(self, reason: str, user_stopped: bool = True):
        if not self.active:
            return
        log.info("%s", reason)
        self.stop()
        self.on_stopped(user_stopped)

    def _on_bus_message(self, _bus, msg):
        if msg.type == Gst.MessageType.ERROR:
            err, debug = msg.parse_error()
            log.error("GStreamer: %s (%s)", err.message, debug)
            self._stop_self("capture failed", user_stopped=False)
        elif msg.type == Gst.MessageType.EOS:
            self._stop_self("stream ended", user_stopped=False)

    def _tick(self):
        sample = self.sink.emit("try-pull-sample", 0) if self.sink else None
        if sample is not None:
            self._process(sample)
        return True  # keep the GLib timer running

    def _process(self, sample):
        buf = sample.get_buffer()
        st = sample.get_caps().get_structure(0)
        w, h = st.get_value("width"), st.get_value("height")
        data = buf.extract_dup(0, buf.get_size())
        if len(data) < w * h * 3:
            return
        color = read_zone_color(data, w, h)

        if color is None:
            if self.visible:
                log.info("marker not visible, keeping the current color")
                self.visible = False
            return

        if not self.visible:
            log.info("marker visible")
            self.visible = True
        if color_close(color, self.sent):
            return
        if self.lights.set_color(color):
            log.info("zone color %s", hex_color(color))
            self.sent = color


# ---------------------------------------------------------------------------
# Watcher: starts and stops the capture with the game
# ---------------------------------------------------------------------------

class Watcher:
    WATCH_SECONDS = 3
    RETRY_SECONDS = 30   # after a capture error while the game keeps running

    def __init__(self, args, lights: Lights, loop: GLib.MainLoop):
        self.args = args
        self.lights = lights
        self.loop = loop
        self.capture = Capture(args, lights, self._on_capture_stopped)
        self.names = set(args.process)
        self.game = False
        self.suppressed = False   # user cancelled/stopped sharing: wait until the game restarts
        self.retry_at = 0.0
        self.restore_pending = False  # profile still has to be loaded (OpenRGB was down)
        self.starting = False         # portal dialog open (nested main loop), don't start twice

    def run(self):
        if self.args.always:
            log.info("capturing without waiting for the game")
        else:
            log.info("waiting for %s", ", ".join(sorted(self.names)))
        self._check()
        GLib.timeout_add_seconds(self.WATCH_SECONDS, self._check)

    def _check(self):
        if self.starting:
            return True
        game = self.args.always or game_running(self.names)
        if game != self.game:
            self.game = game
            if game:
                log.info("game started")
            else:
                log.info("game exited")
                self.suppressed = False
                self.retry_at = 0.0
                if self.capture.active:
                    self.capture.stop()
                self.restore_pending = True

        if self.restore_pending and self.lights.load_profile():
            self.restore_pending = False

        if (self.game and not self.capture.active and not self.suppressed
                and time.monotonic() >= self.retry_at):
            self._start_capture()
        return True

    def _start_capture(self):
        self.starting = True
        try:
            self.capture.start()
            self.restore_pending = False
        except PortalError as e:
            if self.args.always:
                log.error("screen capture: %s", e)
                self.loop.quit()
                return
            log.warning("screen capture: %s. Not retrying until the game is restarted.", e)
            self.suppressed = True
        except (dbus.DBusException, RuntimeError) as e:
            log.error("screen capture failed: %s. Retrying in %ds.", e, self.RETRY_SECONDS)
            self.retry_at = time.monotonic() + self.RETRY_SECONDS
        finally:
            self.starting = False

    def _on_capture_stopped(self, user_stopped: bool):
        if self.args.always:
            self.loop.quit()
            return
        if user_stopped:
            log.info("not capturing again until the game is restarted")
            self.suppressed = True
        else:
            self.retry_at = time.monotonic() + self.RETRY_SECONDS
        self.restore_pending = True

    def shutdown(self):
        self.capture.stop()
        self.lights.load_profile()
        self.lights.close()


def parse_args():
    p = argparse.ArgumentParser(description="Sync OpenRGB lighting with the ZoneGlow WoW addon.")
    p.add_argument("--host", default="127.0.0.1", help="OpenRGB SDK server host (default: %(default)s)")
    p.add_argument("--port", type=int, default=6742, help="OpenRGB SDK server port (default: %(default)s)")
    p.add_argument("--profile", help="OpenRGB profile to load when the game exits and when the script stops")
    p.add_argument("--process", nargs="+", default=["Wow.exe"], metavar="NAME",
                   help="game process names to wait for (default: %(default)s)")
    p.add_argument("--always", action="store_true",
                   help="capture right away instead of waiting for the game; exit when capture stops")
    p.add_argument("--fps", type=float, default=10, help="checks per second (default: %(default)s)")
    p.add_argument("--source", choices=SOURCE_TYPES, default="monitor",
                   help="capture a whole monitor or just the game window (default: %(default)s)")
    p.add_argument("--offset", type=int, nargs=2, default=(0, 0), metavar=("X", "Y"),
                   help="position of the game's top-left corner in the captured image (windowed mode)")
    p.add_argument("--reset", action="store_true", help="forget the saved monitor/window choice")
    p.add_argument("--dry-run", action="store_true", help="only print colors, do not touch OpenRGB")
    p.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    DBusGMainLoop(set_as_default=True)
    Gst.init(None)
    if args.reset:
        (CONFIG_DIR / f"restore_token_{args.source}").unlink(missing_ok=True)
    if args.dry_run:
        log.info("dry run: colors are only printed")

    loop = GLib.MainLoop()
    lights = Lights(args.host, args.port, args.profile, args.dry_run)
    watcher = Watcher(args, lights, loop)
    for sig in (signal.SIGINT, signal.SIGTERM):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: (loop.quit(), False)[1])

    watcher.run()
    try:
        loop.run()
    finally:
        watcher.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
