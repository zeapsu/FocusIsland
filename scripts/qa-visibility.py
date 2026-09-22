#!/usr/bin/env python3
"""Verify actual WindowServer presence on desktop and native full-screen Spaces.

Uses the disposable fixture on the 1710x1107 test display. Works with release
or DEBUG builds and never changes the timer or preferences.
"""
import importlib.util
import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("qa", ROOT / "scripts/qa-lifecycle.py")
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
OUT = ROOT / "qa/fullscreen-available"
OUT.mkdir(exist_ok=True)
FIXTURE = "local.focusisland.fullscreen-qa"

def fullscreen():
    r = subprocess.run(["osascript", "-e", 'tell application "System Events" to tell process "FullscreenFixture" to get value of attribute "AXFullScreen" of window "Focus Island Fullscreen QA"'], text=True, capture_output=True)
    return r.stdout.strip() == "true" if r.returncode == 0 else None

def windows():
    return json.loads(q.tool("onscreen-windows", q.APP))

def visible():
    # The popover sits below the menu bar; only the island occupies y=0.
    return any(w["layer"] == 25 and w["bounds"]["Y"] == 0 and w["bounds"]["Width"] >= 400 for w in windows())

def settle(predicate, timeout=10):
    end = time.monotonic() + timeout
    consecutive = 0
    while time.monotonic() < end:
        consecutive = consecutive + 1 if predicate() else 0
        if consecutive >= 3:
            return
        time.sleep(.2)
    raise AssertionError("Space/visibility did not settle")

def record(name, expected):
    settle(lambda: visible() == expected)
    rows = windows()
    (OUT / f"{name}.json").write_text(json.dumps({"fixtureFullscreen": fullscreen(), "islandOnScreen": visible(), "windows": rows}, indent=2))
    print(f"PASS {name}: islandOnScreen={expected}", flush=True)

def toggle_fullscreen():
    subprocess.run(["open", str(ROOT / ".build/FullscreenFixture.app")], check=True)
    settle(lambda: subprocess.check_output(["osascript", "-e", 'tell application "System Events" to get name of first application process whose frontmost is true'], text=True).strip() == "FullscreenFixture")
    # AXPress can report success without entering a new Space. Drive the real
    # button with a mouse click, then let the caller verify AXFullScreen.
    control = q.tool("inspect", FIXTURE, "Toggle Full Screen")
    match = re.search(r"frame=\{\{([\d.-]+), ([\d.-]+)\}, \{([\d.-]+), ([\d.-]+)\}\}", control)
    assert match, control
    x, y, width, height = map(float, match.groups())
    q.tool("click", str(x + width / 2), str(y + height / 2))

subprocess.run(["open", str(ROOT / ".build/FullscreenFixture.app")], check=True)
time.sleep(.5)
if fullscreen() is True:
    toggle_fullscreen()
settle(lambda: fullscreen() is False)
q.tool("press", FIXTURE, "Normal Window")
q.tool("move", "1200", "400")
record("desktop-normal", True)
q.tool("press", FIXTURE, "Maximize on Desktop")
settle(lambda: fullscreen() is False)
record("desktop-maximized-after", True)
q.tool("move", "855", "15")
time.sleep(.5)
assert "id=island-controls" in q.tool("tree", q.APP, "8")
record("desktop-maximized-hover", True)
q.tool("move", "1200", "400")

for index in range(2):
    toggle_fullscreen()
    settle(lambda: fullscreen() is True)
    q.tool("move", "1200", "400")
    time.sleep(.5)
    record(f"fullscreen-{index}", True)
    assert "id=island-controls" not in q.tool("tree", q.APP, "8"), "island did not settle compact"
    q.tool("move", "855", "15")
    time.sleep(.4)
    assert visible(), "island disappeared during full-screen hover"
    assert "id=island-controls" in q.tool("tree", q.APP, "8"), "full-screen hover did not expand"
    assert fullscreen() is True, "hover left the full-screen Space"
    front = subprocess.check_output(["osascript", "-e", 'tell application "System Events" to get name of first application process whose frontmost is true'], text=True).strip()
    assert front == "FullscreenFixture", f"passive hover stole focus: {front}"
    record(f"fullscreen-hover-{index}", True)
    q.tool("press", q.APP, "Focus Island menu")
    time.sleep(.4)
    assert "role=AXPopover" in q.tool("tree", q.APP, "7")
    record(f"fullscreen-menu-{index}", True)
    q.tool("click", "500", "450")
    time.sleep(.4)
    assert "role=AXPopover" not in q.tool("tree", q.APP, "7"), "full-screen click-away left popup open"
    toggle_fullscreen()
    settle(lambda: fullscreen() is False)
    record(f"desktop-restored-{index}", True)

q.tool("press", FIXTURE, "Normal Window")
q.tool("move", "1200", "400")
print("PASS desktop/maximized desktop, native full screen, menu access, and repeated Space transitions", flush=True)
