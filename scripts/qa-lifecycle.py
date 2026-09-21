#!/usr/bin/env python3
"""Drive the running DEBUG app through real macOS Accessibility controls.

Requires --qa-speed --qa-artifacts "$PWD/qa/live", with committed 5/10/3
minute preferences. No command in this script changes the session model.
"""
import json
import pathlib
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIVE = ROOT / "qa/live"
OUT = ROOT / "qa/final"
APP = "local.focusisland.app"
OUT.mkdir(parents=True, exist_ok=True)

def tool(*args, required=True):
    result = subprocess.run([str(ROOT / ".build/ui-tool"), *args], text=True, capture_output=True)
    if required and result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout

def state():
    return json.loads((LIVE / "live.json").read_text())

def wait_for(expected, timeout=40):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        current = state()
        if current["state"] == expected and time.time() - current["time"] < 3:
            return current
        time.sleep(0.2)
    raise AssertionError(f"Wanted {expected}; got {state()}")

def capture(name):
    time.sleep(1.1)
    current = state()
    (OUT / f"{name}.json").write_text(json.dumps(current, indent=2))
    (OUT / f"{name}-ax.txt").write_text(tool("tree", APP, "10"))
    for window in current["windows"]:
        source = LIVE / f"window-{window['index']}.png"
        if source.exists():
            shutil.copy2(source, OUT / f"{name}-window-{window['index']}.png")
    print(f"PASS {name}: {current['state']} {current['clock']}", flush=True)
    return current

def menu():
    tool("move", "100", "400")
    time.sleep(0.5)
    if "role=AXPopover" not in tool("tree", APP, "8"):
        tool("press", APP, "Focus Island menu")
        time.sleep(0.4)

def press(label):
    try:
        tool("press", APP, label)
    except RuntimeError as error:
        if "No accessibility element" not in str(error):
            raise
        menu()
        tool("press", APP, label)
    time.sleep(0.3)

def main():
    assert wait_for("idle")
    menu()
    press("Start Focus")
    started = wait_for("focusBeforeCheckpoint")
    assert abs(started["checkpointAt"] - started["sessionStart"] - 15) < 0.01
    assert abs(started["hardStopAt"] - started["sessionStart"] - 30) < 0.01
    capture("focus-started")
    wait_for("checkpointReached")
    capture("checkpoint")
    time.sleep(1)
    assert state()["state"] == "checkpointReached", "checkpoint must not stop focus"
    if "Settings…" in tool("tree", APP, "8"):
        tool("press", APP, "Focus Island menu")
        time.sleep(0.3)
    tool("move", "855", "15")
    time.sleep(0.5)
    assert "id=island-controls" in tool("tree", APP, "8"), "checkpoint action must be exposed by the island"
    press("Continue Focus")
    wait_for("focusAfterCheckpoint")
    capture("continued-from-island")
    tool("move", "100", "400")
    wait_for("hardStopReached")
    capture("hard-stop")
    assert "Time to get up and move" in tool("tree", APP, "10")
    press("Start Break")
    broken = wait_for("onBreak")
    assert 0 < broken["breakEndAt"] - time.time() <= 9.1
    capture("break-started")
    assert "Continue Focus" not in tool("tree", APP, "10")
    wait_for("idle")
    capture("break-completed")

    menu()
    press("Start Focus")
    wait_for("checkpointReached")
    press("Start Break")
    wait_for("onBreak")
    capture("early-break-at-checkpoint")
    press("End Break")
    wait_for("idle")
    capture("end-break")

    for _ in range(3):
        menu()
        press("Start Focus")
        wait_for("focusBeforeCheckpoint")
        press("Cancel Focus")
        wait_for("idle")
    capture("rapid-start-cancel")
    print("PASS full lifecycle, early break, cross-surface actions and rapid cancellation", flush=True)

if __name__ == "__main__":
    main()
