#!/usr/bin/env python3
"""Real pointer/AX regression checks, using the separate fullscreen fixture.

Requires a running DEBUG app with --qa-speed --qa-artifacts qa/live, saved
5/10/3 durations, and .build/FullscreenFixture.app running in a normal window.
"""
import importlib.util
import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("lifecycle", ROOT / "scripts/qa-lifecycle.py")
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
qa.OUT = ROOT / "qa/fullscreen-available/placement"
qa.OUT.mkdir(parents=True, exist_ok=True)
FIXTURE = "local.focusisland.fullscreen-qa"

def wait_until(predicate, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.2)
    raise AssertionError("Condition did not become true")

def island_visible():
    return any(w["title"] == "Focus Island" and w["onScreen"] for w in qa.state()["windows"])

def ax_frame(line):
    m = re.search(r"frame=\{\{([\d.-]+), ([\d.-]+)\}, \{([\d.-]+), ([\d.-]+)\}\}", line)
    assert m, line
    return tuple(float(x) for x in m.groups())

def popup_anchor(name):
    tree = qa.tool("tree", qa.APP, "5")
    icon = ax_frame(next(x for x in tree.splitlines() if "role=AXMenuBarItem" in x))
    popup = ax_frame(next(x for x in tree.splitlines() if "role=AXPopover" in x))
    assert abs(popup[0] + popup[2]/2 - icon[0] - icon[2]/2) < 2, (icon, popup)
    assert -8 <= popup[1] - icon[1] - icon[3] <= 24, (icon, popup)
    (qa.OUT / f"{name}-anchor.json").write_text(json.dumps({"icon": icon, "popup": popup}, indent=2))
    qa.capture(name)

def fixture_fullscreen():
    result = subprocess.run(["osascript", "-e", 'tell application "System Events" to tell process "FullscreenFixture" to get value of attribute "AXFullScreen" of window "Focus Island Fullscreen QA"'], text=True, capture_output=True)
    # AppKit temporarily removes the window from AX during the Space animation.
    return result.stdout.strip() == "true" if result.returncode == 0 else None

qa.wait_for("idle")
subprocess.run(["open", str(ROOT / ".build/FullscreenFixture.app")], check=True)
if fixture_fullscreen() is True:
    qa.tool("press", FIXTURE, "Toggle Full Screen")
wait_until(lambda: fixture_fullscreen() is False)
wait_until(island_visible)
assert not fixture_fullscreen()
qa.tool("move", "1200", "400")
time.sleep(0.7)
tree = qa.tool("tree", qa.APP, "4")
compact = ax_frame(next(x for x in tree.splitlines() if "id=island-summary" in x))
assert compact[1] == 0 and compact[3] == 33, compact
qa.capture("notch-band-idle")

# The expanded shell covers this status position. Its right-wing menu shortcut
# opens the same anchored popover and folds the island away.
qa.tool("move", "855", "15")
time.sleep(0.4)
qa.capture("notch-band-expanded")
qa.tool("click", "991", "17")
time.sleep(0.5)
popup_anchor("popup-from-hover")
qa.press("Start Focus")
qa.wait_for("focusBeforeCheckpoint")
time.sleep(0.5)
popup_anchor("popup-after-start")
qa.press("Cancel Focus")
qa.wait_for("idle")
qa.tool("press", qa.APP, "Focus Island menu")
qa.tool("move", "1200", "400")

qa.tool("press", FIXTURE, "Toggle Full Screen")
wait_until(fixture_fullscreen)
wait_until(island_visible)
qa.tool("move", "855", "15")
time.sleep(1)
assert island_visible(), "island must remain available in fullscreen"
assert "id=island-controls" in qa.tool("tree", qa.APP, "7"), "fullscreen hover must expose controls"
qa.capture("fullscreen-expanded")
qa.menu()
popup_anchor("fullscreen-popup")
assert island_visible(), "menu opening must keep the island on screen"
qa.press("Start Focus")
start = qa.wait_for("focusBeforeCheckpoint")
assert abs(start["hardStopAt"] - start["sessionStart"] - 30) < .01
qa.tool("press", qa.APP, "Focus Island menu")
qa.tool("move", "1200", "400")
qa.wait_for("hardStopReached")
assert island_visible(), "hard stop must remain visible in fullscreen"
assert fixture_fullscreen() is True
assert "Time to get up and move" in qa.tool("tree", qa.APP, "7")
qa.capture("fullscreen-hard-stop-visible")
qa.press("Start Break")
qa.wait_for("onBreak")
qa.wait_for("idle")
qa.capture("fullscreen-break-complete")
qa.tool("press", FIXTURE, "Toggle Full Screen")
wait_until(lambda: fixture_fullscreen() is False)
wait_until(island_visible)
qa.capture("desktop-idle-returned")
print("PASS notch band, popup anchor, full-screen visibility and hover, visible hard stop, break completion, and desktop return", flush=True)
