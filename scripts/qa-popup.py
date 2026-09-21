#!/usr/bin/env python3
"""Real mouse tests for popup dismissal. --actions requires the isolated QA app."""
import importlib.util
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("qa", ROOT / "scripts/qa-lifecycle.py")
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
OUT = ROOT / "qa/visibility"
OUT.mkdir(exist_ok=True)

def tree(): return q.tool("tree", q.APP, "8")
def shown(): return "role=AXPopover" in tree()
def frame(line):
    m = re.search(r"frame=\{\{([\d.-]+), ([\d.-]+)\}, \{([\d.-]+), ([\d.-]+)\}\}", line)
    assert m, line
    return tuple(map(float, m.groups()))
def click(x, y):
    q.tool("click", str(x), str(y))
    time.sleep(.4)
def open_menu():
    q.tool("move", "1200", "400")
    time.sleep(.5)
    if not shown(): click(991, 17)
    assert shown(), "menu failed to open"
def click_control(label):
    line = next(l for l in tree().splitlines() if "role=AXButton" in l and f"desc={label} " in l)
    x,y,w,h = frame(line)
    click(x+w/2, y+h/2)

subprocess.run(["open", str(ROOT / ".build/FullscreenFixture.app")], check=True)
time.sleep(.5)
open_menu()
click(500, 450)
assert not shown(), "click in another app did not dismiss"
open_menu()
x,y,w,h = frame(next(l for l in tree().splitlines() if "role=AXPopover" in l))
click(x+80, y+35)
assert not shown(), "click in popup background did not dismiss"
open_menu()
click(750, 15)
assert not shown(), "click on the collapsed notch surface did not dismiss"
print("PASS other-app, popup-background, and notch-surface click dismissal", flush=True)

for _ in range(3):
    open_menu()
    click(991, 17)
    assert not shown(), "status toggle closed then reopened"
print("PASS repeated status-item open/close", flush=True)

open_menu()
click_control("Settings…")
assert not shown(), "Settings action left popup open"
assert "title=Focus Island Settings" in tree(), "Settings action was lost"
open_menu()
x,y,w,h = frame(next(l for l in tree().splitlines() if "role=AXWindow" in l and "title=Focus Island Settings" in l))
click(x+16, y+80)
assert not shown(), "same-app Settings click did not dismiss"
q.tool("close-window", q.APP, "Focus Island Settings")
print("PASS Settings action and same-app click dismissal", flush=True)

if "--actions" in sys.argv:
    assert q.wait_for("idle")
    open_menu()
    click_control("Start Focus")
    assert not shown(), "timer action left popup open"
    q.wait_for("focusBeforeCheckpoint")
    open_menu()
    click_control("Cancel Focus")
    assert not shown()
    q.wait_for("idle")
    print("PASS actual timer action completes before dismissal", flush=True)

(OUT / "popup-result.json").write_text(json.dumps({"result":"pass", "timerActions":"--actions" in sys.argv}, indent=2))
q.tool("move", "1200", "400")
