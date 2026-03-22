#!/usr/bin/env python3
import argparse
import datetime as dt
import os
import subprocess
import time
from dataclasses import dataclass, field
from typing import Dict, Iterable, Optional, Tuple


BROWSER_APP_MAP = {
    "google chrome": "chrome",
    "microsoft edge": "msedge",
    "brave browser": "brave",
    "safari": "safari",
    "firefox": "firefox",
}

IGNORE_APPS = {
    "finder",
    "dock",
    "controlcenter",
    "systemuiserver",
    "windowserver",
    "loginwindow",
    "unknown",
}

IGNORE_DIRS = {".git", "node_modules", "__pycache__", ".openclaw"}
IGNORE_SUFFIXES = (".tmp", ".log", "~")


@dataclass
class ObserverState:
    current_key: str = ""
    start_time: dt.datetime = field(default_factory=dt.datetime.now)
    last_process: str = ""
    last_title: str = ""
    last_url: str = ""
    last_document_path: str = ""
    browser_entry_emitted: bool = False
    last_browser_tick: Optional[dt.datetime] = None
    app_entry_emitted: bool = False
    last_app_tick: Optional[dt.datetime] = None
    file_throttle: Dict[str, dt.datetime] = field(default_factory=dict)
    file_mtimes: Dict[str, float] = field(default_factory=dict)


def clean(value: str) -> str:
    return (value or "").replace("\r", " ").replace("\n", " ").strip()


def run_osascript(lines: Iterable[str]) -> str:
    args = ["osascript"]
    for line in lines:
        args.extend(["-e", line])
    try:
        proc = subprocess.run(args, check=False, capture_output=True, text=True, timeout=2)
        if proc.returncode != 0:
            return ""
        return clean(proc.stdout)
    except Exception:
        return ""


def get_frontmost_app_and_title() -> Tuple[str, str]:
    output = run_osascript(
        [
            'tell application "System Events"',
            "set frontApp to first application process whose frontmost is true",
            "set appName to name of frontApp",
            'set winTitle to ""',
            "try",
            "set winTitle to name of front window of frontApp",
            "end try",
            'return appName & "|||" & winTitle',
            "end tell",
        ]
    )
    if not output or "|||" not in output:
        return "Unknown", ""
    app_name, title = output.split("|||", 1)
    return clean(app_name) or "Unknown", clean(title)


def normalize_process_name(raw_app_name: str) -> str:
    lower = clean(raw_app_name).lower()
    if lower in BROWSER_APP_MAP:
        return BROWSER_APP_MAP[lower]
    return lower.replace(" ", "")


def get_browser_url(process_name: str) -> str:
    scripts = {
        "chrome": [
            'tell application "Google Chrome"',
            "if (count of windows) = 0 then return \"URL Unknown\"",
            "return URL of active tab of front window",
            "end tell",
        ],
        "msedge": [
            'tell application "Microsoft Edge"',
            "if (count of windows) = 0 then return \"URL Unknown\"",
            "return URL of active tab of front window",
            "end tell",
        ],
        "brave": [
            'tell application "Brave Browser"',
            "if (count of windows) = 0 then return \"URL Unknown\"",
            "return URL of active tab of front window",
            "end tell",
        ],
        "safari": [
            'tell application "Safari"',
            "if (count of windows) = 0 then return \"URL Unknown\"",
            "return URL of front document",
            "end tell",
        ],
    }
    if process_name not in scripts:
        return "URL Unknown"
    result = run_osascript(scripts[process_name])
    if not result:
        return "URL Unknown"
    return result


def ensure_log_file(log_file: str) -> None:
    parent = os.path.dirname(log_file) or "."
    os.makedirs(parent, exist_ok=True)
    if not os.path.exists(log_file):
        with open(log_file, "w", encoding="utf-8") as f:
            f.write(f"# Activity2Context Behavior Context - {dt.datetime.now():%Y-%m-%d}\n")


def write_behavior_log(log_file: str, kind: str, details: str) -> None:
    ensure_log_file(log_file)
    timestamp = dt.datetime.now().strftime("%H:%M:%S")
    line = f"* [{timestamp}] **{kind}**: {details}"
    with open(log_file, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line, flush=True)


