#!/usr/bin/env python3
import argparse
import json
import os
import signal
import subprocess
import sys
import time
from typing import Optional


def read_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def read_alive_pid(pid_file: str) -> Optional[int]:
    if not os.path.exists(pid_file):
        return None
    try:
        raw = open(pid_file, "r", encoding="utf-8").read().strip()
    except OSError:
        return None
    digits = "".join(ch for ch in raw if ch.isdigit())
    if not digits:
        try:
            os.remove(pid_file)
        except OSError:
            pass
        return None
    pid = int(digits)
    try:
        os.kill(pid, 0)
        return pid
    except OSError:
        try:
            os.remove(pid_file)
        except OSError:
            pass
        return None


def save_pid(pid_file: str, pid: int) -> None:
    with open(pid_file, "w", encoding="ascii") as f:
        f.write(str(pid))


def terminate_pid(pid: Optional[int]) -> None:
    if not pid:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    for _ in range(5):
        time.sleep(1)
        try:
            os.kill(pid, 0)
        except OSError:
            return
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def dump(obj: dict) -> None:
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--command", choices=["start", "stop", "status", "index"], default="status")
    parser.add_argument("--install-root", default=os.path.expanduser("~/.activity2context"))
    parser.add_argument("--config-path", default="")
    args = parser.parse_args()

    install_root = os.path.abspath(os.path.expanduser(args.install_root))
    config_path = os.path.abspath(os.path.expanduser(args.config_path or os.path.join(install_root, "config.json")))
    run_dir = os.path.join(install_root, "run")
    ensure_dir(run_dir)

    observer_pid_file = os.path.join(run_dir, "observer.pid")
    indexer_pid_file = os.path.join(run_dir, "indexer.pid")
    indexer_stop_flag = os.path.join(run_dir, "indexer.stop.flag")

    observer_script = os.path.join(install_root, "runtime", "macos", "activity2context-observer.py")
    indexer_script = os.path.join(install_root, "runtime", "macos", "activity2context-entity-indexer.py")
    indexer_loop_script = os.path.join(install_root, "runtime", "macos", "activity2context-indexer-loop.py")

    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Config not found: {config_path}")
    cfg = read_json(config_path)

    behavior_log = os.path.abspath(os.path.expanduser(cfg.get("behaviorLog", "")))
    entities_log = os.path.abspath(os.path.expanduser(cfg.get("entitiesLog", "")))
    workspace = os.path.abspath(os.path.expanduser(cfg.get("workspace", os.getcwd())))
    observer_cfg = cfg.get("observer", {})
    indexer_cfg = cfg.get("indexer", {})

    behavior_dir = os.path.dirname(behavior_log)
    ensure_dir(behavior_dir)
    observer_stop_flag = os.path.join(behavior_dir, "stop.flag")

    if args.command == "start":
        if os.path.exists(observer_stop_flag):
            try:
                os.remove(observer_stop_flag)
            except OSError:
                pass
        if os.path.exists(indexer_stop_flag):
            try:
                os.remove(indexer_stop_flag)
            except OSError:
                pass

        observer_pid = read_alive_pid(observer_pid_file)
        if not observer_pid:
            obs_log = open(os.path.join(run_dir, "observer.log"), "a", encoding="utf-8")
            obs_cmd = [
                sys.executable,
                observer_script,
                "--workspace",
                workspace,
                "--log-file",
                behavior_log,
                "--entities-log",
                entities_log,
                "--browser-threshold",
                str(int(observer_cfg.get("browserThreshold", 5))),
                "--browser-update-interval",
                str(int(observer_cfg.get("browserUpdateInterval", 10))),
                "--app-threshold",
                str(int(observer_cfg.get("appThreshold", 5))),
                "--app-update-interval",
                str(int(observer_cfg.get("appUpdateInterval", 10))),
                "--poll-seconds",
                str(int(observer_cfg.get("pollSeconds", 2))),
            ]
            proc = subprocess.Popen(obs_cmd, stdout=obs_log, stderr=obs_log)
            observer_pid = proc.pid
            save_pid(observer_pid_file, observer_pid)

        indexer_pid = read_alive_pid(indexer_pid_file)
        if not indexer_pid:
            idx_log = open(os.path.join(run_dir, "indexer.log"), "a", encoding="utf-8")
            idx_cmd = [
                sys.executable,
                indexer_loop_script,
                "--install-root",
                install_root,
                "--config-path",
                config_path,
            ]
            proc2 = subprocess.Popen(idx_cmd, stdout=idx_log, stderr=idx_log)
            indexer_pid = proc2.pid
            save_pid(indexer_pid_file, indexer_pid)

        dump(
            {
                "command": "start",
                "observerPid": observer_pid,
                "indexerPid": indexer_pid,
                "behaviorLog": behavior_log,
                "entitiesLog": entities_log,
            }
        )
        return 0

    if args.command == "stop":
        open(observer_stop_flag, "w", encoding="ascii").write("stop")
        open(indexer_stop_flag, "w", encoding="ascii").write("stop")

        observer_pid = read_alive_pid(observer_pid_file)
        indexer_pid = read_alive_pid(indexer_pid_file)
        terminate_pid(observer_pid)
        terminate_pid(indexer_pid)

        for p in [observer_pid_file, indexer_pid_file, indexer_stop_flag]:
            try:
                os.remove(p)
            except OSError:
                pass

        dump({"command": "stop", "observerStopped": True, "indexerStopped": True})
        return 0

    if args.command == "status":
        observer_pid = read_alive_pid(observer_pid_file)
        indexer_pid = read_alive_pid(indexer_pid_file)
        dump(
            {
                "command": "status",
                "observerRunning": bool(observer_pid),
                "observerPid": observer_pid,
                "indexerRunning": bool(indexer_pid),
                "indexerPid": indexer_pid,
                "behaviorLog": behavior_log,
                "entitiesLog": entities_log,
                "workspace": workspace,
            }
        )
        return 0

    if args.command == "index":
        cmd = [
            sys.executable,
            indexer_script,
            "--input-log",
            behavior_log,
            "--output-file",
            entities_log,
            "--min-duration-seconds",
            str(int(indexer_cfg.get("minDurationSeconds", 10))),
            "--max-age-minutes",
            str(int(indexer_cfg.get("maxAgeMinutes", 60))),
            "--max-total",
            str(int(indexer_cfg.get("maxTotal", 10))),
            "--max-web",
            str(int(indexer_cfg.get("maxWeb", 3))),
            "--max-doc",
            str(int(indexer_cfg.get("maxDoc", 4))),
            "--max-app",
            str(int(indexer_cfg.get("maxApp", 3))),
        ]
        subprocess.run(cmd, check=False)
        dump({"command": "index", "output": entities_log})
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
