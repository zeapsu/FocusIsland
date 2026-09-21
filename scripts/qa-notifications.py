#!/usr/bin/env python3
"""Check the already-decided notification permission action without changing it.

Uses the running app and existing macOS Accessibility access. Navigates System
Settings but never toggles notification permission or changes timer settings.
"""
import importlib.util
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("qa", ROOT / "scripts/qa-lifecycle.py")
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
OUT = ROOT / "qa/notifications"
OUT.mkdir(exist_ok=True)

def wait_for(predicate):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(.2)
    raise AssertionError("Notification settings action did not complete")

def system_tree():
    return q.tool("tree", "com.apple.systempreferences", "12")

def app_settings():
    q.menu()
    q.press("openSettings")
    time.sleep(.5)
    return q.tool("tree", q.APP, "8")

# Start on another pane so an old, already-open Notifications window cannot
# make a broken action look successful. This only changes the visible pane.
subprocess.run(["open", "x-apple.systempreferences:com.apple.Appearance-Settings.extension"], check=True)
wait_for(lambda: "role=AXWindow id=main title=Appearance" in system_tree())
before = app_settings()
assert "id=notificationStatus" in before
line = next(l for l in before.splitlines() if "id=notificationPermission" in l)
assert "desc=Open Notification Settings…" in line, "Requires a previously decided notification permission"
(OUT / "updated-settings-ax.txt").write_text(before)

# Bring the Settings window forward with an actual title-bar click. An AXPress
# that opens an accessory app's window does not guarantee foreground activation.
window = next(l for l in before.splitlines() if "role=AXWindow" in l and "title=Focus Island Settings" in l)
m = re.search(r"frame=\{\{([\d.-]+), ([\d.-]+)\}, \{([\d.-]+), ([\d.-]+)\}\}", window)
assert m, window
wx, wy, _, _ = map(float, m.groups())
q.tool("click", str(wx+75), str(wy+16))
time.sleep(.4)
m = re.search(r"frame=\{\{([\d.-]+), ([\d.-]+)\}, \{([\d.-]+), ([\d.-]+)\}\}", line)
assert m, line
x, y, w, h = map(float, m.groups())
assert "notificationPermission" in q.tool("at", str(x+w/2), str(y+h/2)), "Another window covers the notification button"
q.tool("click", str(x+w/2), str(y+h/2))
wait_for(lambda: "role=AXWindow id=main title=Focus Island" in system_tree())
system = system_tree()
assert "Allow notifications" in system
selected = "\n".join(l for l in system.splitlines() if "Focus Island" in l or "Allow notifications" in l)
(OUT / "opened-system-settings.txt").write_text(selected)
returned = app_settings()
assert "id=notificationStatus" in returned and "desc=Open Notification Settings…" in returned
assert "Checking Notifications…" not in returned
(OUT / "returned-settings-ax.txt").write_text(returned)
print("PASS actual Settings click opens Focus Island's notification pane; status and action remain usable on return", flush=True)