def write_or_update_browser_log(log_file: str, mode: str, seconds: int, title: str, url: str) -> None:
    ensure_log_file(log_file)
    title = clean(title)
    url = clean(url) or "URL Unknown"
    timestamp = dt.datetime.now().strftime("%H:%M:%S")
    line = f"* [{timestamp}] **BROWSER**: {mode}:{seconds}s | Title:{title} | URL:{url}"

    with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.read().splitlines()

    last_index = -1
    for idx in range(len(lines) - 1, -1, -1):
        if lines[idx].startswith("* [") and "**BROWSER**:" in lines[idx]:
            last_index = idx
            break

    same_page = False
    if last_index >= 0:
        same_page = lines[last_index].endswith(f"| Title:{title} | URL:{url}") or (
            f"| Title:{title} | URL:{url}" in lines[last_index]
        )

    if same_page and last_index >= 0:
        lines[last_index] = line
    else:
        lines.append(line)

    with open(log_file, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))
    print(line, flush=True)


def write_or_update_app_log(log_file: str, mode: str, seconds: int, app: str, title: str, recent_doc: str) -> None:
    ensure_log_file(log_file)
    app = clean(app) or "unknown"
    title = clean(title)
    details = f"{mode}:{seconds}s | App:{app} | Title:{title}"
    if recent_doc:
        details += f" | RecentDoc:{clean(recent_doc)}"
    timestamp = dt.datetime.now().strftime("%H:%M:%S")
    line = f"* [{timestamp}] **APP**: {details}"

    with open(log_file, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.read().splitlines()

    last_index = -1
    for idx in range(len(lines) - 1, -1, -1):
        if lines[idx].startswith("* [") and "**APP**:" in lines[idx]:
            last_index = idx
            break

    same_window = False
    if last_index >= 0:
        marker = f"| App:{app} | Title:{title}"
        same_window = marker in lines[last_index]

    if same_window and last_index >= 0:
        lines[last_index] = line
    else:
        lines.append(line)

    with open(log_file, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + ("\n" if lines else ""))
    print(line, flush=True)


def iter_workspace_files(workspace: str) -> Iterable[str]:
    for root, dirs, files in os.walk(workspace):
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
        for name in files:
            if name.endswith(IGNORE_SUFFIXES):
                continue
            path = os.path.join(root, name)
            if ".openclaw" in path:
                continue
            yield path


def scan_file_events(workspace: str, state: ObserverState, log_file: str) -> None:
    now = dt.datetime.now()
    current: Dict[str, float] = {}
    for path in iter_workspace_files(workspace):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        current[path] = mtime
        prev = state.file_mtimes.get(path)
        action = None
        if prev is None:
            action = "Created"
        elif mtime != prev:
            action = "Changed"
        if not action:
            continue

        last_hit = state.file_throttle.get(path)
        if last_hit and (now - last_hit).total_seconds() < 3:
            continue
        state.file_throttle[path] = now
        full_path = os.path.abspath(path)
        rel_name = os.path.relpath(path, workspace)
        state.last_document_path = full_path
        write_behavior_log(log_file, "DOCUMENT", f"Action:{action} | Name:{rel_name} | Path:{full_path}")

    state.file_mtimes = current


def finalize_current_window(state: ObserverState, log_file: str, browser_threshold: int, app_threshold: int) -> None:
    if not state.current_key:
        return
    duration = int(round((dt.datetime.now() - state.start_time).total_seconds()))
    proc = state.last_process

    if proc in BROWSER_APP_MAP.values():
        if duration >= browser_threshold:
            write_or_update_browser_log(log_file, "Focus", duration, state.last_title, state.last_url)
        return

    if proc not in IGNORE_APPS and duration >= app_threshold:
        write_or_update_app_log(log_file, "Focus", duration, proc, state.last_title, state.last_document_path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", default=os.getcwd())
    parser.add_argument("--log-file", default=os.path.expanduser("~/.activity2context/data/activity2context_behavior.md"))
    parser.add_argument("--browser-threshold", type=int, default=5)
    parser.add_argument("--browser-update-interval", type=int, default=10)
    parser.add_argument("--app-threshold", type=int, default=5)
    parser.add_argument("--app-update-interval", type=int, default=10)
    parser.add_argument("--poll-seconds", type=int, default=2)
    parser.add_argument("--file-scan-interval", type=int, default=3)
    args = parser.parse_args()

    workspace = os.path.abspath(os.path.expanduser(args.workspace))
    log_file = os.path.abspath(os.path.expanduser(args.log_file))
    stop_flag = os.path.join(os.path.dirname(log_file), "stop.flag")

    state = ObserverState()
    ensure_log_file(log_file)
    write_behavior_log(
        log_file,
        "SYSTEM",
        (
            f"Observer started. Workspace={workspace} Poll={args.poll_seconds}s "
            f"BrowserFirstLogSeconds={args.browser_threshold}s BrowserUpdateInterval={args.browser_update_interval}s "
            f"AppThreshold={args.app_threshold}s AppUpdateInterval={args.app_update_interval}s"
        ),
    )
    print(f"[activity2context] observer started, workspace={workspace}", flush=True)

    next_scan = 0.0
    try:
        while True:
            now_ts = time.time()
            if now_ts >= next_scan:
                scan_file_events(workspace, state, log_file)
                next_scan = now_ts + max(1, args.file_scan_interval)

            if os.path.exists(stop_flag):
                try:
                    os.remove(stop_flag)
                except OSError:
                    pass
                write_behavior_log(log_file, "SYSTEM", "Stop flag detected. Exiting.")
                break

            raw_app, title = get_frontmost_app_and_title()
            process_name = normalize_process_name(raw_app)
            current_key = f"{clean(raw_app)}|||{title}"

            if current_key != state.current_key:
                finalize_current_window(state, log_file, args.browser_threshold, args.app_threshold)
                state.current_key = current_key
                state.start_time = dt.datetime.now()
                state.last_process = process_name
                state.last_title = title
                state.last_url = get_browser_url(process_name) if process_name in BROWSER_APP_MAP.values() else ""
                state.browser_entry_emitted = False
                state.last_browser_tick = None
                state.app_entry_emitted = False
                state.last_app_tick = None
            elif state.last_process in BROWSER_APP_MAP.values():
                current_url = get_browser_url(state.last_process)
                old_url = state.last_url or ""
                old_title = state.last_title or ""
                title_changed = title != old_title
                url_changed = (
                    old_url
                    and old_url != "URL Unknown"
                    and current_url
                    and current_url != "URL Unknown"
                    and current_url != old_url
                )
                page_changed = url_changed or ((not old_url or old_url == "URL Unknown") and title_changed)

                if page_changed:
                    duration = int(round((dt.datetime.now() - state.start_time).total_seconds()))
                    if duration >= args.browser_threshold:
                        write_or_update_browser_log(log_file, "Focus", duration, old_title, old_url)
                    state.start_time = dt.datetime.now()
                    state.last_title = title
                    state.last_url = current_url
                    state.browser_entry_emitted = False
                    state.last_browser_tick = None
                else:
                    if (not old_url or old_url == "URL Unknown") and current_url and current_url != "URL Unknown":
                        state.last_url = current_url
                    if not state.last_title and title:
                        state.last_title = title

            if state.last_process in BROWSER_APP_MAP.values():
                elapsed = (dt.datetime.now() - state.start_time).total_seconds()
                if elapsed >= args.browser_threshold:
                    if not state.browser_entry_emitted:
                        write_or_update_browser_log(log_file, "Stay", int(round(elapsed)), state.last_title, state.last_url)
                        state.browser_entry_emitted = True
                        state.last_browser_tick = dt.datetime.now()
                    else:
                        since_last = (
                            (dt.datetime.now() - state.last_browser_tick).total_seconds()
                            if state.last_browser_tick
                            else 999999
                        )
                        if since_last >= args.browser_update_interval:
                            write_or_update_browser_log(
                                log_file, "Stay", int(round(elapsed)), state.last_title, state.last_url
                            )
                            state.last_browser_tick = dt.datetime.now()

            if state.last_process not in BROWSER_APP_MAP.values() and state.last_process not in IGNORE_APPS:
                elapsed = (dt.datetime.now() - state.start_time).total_seconds()
                if elapsed >= args.app_threshold:
                    if not state.app_entry_emitted:
                        write_or_update_app_log(
                            log_file,
                            "Stay",
                            int(round(elapsed)),
                            state.last_process,
                            state.last_title,
                            state.last_document_path,
                        )
                        state.app_entry_emitted = True
                        state.last_app_tick = dt.datetime.now()
                    else:
                        since_last_app = (
                            (dt.datetime.now() - state.last_app_tick).total_seconds() if state.last_app_tick else 999999
                        )
                        if since_last_app >= args.app_update_interval:
                            write_or_update_app_log(
                                log_file,
                                "Stay",
                                int(round(elapsed)),
                                state.last_process,
                                state.last_title,
                                state.last_document_path,
                            )
                            state.last_app_tick = dt.datetime.now()

            time.sleep(max(1, args.poll_seconds))
    except KeyboardInterrupt:
        write_behavior_log(log_file, "SYSTEM", "Observer interrupted.")

    finalize_current_window(state, log_file, args.browser_threshold, args.app_threshold)
    write_behavior_log(log_file, "SYSTEM", "Observer stopped.")
    print("[activity2context] observer stopped", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
