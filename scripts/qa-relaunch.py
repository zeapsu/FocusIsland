#!/usr/bin/env python3
"""Verify persisted sessions using normal Quit/relaunch and a bounded app suspension."""
import json
import os
import pathlib
import plistlib
import runpy
import signal
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
helpers = runpy.run_path(str(ROOT / "scripts/qa-lifecycle.py"), run_name="qa_helpers")
state, wait_for, capture, menu, press, tool = (helpers[key] for key in ("state", "wait_for", "capture", "menu", "press", "tool"))

def launch():
    subprocess.run(["open", str(ROOT / "dist/Focus Island.app"), "--args", "--qa-speed", "--qa-artifacts", str(ROOT / "qa/live")], check=True)
    time.sleep(2)

def quit_app():
    menu()
    tool("press", "local.focusisland.app", "Quit", required=False)
    deadline = time.monotonic() + 5
    while subprocess.run(["pgrep", "-x", "FocusIsland"], capture_output=True).returncode == 0:
        if time.monotonic() > deadline:
            raise AssertionError("Normal Quit did not finish within five seconds")
        time.sleep(0.1)

wait_for("idle")
menu()
press("Start Focus")
before = wait_for("focusBeforeCheckpoint")
capture("before-relaunch")
quit_app()
time.sleep(2)
launch()
after = wait_for("focusBeforeCheckpoint")
assert (after["sessionStart"], after["checkpointAt"], after["hardStopAt"]) == (before["sessionStart"], before["checkpointAt"], before["hardStopAt"])
capture("after-relaunch")
stored = plistlib.loads((pathlib.Path.home() / "Library/Preferences/local.focusisland.qa.plist").read_bytes())
settings = json.loads(stored["focusIsland.settings.v1"])
assert (settings["checkpointMinutes"], settings["hardStopMinutes"], settings["breakMinutes"]) == (5, 10, 3)

pid = int(subprocess.check_output(["pgrep", "-x", "FocusIsland"], text=True).strip())
try:
    os.kill(pid, signal.SIGSTOP)
    time.sleep(17)
finally:
    os.kill(pid, signal.SIGCONT)
wait_for("checkpointReached", timeout=8)
capture("after-ui-suspension")
press("Continue Focus")
wait_for("hardStopReached", timeout=15)
capture("hard-stop-after-suspension")
press("End Session")
wait_for("idle")

menu()
press("Start Focus")
wait_for("focusBeforeCheckpoint")
capture("before-offline-hard-stop")
quit_app()
time.sleep(31)
launch()
wait_for("hardStopReached", timeout=8)
capture("relaunch-after-hard-stop")
press("End Session")
wait_for("idle")
print("PASS relaunch deadlines, preferences, suspended UI, offline hard stop and normal Quit", flush=True)
