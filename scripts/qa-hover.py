#!/usr/bin/env python3
"""Native pointer regression checks for the notch hover interaction.

Uses the same 1710x1107 test display as qa-placement.py. Run with the disposable
fixture open normally, the app idle, and no timer menu/settings window open.
Works against both release and debug builds; it never writes the model.
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
OUT = ROOT / "qa/hover"
OUT.mkdir(exist_ok=True)

def tree():
    return q.tool("tree", q.APP, "7")

def has_controls():
    return "id=island-controls" in tree()

def frame(line):
    match = re.search(r"frame=\{\{([\d.-]+), ([\d.-]+)\}, \{([\d.-]+), ([\d.-]+)\}\}", line)
    assert match, line
    return tuple(map(float, match.groups()))

def island_frame():
    return frame(next(line for line in tree().splitlines() if "role=AXWindow" in line and "title=Focus Island desc=" in line))

def click_control(label):
    line = next(line for line in tree().splitlines() if "role=AXButton" in line and f"desc={label} " in line)
    x, y, w, h = frame(line)
    q.tool("click", str(x+w/2), str(y+h/2))
    time.sleep(.3)

subprocess.run(["open", str(ROOT / ".build/FullscreenFixture.app")], check=True)
q.tool("move", "1200", "400")
time.sleep(.6)
assert not has_controls()
canvas = island_frame()
compact_icon = frame(next(line for line in tree().splitlines() if "role=AXImage" in line and "id=circle.dotted" in line))
compact_menu = frame(next(line for line in tree().splitlines() if "id=islandMenu" in line))

# A transit across the notch should not expose controls, even briefly.
for _ in range(4):
    q.tool("move", "855", "15")
    q.tool("move", "1200", "400")
    time.sleep(.05)
    assert not has_controls(), "quick menu-bar transit unexpectedly opened the island"
    time.sleep(.3)
print("PASS quick flybys do not open", flush=True)

q.tool("move", "855", "15")
time.sleep(.35)
assert has_controls()
assert island_frame() == canvas, "hover must not animate or reposition the native canvas"
expanded_icon = frame(next(line for line in tree().splitlines() if "role=AXImage" in line and "id=circle.dotted" in line))
expanded_menu = frame(next(line for line in tree().splitlines() if "id=islandMenu" in line))
assert expanded_icon[0] < compact_icon[0] - 30, "left icon did not move out with the shell"
assert expanded_menu[2] > compact_menu[2] + 60, "right menu wing did not expand around the camera"
(OUT / "expanded-ax.txt").write_text(tree())

# Travel through the body to the buttons and reverse direction without losing hover.
for x, y in [(855, 40), (810, 70), (742, 109), (860, 90), (720, 65), (855, 20)]:
    q.tool("move", str(x), str(y))
    time.sleep(.16)
    assert has_controls(), f"controls collapsed under pointer at {(x,y)}"
    assert island_frame() == canvas
print("PASS expanding header, outward-moving icons, and stable control layout", flush=True)

q.tool("move", "1200", "400")
time.sleep(.08)
q.tool("move", "855", "15")
time.sleep(.2)
assert has_controls(), "brief leave/re-entry lost expansion"
# Re-enter the visible body after collapse has begun, without crossing the header.
q.tool("move", "1200", "400")
time.sleep(.25)
q.tool("move", "855", "36")
time.sleep(.3)
assert has_controls(), "visible collapsing body could not reverse the animation"
click_control("Start Focus")
assert "desc=Cancel Focus" in tree()
assert island_frame() == canvas, "state change moved the native canvas"
click_control("Cancel Focus")
assert has_controls()

# This point is inside the native window but below the visible idle surface.
q.tool("move", "850", "145")
time.sleep(.55)
assert not has_controls(), "transparent canvas kept the island expanded"
q.tool("move", "700", "15")
time.sleep(.35)
assert not has_controls(), "transparent menu-bar shoulder opened the island"
print("PASS state changes, re-entry, and transparent-canvas boundaries", flush=True)

for click_x, click_y in [(991, 17), (980, 28)]:
    q.tool("move", "855", "15")
    time.sleep(.35)
    q.tool("click", str(click_x), str(click_y))
    time.sleep(.4)
    text = tree()
    assert "role=AXPopover" in text, f"island menu shortcut failed at {(click_x, click_y)}"
    assert "id=island-controls" not in text, "island must fold away while the menu is open"
    icon = frame(next(line for line in text.splitlines() if "role=AXMenuBarItem" in line))
    popup = frame(next(line for line in text.splitlines() if "role=AXPopover" in line))
    assert abs(popup[0]+popup[2]/2-icon[0]-icon[2]/2) < 2
    assert -8 <= popup[1]-icon[1]-icon[3] <= 24
    q.tool("press", q.APP, "Focus Island menu")
    q.tool("move", "1200", "400")
    time.sleep(.5)
(OUT / "result.json").write_text(json.dumps({"canvas":canvas, "icon":icon, "popup":popup, "result":"pass"},indent=2))
print("PASS island menu shortcut, collapse while menu is open, and native popup anchor", flush=True)
